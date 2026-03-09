// ignore_for_file: prefer_final_fields, use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../../auth/tenant_auth_client.dart';
import '../../../channels/player/channel_mini_player_manager.dart';
import '../../../main.dart';
import '../../../core/navigation/route_stack_observer.dart';
import '../../../core/services/pip_service.dart';

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
  bool _showUi = true;
  Timer? _hideTimer;
  bool _suppressUi = false; // hide overlays during rotation window
  final bool _useNativeControls = true;

  void _expandFromMini() {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final target = '/series/player/${widget.episodeId}';
    try {
      if (appRouteStackObserver.containsName(target)) {
        nav.popUntil((route) => route.settings.name == target);
        return;
      }
    } catch (_) {}
    nav.push(
      MaterialPageRoute(
        settings: RouteSettings(name: target),
        builder: (_) => PlayerPage(
          api: widget.api,
          tenantId: widget.tenantId,
          episodeId: widget.episodeId,
          title: widget.title,
          thumbnailUrl: widget.thumbnailUrl,
        ),
      ),
    );
  }

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
    PipService.setActive(true);
    WidgetsBinding.instance.addObserver(this);
    ChannelMiniPlayerManager.I.setSuppressed(true);
    ChannelMiniPlayerManager.I.setMinimized(false);
    ChannelMiniPlayerManager.I.ytController.addListener(_syncController);
    _syncController();
    _load();
  }

  @override
  void dispose() {
    PipService.setActive(false);
    try {
      ChannelMiniPlayerManager.I.ytController.removeListener(_syncController);
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
    ChannelMiniPlayerManager.I.setSuppressed(false);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() => _suppressUi = false);
    }
  }

  void _syncController() {
    if (!mounted) return;
    setState(() {
      _yt = ChannelMiniPlayerManager.I.ytController.value;
    });
  }

  Future<void> _load() async {
    widget.api.setTenant(widget.tenantId);
    try {
      final play = await widget.api.seriesEpisodePlay(widget.episodeId);
      final raw = (play['video_id'] ?? '').toString();
      final vid = _extractVideoId(raw);
      final now = ChannelMiniPlayerManager.I.nowPlaying.value;
      if (now == null || now.videoId != vid) {
        ChannelMiniPlayerManager.I.setVideo(
          videoId: vid,
          title: widget.title,
          playlistTitle: widget.title,
          thumbnailUrl: widget.thumbnailUrl,
          openIfSame: false,
          onExpand: _expandFromMini,
        );
      }
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
        ChannelMiniPlayerManager.I.setSuppressed(false);
        ChannelMiniPlayerManager.I.setMinimized(true);
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
                              ChannelMiniPlayerManager.I.setSuppressed(false);
                              ChannelMiniPlayerManager.I.setMinimized(true);
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
