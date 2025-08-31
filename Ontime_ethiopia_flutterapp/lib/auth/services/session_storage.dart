import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:math';

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
