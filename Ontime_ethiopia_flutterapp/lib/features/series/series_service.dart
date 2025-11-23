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

  Future<List<Map<String, dynamic>>> getTrendingShows() async {
    api.setTenant(tenantId);
    try {
      return await api.seriesShows(queryParameters: {'trending': 1});
    } catch (e) {
      debugPrint('[SeriesService] getTrendingShows error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getNewReleases() async {
    api.setTenant(tenantId);
    try {
      return await api.seriesShows(queryParameters: {'new': 1});
    } catch (e) {
      debugPrint('[SeriesService] getNewReleases error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    api.setTenant(tenantId);
    try {
      return await api.seriesCategories();
    } catch (e) {
      debugPrint('[SeriesService] getCategories error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getShowsByCategory(String slug) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesShows(queryParameters: {'category': slug});
    } catch (e) {
      debugPrint('[SeriesService] getShowsByCategory error: $e');
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

  // --- Reminders ---
  Future<Map<String, dynamic>> getReminderStatus(String showSlug) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesReminderStatus(showSlug);
    } catch (e) {
      debugPrint('[SeriesService] getReminderStatus error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createReminder(String showSlug) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesCreateReminder(showSlug);
    } catch (e) {
      debugPrint('[SeriesService] createReminder error: $e');
      rethrow;
    }
  }

  Future<void> deleteReminder(int id) async {
    api.setTenant(tenantId);
    try {
      await api.seriesDeleteReminder(id);
    } catch (e) {
      debugPrint('[SeriesService] deleteReminder error: $e');
      rethrow;
    }
  }
}
