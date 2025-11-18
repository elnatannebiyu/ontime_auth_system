// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
// Inline player mode only
import '../../../auth/tenant_auth_client.dart';
import '../series_service.dart';

class SeriesEpisodesPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final int seasonId;
  final String title;
  final String? coverImage;

  const SeriesEpisodesPage({
    super.key,
    required this.api,
    required this.tenantId,
    required this.seasonId,
    required this.title,
    this.coverImage,
  });

  @override
  State<SeriesEpisodesPage> createState() => _SeriesEpisodesPageState();
}

class _PlayerHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minExtentHeight;
  final double maxExtentHeight;
  final WidgetBuilder builder;

  _PlayerHeaderDelegate({
    required this.minExtentHeight,
    required this.maxExtentHeight,
    required this.builder,
  });

  @override
  double get minExtent => minExtentHeight;

  @override
  double get maxExtent => maxExtentHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Colors.transparent,
      child: builder(context),
    );
  }

  @override
  bool shouldRebuild(covariant _PlayerHeaderDelegate oldDelegate) {
    return oldDelegate.minExtentHeight != minExtentHeight ||
        oldDelegate.maxExtentHeight != maxExtentHeight ||
        oldDelegate.builder != builder;
  }
}

class _SeriesEpisodesPageState extends State<SeriesEpisodesPage>
    with WidgetsBindingObserver {
  late final SeriesService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _episodes = const [];
  final Set<int> _likedEpisodes = <int>{};

  YoutubePlayerController? _yt;
  VoidCallback? _ytListener;
  String? _currentVideoId;
  bool _isFullScreen = false;
  int? _currentEpisodeId;
  bool _showFsControls = true;
  Timer? _controlsHideTimer;
  bool? _lastLandscape; // guard to avoid repeated toggles

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
    _service = SeriesService(api: widget.api, tenantId: widget.tenantId);
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
    // Restore system UI when leaving page
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    try {
      _controlsHideTimer?.cancel();
    } catch (_) {}
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    super.dispose();
  }

  // Robust rotation handling: when metrics change, sync fullscreen to orientation.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Post-frame to ensure MediaQuery updated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncFullscreenWithOrientation(context);
    });
  }

  void _syncFullscreenWithOrientation(BuildContext context) {
    final c = _yt;
    if (c == null) return;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (_lastLandscape == isLandscape) return; // unchanged, skip
    _lastLandscape = isLandscape;
    final fs = c.value.isFullScreen;
    try {
      if (isLandscape && !fs) {
        c.toggleFullScreenMode();
      } else if (!isLandscape && fs) {
        c.toggleFullScreenMode();
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getEpisodes(widget.seasonId);
      // Initialize liked set if backend provides a flag
      final liked = <int>{};
      for (final e in data) {
        final id = e['id'] as int?;
        final isLiked = (e['liked'] ?? e['is_liked'] ?? e['favorite']) as bool?;
        if (id != null && (isLiked ?? false)) liked.add(id);
      }
      setState(() {
        _episodes = data;
        _likedEpisodes
          ..clear()
          ..addAll(liked);
      });
    } catch (_) {
      setState(() => _error = 'Failed to load episodes');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _playInline(int episodeId, {String? title}) async {
    widget.api.setTenant(widget.tenantId);
    try {
      final play = await widget.api.seriesEpisodePlay(episodeId);
      final raw = (play['video_id'] ?? '').toString();
      final vid = _extractVideoId(raw);
      final old = _yt;
      final c = YoutubePlayerController(
        initialVideoId: vid,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          controlsVisibleAtStart: false,
          hideControls: true,
          forceHD: false,
          enableCaption: false,
        ),
      );
      // listener: track fullscreen and toggle immersive system UI
      _ytListener = () {
        final fs = c.value.isFullScreen;
        if (fs != _isFullScreen) {
          if (mounted) setState(() => _isFullScreen = fs);
          try {
            if (fs) {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
              // Ensure free rotation in fullscreen
              SystemChrome.setPreferredOrientations(const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]);
            } else {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              // Restore free rotation after exiting fullscreen as well
              SystemChrome.setPreferredOrientations(const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]);
            }
          } catch (_) {}
        }
      };
      c.addListener(_ytListener!);
      setState(() {
        _currentVideoId = vid;
        _currentEpisodeId = episodeId;
        _yt = c;
      });
      Future.microtask(() {
        try {
          old?.pause();
        } catch (_) {}
        try {
          old?.removeListener(_ytListener!);
        } catch (_) {}
        try {
          old?.dispose();
        } catch (_) {}
      });
      // Optional: persist continue watching lightweight marker
      _saveContinueWatching(episodeId: episodeId, title: title ?? widget.title);
    } catch (_) {}
  }

  int _indexOfEpisode(int id) {
    for (var i = 0; i < _episodes.length; i++) {
      if ((_episodes[i]['id'] as int) == id) return i;
    }
    return -1;
  }

  void _playNext() {
    final cur = _currentEpisodeId;
    if (cur == null) return;
    final idx = _indexOfEpisode(cur);
    if (idx >= 0 && idx + 1 < _episodes.length) {
      final e = _episodes[idx + 1];
      final id = e['id'] as int;
      final t = (e['display_title'] ?? e['title'] ?? '').toString();
      _playInline(id, title: t);
    }
  }

  void _playPrev() {
    final cur = _currentEpisodeId;
    if (cur == null) return;
    final idx = _indexOfEpisode(cur);
    if (idx > 0) {
      final e = _episodes[idx - 1];
      final id = e['id'] as int;
      final t = (e['display_title'] ?? e['title'] ?? '').toString();
      _playInline(id, title: t);
    }
  }

  void _seekBy(int seconds) {
    final c = _yt;
    if (c == null) return;
    try {
      final pos = c.value.position;
      final dur = c.value.metaData.duration;
      final target = pos + Duration(seconds: seconds);
      final clamped = target < Duration.zero
          ? Duration.zero
          : (dur != Duration.zero && target > dur ? dur : target);
      c.seekTo(clamped);
    } catch (_) {}
  }

  void _togglePlayPause() {
    final c = _yt;
    if (c == null) return;
    try {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
    } catch (_) {}
  }

  void _showControlsTemporarily() {
    setState(() => _showFsControls = true);
    try {
      _controlsHideTimer?.cancel();
    } catch (_) {}
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showFsControls = false);
    });
  }

  Future<void> _saveContinueWatching(
      {required int episodeId, required String title}) async {
    final sid = widget.seasonId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'cw_season_$sid',
          jsonEncode({
            'episode_id': episodeId,
            'title': title,
            'season_id': sid,
            'updated_at': DateTime.now().toIso8601String(),
          }));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Do not force orientation or system UI. Let the player/plugin handle fullscreen transitions.
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
            title: Text(widget.title),
            backgroundColor: Colors.transparent,
            elevation: 0),
        body: Center(
            child: Text(_error!, style: const TextStyle(color: Colors.red))),
      );
    }

    // Ensure orientation sync also at build time (first frame after rebuild)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncFullscreenWithOrientation(context);
    });

    // Inline-only mode: no mini player wiring

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
          child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              slivers: [
                if (_yt != null)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PlayerHeaderDelegate(
                      minExtentHeight: math.min(
                          MediaQuery.of(context).size.width * 9 / 16,
                          MediaQuery.of(context).size.height),
                      maxExtentHeight: math.min(
                          MediaQuery.of(context).size.width * 9 / 16,
                          MediaQuery.of(context).size.height),
                      builder: (ctx) {
                        final mq = MediaQuery.of(ctx);
                        final widthDerivedHeight = mq.size.width * 9 / 16;
                        final availableHeight = mq.size.height;
                        final playerHeight =
                            math.min(widthDerivedHeight, availableHeight);
                        return SizedBox(
                          height: playerHeight,
                          child: KeyedSubtree(
                            key: ValueKey(_currentVideoId ?? ''),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                YoutubePlayer(
                                  controller: _yt!,
                                  showVideoProgressIndicator: true,
                                ),
                                // Tap to show controls (portrait and fullscreen)
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _showControlsTemporarily,
                                    child: const SizedBox.shrink(),
                                  ),
                                ),
                                // Back button: in fullscreen draw without SafeArea for true full bleed
                                if (!(_yt?.value.isFullScreen ?? false) ||
                                    (_isFullScreen && _showFsControls))
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    child: (_isFullScreen
                                        ? Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Material(
                                              color: Colors.black45,
                                              shape: const CircleBorder(),
                                              child: IconButton(
                                                icon: const Icon(
                                                    Icons.arrow_back,
                                                    color: Colors.white),
                                                tooltip: 'Back',
                                                onPressed: () {
                                                  final v = _yt?.value;
                                                  try {
                                                    _yt?.pause();
                                                  } catch (_) {}
                                                  if (v != null &&
                                                      v.isFullScreen) {
                                                    try {
                                                      _yt?.toggleFullScreenMode();
                                                    } catch (_) {}
                                                  }
                                                  // Close player (hide header) but stay on page
                                                  final old = _yt;
                                                  setState(() {
                                                    _yt = null;
                                                    _currentVideoId = null;
                                                  });
                                                  try {
                                                    old?.dispose();
                                                  } catch (_) {}
                                                },
                                              ),
                                            ),
                                          )
                                        : SafeArea(
                                            bottom: false,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: Material(
                                                color: Colors.black45,
                                                shape: const CircleBorder(),
                                                child: IconButton(
                                                  icon: const Icon(
                                                      Icons.arrow_back,
                                                      color: Colors.white),
                                                  tooltip: 'Back',
                                                  onPressed: () {
                                                    // Close player (hide header) but stay on page
                                                    try {
                                                      _yt?.pause();
                                                    } catch (_) {}
                                                    final old = _yt;
                                                    setState(() {
                                                      _yt = null;
                                                      _currentVideoId = null;
                                                    });
                                                    try {
                                                      old?.dispose();
                                                    } catch (_) {}
                                                  },
                                                ),
                                              ),
                                            ),
                                          )),
                                  ),
                                // Controls bar (portrait and fullscreen) - centered and smaller icons
                                if (_showFsControls)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: false,
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _FsIcon(
                                                icon: Icons.skip_previous,
                                                size: 28,
                                                onPressed: _playPrev,
                                              ),
                                              const SizedBox(width: 14),
                                              _FsIcon(
                                                icon: Icons.replay_10,
                                                size: 28,
                                                onPressed: () => _seekBy(-10),
                                              ),
                                              const SizedBox(width: 14),
                                              _FsIcon(
                                                icon: (_yt?.value.isPlaying ??
                                                        false)
                                                    ? Icons.pause_circle_filled
                                                    : Icons.play_circle_fill,
                                                size: 36,
                                                onPressed: _togglePlayPause,
                                              ),
                                              const SizedBox(width: 14),
                                              _FsIcon(
                                                icon: Icons.forward_10,
                                                size: 28,
                                                onPressed: () => _seekBy(10),
                                              ),
                                              const SizedBox(width: 14),
                                              _FsIcon(
                                                icon: Icons.skip_next,
                                                size: 28,
                                                onPressed: _playNext,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // Back button: in fullscreen draw without SafeArea for true full bleed
                                if (!(_yt?.value.isFullScreen ?? false) ||
                                    (_isFullScreen && _showFsControls))
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    child: (_isFullScreen
                                        ? Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Material(
                                              color: Colors.black45,
                                              shape: const CircleBorder(),
                                              child: IconButton(
                                                icon: const Icon(
                                                    Icons.arrow_back,
                                                    color: Colors.white),
                                                tooltip: 'Back',
                                                onPressed: () {
                                                  final v = _yt?.value;
                                                  try {
                                                    _yt?.pause();
                                                  } catch (_) {}
                                                  if (v != null &&
                                                      v.isFullScreen) {
                                                    try {
                                                      _yt?.toggleFullScreenMode();
                                                    } catch (_) {}
                                                  }
                                                  // Close player (hide header) but stay on page
                                                  final old = _yt;
                                                  setState(() {
                                                    _yt = null;
                                                    _currentVideoId = null;
                                                  });
                                                  try {
                                                    old?.dispose();
                                                  } catch (_) {}
                                                },
                                              ),
                                            ),
                                          )
                                        : SafeArea(
                                            bottom: false,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: Material(
                                                color: Colors.black45,
                                                shape: const CircleBorder(),
                                                child: IconButton(
                                                  icon: const Icon(
                                                      Icons.arrow_back,
                                                      color: Colors.white),
                                                  tooltip: 'Back',
                                                  onPressed: () {
                                                    // Close player (hide header) but stay on page
                                                    try {
                                                      _yt?.pause();
                                                    } catch (_) {}
                                                    final old = _yt;
                                                    setState(() {
                                                      _yt = null;
                                                      _currentVideoId = null;
                                                    });
                                                    try {
                                                      old?.dispose();
                                                    } catch (_) {}
                                                  },
                                                ),
                                              ),
                                            ),
                                          )),
                                  ),
                                // Controls bar (portrait and fullscreen) - centered and smaller icons
                                if (_showFsControls)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: false,
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _FsIcon(
                                                icon: Icons.skip_previous,
                                                size: 28,
                                                onPressed: _playPrev,
                                              ),
                                              const SizedBox(width: 14),
                                              _FsIcon(
                                                icon: Icons.replay_10,
                                                size: 28,
                                                onPressed: () => _seekBy(-10),
                                              ),
                                              const SizedBox(width: 14),
                                              _FsIcon(
                                                icon: (_yt?.value.isPlaying ??
                                                        false)
                                                    ? Icons.pause_circle_filled
                                                    : Icons.play_circle_fill,
                                                size: 36,
                                                onPressed: _togglePlayPause,
                                              ),
                                              const SizedBox(width: 14),
                                              _FsIcon(
                                                icon: Icons.forward_10,
                                                size: 28,
                                                onPressed: () => _seekBy(10),
                                              ),
                                              const SizedBox(width: 14),
                                              _FsIcon(
                                                icon: Icons.skip_next,
                                                size: 28,
                                                onPressed: _playNext,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // (removed drag scrub overlay)
                                // Timeline at the bottom (time + seek bar) in both modes
                                if (_showFsControls)
                                  Positioned(
                                    left: 12,
                                    right: 12,
                                    bottom: 12,
                                    child: Builder(
                                      builder: (context) {
                                        final c = _yt;
                                        final pos =
                                            c?.value.position ?? Duration.zero;
                                        final dur =
                                            c?.value.metaData.duration ??
                                                Duration.zero;
                                        final max = dur.inSeconds > 0
                                            ? dur.inSeconds.toDouble()
                                            : 1.0;
                                        final value = pos.inSeconds
                                            .clamp(0, dur.inSeconds)
                                            .toDouble();
                                        return Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(_fmt(pos),
                                                    style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 12)),
                                                Text(_fmt(dur),
                                                    style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 12)),
                                              ],
                                            ),
                                            SliderTheme(
                                              data: SliderTheme.of(context)
                                                  .copyWith(
                                                trackHeight: 2,
                                                thumbShape:
                                                    const RoundSliderThumbShape(
                                                        enabledThumbRadius: 6),
                                                overlayShape:
                                                    SliderComponentShape
                                                        .noOverlay,
                                              ),
                                              child: Slider(
                                                min: 0,
                                                max: max,
                                                value:
                                                    value.isFinite ? value : 0,
                                                activeColor: Colors.white,
                                                inactiveColor: Colors.white24,
                                                onChanged: (v) {
                                                  // show UI only; seek onChangeEnd
                                                  _showControlsTemporarily();
                                                },
                                                onChangeEnd: (v) {
                                                  try {
                                                    _yt?.seekTo(Duration(
                                                        seconds: v.round()));
                                                  } catch (_) {}
                                                  _showControlsTemporarily();
                                                },
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                // Fullscreen toggle overlay (no extra time labels)
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Material(
                                    color: Colors.black45,
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      tooltip: 'Fullscreen',
                                      icon: Icon(
                                        (_yt?.value.isFullScreen ?? false)
                                            ? Icons.fullscreen_exit
                                            : Icons.fullscreen,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        try {
                                          _yt?.toggleFullScreenMode();
                                        } catch (_) {}
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                SliverSafeArea(
                  top: false,
                  bottom: true,
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final e = _episodes[i];
                        final id = e['id'] as int;
                        final title =
                            (e['display_title'] ?? e['title'] ?? '').toString();
                        final desc = (e['description_override'] ??
                                e['description'] ??
                                '')
                            .toString();
                        final thumbs = e['thumbnails'] as Map<String, dynamic>?;
                        final cover = _pickThumb(thumbs);
                        return Padding(
                          padding:
                              EdgeInsets.fromLTRB(12, i == 0 ? 4 : 8, 12, 8),
                          child: EpisodeCard(
                            title: title,
                            subtitle: e['episode_number'] != null
                                ? 'Episode ${e['episode_number']}'
                                : null,
                            description: desc,
                            imageUrl: cover,
                            liked: _likedEpisodes.contains(id),
                            onPlay: () => _playInline(id, title: title),
                            onToggleLike: () async {
                              try {
                                if (_likedEpisodes.contains(id)) {
                                  await widget.api.seriesEpisodeUnlike(id);
                                  if (mounted) {
                                    setState(() => _likedEpisodes.remove(id));
                                  }
                                } else {
                                  await widget.api.seriesEpisodeLike(id);
                                  if (mounted) {
                                    setState(() => _likedEpisodes.add(id));
                                  }
                                }
                              } catch (_) {}
                            },
                          ),
                        );
                      },
                      childCount: _episodes.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                      height: 60 + MediaQuery.of(context).padding.bottom),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _extractVideoId(String input) {
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

  static String _pickThumb(Map<String, dynamic>? thumbs) {
    if (thumbs == null) return '';
    const order = ['maxres', 'standard', 'high', 'medium', 'default'];
    for (final k in order) {
      final t = thumbs[k];
      if (t is Map && t['url'] is String && (t['url'] as String).isNotEmpty) {
        return t['url'] as String;
      }
    }
    if (thumbs['url'] is String) return thumbs['url'] as String;
    return '';
  }
}

class EpisodeCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String description;
  final String imageUrl;
  final bool liked;
  final VoidCallback onPlay;
  final VoidCallback onToggleLike;

  const EpisodeCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.description,
    required this.imageUrl,
    required this.liked,
    required this.onPlay,
    required this.onToggleLike,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlay,
      child: Card(
        elevation: 6,
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with like button overlay
            ClipRRect(
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12), topRight: Radius.circular(12)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageUrl.isNotEmpty
                        ? Image.network(imageUrl, fit: BoxFit.cover)
                        : Container(color: Colors.black12),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Material(
                        color: Colors.black45,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: liked ? 'Unfavorite' : 'Favorite',
                          icon: Icon(
                              liked ? Icons.favorite : Icons.favorite_border,
                              color: liked ? Colors.redAccent : Colors.white),
                          onPressed: onToggleLike,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                        ),
                      ),
                      IconButton(
                        onPressed: onToggleLike,
                        icon: Icon(
                            liked ? Icons.favorite : Icons.favorite_border),
                        tooltip: liked ? 'Unfavorite' : 'Favorite',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FsIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  const _FsIcon({required this.icon, required this.onPressed, this.size = 40});

  @override
  Widget build(BuildContext context) {
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
