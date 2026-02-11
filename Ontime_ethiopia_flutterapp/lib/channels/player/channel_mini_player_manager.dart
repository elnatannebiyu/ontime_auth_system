import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  final ValueNotifier<double> miniPlayerHeight = ValueNotifier<double>(0);
  VoidCallback? _pausePlayback;
  ValueSetter<ChannelNowPlaying>? _expandHandler;
  String? _lastPlaylistId;
  String? _lastPlaylistTitle;
  String? _pendingOpenPlaylistId;
  bool _pendingOpenFromMini = false;

  void setNowPlaying(ChannelNowPlaying now) {
    try {
      // Ensure only one floating player is active globally.
      MiniPlayerManager.I.clear();
    } catch (_) {}
    if ((now.playlistId ?? '').isNotEmpty) {
      _lastPlaylistId = now.playlistId;
      _lastPlaylistTitle = now.playlistTitle ?? now.title;
    }
    nowPlaying.value = now;
    if (kDebugMode) {
      debugPrint('[ChannelMiniPlayerManager] setNowPlaying ${now.videoId}');
    }
  }

  String? get lastPlaylistId => _lastPlaylistId;
  String? get lastPlaylistTitle => _lastPlaylistTitle;

  void setPendingOpenFromMini(String playlistId) {
    _pendingOpenPlaylistId = playlistId;
    _pendingOpenFromMini = true;
  }

  bool consumePendingOpenFromMini(String playlistId) {
    final match = _pendingOpenFromMini && _pendingOpenPlaylistId == playlistId;
    _pendingOpenFromMini = false;
    _pendingOpenPlaylistId = null;
    return match;
  }

  void setFloatingPlayer(Widget? player) {
    if (floatingPlayer.value == player) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (floatingPlayer.value == player) return;
        floatingPlayer.value = player;
      });
      return;
    }
    floatingPlayer.value = player;
  }

  void setMinimized(bool value) {
    if (isMinimized.value == value) return;
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

  void setExpandHandler(ValueSetter<ChannelNowPlaying>? handler) {
    _expandHandler = handler;
  }

  void requestExpand(ChannelNowPlaying now) {
    debugPrint(
        '[ChannelMiniPlayerManager] requestExpand playlistId=${now.playlistId} title=${now.title}');
    _expandHandler?.call(now);
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

  void clear({bool disposeController = true}) {
    try {
      _pausePlayback?.call();
    } catch (_) {}
    if (disposeController) {
      final controller = ytController.value;
      ytController.value = null;
      if (controller != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            controller.dispose();
          } catch (_) {}
        });
      }
    }
    nowPlaying.value = null;
    isMinimized.value = false;
    floatingPlayer.value = null;
    isSuppressed.value = false;
    miniPlayerHeight.value = 0;
    if (disposeController) {
      _pausePlayback = null;
    }
    _lastPlaylistId = null;
    _lastPlaylistTitle = null;
    if (!disposeController && ytController.value == null) {
      ytController.value = null;
    }
    autoPlayNext.value = autoPlayNext.value;
    if (kDebugMode) {
      debugPrint('[ChannelMiniPlayerManager] clear');
      debugPrintStack(label: '[ChannelMiniPlayerManager] clear stack');
    }
  }

  void setMiniPlayerHeight(double value) {
    if (miniPlayerHeight.value == value) return;
    miniPlayerHeight.value = value;
  }
}
