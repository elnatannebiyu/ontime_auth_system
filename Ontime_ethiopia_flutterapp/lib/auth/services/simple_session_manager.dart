import 'dart:async';
import 'package:dio/dio.dart';
import '../../api_client.dart';
import '../../core/notifications/fcm_manager.dart';
import '../tenant_auth_client.dart';
import '../secure_token_store.dart';
import '../../core/services/social_auth.dart';
import '../../config.dart';

/// Simple session manager that works with existing auth infrastructure
class SimpleSessionManager {
  static final SimpleSessionManager _instance =
      SimpleSessionManager._internal();
  factory SimpleSessionManager() => _instance;
  SimpleSessionManager._internal();

  final ApiClient _apiClient = ApiClient();
  final AuthApi _authApi = AuthApi();
  final SecureTokenStore _tokenStore = SecureTokenStore();

  Timer? _refreshTimer;
  bool _isLoggedIn = false;
  final _sessionController = StreamController<bool>.broadcast();

  Stream<bool> get sessionStream => _sessionController.stream;
  bool get isLoggedIn => _isLoggedIn;

  /// Initialize session manager
  Future<void> initialize() async {
    // Check if we have an existing token
    final token = await _tokenStore.getAccess();
    if (token != null && token.isNotEmpty) {
      _apiClient.setAccessToken(token);
      _isLoggedIn = true;
      _sessionController.add(true);
      _startRefreshTimer();
      // Ensure device is registered for push if we already had a valid token
      try {
        await FcmManager().ensureRegisteredWithBackend();
      } catch (_) {}
    }
  }

  /// Login using existing auth API
  Future<void> login({
    required String email,
    required String password,
    required String tenantId,
  }) async {
    try {
      _authApi.setTenant(tenantId);
      final tokens = await _authApi.login(
        tenantId: tenantId,
        username: email,
        password: password,
      );

      // Store tokens
      await _tokenStore.setTokens(tokens.access, tokens.refresh);
      _apiClient.setAccessToken(tokens.access);

      _isLoggedIn = true;
      _sessionController.add(true);
      _startRefreshTimer();
      // Ensure FCM token is registered now that we have access
      try {
        await FcmManager().ensureRegisteredWithBackend();
      } catch (_) {}
    } catch (e) {
      _isLoggedIn = false;
      _sessionController.add(false);
      rethrow;
    }
  }

  /// Refresh token
  Future<void> refreshToken() async {
    try {
      final response = await _apiClient.post('/token/refresh/');
      final newAccessToken =
          response.data['access'] ?? response.data['access_token'];

      if (newAccessToken != null) {
        await _tokenStore.setTokens(newAccessToken, null);
        _apiClient.setAccessToken(newAccessToken);
        // Optionally ensure device registration after refresh as well
        try {
          await FcmManager().ensureRegisteredWithBackend();
        } catch (_) {}
      }
    } catch (e) {
      // Do not logout on refresh failure. Handle common cases gracefully.
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionError) {
          // Likely offline; keep session and try again later.
          return;
        }
        final status = e.response?.statusCode;
        if (status == 401) {
          final data = e.response?.data;
          final detail =
              (data is Map && data['detail'] is String) ? data['detail'] as String : '';
          if (detail.contains('Refresh token not found')) {
            // Likely missing cookie due to offline/network; do not logout.
            return;
          }
        }
      }
      // For other unexpected errors, rethrow to surface in logs/metrics
      rethrow;
    }
  }

  /// Logout
  Future<void> logout() async {
    try {
      // First disable push for this user+device while Authorization is valid
      try {
        await _apiClient.post('/user-sessions/unregister-device/');
      } catch (_) {}
      // Then logout server-side
      await _apiClient.post('/logout/');
    } catch (e) {
      // Continue with logout even if API call fails
    } finally {
      // Also sign out of Google so the account chooser appears next time
      try {
        await SocialAuthService(serverClientId: kGoogleWebClientId).signOutGoogle();
      } catch (_) {}
      await _tokenStore.clear();
      _apiClient.setAccessToken(null);
      _isLoggedIn = false;
      _sessionController.add(false);
      _stopRefreshTimer();
    }
  }

  /// Start refresh timer
  void _startRefreshTimer() {
    _stopRefreshTimer();
    // Refresh every 4 minutes (tokens expire in 5 minutes)
    _refreshTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      if (_isLoggedIn) {
        refreshToken().catchError((e) {
          print('Auto-refresh failed: $e');
        });
      }
    });
  }

  /// Stop refresh timer
  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Dispose resources
  void dispose() {
    _stopRefreshTimer();
    _sessionController.close();
  }
}
