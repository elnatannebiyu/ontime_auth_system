import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../auth/tenant_auth_client.dart';

class SeriesService {
  final AuthApi api;
  final String tenantId;

  static final Map<String, Future<Map<String, dynamic>>> _inFlightReminder =
      <String, Future<Map<String, dynamic>>>{};
  static final Map<String, Map<String, dynamic>> _reminderCache =
      <String, Map<String, dynamic>>{};
  static final Map<String, DateTime> _reminderCacheAt = <String, DateTime>{};
  static const Duration _reminderCacheTtl = Duration(seconds: 30);

  SeriesService({required this.api, required this.tenantId});

  Future<List<Map<String, dynamic>>> getShows() async {
    api.setTenant(tenantId);
    try {
      return await api.seriesShows();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getShows error: $e');
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getHeroRandomShows({int limit = 5}) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesHeroRandom(limit: limit);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getHeroRandomShows error: $e');
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getTrendingShows() async {
    api.setTenant(tenantId);
    try {
      return await api.seriesShows(queryParameters: {'trending': 1});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getTrendingShows error: $e');
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getNewReleases() async {
    api.setTenant(tenantId);
    try {
      return await api.seriesShows(queryParameters: {'new': 1});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getNewReleases error: $e');
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    api.setTenant(tenantId);
    try {
      return await api.seriesCategories();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getCategories error: $e');
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getShowsByCategory(String slug) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesShows(queryParameters: {'category': slug});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getShowsByCategory error: $e');
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getSeasons(String showSlug) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesSeasonsForShow(showSlug);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getSeasons error: $e');
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getEpisodes(int seasonId) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesEpisodesForSeason(seasonId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getEpisodes error: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPlay(int episodeId) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesEpisodePlay(episodeId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getPlay error: $e');
      }
      rethrow;
    }
  }

  // --- Reminders ---
  Future<Map<String, dynamic>> getReminderStatus(String showSlug) async {
    api.setTenant(tenantId);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      return <String, dynamic>{
        'has_reminder': false,
        'is_active': false,
        'id': null,
      };
    }

    final cachedAt = _reminderCacheAt[showSlug];
    final cached = _reminderCache[showSlug];
    if (cachedAt != null && cached != null) {
      if (DateTime.now().difference(cachedAt) <= _reminderCacheTtl) {
        return Map<String, dynamic>.from(cached);
      }
    }

    final existing = _inFlightReminder[showSlug];
    if (existing != null) return existing;

    try {
      final fut = api.seriesReminderStatus(showSlug);
      _inFlightReminder[showSlug] = fut;
      final res = await fut;
      _reminderCache[showSlug] = Map<String, dynamic>.from(res);
      _reminderCacheAt[showSlug] = DateTime.now();
      return Map<String, dynamic>.from(res);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] getReminderStatus error: $e');
      }
      return <String, dynamic>{
        'has_reminder': false,
        'is_active': false,
        'id': null,
      };
    } finally {
      _inFlightReminder.remove(showSlug);
    }
  }

  Future<Map<String, dynamic>> createReminder(String showSlug) async {
    api.setTenant(tenantId);
    try {
      return await api.seriesCreateReminder(showSlug);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] createReminder error: $e');
      }
      rethrow;
    }
  }

  Future<void> deleteReminder(int id) async {
    api.setTenant(tenantId);
    try {
      await api.seriesDeleteReminder(id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SeriesService] deleteReminder error: $e');
      }
      rethrow;
    }
  }
}
