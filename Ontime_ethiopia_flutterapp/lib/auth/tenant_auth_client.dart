import 'package:dio/dio.dart';
import '../api_client.dart';

class Tokens {
  final String access;
  final String?
      refresh; // backend moves refresh into HttpOnly cookie; may be null
  Tokens({required this.access, this.refresh});
}

abstract class TokenStore {
  Future<void> setTokens(String access, String? refresh);
  Future<String?> getAccess();
  Future<String?> getRefresh();
  Future<void> clear();
}

class InMemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  Future<void> setTokens(String access, String? refresh) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }

  @override
  Future<String?> getAccess() async => _access;

  @override
  Future<String?> getRefresh() async => _refresh;
}

class AuthApi {
  final ApiClient _client = ApiClient();

  // Ensure tenant header is set for subsequent calls
  void setTenant(String tenantId) => _client.setTenant(tenantId);

  Future<Tokens> login({
    required String tenantId,
    required String username,
    required String password,
  }) async {
    setTenant(tenantId);
    final res = await _client.post('/token/', data: {
      'username': username,
      'password': password,
    });
    final data = res.data as Map;
    final access = data['access'] as String?;
    if (access == null) {
      throw DioException(
          requestOptions: res.requestOptions, message: 'No access token');
    }
    _client.setAccessToken(access);
    return Tokens(access: access, refresh: null);
  }

  Future<Tokens> register({
    required String tenantId,
    required String email,
    required String password,
  }) async {
    setTenant(tenantId);
    final res = await _client.post('/register/', data: {
      'email': email,
      'password': password,
    });
    final data = res.data as Map;
    final access = data['access'] as String?;
    if (access == null) {
      throw DioException(
          requestOptions: res.requestOptions, message: 'No access token');
    }
    _client.setAccessToken(access);
    return Tokens(access: access, refresh: null);
  }

  Future<Map<String, dynamic>> me() async {
    final res = await _client.get('/me/');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> logout() async {
    await _client.post('/logout/');
    _client.setAccessToken(null);
  }
}
