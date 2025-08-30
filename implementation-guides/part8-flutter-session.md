# Part 8: Flutter Session Management

## Overview
Implement Flutter session management with token storage, refresh, and device tracking.

## 8.1 Session Storage Service

```dart
// lib/auth/services/session_storage.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class SessionStorage {
  static const _storage = FlutterSecureStorage();
  
  // Keys
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _sessionIdKey = 'session_id';
  static const _userDataKey = 'user_data';
  static const _deviceIdKey = 'device_id';
  static const _tokenExpiryKey = 'token_expiry';
  
  /// Save session data
  static Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String sessionId,
    Map<String, dynamic>? userData,
    int? expiresIn,
  }) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(key: _sessionIdKey, value: sessionId),
      if (userData != null)
        _storage.write(key: _userDataKey, value: jsonEncode(userData)),
      if (expiresIn != null)
        _storage.write(
          key: _tokenExpiryKey,
          value: DateTime.now()
              .add(Duration(seconds: expiresIn))
              .millisecondsSinceEpoch
              .toString(),
        ),
    ]);
  }
  
  /// Get access token
  static Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }
  
  /// Get refresh token
  static Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }
  
  /// Get session ID
  static Future<String?> getSessionId() async {
    return await _storage.read(key: _sessionIdKey);
  }
  
  /// Get user data
  static Future<Map<String, dynamic>?> getUserData() async {
    final data = await _storage.read(key: _userDataKey);
    if (data != null) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return null;
  }
  
  /// Check if token is expired
  static Future<bool> isTokenExpired() async {
    final expiryStr = await _storage.read(key: _tokenExpiryKey);
    if (expiryStr == null) return true;
    
    final expiry = DateTime.fromMillisecondsSinceEpoch(int.parse(expiryStr));
    return DateTime.now().isAfter(expiry);
  }
  
  /// Get device ID (generate if not exists)
  static Future<String> getDeviceId() async {
    var deviceId = await _storage.read(key: _deviceIdKey);
    if (deviceId == null) {
      // Generate UUID for device
      deviceId = _generateUUID();
      await _storage.write(key: _deviceIdKey, value: deviceId);
    }
    return deviceId;
  }
  
  /// Clear session (logout)
  static Future<void> clearSession() async {
    await _storage.deleteAll();
  }
  
  /// Check if user is logged in
  static Future<bool> hasSession() async {
    final token = await getAccessToken();
    final sessionId = await getSessionId();
    return token != null && sessionId != null;
  }
  
  /// Update access token (after refresh)
  static Future<void> updateAccessToken(String newToken, int expiresIn) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: newToken),
      _storage.write(
        key: _tokenExpiryKey,
        value: DateTime.now()
            .add(Duration(seconds: expiresIn))
            .millisecondsSinceEpoch
            .toString(),
      ),
    ]);
  }
  
  static String _generateUUID() {
    // Simple UUID v4 generator
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    
    // Set version (4) and variant bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
           '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
           '${hex.substring(20, 32)}';
  }
}
```

## 8.2 Session Manager

```dart
// lib/auth/services/session_manager.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'session_storage.dart';
import '../models/session_model.dart';
import '../api/auth_api.dart';

enum SessionState {
  unauthenticated,
  authenticated,
  expired,
  revoked,
}

class SessionManager extends ChangeNotifier {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();
  
  SessionState _state = SessionState.unauthenticated;
  SessionModel? _currentSession;
  Timer? _refreshTimer;
  bool _isRefreshing = false;
  
  SessionState get state => _state;
  SessionModel? get currentSession => _currentSession;
  bool get isAuthenticated => _state == SessionState.authenticated;
  
  /// Initialize session manager
  Future<void> initialize() async {
    final hasSession = await SessionStorage.hasSession();
    
    if (hasSession) {
      // Check if token is expired
      final isExpired = await SessionStorage.isTokenExpired();
      
      if (isExpired) {
        // Try to refresh
        await refreshSession();
      } else {
        // Load existing session
        await _loadSession();
        _startRefreshTimer();
      }
    } else {
      _updateState(SessionState.unauthenticated);
    }
  }
  
  /// Create new session after login
  Future<void> createSession({
    required String accessToken,
    required String refreshToken,
    required String sessionId,
    required Map<String, dynamic> userData,
    int expiresIn = 300, // 5 minutes default
  }) async {
    // Save to storage
    await SessionStorage.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      sessionId: sessionId,
      userData: userData,
      expiresIn: expiresIn,
    );
    
    // Create session model
    _currentSession = SessionModel(
      sessionId: sessionId,
      userId: userData['id'],
      accessToken: accessToken,
      refreshToken: refreshToken,
      userData: userData,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
    
    _updateState(SessionState.authenticated);
    _startRefreshTimer();
  }
  
  /// Refresh session
  Future<bool> refreshSession() async {
    if (_isRefreshing) return false;
    _isRefreshing = true;
    
    try {
      final refreshToken = await SessionStorage.getRefreshToken();
      final deviceId = await SessionStorage.getDeviceId();
      
      if (refreshToken == null) {
        await logout();
        return false;
      }
      
      // Call refresh API
      final response = await AuthApi.refreshToken(
        refreshToken: refreshToken,
        deviceId: deviceId,
      );
      
      if (response.success) {
        // Update tokens
        await SessionStorage.updateAccessToken(
          response.data['access'],
          response.data['expires_in'] ?? 300,
        );
        
        // Update session
        if (_currentSession != null) {
          _currentSession = _currentSession!.copyWith(
            accessToken: response.data['access'],
            expiresAt: DateTime.now().add(
              Duration(seconds: response.data['expires_in'] ?? 300),
            ),
          );
        }
        
        _updateState(SessionState.authenticated);
        _startRefreshTimer();
        return true;
      } else {
        // Handle refresh failure
        if (response.errorCode == 'TOKEN_REVOKED' ||
            response.errorCode == 'INVALID_REFRESH') {
          await logout();
        }
        return false;
      }
    } catch (e) {
      debugPrint('Refresh failed: $e');
      return false;
    } finally {
      _isRefreshing = false;
    }
  }
  
  /// Logout and clear session
  Future<void> logout() async {
    try {
      // Call logout API to revoke session
      final sessionId = await SessionStorage.getSessionId();
      if (sessionId != null) {
        await AuthApi.logout(sessionId: sessionId);
      }
    } catch (e) {
      debugPrint('Logout API failed: $e');
    }
    
    // Clear local session
    await SessionStorage.clearSession();
    _currentSession = null;
    _cancelRefreshTimer();
    _updateState(SessionState.unauthenticated);
  }
  
  /// Force logout (for session revocation)
  Future<void> forceLogout(String reason) async {
    await SessionStorage.clearSession();
    _currentSession = null;
    _cancelRefreshTimer();
    _updateState(SessionState.revoked);
    
    // Show reason to user
    _showSessionRevokedDialog(reason);
  }
  
  /// Load session from storage
  Future<void> _loadSession() async {
    final sessionId = await SessionStorage.getSessionId();
    final accessToken = await SessionStorage.getAccessToken();
    final refreshToken = await SessionStorage.getRefreshToken();
    final userData = await SessionStorage.getUserData();
    
    if (sessionId != null && accessToken != null && refreshToken != null) {
      _currentSession = SessionModel(
        sessionId: sessionId,
        userId: userData?['id'] ?? '',
        accessToken: accessToken,
        refreshToken: refreshToken,
        userData: userData ?? {},
        expiresAt: DateTime.now().add(Duration(minutes: 5)), // Estimate
      );
      
      _updateState(SessionState.authenticated);
    }
  }
  
  /// Start refresh timer
  void _startRefreshTimer() {
    _cancelRefreshTimer();
    
    // Refresh 30 seconds before expiry
    const refreshBuffer = Duration(seconds: 30);
    
    if (_currentSession != null) {
      final timeUntilRefresh = _currentSession!.expiresAt
          .subtract(refreshBuffer)
          .difference(DateTime.now());
      
      if (timeUntilRefresh.isNegative) {
        // Token already expired, refresh immediately
        refreshSession();
      } else {
        _refreshTimer = Timer(timeUntilRefresh, () {
          refreshSession();
        });
      }
    }
  }
  
  /// Cancel refresh timer
  void _cancelRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
  
  /// Update state and notify listeners
  void _updateState(SessionState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }
  
  /// Show session revoked dialog
  void _showSessionRevokedDialog(String reason) {
    // This should be handled by the UI layer
    // Emit an event or use a global navigator key
  }
  
  @override
  void dispose() {
    _cancelRefreshTimer();
    super.dispose();
  }
}
```

## 8.3 Session Model

```dart
// lib/auth/models/session_model.dart
class SessionModel {
  final String sessionId;
  final String userId;
  final String accessToken;
  final String refreshToken;
  final Map<String, dynamic> userData;
  final DateTime expiresAt;
  final DateTime? createdAt;
  
  SessionModel({
    required this.sessionId,
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.userData,
    required this.expiresAt,
    this.createdAt,
  });
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  
  Duration get timeUntilExpiry => expiresAt.difference(DateTime.now());
  
  SessionModel copyWith({
    String? sessionId,
    String? userId,
    String? accessToken,
    String? refreshToken,
    Map<String, dynamic>? userData,
    DateTime? expiresAt,
    DateTime? createdAt,
  }) {
    return SessionModel(
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      userData: userData ?? this.userData,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'userId': userId,
      'userData': userData,
      'expiresAt': expiresAt.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
```

## 8.4 Device Information Service

```dart
// lib/auth/services/device_info_service.dart
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DeviceInfoService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  /// Get device information for session tracking
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    Map<String, dynamic> deviceData = {
      'app_version': packageInfo.version,
      'build_number': packageInfo.buildNumber,
      'package_name': packageInfo.packageName,
    };
    
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      deviceData.addAll({
        'platform': 'android',
        'device_name': androidInfo.model,
        'device_model': androidInfo.model,
        'manufacturer': androidInfo.manufacturer,
        'os_version': androidInfo.version.release,
        'sdk_version': androidInfo.version.sdkInt.toString(),
        'device_id': androidInfo.id,
        'is_physical': androidInfo.isPhysicalDevice,
      });
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      deviceData.addAll({
        'platform': 'ios',
        'device_name': iosInfo.name,
        'device_model': iosInfo.model,
        'system_name': iosInfo.systemName,
        'os_version': iosInfo.systemVersion,
        'device_id': iosInfo.identifierForVendor,
        'is_physical': iosInfo.isPhysicalDevice,
      });
    }
    
    return deviceData;
  }
  
  /// Get platform string
  static String getPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
  
  /// Get app version
  static Future<String> getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }
  
  /// Get build number
  static Future<String> getBuildNumber() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.buildNumber;
  }
}
```

## 8.5 Session Provider Widget

```dart
// lib/auth/widgets/session_provider.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_manager.dart';

class SessionProvider extends StatefulWidget {
  final Widget child;
  final Widget? loadingWidget;
  final Function(SessionState)? onStateChanged;
  
  const SessionProvider({
    Key? key,
    required this.child,
    this.loadingWidget,
    this.onStateChanged,
  }) : super(key: key);
  
  @override
  State<SessionProvider> createState() => _SessionProviderState();
}

class _SessionProviderState extends State<SessionProvider> {
  final SessionManager _sessionManager = SessionManager();
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializeSession();
  }
  
  Future<void> _initializeSession() async {
    await _sessionManager.initialize();
    
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
    
    // Listen for state changes
    _sessionManager.addListener(_onSessionStateChanged);
  }
  
  void _onSessionStateChanged() {
    if (widget.onStateChanged != null) {
      widget.onStateChanged!(_sessionManager.state);
    }
    
    // Handle session revocation
    if (_sessionManager.state == SessionState.revoked) {
      _showSessionRevokedDialog();
    }
  }
  
  void _showSessionRevokedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Session Expired'),
        content: Text('Your session has been revoked. Please login again.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Navigate to login
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _sessionManager.removeListener(_onSessionStateChanged);
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return widget.loadingWidget ?? 
        Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
    }
    
    return ChangeNotifierProvider<SessionManager>.value(
      value: _sessionManager,
      child: widget.child,
    );
  }
}

// Helper widget to access session
class SessionConsumer extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    SessionManager session,
    Widget? child,
  ) builder;
  final Widget? child;
  
  const SessionConsumer({
    Key? key,
    required this.builder,
    this.child,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: builder,
      child: child,
    );
  }
}
```

## 8.6 Usage in Main App

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'auth/widgets/session_provider.dart';
import 'auth/services/session_manager.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SessionProvider(
      onStateChanged: (state) {
        // Handle global session state changes
        if (state == SessionState.unauthenticated) {
          // Navigate to login
        }
      },
      child: MaterialApp(
        title: 'Flutter Auth',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: AuthGate(),
        routes: {
          '/login': (context) => LoginScreen(),
          '/home': (context) => HomeScreen(),
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SessionConsumer(
      builder: (context, session, child) {
        switch (session.state) {
          case SessionState.authenticated:
            return HomeScreen();
          case SessionState.unauthenticated:
          case SessionState.expired:
          case SessionState.revoked:
            return LoginScreen();
        }
      },
    );
  }
}
```

## Testing

### Test session storage
```dart
// test/session_storage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/auth/services/session_storage.dart';

void main() {
  test('Store and retrieve session', () async {
    await SessionStorage.saveSession(
      accessToken: 'test_access',
      refreshToken: 'test_refresh',
      sessionId: 'test_session',
      expiresIn: 300,
    );
    
    final token = await SessionStorage.getAccessToken();
    expect(token, 'test_access');
    
    final sessionId = await SessionStorage.getSessionId();
    expect(sessionId, 'test_session');
  });
}
```

## Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  flutter_secure_storage: ^9.0.0
  device_info_plus: ^10.0.0
  package_info_plus: ^5.0.0
  provider: ^6.0.0
```

## Security Notes

1. **Secure Storage**: Uses encrypted storage for tokens
2. **Token Refresh**: Automatic refresh before expiry
3. **Session Revocation**: Immediate logout on revocation
4. **Device Binding**: Sessions tied to device ID
5. **Memory Management**: Clear sensitive data from memory

## Next Steps

✅ Secure session storage
✅ Session manager with refresh
✅ Device information tracking
✅ Session provider widget
✅ Integration with main app

Continue to [Part 9: Flutter Interceptors](./part9-flutter-interceptors.md)
