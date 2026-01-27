import 'package:flutter/foundation.dart';
import '../api_client.dart';

class ChannelsService {
  final ApiClient _client;
  ChannelsService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Map<String, dynamic>?> getChannel(String slug) async {
    try {
      final res = await _client.get('/channels/$slug/');
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChannelsService] getChannel failed: $e');
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> getPlaylistDetail(String id) async {
    try {
      final res = await _client.get('/channels/playlists/$id/');
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChannelsService] getPlaylistDetail failed: $e');
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> getPlaylists(String slug, {int page = 1}) async {
    try {
      final res = await _client.get('/channels/playlists/', queryParameters: {
        'channel': slug,
        'is_active': 'true',
        'page': page.toString(),
      });
      return _normalizePaginated(res.data);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChannelsService] getPlaylists failed: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPlaylistVideos(String playlistId,
      {int page = 1}) async {
    try {
      final res = await _client.get('/channels/videos/', queryParameters: {
        'playlist': playlistId,
        'page': page.toString(),
      });
      return _normalizePaginated(res.data);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChannelsService] getPlaylistVideos failed: $e');
      }
      rethrow;
    }
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
