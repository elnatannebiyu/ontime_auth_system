import 'dart:io';

import 'package:just_audio/just_audio.dart';

class HttpStreamAudioSource extends StreamAudioSource {
  HttpStreamAudioSource(this._uri, [Map<String, String>? headers])
      : _headers = headers ?? <String, String>{};

  final Uri _uri;
  final Map<String, String> _headers;

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final req = await _client.getUrl(_uri);
    _headers.forEach(req.headers.set);
    if (start != null || end != null) {
      final s = start ?? 0;
      final e = end != null ? end - 1 : null;
      req.headers.set('Range', e != null ? 'bytes=$s-$e' : 'bytes=$s-');
    }

    final res = await req.close();
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw HttpException('HTTP ${res.statusCode}', uri: _uri);
    }

    int? totalLength;
    // When server returns 206, prefer Content-Range total length if present.
    // Example: Content-Range: bytes 0-1023/12345
    final contentRange = res.headers.value('content-range');
    if (contentRange != null) {
      final m = RegExp(r'^bytes\s+\d+-\d+\/(\d+|\*)$', caseSensitive: false)
          .firstMatch(contentRange.trim());
      final total = m?.group(1);
      if (total != null && total != '*') {
        totalLength = int.tryParse(total);
      }
    }

    final ct = res.headers.contentType?.mimeType ?? 'audio/mpeg';
    final len = res.contentLength >= 0 ? res.contentLength : null;
    final sourceLen = totalLength ?? len;

    return StreamAudioResponse(
      sourceLength: sourceLen,
      contentLength: len,
      offset: start ?? 0,
      contentType: ct,
      stream: res,
    );
  }
}
