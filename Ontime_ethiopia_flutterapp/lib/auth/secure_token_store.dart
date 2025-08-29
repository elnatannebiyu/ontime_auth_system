import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'tenant_auth_client.dart';

class SecureTokenStore implements TokenStore {
  static const _keyAccess = 'access_token';
  static const _keyRefresh = 'refresh_token';
  final FlutterSecureStorage _storage;

  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> clear() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
  }

  @override
  Future<String?> getAccess() => _storage.read(key: _keyAccess);

  @override
  Future<String?> getRefresh() => _storage.read(key: _keyRefresh);

  @override
  Future<void> setTokens(String access, String? refresh) async {
    await _storage.write(key: _keyAccess, value: access);
    if (refresh != null) {
      await _storage.write(key: _keyRefresh, value: refresh);
    }
  }
}
