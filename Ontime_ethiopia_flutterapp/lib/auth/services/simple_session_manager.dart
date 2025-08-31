import 'dart:async';
import '../../api_client.dart';
import '../tenant_auth_client.dart';
import '../secure_token_store.dart';

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
      }
    } catch (e) {
      // If refresh fails, logout
      await logout();
      rethrow;
    }
  }

  /// Logout
  Future<void> logout() async {
    try {
      await _apiClient.post('/logout/');
    } catch (e) {
      // Continue with logout even if API call fails
    } finally {
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
