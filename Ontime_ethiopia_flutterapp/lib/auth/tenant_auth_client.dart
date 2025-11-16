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
    final me = Map<String, dynamic>.from(res.data as Map);
    _client.setLastMe(me);
    return me;
  }

  Future<Tokens> socialLogin({
    required String tenantId,
    required String provider, // 'google' | 'apple'
    required String token, // id token (google/apple)
    String? nonce, // apple nonce when applicable
    Map<String, dynamic>? userData,
    bool allowCreate = false,
  }) async {
    setTenant(tenantId);
    final res = await _client.post('/social/login/', data: {
      'provider': provider,
      'token': token,
      'allow_create': allowCreate,
      if (nonce != null) 'nonce': nonce,
      if (userData != null) 'user_data': userData,
    });
    final data = res.data as Map;
    final access = data['access'] as String?;
    if (access == null || access.isEmpty) {
      throw DioException(
        requestOptions: res.requestOptions,
        message: 'No access token from social login',
      );
    }
    _client.setAccessToken(access);
    final refresh = data['refresh'] as String?;
    return Tokens(access: access, refresh: refresh);
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final res = await _client.put('/me/', data: data);
    final me = Map<String, dynamic>.from(res.data as Map);
    _client.setLastMe(me);
    return me;
  }

  Future<void> logout() async {
    await _client.post('/logout/');
    _client.setAccessToken(null);
  }

  // ---- Series APIs ----
  Future<List<Map<String, dynamic>>> seriesShows(
      {Map<String, dynamic>? queryParameters}) async {
    final res =
        await _client.get('/series/shows/', queryParameters: queryParameters);
    final data = res.data;
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    // If paginated in future, support {results: []}
    if (data is Map && data['results'] is List) {
      final list = data['results'] as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> seriesCategories() async {
    final res = await _client.get('/series/categories/');
    final data = res.data;
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map && data['results'] is List) {
      final list = data['results'] as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> seriesSeasonsForShow(
      String showSlug) async {
    final res = await _client.get('/series/seasons/', queryParameters: {
      'show': showSlug,
    });
    final data = res.data;
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map && data['results'] is List) {
      final list = data['results'] as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> seriesEpisodesForSeason(
      int seasonId) async {
    // Fetch all episodes for a season, following DRF-style pagination if present.
    final List<Map<String, dynamic>> all = [];
    int page = 1;
    while (true) {
      final res = await _client.get(
        '/series/episodes/',
        queryParameters: {
          'season': seasonId,
          'page': page,
        },
      );
      final data = res.data;
      List<dynamic> pageItems;
      if (data is List) {
        // Unpaginated response: treat as full list and return once.
        pageItems = data;
      } else if (data is Map && data['results'] is List) {
        pageItems = data['results'] as List;
      } else {
        break;
      }

      if (pageItems.isEmpty) {
        break;
      }
      all.addAll(pageItems.map((e) => Map<String, dynamic>.from(e as Map)));

      // If response is not a paginated map with a next page indicator, stop.
      if (data is! Map || data['next'] == null) {
        break;
      }
      page += 1;
    }
    return all;
  }

  Future<Map<String, dynamic>> seriesEpisodePlay(int episodeId) async {
    final res = await _client.get('/series/episodes/$episodeId/play/');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> seriesEpisodeLike(int episodeId) async {
    await _client.post('/series/episodes/$episodeId/like/');
  }

  Future<void> seriesEpisodeUnlike(int episodeId) async {
    await _client.post('/series/episodes/$episodeId/unlike/');
  }

  // ---- Dev utilities (development only) ----
  Future<void> devReset({String? baseUrl}) async {
    if (baseUrl != null && baseUrl.isNotEmpty) {
      _client.setBaseUrl(baseUrl);
    }
    try {
      await _client.cookieJar.deleteAll();
    } catch (_) {}
    _client.setAccessToken(null);
  }

  // ---- View tracking APIs ----
  Future<Map<String, dynamic>> viewStart({
    required int episodeId,
    required String playbackToken,
    String? deviceId,
  }) async {
    final res = await _client.post('/series/views/start', data: {
      'episode_id': episodeId,
      'playback_token': playbackToken,
      if (deviceId != null) 'device_id': deviceId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> viewHeartbeat({
    required int viewId,
    required String playbackToken,
    required int secondsWatched,
    String state = 'playing',
    int? positionSeconds,
  }) async {
    await _client.post('/series/views/heartbeat', data: {
      'view_id': viewId,
      'playback_token': playbackToken,
      'seconds_watched': secondsWatched,
      'player_state': state,
      if (positionSeconds != null) 'position_seconds': positionSeconds,
    });
  }

  Future<void> viewComplete({
    required int viewId,
    required String playbackToken,
    required int totalSeconds,
  }) async {
    await _client.post('/series/views/complete', data: {
      'view_id': viewId,
      'playback_token': playbackToken,
      'total_seconds': totalSeconds,
      'completed': true,
    });
  }
}
