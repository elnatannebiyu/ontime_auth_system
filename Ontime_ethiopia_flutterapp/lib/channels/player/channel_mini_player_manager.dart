import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'channel_now_playing.dart';
import '../../features/series/mini_player/mini_player_manager.dart';
import '../../live/tv_controller.dart';

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
  bool _forceResumeOnExpand = false;
  VoidCallback? _controllerListener;
  bool? _lastControllerPlaying;
  Duration? _lastControllerDuration;
  Duration _lastPlaybackPosition = Duration.zero;
  static const Duration _minReliablePlaybackPosition =
      Duration(milliseconds: 400);

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

  String? get currentVideoId => _controllerVideoId(ytController.value);
  Duration get lastPlaybackPosition => _lastPlaybackPosition;

  void _attachController(YoutubePlayerController controller) {
    _detachController();
    _lastControllerPlaying = controller.value.isPlaying;
    _lastControllerDuration = controller.value.metaData.duration;
    try {
      _lastPlaybackPosition = controller.value.position;
    } catch (_) {}
    _controllerListener = () {
      final value = controller.value;
      final playing = value.isPlaying;
      final dur = value.metaData.duration;
      final pos = value.position;
      final isUnexpectedRestartRegression =
          _lastPlaybackPosition > _minReliablePlaybackPosition &&
              pos <= const Duration(seconds: 1) &&
              playing;
      if (!isUnexpectedRestartRegression) {
        _lastPlaybackPosition = pos;
      }
      final playingChanged = _lastControllerPlaying != playing;
      final durationChanged = _lastControllerDuration != dur;
      if (playingChanged || durationChanged) {
        _lastControllerPlaying = playing;
        _lastControllerDuration = dur;
        update(
          isPlaying: playing,
          duration: dur,
        );
      }
      if (value.playerState == PlayerState.ended) {
        autoPlayNext.value = autoPlayNext.value;
      }
    };
    controller.addListener(_controllerListener!);
  }

  void _detachController() {
    final current = ytController.value;
    if (current != null && _controllerListener != null) {
      try {
        current.removeListener(_controllerListener!);
      } catch (_) {}
    }
    _controllerListener = null;
    _lastControllerPlaying = null;
    _lastControllerDuration = null;
    _lastPlaybackPosition = Duration.zero;
  }

  YoutubePlayerController _createController(String videoId,
      {bool autoPlay = true}) {
    return YoutubePlayerController(
      initialVideoId: videoId,
      flags: YoutubePlayerFlags(
        autoPlay: autoPlay,
        controlsVisibleAtStart: false,
        hideControls: false,
        disableDragSeek: true,
        enableCaption: true,
      ),
    );
  }

  String? _controllerVideoId(YoutubePlayerController? controller) {
    if (controller == null) return null;
    try {
      final id = controller.value.metaData.videoId;
      if (id.isNotEmpty) return id;
    } catch (_) {}
    try {
      // ignore: invalid_use_of_protected_member
      final id = controller.initialVideoId;
      if (id.isNotEmpty) return id;
    } catch (_) {}
    return null;
  }

  void setVideo({
    required String videoId,
    required String title,
    String? playlistId,
    String? playlistTitle,
    String? thumbnailUrl,
    bool? autoPlay,
    bool openIfSame = false,
    VoidCallbackFn? onExpand,
  }) {
    final current = nowPlaying.value;
    final shouldAutoPlay = autoPlay ?? (current?.isPlaying ?? true);
    if (current != null && current.videoId == videoId) {
      update(
        title: title,
        playlistId: playlistId,
        playlistTitle: playlistTitle,
        thumbnailUrl: thumbnailUrl,
        onTogglePlayPause: togglePlayPause,
        onExpand: onExpand ?? current.onExpand,
      );
      if (openIfSame) {
        requestExpand(current.copyWith(onExpand: onExpand ?? current.onExpand));
      }
      return;
    }

    final existingController = ytController.value;
    final existingVideoId = _controllerVideoId(existingController);
    if (existingController != null && existingVideoId == videoId) {
      final playing = existingController.value.isPlaying;
      final position = existingController.value.position;
      final duration = existingController.value.metaData.duration;
      setNowPlaying(
        ChannelNowPlaying(
          videoId: videoId,
          title: title,
          playlistId: playlistId,
          playlistTitle: playlistTitle,
          thumbnailUrl: thumbnailUrl,
          isPlaying: playing,
          playbackPosition: position,
          duration: duration,
          onTogglePlayPause: togglePlayPause,
          onExpand: onExpand,
        ),
      );
      if (openIfSame) {
        requestExpand(nowPlaying.value!);
      }
      return;
    }

    final oldController = ytController.value;
    if (oldController != null) {
      try {
        oldController.pause();
      } catch (_) {}
      try {
        oldController.dispose();
      } catch (_) {}
    }
    final next = _createController(videoId, autoPlay: shouldAutoPlay);
    ytController.value = next;
    _attachController(next);

    setNowPlaying(
      ChannelNowPlaying(
        videoId: videoId,
        title: title,
        playlistId: playlistId,
        playlistTitle: playlistTitle,
        thumbnailUrl: thumbnailUrl,
        isPlaying: shouldAutoPlay,
        playbackPosition: Duration.zero,
        duration: null,
        onTogglePlayPause: togglePlayPause,
        onExpand: onExpand,
      ),
    );
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
    if (phase != SchedulerPhase.idle) {
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
    if (value) {
      final c = ytController.value;
      if (c != null) {
        try {
          update(
            isPlaying: c.value.isPlaying,
            playbackPosition: c.value.position,
            duration: c.value.metaData.duration,
          );
        } catch (_) {}
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final now = nowPlaying.value;
        if (now == null) return;
        if (now.isPlaying != true) return;
        if (now.videoId.startsWith('live:')) {
          try {
            TvController.instance.resumePlayback();
          } catch (_) {}
          return;
        }
        final c = ytController.value;
        if (c == null) return;
        if (c.value.isReady && !c.value.isPlaying) {
          try {
            c.play();
          } catch (_) {}
        }
      });
    }
    if (!value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final now = nowPlaying.value;
        if (now == null) return;
        if (now.videoId.startsWith('live:')) {
          if (now.isPlaying == true) {
            try {
              TvController.instance.resumePlayback();
            } catch (_) {}
          }
          return;
        }
        final c = ytController.value;
        if (c == null) return;
        if (!c.value.isReady) return;
        if (now.isPlaying == true || _forceResumeOnExpand) {
          final resumeAt = lastPlaybackPosition;
          final currentAt = c.value.position;
          final shouldRecoverPosition =
              resumeAt > _minReliablePlaybackPosition &&
                  currentAt <= const Duration(seconds: 1);
          if (kDebugMode) {
            debugPrint(
                '[ChannelMiniPlayerManager] resume check recover=$shouldRecoverPosition at=${resumeAt.inMilliseconds}ms current=${currentAt.inMilliseconds}ms');
          }
          if (shouldRecoverPosition) {
            try {
              c.seekTo(resumeAt);
            } catch (_) {}
          }
          if (!c.value.isPlaying) {
            try {
              c.play();
            } catch (_) {}
          }
          _forceResumeOnExpand = false;
        }
      });
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

  void requestExpandWithPauseResume(ChannelNowPlaying now) {
    if (now.videoId.startsWith('live:')) {
      if (kDebugMode) {
        debugPrint(
            '[ChannelMiniPlayerManager] expand live bypass pause videoId=${now.videoId}');
      }
      requestExpand(now);
      return;
    }
    final c = ytController.value;
    final wasPlaying =
        (c?.value.isPlaying == true) || (nowPlaying.value?.isPlaying == true);
    _forceResumeOnExpand = wasPlaying;
    if (c != null) {
      try {
        update(
          isPlaying: c.value.isPlaying,
          playbackPosition: c.value.position,
          duration: c.value.metaData.duration,
        );
      } catch (_) {}
    }
    if (kDebugMode) {
      final cPlaying = c?.value.isPlaying == true;
      final cPositionMs = c == null ? -1 : c.value.position.inMilliseconds;
      debugPrint(
          '[ChannelMiniPlayerManager] expand pause-check wasPlaying=$wasPlaying controllerPlaying=$cPlaying positionMs=$cPositionMs');
    }
    if (wasPlaying) {
      try {
        _pausePlayback?.call();
      } catch (_) {}
      try {
        c?.pause();
      } catch (_) {}
      if (kDebugMode) {
        final afterPausePlaying = c?.value.isPlaying == true;
        debugPrint(
            '[ChannelMiniPlayerManager] expand paused before route afterPausePlaying=$afterPausePlaying');
      }
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        requestExpand(now);
      });
      return;
    }
    requestExpand(now);
  }

  void pause() {
    if (kDebugMode) {
      debugPrint('[ChannelMiniPlayerManager] pause');
    }
    _pausePlayback?.call();
  }

  void togglePlayPause() {
    final c = ytController.value;
    if (c == null) return;
    if (!c.value.isReady) return;
    if (c.value.isPlaying) {
      update(isPlaying: false);
      try {
        c.pause();
      } catch (_) {}
    } else {
      update(isPlaying: true);
      try {
        c.play();
      } catch (_) {}
    }
  }

  void update({
    bool? isPlaying,
    String? title,
    String? playlistId,
    String? playlistTitle,
    String? thumbnailUrl,
    Duration? playbackPosition,
    Duration? duration,
    VoidCallbackFn? onTogglePlayPause,
    VoidCallbackFn? onExpand,
  }) {
    final current = nowPlaying.value;
    if (current == null) return;
    nowPlaying.value = current.copyWith(
      isPlaying: isPlaying,
      title: title,
      playlistId: playlistId,
      playlistTitle: playlistTitle,
      thumbnailUrl: thumbnailUrl,
      playbackPosition: playbackPosition,
      duration: duration,
      onTogglePlayPause: onTogglePlayPause,
      onExpand: onExpand,
    );
  }

  void clear({bool disposeController = true}) {
    try {
      _pausePlayback?.call();
    } catch (_) {}
    if (disposeController) {
      _detachController();
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
    _forceResumeOnExpand = false;
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
