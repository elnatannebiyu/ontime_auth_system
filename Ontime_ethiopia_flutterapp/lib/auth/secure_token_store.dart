import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'tenant_auth_client.dart';

class SecureTokenStore implements TokenStore {
  static const _keyAccess = 'access_token';
  static const _keyRefresh = 'refresh_token';
  final FlutterSecureStorage _storage;
  // In-memory fallback for session-only use when secure write fails
  String? _memAccess;
  String? _memRefresh;

  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  IOSOptions get _iosOptions => const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
        synchronizable: false,
      );
  AndroidOptions get _androidOptions => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

  @override
  Future<void> clear() async {
    await _storage.delete(
        key: _keyAccess, iOptions: _iosOptions, aOptions: _androidOptions);
    await _storage.delete(
        key: _keyRefresh, iOptions: _iosOptions, aOptions: _androidOptions);
    _memAccess = null;
    _memRefresh = null;
  }

  @override
  Future<String?> getAccess() async {
    final v = await _storage.read(
        key: _keyAccess, iOptions: _iosOptions, aOptions: _androidOptions);
    return v ?? _memAccess;
  }

  @override
  Future<String?> getRefresh() async {
    final v = await _storage.read(
        key: _keyRefresh, iOptions: _iosOptions, aOptions: _androidOptions);
    return v ?? _memRefresh;
  }

  @override
  Future<void> setTokens(String access, String? refresh) async {
    // Helper to safely write with delete-on-collision behavior
    Future<void> safeWrite(String key, String value) async {
      try {
        await _storage.write(
            key: key,
            value: value,
            iOptions: _iosOptions,
            aOptions: _androidOptions);
      } on PlatformException catch (e) {
        final codeStr = e.code.toLowerCase();
        final msgStr = (e.message ?? '').toLowerCase();
        // iOS keychain collision (-25299): delete then write again
        if (codeStr.contains('25299') ||
            msgStr.contains('25299') ||
            msgStr.contains('already exists')) {
          await _storage.delete(
              key: key, iOptions: _iosOptions, aOptions: _androidOptions);
          await _storage.write(
              key: key,
              value: value,
              iOptions: _iosOptions,
              aOptions: _androidOptions);
        } else {
          // Fallback to in-memory for session; rethrow to surface if needed
          if (key == _keyAccess) {
            _memAccess = value;
          } else if (key == _keyRefresh) _memRefresh = value;
          rethrow;
        }
      } catch (e) {
        // Any unexpected failure: keep in-memory for this session
        if (key == _keyAccess) {
          _memAccess = value;
        } else if (key == _keyRefresh) _memRefresh = value;
      }
    }

    await safeWrite(_keyAccess, access);
    if (refresh != null) {
      await safeWrite(_keyRefresh, refresh);
    }
  }
}
