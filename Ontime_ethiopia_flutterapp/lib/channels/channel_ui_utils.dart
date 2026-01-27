import '../api_client.dart';

Map<String, String>? authHeadersFor(String url) {
  if (!url.startsWith(kApiBase)) return null;
  final client = ApiClient();
  final token = client.getAccessToken();
  final tenant = client.tenant;
  final headers = <String, String>{};
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  if (tenant != null && tenant.isNotEmpty) headers['X-Tenant-Id'] = tenant;
  return headers.isEmpty ? null : headers;
}

String? thumbFromMap(Map<String, dynamic> m) {
  const keys = [
    'thumbnail',
    'thumbnail_url',
    'thumb',
    'thumb_url',
    'image',
    'image_url',
    'logo',
    'logo_url',
    'poster',
    'poster_url',
    'cover_image',
    'channel_logo_url'
  ];
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.isNotEmpty) return v;
  }
  final t = m['thumbnails'];
  if (t is Map) {
    for (final size in ['maxres', 'standard', 'high', 'medium', 'default']) {
      final s = t[size];
      if (s is Map && s['url'] is String && (s['url'] as String).isNotEmpty) {
        return s['url'] as String;
      }
    }
    if (t['url'] is String && (t['url'] as String).isNotEmpty) {
      return t['url'] as String;
    }
  }
  return null;
}
