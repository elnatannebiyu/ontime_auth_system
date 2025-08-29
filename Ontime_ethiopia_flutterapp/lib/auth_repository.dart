import 'package:dio/dio.dart';
import 'api_client.dart';

class AuthRepository {
  final _client = ApiClient();

  Future<void> login(String username, String password) async {
    final res = await _client.post('/token/', data: {
      'username': username,
      'password': password,
    });
    final map = res.data as Map;
    final access = map['access'] as String?;
    if (access == null) {
      throw DioException(requestOptions: res.requestOptions, message: 'No access in response');
    }
    _client.setAccessToken(access);
    // Refresh cookie set by server is now saved inside CookieJar (HttpOnly) automatically
  }

  Future<void> logout() async {
    await _client.post('/logout/');
    _client.setAccessToken(null);
  }

  Future<Map<String, dynamic>> me() async {
    final res = await _client.get('/me/');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> adminOnly() async {
    final res = await _client.get('/admin-only/');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final res = await _client.get('/users/');
    final data = res.data as Map;
    return List<Map<String, dynamic>>.from(data['results'] as List);
  }

  bool get isLoggedIn => _client.getAccessToken() != null;
  
  String? get currentToken => _client.getAccessToken();
}
