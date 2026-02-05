import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'channel_now_playing.dart';
import '../../features/series/mini_player/mini_player_manager.dart';

class ChannelMiniPlayerManager {
  ChannelMiniPlayerManager._();
  static final ChannelMiniPlayerManager I = ChannelMiniPlayerManager._();

  final ValueNotifier<ChannelNowPlaying?> nowPlaying =
      ValueNotifier<ChannelNowPlaying?>(null);
  final ValueNotifier<bool> isMinimized = ValueNotifier<bool>(false);
  final ValueNotifier<Widget?> floatingPlayer = ValueNotifier<Widget?>(null);
  final ValueNotifier<bool> isSuppressed = ValueNotifier<bool>(false);
  final ValueNotifier<bool> hideGlobalBottomOverlays =
      ValueNotifier<bool>(false);
  final ValueNotifier<YoutubePlayerController?> ytController =
      ValueNotifier<YoutubePlayerController?>(null);
  final ValueNotifier<bool> autoPlayNext = ValueNotifier<bool>(false);
  VoidCallback? _pausePlayback;

  void setNowPlaying(ChannelNowPlaying now) {
    try {
      // Ensure only one floating player is active globally.
      MiniPlayerManager.I.clear();
    } catch (_) {}
    nowPlaying.value = now;
    if (kDebugMode) {
      debugPrint('[ChannelMiniPlayerManager] setNowPlaying ${now.videoId}');
    }
  }

  void setMinimized(bool value) {
    isMinimized.value = value;
    if (kDebugMode) {
      debugPrint('[ChannelMiniPlayerManager] setMinimized=$value');
    }
    if (!value) {
      nowPlaying.value = nowPlaying.value;
    }
  }

  void setSuppressed(bool value) {
    isSuppressed.value = value;
    if (kDebugMode) {
      debugPrint('[ChannelMiniPlayerManager] setSuppressed=$value');
    }
  }

  void setHideGlobalBottomOverlays(bool value) {
    hideGlobalBottomOverlays.value = value;
    if (kDebugMode) {
      debugPrint('[ChannelMiniPlayerManager] hideGlobalBottomOverlays=$value');
    }
  }

  void setPauseCallback(VoidCallback? callback) {
    _pausePlayback = callback;
  }

  void pause() {
    if (kDebugMode) {
      debugPrint('[ChannelMiniPlayerManager] pause');
    }
    _pausePlayback?.call();
  }

  void update({
    bool? isPlaying,
    String? title,
    String? thumbnailUrl,
    VoidCallbackFn? onTogglePlayPause,
    VoidCallbackFn? onExpand,
  }) {
    final current = nowPlaying.value;
    if (current == null) return;
    nowPlaying.value = current.copyWith(
      isPlaying: isPlaying,
      title: title,
      thumbnailUrl: thumbnailUrl,
      onTogglePlayPause: onTogglePlayPause,
      onExpand: onExpand,
    );
  }

  void clear() {
    try {
      _pausePlayback?.call();
    } catch (_) {}
    nowPlaying.value = null;
    isMinimized.value = false;
    floatingPlayer.value = null;
    isSuppressed.value = false;
    _pausePlayback = null;
    ytController.value = null;
    autoPlayNext.value = autoPlayNext.value;
    if (kDebugMode) {
      debugPrint('[ChannelMiniPlayerManager] clear');
      debugPrintStack(label: '[ChannelMiniPlayerManager] clear stack');
    }
  }
}
