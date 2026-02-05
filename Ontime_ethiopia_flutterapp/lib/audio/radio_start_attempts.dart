import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../api_client.dart';
import 'audio_player_service.dart';
import 'http_stream_audio_source.dart';
import 'radio_playback_waits.dart';

class RadioStartResult {
  final String? successUrl;
  final Exception? lastError;

  const RadioStartResult({required this.successUrl, required this.lastError});

  bool get isSuccess => lastError == null && successUrl != null;
}

class RadioStartAttempts {
  final AudioPlayerService playerService;
  final RadioPlaybackWaits waits;

  RadioStartAttempts(this.playerService)
      : waits = RadioPlaybackWaits(playerService);

  bool _isBackendRadioProxyUrl(String u) {
    final api = Uri.tryParse(kApiBase);
    final uri = Uri.tryParse(u);
    if (api == null || uri == null) return false;
    if (api.host.toLowerCase() != uri.host.toLowerCase()) return false;
    final p = uri.path.toLowerCase();
    return p.contains('/api/live/radio/') && p.contains('/stream');
  }

  Future<RadioStartResult> start({
    required List<String> urls,
    required String tenant,
    required String? token,
    required bool Function() isStale,
    required void Function() onBuffering,
    required void Function() onPausedBySystem,
    Duration overallBudget = const Duration(seconds: 18),
  }) async {
    Exception? lastErr;
    final startedAt = DateTime.now();
    final maxUrls = urls.length < 3 ? urls.length : 3;
    String? successUrl;

    for (var i = 0; i < maxUrls; i++) {
      if (isStale()) {
        return const RadioStartResult(successUrl: null, lastError: null);
      }

      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed > overallBudget) {
        lastErr = Exception('Timeout starting radio');
        break;
      }
      final remaining = overallBudget - elapsed;
      final u = urls[i];

      try {
        successUrl = u;

        AudioSource src;
        if (_isBackendRadioProxyUrl(u)) {
          final bearer = token;
          if ((bearer ?? '').isEmpty) {
            throw Exception('Missing access token');
          }
          src = HttpStreamAudioSource(
            Uri.parse(u),
            {
              'Authorization': 'Bearer $bearer',
              'X-Tenant-Id': tenant,
              'Accept': 'application/octet-stream',
            },
          );
        } else {
          src = AudioSource.uri(Uri.parse(u));
        }

        await playerService.setSource(src).timeout(
            remaining < const Duration(seconds: 8)
                ? remaining
                : const Duration(seconds: 8));
        if (isStale()) {
          return const RadioStartResult(successUrl: null, lastError: null);
        }

        onBuffering();

        await waits.waitReadyOrBuffering(
          remaining < const Duration(seconds: 8)
              ? remaining
              : const Duration(seconds: 8),
        );
        if (isStale()) {
          return const RadioStartResult(successUrl: null, lastError: null);
        }

        await playerService.play();

        final waitBudget = remaining < const Duration(seconds: 7)
            ? remaining
            : const Duration(seconds: 7);
        await waits.waitPlayingWithInterruption(
          waitBudget: waitBudget,
          isStale: isStale,
          onPausedBySystem: onPausedBySystem,
        );

        lastErr = null;
        break;
      } catch (e) {
        if (playerService.isPlaying) {
          lastErr = null;
          break;
        }
        successUrl = null;
        lastErr = Exception(e.toString());
        try {
          await playerService.stop();
        } catch (_) {}
      }
    }

    return RadioStartResult(successUrl: successUrl, lastError: lastErr);
  }
}
