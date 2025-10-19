import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight persistent cache for channels per tenant.
/// Stores a JSON list and a lastUpdated timestamp. Non-sensitive data only.
class ChannelCache {
  static const _kPrefix = 'cache.channels.'; // + tenant
  static const _kMetaPrefix = 'cache.channels.meta.'; // + tenant

  /// Save channels list (List<Map>) for a tenant.
  static Future<void> save(String tenant, List<dynamic> channels) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kPrefix$tenant';
    final metaKey = '$_kMetaPrefix$tenant';
    try {
      final jsonStr = jsonEncode(channels);
      await prefs.setString(key, jsonStr);
      await prefs.setString(metaKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Ignore encoding/storage errors silently
    }
  }

  /// Load channels list for a tenant. Returns [] if none.
  static Future<List<dynamic>> load(String tenant) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kPrefix$tenant';
    final jsonStr = prefs.getString(key);
    if (jsonStr == null || jsonStr.isEmpty) return <dynamic>[];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) return decoded;
    } catch (_) {}
    return <dynamic>[];
  }

  /// Get last updated timestamp string, or null.
  static Future<String?> lastUpdated(String tenant) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_kMetaPrefix$tenant');
  }

  /// Optionally clear cache for a tenant (not called on logout by default).
  static Future<void> clear(String tenant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kPrefix$tenant');
    await prefs.remove('$_kMetaPrefix$tenant');
  }
}
