List<String> resolveRadioStreamUrls({
  required String slug,
  required String baseUrl,
  required String primary,
  required String backup,
  required String tenant,
  required bool hasToken,
}) {
  bool isHttpsUrl(String u) {
    final uri = Uri.tryParse(u);
    return uri != null && uri.scheme.toLowerCase() == 'https';
  }

  String norm(String s) => s.trim();
  final cands = <String>[];
  // Try backend proxy first only when it's safe and usable.
  // - If the API base is http/localhost, Android may block it (cleartext).
  // - If we don't have a token, the proxy endpoint returns 401.
  final baseApi = baseUrl;
  final uri = Uri.tryParse(baseApi);
  final isLocalHost = (uri?.host.toLowerCase() ?? '') == '127.0.0.1' ||
      (uri?.host.toLowerCase() ?? '') == 'localhost';
  final isHttps = (uri?.scheme.toLowerCase() ?? '') == 'https';
  if (isHttps && !isLocalHost && hasToken) {
    cands.add('$baseApi/api/live/radio/$slug/stream/?tenant=$tenant');
  }
  if (primary.isNotEmpty && isHttpsUrl(primary)) cands.add(norm(primary));
  if (backup.isNotEmpty && backup != primary && isHttpsUrl(backup)) {
    cands.add(norm(backup));
  }
  // For roots or missing mountpoints, try common aliases (avoid exploding attempts for token hosts)
  bool isZeno(String u) => u.contains('zeno.fm') || u.contains('stream-');
  final tokenHost = isZeno(primary) || isZeno(backup);
  if (!tokenHost) {
    for (final base in [primary, backup]) {
      if (base.isEmpty) continue;
      if (!isHttpsUrl(base)) continue;
      final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      cands.add('$b/live');
      cands.add('$b/live.mp3');
      cands.add('$b/stream');
      cands.add('$b/stream.mp3');
      cands.add('$b/;stream/1');
      cands.add('$b/;?type=http');
      cands.add('$b/;');
    }
  } else {
    // Tokenized streams usually only work with exact URL; try minimal safe suffixes
    for (final base in [primary, backup]) {
      if (base.isEmpty) continue;
      if (!isHttpsUrl(base)) continue;
      final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      cands.add('$b/live');
      cands.add('$b/live.mp3');
    }
  }
  // Deduplicate while preserving order
  final seen = <String>{};
  final out = <String>[];
  for (final u in cands) {
    if (u.isEmpty) continue;
    if (seen.add(u)) out.add(u);
  }
  return out;
}

List<String> resolveRadioStreamUrlsHttpsOnly({
  required String primary,
  required String backup,
}) {
  bool isHttps(String u) {
    final uri = Uri.tryParse(u);
    return uri != null && uri.scheme.toLowerCase() == 'https';
  }

  String norm(String s) => s.trim();
  final cands = <String>[];
  if (primary.isNotEmpty && isHttps(primary)) cands.add(norm(primary));
  if (backup.isNotEmpty && backup != primary && isHttps(backup)) {
    cands.add(norm(backup));
  }

  final seen = <String>{};
  final out = <String>[];
  for (final u in cands) {
    if (u.isEmpty) continue;
    if (seen.add(u)) out.add(u);
    if (out.length >= 3) break;
  }
  return out;
}
