// ignore_for_file: prefer_final_fields, use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../mini_player/mini_player_manager.dart';
import '../mini_player/series_now_playing.dart';
import '../../../auth/tenant_auth_client.dart';

class PlayerPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final int episodeId;
  final String title;
  final String? thumbnailUrl;

  const PlayerPage({
    super.key,
    required this.api,
    required this.tenantId,
    required this.episodeId,
    required this.title,
    this.thumbnailUrl,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  YoutubePlayerController? _yt;
  VoidCallback? _ytListener;
  bool _isFull = false;
  bool _showUi = true;
  Timer? _hideTimer;
  bool? _lastLandscape;
  Timer? _rotateDebounce;
  bool _autoRotate = true; // toggle: auto-enter/exit fullscreen on orientation
  bool _suppressUi = false; // hide overlays during rotation window
  DateTime? _lastToggleAt; // min interval guard
  String? _videoId; // for stability mode rebuilds
  final bool _useNativeControls = true;

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    try {
      if (_ytListener != null && _yt != null) _yt!.removeListener(_ytListener!);
      _yt?.pause();
      _yt?.dispose();
    } catch (_) {}
    try {
      _hideTimer?.cancel();
    } catch (_) {}
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    try {
      _rotateDebounce?.cancel();
    } catch (_) {}
    try {
      MiniPlayerManager.I.clear();
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Debounce orientation-driven fullscreen sync to avoid surface churn
    try {
      _rotateDebounce?.cancel();
    } catch (_) {}
    setState(() => _suppressUi = true);
    _rotateDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      await _rebuildForOrientation(context);
      if (mounted) setState(() => _suppressUi = false);
    });
  }

  Future<void> _rebuildForOrientation(BuildContext ctx) async {
    if (!_autoRotate) return;
    final c = _yt;
    if (c == null) return;
    // Require stable orientation across two frames
    final o1 = MediaQuery.of(ctx).orientation;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    final o2 = MediaQuery.of(ctx).orientation;
    if (o1 != o2) return; // not stable yet
    final isLand = o2 == Orientation.landscape;
    if (_lastLandscape == isLand && _isFull == isLand) return;
    // Min interval guard
    final now = DateTime.now();
    if (_lastToggleAt != null &&
        now.difference(_lastToggleAt!) < const Duration(milliseconds: 800)) {
      _lastLandscape = isLand;
      return;
    }

    // Capture state
    Duration pos = Duration.zero;
    bool wasPlaying = false;
    try {
      pos = c.value.position;
      wasPlaying = c.value.isPlaying;
    } catch (_) {}

    try {
      c.pause();
    } catch (_) {}
    try {
      c.removeListener(_ytListener!);
    } catch (_) {}
    try {
      c.dispose();
    } catch (_) {}
    setState(() {
      _yt = null;
    });

    // Recreate after short delay
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted || _videoId == null || _videoId!.isEmpty) return;

    final nc = YoutubePlayerController(
      initialVideoId: _videoId!,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        controlsVisibleAtStart: true,
        hideControls: false,
        forceHD: false,
        enableCaption: false,
      ),
    );
    _ytListener = () {
      final fs = nc.value.isFullScreen;
      if (fs != _isFull) {
        setState(() => _isFull = fs);
        try {
          if (fs) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          } else {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          }
        } catch (_) {}
      }
      try {
        final pos = nc.value.position;
        final dur = nc.value.metaData.duration;
        final playing = nc.value.isPlaying;
        final current = MiniPlayerManager.I.nowPlaying.value;
        if (current == null || current.episodeId != widget.episodeId) {
          MiniPlayerManager.I.setNowPlaying(
            SeriesNowPlaying(
              episodeId: widget.episodeId,
              title: widget.title,
              thumbnailUrl: widget.thumbnailUrl,
              position: pos,
              duration: dur,
              isPlaying: playing,
              onTogglePlayPause: () {
                try {
                  if (nc.value.isPlaying) {
                    nc.pause();
                  } else {
                    nc.play();
                  }
                } catch (_) {}
              },
              onExpand: () {},
            ),
          );
        } else {
          MiniPlayerManager.I.update(
            position: pos,
            duration: dur,
            isPlaying: playing,
            onTogglePlayPause: () {
              try {
                if (nc.value.isPlaying) {
                  nc.pause();
                } else {
                  nc.play();
                }
              } catch (_) {}
            },
          );
        }
      } catch (_) {}
    };
    nc.addListener(_ytListener!);
    setState(() {
      _yt = nc;
      _lastLandscape = isLand;
      _lastToggleAt = DateTime.now();
    });

    // Wait a frame, then seek and set fullscreen to match orientation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        _yt?.seekTo(pos);
      } catch (_) {}
      if (wasPlaying) {
        try {
          _yt?.play();
        } catch (_) {}
      }
      final fs = _yt?.value.isFullScreen ?? false;
      try {
        if (isLand && !fs) {
          _yt?.toggleFullScreenMode();
        } else if (!isLand && fs) {
          _yt?.toggleFullScreenMode();
        }
      } catch (_) {}
    });
  }

  Future<void> _load() async {
    widget.api.setTenant(widget.tenantId);
    try {
      final play = await widget.api.seriesEpisodePlay(widget.episodeId);
      final raw = (play['video_id'] ?? '').toString();
      final vid = _extractVideoId(raw);
      final c = YoutubePlayerController(
        initialVideoId: vid,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          controlsVisibleAtStart: true,
          hideControls: false,
          forceHD: false,
          enableCaption: false,
        ),
      );
      _videoId = vid;
      _lastLandscape = null; // reset guard on new controller
      _ytListener = () {
        final fs = c.value.isFullScreen;
        if (fs != _isFull) {
          setState(() => _isFull = fs);
          try {
            if (fs) {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            } else {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            }
          } catch (_) {}
        }
        try {
          final pos = c.value.position;
          final dur = c.value.metaData.duration;
          final playing = c.value.isPlaying;
          final current = MiniPlayerManager.I.nowPlaying.value;
          if (current == null || current.episodeId != widget.episodeId) {
            MiniPlayerManager.I.setNowPlaying(
              SeriesNowPlaying(
                episodeId: widget.episodeId,
                title: widget.title,
                thumbnailUrl: widget.thumbnailUrl,
                position: pos,
                duration: dur,
                isPlaying: playing,
                onTogglePlayPause: () {
                  try {
                    if (c.value.isPlaying) {
                      c.pause();
                    } else {
                      c.play();
                    }
                  } catch (_) {}
                },
                onExpand: () {},
              ),
            );
          } else {
            MiniPlayerManager.I.update(
              position: pos,
              duration: dur,
              isPlaying: playing,
              onTogglePlayPause: () {
                try {
                  if (c.value.isPlaying) {
                    c.pause();
                  } else {
                    c.play();
                  }
                } catch (_) {}
              },
            );
          }
        } catch (_) {}
      };
      c.addListener(_ytListener!);
      setState(() => _yt = c);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _rebuildForOrientation(context));
    } catch (_) {}
  }

  void _showUiTemp() {
    setState(() => _showUi = true);
    try {
      _hideTimer?.cancel();
    } catch (_) {}
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showUi = false);
    });
  }

  void _seekBy(int s) {
    final c = _yt;
    if (c == null) return;
    try {
      final pos = c.value.position;
      final dur = c.value.metaData.duration;
      var t = pos + Duration(seconds: s);
      if (t < Duration.zero) t = Duration.zero;
      if (dur != Duration.zero && t > dur) t = dur;
      c.seekTo(t);
    } catch (_) {}
  }

  String _extractVideoId(String input) {
    String s = input.trim();
    if (s.isEmpty) return '';
    final idLike = RegExp(r'^[A-Za-z0-9_-]{11}$');
    if (idLike.hasMatch(s)) return s;
    final short = RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})');
    final m1 = short.firstMatch(s);
    if (m1 != null) return m1.group(1)!;
    final watch = RegExp(r'[?&]v=([A-Za-z0-9_-]{11})');
    final m2 = watch.firstMatch(s);
    if (m2 != null) return m2.group(1)!;
    final embed = RegExp(r'embed/([A-Za-z0-9_-]{11})');
    final m3 = embed.firstMatch(s);
    if (m3 != null) return m3.group(1)!;
    final noList = s.replaceAll(RegExp(r'[?&]list=[^&]+'), '');
    final m4 = watch.firstMatch(noList);
    if (m4 != null) return m4.group(1)!;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final v = _yt?.value;
        if (v != null && v.isFullScreen) {
          try {
            _yt?.toggleFullScreenMode();
          } catch (_) {}
          return false;
        }
        return true;
      },
      child: Scaffold(
        body: SafeArea(
          top: true,
          bottom: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showUiTemp,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_yt != null)
                  YoutubePlayer(
                    controller: _yt!,
                    showVideoProgressIndicator: true,
                  )
                else
                  const Center(child: CircularProgressIndicator()),

                // Back button (top-left), visible when UI is shown and not suppressed
                if (_showUi && !_suppressUi)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Material(
                          color: Colors.black45,
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
                            onPressed: () {
                              try {
                                _yt?.pause();
                              } catch (_) {}
                              Navigator.of(context).maybePop();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                // Center controls (disabled when using native controls)
                if (!_useNativeControls && _showUi && !_suppressUi)
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ctrlBtn(Icons.skip_previous, () => _seekBy(-30)),
                        const SizedBox(width: 14),
                        _ctrlBtn(Icons.replay_10, () => _seekBy(-10)),
                        const SizedBox(width: 14),
                        _ctrlBtn(
                          (_yt?.value.isPlaying ?? false)
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                          () {
                            final c = _yt;
                            if (c == null) return;
                            if (c.value.isPlaying) {
                              c.pause();
                            } else {
                              c.play();
                            }
                          },
                          size: 36,
                        ),
                        const SizedBox(width: 14),
                        _ctrlBtn(Icons.forward_10, () => _seekBy(10)),
                        const SizedBox(width: 14),
                        _ctrlBtn(Icons.skip_next, () => _seekBy(30)),
                      ],
                    ),
                  ),

                // Timeline bottom (disabled when using native controls)
                if (!_useNativeControls && _showUi && !_suppressUi)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Builder(
                      builder: (context) {
                        final c = _yt;
                        final pos = c?.value.position ?? Duration.zero;
                        final dur = c?.value.metaData.duration ?? Duration.zero;
                        final max =
                            dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 1.0;
                        final value =
                            pos.inSeconds.clamp(0, dur.inSeconds).toDouble();
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmt(pos),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                                Text(_fmt(dur),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(
                                min: 0,
                                max: max,
                                value: value.isFinite ? value : 0,
                                activeColor: Colors.white,
                                inactiveColor: Colors.white24,
                                onChanged: (v) {
                                  _showUiTemp();
                                },
                                onChangeEnd: (v) {
                                  try {
                                    _yt?.seekTo(Duration(seconds: v.round()));
                                  } catch (_) {}
                                  _showUiTemp();
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, VoidCallback onPressed, {double size = 28}) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}
