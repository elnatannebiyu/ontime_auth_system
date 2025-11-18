import 'dart:async';
import 'package:dio/dio.dart';
import '../models/session.dart';
import 'session_storage.dart';
import 'device_info_service.dart';
import '../../api_client.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  final ApiClient _apiClient = ApiClient();
  Session? _currentSession;
  Timer? _refreshTimer;
  final _sessionController = StreamController<Session?>.broadcast();

  // Configuration
  String baseUrl = kApiBase;
  static const Duration refreshInterval = Duration(minutes: 4);

  /// Get session stream
  Stream<Session?> get sessionStream => _sessionController.stream;

  /// Get current session
  Session? get currentSession => _currentSession;

  /// Check if user is logged in
  bool get isLoggedIn => _currentSession != null;

  /// Initialize session manager
  Future<void> initialize() async {
    // Check for existing session
    final hasSession = await SessionStorage.hasSession();
    if (hasSession) {
      await _loadSession();
    }

    // Setup interceptors
    _setupInterceptors();
  }

  /// Login user
  Future<Session> login({
    required String email,
    required String password,
  }) async {
    try {
      // Get device info
      final deviceInfo = await DeviceInfoService.getDeviceInfo();
      final deviceId = await SessionStorage.getDeviceId();

      // Make login request using existing ApiClient
      final response = await _apiClient.post('/token/', data: {
        'username': email, // Backend expects username field
        'password': password,
        'device_info': deviceInfo,
        'device_id': deviceId,
      });

      // Create session from response
      final sessionData = response.data;
      sessionData['device_id'] = deviceId;

      final session = Session.fromJson(sessionData);

      // Save session
      await SessionStorage.saveSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        sessionId: session.sessionId,
        userData: session.userData,
        expiresIn: sessionData['expires_in'] ?? 3600,
      );

      // Update current session
      _currentSession = session;
      _sessionController.add(_currentSession);

      // Start refresh timer
      _startRefreshTimer();

      return session;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Refresh token
  Future<void> refreshToken() async {
    if (_currentSession == null) return;

    try {
      final refreshToken = await SessionStorage.getRefreshToken();
      if (refreshToken == null) {
        throw Exception('No refresh token available');
      }

      // Use ApiClient for refresh - cookies handle refresh token
      final response = await _apiClient.post('/token/refresh/');

      // Update access token
      final newAccessToken =
          response.data['access'] ?? response.data['access_token'];
      final expiresIn = response.data['expires_in'] ?? 3600;

      await SessionStorage.updateAccessToken(newAccessToken, expiresIn);

      // Update current session
      _currentSession = _currentSession!.copyWith(
        accessToken: newAccessToken,
        tokenExpiry: DateTime.now().add(Duration(seconds: expiresIn)),
      );

      _sessionController.add(_currentSession);
    } catch (e) {
      // Do not logout on refresh failure. Handle common cases gracefully and continue.
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionError) {
          // Likely offline; keep session and try again later.
          return;
        }
        if (e.response?.statusCode == 401) {
          final data = e.response?.data;
          final detail = (data is Map && data['detail'] is String)
              ? data['detail'] as String
              : '';
          if (detail.contains('Refresh token not found')) {
            // Likely due to missing cookie while offline; keep session.
            return;
          }
        }
      }
      // For other unexpected errors, rethrow after wrapping
      throw _handleError(e);
    }
  }

  /// Logout user
  Future<void> logout() async {
    try {
      // Call logout endpoint if we have a session
      if (_currentSession != null) {
        final refreshToken = await SessionStorage.getRefreshToken();
        if (refreshToken != null) {
          await _apiClient.post('/logout/', data: {
            'refresh_token': refreshToken,
          });
        }
      }
    } catch (e) {
      // Continue with logout even if API call fails
    } finally {
      // Clear local session
      await _clearSession();
    }
  }

  /// Revoke session on another device
  Future<void> revokeSession(String sessionId) async {
    if (_currentSession == null) {
      throw Exception('Not logged in');
    }

    try {
      await _apiClient.delete('/sessions/$sessionId/');
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get all active sessions
  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    if (_currentSession == null) {
      throw Exception('Not logged in');
    }

    try {
      final response = await _apiClient.get('/sessions/');

      return List<Map<String, dynamic>>.from(response.data['sessions'] ?? []);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Load existing session from storage
  Future<void> _loadSession() async {
    try {
      final accessToken = await SessionStorage.getAccessToken();
      final refreshToken = await SessionStorage.getRefreshToken();
      final sessionId = await SessionStorage.getSessionId();
      final userData = await SessionStorage.getUserData();
      final deviceId = await SessionStorage.getDeviceId();

      if (accessToken != null && refreshToken != null && sessionId != null) {
        _currentSession = Session(
          sessionId: sessionId,
          accessToken: accessToken,
          refreshToken: refreshToken,
          userData: userData,
          deviceId: deviceId,
        );

        _sessionController.add(_currentSession);

        // Check if token needs refresh
        final isExpired = await SessionStorage.isTokenExpired();
        if (isExpired) {
          await this.refreshToken();
        }

        // Start refresh timer
        _startRefreshTimer();
      }
    } catch (e) {
      // If loading fails, clear session
      await _clearSession();
    }
  }

  /// Clear session data
  Future<void> _clearSession() async {
    _currentSession = null;
    _sessionController.add(null);
    _stopRefreshTimer();
    await SessionStorage.clearSession();
  }

  /// Start token refresh timer
  void _startRefreshTimer() {
    _stopRefreshTimer();
    _refreshTimer = Timer.periodic(refreshInterval, (_) {
      if (_currentSession != null) {
        refreshToken().catchError((e) {});
      }
    });
  }

  /// Stop token refresh timer
  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Setup interceptors (ApiClient already has its own)
  void _setupInterceptors() {
    // ApiClient already handles auth headers and refresh logic
    // We just need to keep our session in sync
  }

  /// Handle errors
  Exception _handleError(dynamic error) {
    if (error is DioException) {
      if (error.response != null) {
        final data = error.response!.data;
        if (data is Map && data.containsKey('error')) {
          return Exception(data['error']);
        }
        if (data is Map && data.containsKey('detail')) {
          return Exception(data['detail']);
        }
      }
      return Exception(error.message ?? 'Network error');
    }
    return Exception(error.toString());
  }

  /// Dispose resources
  void dispose() {
    _stopRefreshTimer();
    _sessionController.close();
  }
}
