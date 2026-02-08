import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'radio_audio_handler.dart';

class RadioAudioService {
  static bool _inited = false;
  static Future<void>? _initFuture;
  static late final RadioAudioHandler handler;

  static bool get isInitialized => _inited;

  static Future<void> stopService() async {
    if (!_inited) return;
    try {
      await handler.stop();
    } catch (_) {}
  }

  static Future<void> ensureInitialized(AudioPlayer player) async {
    if (_inited) return;
    if (_initFuture != null) {
      return _initFuture;
    }
    final completer = Completer<void>();
    _initFuture = completer.future;
    try {
      final h = RadioAudioHandler(player);
      await AudioService.init(
        builder: () => h,
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.muler.on_time.radio',
          androidNotificationChannelName: 'Radio Playback',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: true,
        ),
      );
      handler = h;
      _inited = true;
      completer.complete();
    } catch (e, st) {
      _initFuture = null;
      _inited = false;
      completer.completeError(e, st);
      rethrow;
    }
  }

  static Future<void> setNowPlaying({
    required String id,
    required String title,
    Uri? artUri,
  }) async {
    if (!_inited) return;
    final item = MediaItem(id: id, title: title, artUri: artUri);
    handler.setNowPlaying(item);
  }
}
