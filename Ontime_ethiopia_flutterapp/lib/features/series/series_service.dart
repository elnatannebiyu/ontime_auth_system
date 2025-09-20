import 'package:flutter/foundation.dart';
import '../../auth/tenant_auth_client.dart';

class SeriesService {
  final AuthApi api;
  final String tenantId;

  SeriesService({required this.api, required this.tenantId});

  Future<List<Map<String, dynamic>>> getShows() async {
    api.setTenant(tenantId);
    try {
      return await api.seriesShows();
    } catch (e) {
      debugPrint('[SeriesService] getShows error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getSeasons(String showSlug) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesSeasonsForShow(showSlug);
    } catch (e) {
      debugPrint('[SeriesService] getSeasons error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getEpisodes(int seasonId) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesEpisodesForSeason(seasonId);
    } catch (e) {
      debugPrint('[SeriesService] getEpisodes error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPlay(int episodeId) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesEpisodePlay(episodeId);
    } catch (e) {
      debugPrint('[SeriesService] getPlay error: $e');
      rethrow;
    }
  }
}
