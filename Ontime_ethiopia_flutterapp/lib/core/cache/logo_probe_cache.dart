import 'package:dio/dio.dart';

class LogoProbeCache {
  LogoProbeCache._internal();
  static final LogoProbeCache instance = LogoProbeCache._internal();

  final Map<String, _LogoProbeResult> _cache = {};

  /// Returns true if the logo URL appears reachable.
  /// Uses a time-based cache so successful probes are not repeated every time.
  Future<bool> ensureAvailable(
    String url, {
    Map<String, String>? headers,
    Duration ttl = const Duration(minutes: 5),
  }) async {
    if (url.isEmpty) return false;
    final now = DateTime.now();
    final existing = _cache[url];
    if (existing != null) {
      // If within TTL, trust cached result
      if (now.difference(existing.checkedAt) <= ttl) {
        return existing.ok;
      }
    }
    try {
      final res = await Dio().head(
        url,
        options: Options(
          headers: headers,
          validateStatus: (s) => true,
        ),
      );
      final code = res.statusCode ?? 0;
      final ok = code >= 200 && code < 300;
      _cache[url] = _LogoProbeResult(ok: ok, checkedAt: now);
      return ok;
    } catch (_) {
      _cache[url] = _LogoProbeResult(ok: false, checkedAt: now);
      return false;
    }
  }
}

class _LogoProbeResult {
  final bool ok;
  final DateTime checkedAt;
  _LogoProbeResult({required this.ok, required this.checkedAt});
}
