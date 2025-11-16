import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight persistent cache for Home "Trending" shows and "New releases" shorts.
/// Uses SharedPreferences with JSON-encoded lists per tenant.
class HomeTrendingCache {
  static const _kTrendingPrefix = 'cache.trending_shows.'; // + tenant
  static const _kShortsPrefix = 'cache.new_shorts.'; // + tenant

  static Future<void> saveTrending(
      String tenant, List<Map<String, dynamic>> shows) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kTrendingPrefix$tenant';
    try {
      final jsonStr = jsonEncode(shows);
      await prefs.setString(key, jsonStr);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> loadTrending(String tenant) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kTrendingPrefix$tenant';
    final jsonStr = prefs.getString(key);
    if (jsonStr == null || jsonStr.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  static Future<void> saveShorts(
      String tenant, List<Map<String, dynamic>> shorts) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kShortsPrefix$tenant';
    try {
      final jsonStr = jsonEncode(shorts);
      await prefs.setString(key, jsonStr);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> loadShorts(String tenant) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kShortsPrefix$tenant';
    final jsonStr = prefs.getString(key);
    if (jsonStr == null || jsonStr.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }
}
