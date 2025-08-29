import 'package:shared_preferences/shared_preferences.dart';

class TenantPrefs {
  static const _kTenantKey = 'tenant_slug';

  /// Returns the currently saved tenant slug, or null if not set.
  static Future<String?> getTenant() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kTenantKey);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  /// Persist the tenant slug. Pass a non-empty string.
  static Future<void> setTenant(String tenant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTenantKey, tenant);
  }

  /// Remove the saved tenant.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTenantKey);
  }
}
