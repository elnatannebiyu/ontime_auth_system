import 'package:flutter/foundation.dart';
import 'series_now_playing.dart';

class MiniPlayerManager {
  MiniPlayerManager._();
  static final MiniPlayerManager I = MiniPlayerManager._();

  final ValueNotifier<SeriesNowPlaying?> nowPlaying =
      ValueNotifier<SeriesNowPlaying?>(null);

  void setNowPlaying(SeriesNowPlaying snp) {
    nowPlaying.value = snp;
  }

  void update({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    String? title,
    String? thumbnailUrl,
    VoidCallbackFn? onTogglePlayPause,
    VoidCallbackFn? onExpand,
  }) {
    final current = nowPlaying.value;
    if (current == null) return;
    nowPlaying.value = current.copyWith(
      position: position,
      duration: duration,
      isPlaying: isPlaying,
      title: title,
      thumbnailUrl: thumbnailUrl,
      onTogglePlayPause: onTogglePlayPause,
      onExpand: onExpand,
    );
  }

  void clear() {
    nowPlaying.value = null;
  }

  void forceStopAndClear() {
    final current = nowPlaying.value;
    if (current != null) {
      try {
        if (current.isPlaying && current.onTogglePlayPause != null) {
          current.onTogglePlayPause!();
        }
      } catch (_) {}
    }
    nowPlaying.value = null;
  }
}
