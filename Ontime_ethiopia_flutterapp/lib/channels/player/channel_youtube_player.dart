import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';
import 'channel_mini_player_manager.dart';

class ChannelYoutubePlayer extends StatefulWidget {
  final Map<String, dynamic>? video;
  final String? playlistId;
  final String? playlistTitle;
  final double aspectRatio;
  final Widget? fallback;
  final ValueChanged<bool>? onPlayingChanged;
  final VoidCallback? onExpand;
  final VoidCallback? onClose;
  final bool playOnInit;
  final VoidCallback? onAutoPlayNext;
  final String? autoRotateFullscreenHint;

  const ChannelYoutubePlayer({
    super.key,
    required this.video,
    this.playlistId,
    this.playlistTitle,
    this.aspectRatio = 16 / 9,
    this.fallback,
    this.onPlayingChanged,
    this.onExpand,
    this.onClose,
    this.playOnInit = false,
    this.onAutoPlayNext,
    this.autoRotateFullscreenHint,
  });

  @override
  State<ChannelYoutubePlayer> createState() => _ChannelYoutubePlayerState();
}

class _ChannelYoutubePlayerState extends State<ChannelYoutubePlayer>
    with WidgetsBindingObserver {
  YoutubePlayerController? _controller;
  bool _isFullscreen = false;
  bool _wasPlaying = false;
  bool _wasFullscreen = false;
  bool _lastLandscape = false;
  bool _showRotateOverlay = false;
  Timer? _rotateOverlayTimer;
  Timer? _autoRotateHintTimer;
  Timer? _fullscreenEnterCheckTimer;
  bool _fullscreenToggleInFlight = false;
  Timer? _restoreOrientationsTimer;
  Timer? _restoreAllAfterPortraitTimer;
  Timer? _restorePlaybackTimer;
  int _restorePlaybackAttempts = 0;
  int? _lastRestoredControllerHash;
  static const Duration _minReliablePlaybackPosition =
      Duration(milliseconds: 400);
  bool _preferPortraitOnNextExit = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  void _restoreAllOrientations() {
    try {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ChannelMiniPlayerManager.I.ytController.value;
    ChannelMiniPlayerManager.I.ytController.addListener(_onGlobalController);
    _attachController(_controller);
  }

  @override
  void didUpdateWidget(covariant ChannelYoutubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video != widget.video) {
      setState(() {});
    }
  }

  void _onGlobalController() {
    final next = ChannelMiniPlayerManager.I.ytController.value;
    if (next == _controller) return;
    _detachController(_controller);
    _controller = next;
    _attachController(_controller);
    if (mounted) setState(() {});
  }

  void _attachController(YoutubePlayerController? controller) {
    if (controller == null) return;
    controller.addListener(_handlePlayback);
    controller.addListener(_handleFullscreenState);
    _restorePlaybackFromSession(controller);
    ChannelMiniPlayerManager.I.setPauseCallback(() {
      controller.pause();
    });
  }

  void _detachController(YoutubePlayerController? controller) {
    if (controller == null) return;
    try {
      controller.removeListener(_handlePlayback);
      controller.removeListener(_handleFullscreenState);
    } catch (_) {}
  }

  @override
  void dispose() {
    _restoreSystemUi();
    _restoreAllOrientations();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    try {
      _rotateOverlayTimer?.cancel();
    } catch (_) {}
    try {
      _autoRotateHintTimer?.cancel();
    } catch (_) {}
    try {
      _fullscreenEnterCheckTimer?.cancel();
    } catch (_) {}
    try {
      _restoreOrientationsTimer?.cancel();
    } catch (_) {}
    try {
      _restoreAllAfterPortraitTimer?.cancel();
    } catch (_) {}
    try {
      _restorePlaybackTimer?.cancel();
    } catch (_) {}
    try {
      _hideControlsTimer?.cancel();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    ChannelMiniPlayerManager.I.ytController.removeListener(_onGlobalController);
    _detachController(_controller);
    super.dispose();
  }

  void _restorePlaybackFromSession(YoutubePlayerController controller) {
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    final nowPosition = now?.playbackPosition ?? Duration.zero;
    final sessionPosition = nowPosition > Duration.zero
        ? nowPosition
        : ChannelMiniPlayerManager.I.lastPlaybackPosition;
    if (sessionPosition <= Duration.zero) return;
    final controllerHash = controller.hashCode;
    if (_lastRestoredControllerHash == controllerHash) return;
    _lastRestoredControllerHash = controllerHash;
    _restorePlaybackAttempts = 0;
    _restorePlaybackTimer?.cancel();
    _restorePlaybackTimer =
        Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _restorePlaybackAttempts += 1;
      final ready = controller.value.isReady;
      if (!ready) {
        if (_restorePlaybackAttempts >= 12) {
          timer.cancel();
        }
        return;
      }
      final currentPos = controller.value.position;
      final delta = (currentPos - sessionPosition).inSeconds.abs();
      // Only restore if the surface came back near the beginning.
      // Avoid seeking backwards when playback is already continuing.
      final shouldSeek =
          currentPos <= const Duration(seconds: 1) &&
              sessionPosition > _minReliablePlaybackPosition &&
              delta > 1;
      if (kDebugMode) {
        debugPrint(
            '[ChannelYoutubePlayer] restore check seek=$shouldSeek session=${sessionPosition.inMilliseconds}ms current=${currentPos.inMilliseconds}ms');
      }
      if (shouldSeek) {
        try {
          controller.seekTo(sessionPosition);
        } catch (_) {}
      }
      if (now?.isPlaying == true) {
        try {
          controller.play();
        } catch (_) {}
      } else if (now?.isPlaying == false) {
        try {
          controller.pause();
        } catch (_) {}
      }
      timer.cancel();
    });
  }

  void _startRotateOverlay() {
    setState(() {
      _showRotateOverlay = true;
    });
    _rotateOverlayTimer = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      setState(() {
        _showRotateOverlay = false;
      });
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Force a rebuild on metrics/orientation changes to reduce cases where
    // fullscreen/orientation state feels stuck on some devices.
    if (mounted) setState(() {});
  }

  void _handlePlayback() {
    final playerState = _controller?.value.playerState;
    if (playerState == PlayerState.ended) {
      if (ChannelMiniPlayerManager.I.autoPlayNext.value) {
        widget.onAutoPlayNext?.call();
      }
      return;
    }
    final playing = _controller?.value.isPlaying ?? false;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    if (playing) {
      _scheduleHideControls();
    } else {
      _showControlsOverlay();
    }
    try {
      if (playing) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (_) {}
    widget.onPlayingChanged?.call(playing);
  }

  void _showControlsOverlay() {
    if (!mounted) return;
    _hideControlsTimer?.cancel();
    if (_showControls) return;
    setState(() => _showControls = true);
  }

  void _scheduleHideControls() {
    if (!mounted) return;
    _hideControlsTimer?.cancel();
    _showControls = true;
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showControls = false);
    });
  }

  void _handleFullscreenState() {
    final isFullscreen = _controller?.value.isFullScreen ?? false;
    if (isFullscreen == _wasFullscreen) return;
    _wasFullscreen = isFullscreen;
    // Fullscreen state changed, so any "in-flight" toggle should be considered complete.
    _fullscreenToggleInFlight = false;
    _startRotateOverlay();
    if (isFullscreen) {
      _enterFullscreen();
    } else {
      _exitFullscreen();
    }
  }

  Future<void> _enterFullscreen() async {
    if (_isFullscreen) return;
    _isFullscreen = true;

    try {
      _restoreOrientationsTimer?.cancel();
    } catch (_) {}

    // Show the Auto-Rotate hint only if we are still portrait AFTER fullscreen
    // settles (avoid showing when rotation works normally).
    try {
      _autoRotateHintTimer?.cancel();
    } catch (_) {}
    final hint = widget.autoRotateFullscreenHint;
    if (hint != null && hint.isNotEmpty) {
      _autoRotateHintTimer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted || !_isFullscreen) return;
        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        if (!isPortrait) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            content: Text(hint),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    // No orientation retry timers: keep fullscreen behavior aligned with system auto-rotate.
  }

  Future<void> _exitFullscreen() async {
    if (!_isFullscreen) return;
    _isFullscreen = false;
    try {
      _fullscreenEnterCheckTimer?.cancel();
    } catch (_) {}
    try {
      _autoRotateHintTimer?.cancel();
    } catch (_) {}
    _fullscreenToggleInFlight = false;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    _restoreSystemUi();

    if (_preferPortraitOnNextExit) {
      _preferPortraitOnNextExit = false;
      try {
        _restoreAllAfterPortraitTimer?.cancel();
      } catch (_) {}
      _restoreAllAfterPortraitTimer =
          Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        _restoreAllOrientations();
      });
      return;
    }
    // Delay restoring orientations slightly; doing it immediately can fight the
    // youtube_player_flutter fullscreen transition and cause a "bounce".
    try {
      _restoreOrientationsTimer?.cancel();
    } catch (_) {}
    _restoreOrientationsTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_isFullscreen) return;
      _restoreAllOrientations();
    });
  }

  void _minimizeToMiniPlayer() {
    final c = _controller;
    if (c != null) {
      try {
        ChannelMiniPlayerManager.I.update(
          playbackPosition: c.value.position,
          duration: c.value.metaData.duration,
          isPlaying: c.value.isPlaying,
        );
      } catch (_) {}
    }
    ChannelMiniPlayerManager.I.setSuppressed(false);
    ChannelMiniPlayerManager.I.setMinimized(true);
    if (c?.value.isFullScreen ?? false) {
      // If minimize is used to exit fullscreen, prefer portrait during the exit
      // transition to avoid Android settling into landscapeLeft.
      _preferPortraitOnNextExit = true;
      try {
        _restoreAllAfterPortraitTimer?.cancel();
      } catch (_) {}
      try {
        SystemChrome.setPreferredOrientations(
            const [DeviceOrientation.portraitUp]);
      } catch (_) {}
      c?.toggleFullScreenMode();
    }
  }

  void _restoreSystemUi() {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: widget.fallback ?? Container(color: Colors.black26),
      );
    }
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape != _lastLandscape) {
      _lastLandscape = isLandscape;
      _startRotateOverlay();
      if (isLandscape) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      }
    }
    return ValueListenableBuilder<bool>(
      valueListenable: ChannelMiniPlayerManager.I.isMinimized,
      builder: (context, minimized, _) {
        final c = _controller;
        if (c == null) {
          return AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: widget.fallback ?? Container(color: Colors.black26),
          );
        }
        final ready = c.value.isReady;
        final canMinimize = ready && !_fullscreenToggleInFlight;
        return YoutubePlayerBuilder(
          player: YoutubePlayer(
            controller: c,
            showVideoProgressIndicator: true,
            topActions: minimized
                ? const []
                : [
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                      onPressed: canMinimize ? _minimizeToMiniPlayer : null,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          ChannelMiniPlayerManager.I.clear();
                          widget.onClose?.call();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
            bottomActions: minimized
                ? const []
                : const [
                    CurrentPosition(),
                    SizedBox(width: 8),
                    ProgressBar(isExpanded: true),
                    SizedBox(width: 8),
                    RemainingDuration(),
                  ],
          ),
          builder: (context, player) {
            return AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  player,
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.white,
                                ),
                                onPressed:
                                    canMinimize ? _minimizeToMiniPlayer : null,
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: () {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    ChannelMiniPlayerManager.I.clear();
                                    widget.onClose?.call();
                                  });
                                },
                              ),
                              const Spacer(),
                              const SizedBox(width: 8),
                            ],
                          ),
                          Row(
                            children: [
                              const CurrentPosition(),
                              const SizedBox(width: 8),
                              Expanded(child: ProgressBar(isExpanded: true)),
                              const SizedBox(width: 8),
                              const RemainingDuration(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showRotateOverlay)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black54,
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
