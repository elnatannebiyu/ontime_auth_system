import '../api_client.dart';

class ChannelsService {
  final ApiClient _client;
  ChannelsService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Map<String, dynamic>?> getChannel(String slug) async {
    try {
      final res = await _client.get('/channels/$slug/');
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> getPlaylists(String slug, {int page = 1}) async {
    final res = await _client.get('/channels/playlists/', queryParameters: {
      'channel': slug,
      'is_active': 'true',
      'page': page.toString(),
    });
    return _normalizePaginated(res.data);
  }

  Future<Map<String, dynamic>> getPlaylistVideos(String playlistId,
      {int page = 1}) async {
    final res = await _client.get('/channels/videos/', queryParameters: {
      'playlist': playlistId,
      'page': page.toString(),
    });
    return _normalizePaginated(res.data);
  }

  Map<String, dynamic> _normalizePaginated(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final results = raw['results'];
      return {
        'results': results is List ? List<dynamic>.from(results) : <dynamic>[],
        'next': raw['next'],
        'previous': raw['previous'],
        'count': raw['count'],
      };
    } else if (raw is List) {
      return {
        'results': List<dynamic>.from(raw),
        'next': null,
        'previous': null,
        'count': raw.length,
      };
    }
    return {'results': <dynamic>[], 'next': null, 'previous': null};
  }
}
