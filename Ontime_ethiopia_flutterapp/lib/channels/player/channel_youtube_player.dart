import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';
import 'channel_mini_player_manager.dart';
import 'channel_now_playing.dart';

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
  String? _videoId;
  bool _isFullscreen = false;
  bool _wasPlaying = false;
  bool _wasFullscreen = false;
  bool _lastLandscape = false;
  bool _shouldResumeAfterMinimize = false;
  bool _playOnInit = false;
  String? _lastEndedVideoId;
  bool _showRotateOverlay = false;
  Timer? _rotateOverlayTimer;
  Timer? _autoRotateHintTimer;
  Timer? _fullscreenEnterCheckTimer;
  bool _fullscreenToggleInFlight = false;
  Timer? _restoreOrientationsTimer;
  Timer? _restoreAllAfterPortraitTimer;
  bool _preferPortraitOnNextExit = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  String? _controllerVideoId(YoutubePlayerController? c) {
    if (c == null) return null;
    try {
      final id = c.value.metaData.videoId;
      if (id.isNotEmpty) return id;
    } catch (_) {}
    try {
      // ignore: invalid_use_of_protected_member
      final id = c.initialVideoId;
      if (id.isNotEmpty) return id;
    } catch (_) {}
    return null;
  }

  bool _shouldKeepControllerForMiniPlayer() {
    final vid = _videoId;
    if (vid == null || vid.isEmpty) return false;
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    if (now == null) return false;
    return now.videoId == vid;
  }

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
    _playOnInit = widget.playOnInit;
    _initController();
  }

  @override
  void didUpdateWidget(covariant ChannelYoutubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextId = _extractVideoId(widget.video);
    if (nextId != _videoId) {
      _videoId = nextId;
      _lastEndedVideoId = null;
      if (_controller != null && nextId != null && nextId.isNotEmpty) {
        _playOnInit = widget.playOnInit;
        _controller!.load(nextId);
        _pushMiniPlayerState();
        _playIfReady();
      } else {
        _playOnInit = widget.playOnInit;
        _disposeController();
        _initController();
        setState(() {});
      }
    }
  }

  void _initController() {
    _videoId = _extractVideoId(widget.video);
    if (_videoId == null || _videoId!.isEmpty) return;

    // If we are expanding from the floating mini-player, reuse the same
    // controller instance so playback doesn't restart or duplicate.
    final existing = ChannelMiniPlayerManager.I.ytController.value;
    final existingVid = _controllerVideoId(existing);
    if (existing != null && existingVid == _videoId) {
      _controller = existing;
    } else {
      _controller = YoutubePlayerController(
        initialVideoId: _videoId!,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          controlsVisibleAtStart: false,
          hideControls: false,
          disableDragSeek: true,
          enableCaption: true,
        ),
      );
      ChannelMiniPlayerManager.I.ytController.value = _controller;
    }
    _controller?.addListener(_handlePlayback);
    _controller?.addListener(_handleFullscreenState);
    ChannelMiniPlayerManager.I.setPauseCallback(() {
      _controller?.pause();
    });
    _pushMiniPlayerState();
    _playIfReady();
  }

  void _playIfReady() {
    if (!_playOnInit) return;
    final ready = _controller?.value.isReady ?? false;
    if (!ready) return;
    _playOnInit = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller?.seekTo(const Duration(seconds: 0));
      _controller?.play();
    });
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
      _hideControlsTimer?.cancel();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);

    // If the unified floating mini-player is active for this same video,
    // keep the controller alive so playback continues across navigation.
    // Detach listeners so this disposed widget state won't receive callbacks.
    if (_shouldKeepControllerForMiniPlayer()) {
      try {
        _controller?.removeListener(_handlePlayback);
        _controller?.removeListener(_handleFullscreenState);
      } catch (_) {}
    } else {
      _disposeController();
    }
    super.dispose();
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

  void _disposeController() {
    final current = _controller;
    _controller?.removeListener(_handlePlayback);
    _controller?.removeListener(_handleFullscreenState);
    if (ChannelMiniPlayerManager.I.ytController.value == current) {
      _controller = null;
      return;
    }
    _controller?.dispose();
    _controller = null;
  }

  void _handlePlayback() {
    _playIfReady();
    final playerState = _controller?.value.playerState;
    if (playerState == PlayerState.ended) {
      final vid = _videoId;
      if (vid != null && vid.isNotEmpty && _lastEndedVideoId != vid) {
        _lastEndedVideoId = vid;
        _pushMiniPlayerState();
        if (ChannelMiniPlayerManager.I.autoPlayNext.value) {
          widget.onAutoPlayNext?.call();
        }
      }
      return;
    }
    if (playerState == PlayerState.playing) {
      _lastEndedVideoId = null;
    }
    final playing = _controller?.value.isPlaying ?? false;
    if (_shouldResumeAfterMinimize && !playing) {
      final ready = _controller?.value.isReady ?? false;
      if (ready) {
        _controller?.play();
        _shouldResumeAfterMinimize = false;
        return;
      }
    }
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
    _pushMiniPlayerState();
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

  void _pushMiniPlayerState() {
    final current = widget.video;
    if (current == null) return;
    final title = (current['title'] ?? '').toString();
    final thumb = [
      current['thumbnail_url'],
      current['thumbnail'],
      current['thumb'],
      current['image'],
      current['poster'],
    ].whereType<String>().firstWhere((t) => t.isNotEmpty, orElse: () => '');
    final id = _videoId ?? '';
    if (id.isEmpty || title.isEmpty) return;
    ChannelMiniPlayerManager.I.setNowPlaying(
      ChannelNowPlaying(
        videoId: id,
        title: title,
        playlistId: widget.playlistId,
        playlistTitle: widget.playlistTitle,
        thumbnailUrl: thumb.isNotEmpty ? thumb : null,
        isPlaying: _wasPlaying,
        onTogglePlayPause: () {
          if (_controller == null) return;
          if (!(_controller!.value.isReady)) return;
          if (_controller!.value.isPlaying) {
            ChannelMiniPlayerManager.I.update(isPlaying: false);
            _controller!.pause();
          } else {
            ChannelMiniPlayerManager.I.update(isPlaying: true);
            _controller!.play();
          }
        },
        onExpand: widget.onExpand,
      ),
    );
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
    final shouldResume = _controller?.value.isPlaying ?? false;
    _shouldResumeAfterMinimize = shouldResume;
    ChannelMiniPlayerManager.I.setSuppressed(false);
    ChannelMiniPlayerManager.I.setMinimized(true);
    _pushMiniPlayerState();
    if (shouldResume) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = _controller;
        if (c == null) return;
        if (!c.value.isPlaying) {
          c.play();
        }
      });
    }
    if (_controller?.value.isFullScreen ?? false) {
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
      _controller?.toggleFullScreenMode();
    }
  }

  void _restoreSystemUi() {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
  }

  String? _extractVideoId(Map<String, dynamic>? v) {
    if (v == null) return null;
    final direct = [
      v['youtube_id'],
      v['youtube_video_id'],
      v['yt_video_id'],
      v['video_id'],
    ].whereType<String>().firstWhere((id) => id.isNotEmpty, orElse: () => '');
    if (direct.isNotEmpty) return direct;
    final url = [
      v['youtube_url'],
      v['youtube_link'],
      v['url'],
      v['link'],
    ].whereType<String>().firstWhere((u) => u.isNotEmpty, orElse: () => '');
    if (url.isEmpty) return null;
    return YoutubePlayer.convertUrlToId(url);
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
                          if (ChannelMiniPlayerManager.I.isMinimized.value) {
                            ChannelMiniPlayerManager.I.clear();
                          } else {
                            ChannelMiniPlayerManager.I
                                .clear(disposeController: false);
                          }
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
                                    if (ChannelMiniPlayerManager
                                        .I.isMinimized.value) {
                                      ChannelMiniPlayerManager.I.clear();
                                    } else {
                                      ChannelMiniPlayerManager.I
                                          .clear(disposeController: false);
                                    }
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
