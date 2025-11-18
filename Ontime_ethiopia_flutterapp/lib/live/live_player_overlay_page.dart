// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api_client.dart';
import '../core/cache/logo_probe_cache.dart';
import 'tv_controller.dart';

class LivePlayerOverlayPage extends StatefulWidget {
  final String slug;
  const LivePlayerOverlayPage({super.key, required this.slug});

  @override
  State<LivePlayerOverlayPage> createState() => _LivePlayerOverlayPageState();
}

class _LivePlayerOverlayPageState extends State<LivePlayerOverlayPage> {
  // Simple in-memory caches per slug
  static final Map<String, String> _masterCache = {};
  static final Map<String, List<_Variant>> _variantCache = {};
  VideoPlayerController? get _c => TvController.instance.controller;

  double _dragDy = 0.0;
  bool _showControls = false;
  Timer? _controlsTimer;
  bool _muted = false;

  // Quality/variants
  String? _masterUrl;
  List<_Variant> _variantOptions = const [];
  String _currentQuality = 'Auto';
  String? _qualityToast;
  Timer? _qualityToastTimer;
  bool _switchingQuality = false;
  bool _fullscreen = false;

  // Metadata
  bool _metaLoading = false;
  String? _titleText;
  String? _channelName;
  String? _channelLogoUrl;
  String? _description;
  String? _playbackType;
  int? _listenerCount;
  int? _totalListens;
  List<String> _allowedUpstream = const [];
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TvController.instance.setInFullPlayer(true);
    });
    _bootstrap();
  }

  Future<void> _enterFullscreen() async {
    if (_fullscreen) return;
    _fullscreen = true;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
  }

  Future<void> _exitFullscreen({bool restoreOnly = false}) async {
    if (!_fullscreen && !restoreOnly) return;
    _fullscreen = false;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    final tv = TvController.instance;
    // If already playing this slug, reuse and just load variants
    // Try cache first to avoid unnecessary backend calls
    setState(() => _metaLoading = true);
    _masterUrl = _masterCache[widget.slug];
    if ((_masterUrl ?? '').isEmpty) {
      try {
        // Fetch Live entry by channel slug (backend endpoint: /live/by-channel/<slug>/)
        final res = await ApiClient().get('/live/by-channel/${widget.slug}/');
        final m = Map<String, dynamic>.from(res.data as Map);
        _masterUrl = (m['playback_url'] ?? m['playbackUrl'] ?? '').toString();
        // Populate metadata from the same response to avoid a second request
        _titleText = (m['title'] ?? '').toString();
        _channelName =
            (m['channel_name'] ?? m['channel_slug'] ?? '').toString();
        _channelLogoUrl = (m['channel_logo_url'] ?? '').toString();
        // Prefetch channel logo (only if exists): probe via LogoProbeCache, then precache
        try {
          final logo = _channelLogoUrl ?? '';
          if (logo.isNotEmpty && mounted) {
            final token = ApiClient().getAccessToken();
            final tenant = ApiClient().tenant;
            final headers = <String, String>{};
            if ((token ?? '').isNotEmpty) {
              headers['Authorization'] = 'Bearer $token';
            }
            if ((tenant ?? '').isNotEmpty) {
              headers['X-Tenant-Id'] = tenant!;
            }
            final ok = await LogoProbeCache.instance
                .ensureAvailable(logo, headers: headers);
            if (ok) {
              await precacheImage(
                  NetworkImage(logo, headers: headers), context);
            }
          }
        } catch (_) {}
        _description = (m['description'] ?? '').toString();
        _playbackType = (m['playback_type'] ?? '').toString();
        _listenerCount = (m['listener_count'] as num?)?.toInt();
        _totalListens = (m['total_listens'] as num?)?.toInt();
        final meta = m['meta'];
        if (meta is Map) {
          _allowedUpstream = List<String>.from(
              (meta['allowed_upstream'] as List? ?? const [])
                  .map((e) => e.toString()));
          _tags = List<String>.from(
              (meta['tags'] as List? ?? const []).map((e) => e.toString()));
        }
        if ((_masterUrl ?? '').isNotEmpty) {
          _masterCache[widget.slug] = _masterUrl!;
        }
      } catch (_) {}
    }
    // If pulled master from cache, still try to get metadata once (but avoid duplicate network calls)
    if (_titleText == null && (_masterUrl ?? '').isNotEmpty) {
      try {
        // We already have the master URL; fetch metadata once if needed
        final res = await ApiClient().get('/live/by-channel/${widget.slug}/');
        final m = Map<String, dynamic>.from(res.data as Map);
        _titleText = (m['title'] ?? '').toString();
        _channelName =
            (m['channel_name'] ?? m['channel_slug'] ?? '').toString();
        _channelLogoUrl = (m['channel_logo_url'] ?? '').toString();
        // Prefetch logo in the cache-metadata path as well (LogoProbeCache first)
        try {
          final logo = _channelLogoUrl ?? '';
          if (logo.isNotEmpty && mounted) {
            final token = ApiClient().getAccessToken();
            final tenant = ApiClient().tenant;
            final headers = <String, String>{};
            if ((token ?? '').isNotEmpty) {
              headers['Authorization'] = 'Bearer $token';
            }
            if ((tenant ?? '').isNotEmpty) {
              headers['X-Tenant-Id'] = tenant!;
            }
            final ok = await LogoProbeCache.instance
                .ensureAvailable(logo, headers: headers);
            if (ok) {
              await precacheImage(
                  NetworkImage(logo, headers: headers), context);
            }
          }
        } catch (_) {}
        _description = (m['description'] ?? '').toString();
        _playbackType = (m['playback_type'] ?? '').toString();
        _listenerCount = (m['listener_count'] as num?)?.toInt();
        _totalListens = (m['total_listens'] as num?)?.toInt();
        final meta = m['meta'];
        if (meta is Map) {
          _allowedUpstream = List<String>.from(
              (meta['allowed_upstream'] as List? ?? const [])
                  .map((e) => e.toString()));
          _tags = List<String>.from(
              (meta['tags'] as List? ?? const []).map((e) => e.toString()));
        }
      } catch (_) {}
    }

    // Start playback if needed (pick lowest variant when possible)
    if (tv.controller == null || tv.slug != widget.slug) {
      // Strictly replace any previous Live session when switching slugs
      try {
        await TvController.instance.stop();
      } catch (_) {}
      String? startUrl = _masterUrl;
      try {
        if ((_masterUrl ?? '').toLowerCase().endsWith('.m3u8')) {
          final txt = await Dio().get<String>(_masterUrl!,
              options: Options(responseType: ResponseType.plain));
          final data = txt.data ?? '';
          final opts = _parseHlsVariantUrls(_masterUrl!, data);
          if (opts.isNotEmpty) {
            opts.sort(
                (a, b) => (a.height ?? 99999).compareTo(b.height ?? 99999));
            startUrl = opts.first.url;
          }
        }
      } catch (_) {}
      if (startUrl != null && startUrl.isNotEmpty) {
        await TvController.instance.startPlayback(
          slug: widget.slug,
          title: 'Live TV',
          url: startUrl,
          sessionId: null,
        );
      }
    }

    // Load variants for quality menu and set current label (use cache when possible)
    await _loadVariantsAndSetCurrent();
    if (mounted) setState(() => _metaLoading = false);
  }

  Future<void> _loadVariantsAndSetCurrent() async {
    // Use cached variants if present
    final cached = _variantCache[widget.slug];
    if (cached != null && cached.isNotEmpty) {
      _variantOptions = cached;
    } else {
      _variantOptions = const [];
    }
    _currentQuality = 'Auto';
    final master = _masterUrl ?? '';
    if (_variantOptions.isEmpty && master.toLowerCase().endsWith('.m3u8')) {
      try {
        final txt = await Dio().get<String>(master,
            options: Options(responseType: ResponseType.plain));
        final data = txt.data ?? '';
        _variantOptions = _parseHlsVariantUrls(master, data);
        if (_variantOptions.isNotEmpty) {
          _variantCache[widget.slug] = _variantOptions;
        }
        final cur = TvController.instance.playbackUrl;
        if (cur != null && cur.isNotEmpty) {
          final match = _variantOptions.where((v) => v.url == cur).toList();
          _currentQuality = match.isNotEmpty ? match.first.label : 'Auto';
        }
      } catch (_) {}
    }
    // If using cached variants, still compute current label
    if (_variantOptions.isNotEmpty && _currentQuality == 'Auto') {
      final cur = TvController.instance.playbackUrl;
      if (cur != null && cur.isNotEmpty) {
        final match = _variantOptions.where((v) => v.url == cur).toList();
        _currentQuality = match.isNotEmpty ? match.first.label : 'Auto';
      }
    }
  }

  @override
  void dispose() {
    try {
      _controlsTimer?.cancel();
    } catch (_) {}
    try {
      _qualityToastTimer?.cancel();
    } catch (_) {}
    _exitFullscreen(restoreOnly: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return WillPopScope(
      onWillPop: () async {
        if (_fullscreen) {
          await _exitFullscreen();
          return false;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          TvController.instance.setInFullPlayer(false);
        });
        return true;
      },
      child: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          child: Builder(
            builder: (ctx) {
              final isLandscape =
                  MediaQuery.of(ctx).orientation == Orientation.landscape;
              // Visual-only drag feedback for the video: translate Y and slight scale
              final double animDy = _dragDy.clamp(-120.0, 120.0);
              final double pDown =
                  _dragDy > 0 ? (_dragDy / 300.0).clamp(0.0, 1.0) : 0.0;
              final double pUp =
                  _dragDy < 0 ? ((-_dragDy) / 120.0).clamp(0.0, 1.0) : 0.0;
              final double animScale = 1.0 - (0.08 * pDown) + (0.04 * pUp);
              return Transform.translate(
                offset: Offset.zero,
                child: Transform.scale(
                  scale: 1.0,
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      // Video at the very top in portrait; in landscape fill available space
                      if (!isLandscape)
                        SafeArea(
                          top: true,
                          bottom: false,
                          child: Transform.translate(
                            offset: Offset(0, animDy),
                            child: Transform.scale(
                              scale: animScale,
                              alignment: Alignment.topCenter,
                              child: AspectRatio(
                                aspectRatio: (c?.value.aspectRatio ?? 0) == 0
                                    ? 16 / 9
                                    : c!.value.aspectRatio,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (c != null)
                                      VideoPlayer(c)
                                    else
                                      const ColoredBox(color: Colors.black12),
                                    // Loading overlay (initializing/buffering)
                                    if (c == null ||
                                        !(c.value.isInitialized) ||
                                        (c.value.isBuffering))
                                      const Center(
                                          child: CircularProgressIndicator()),
                                    if (_switchingQuality)
                                      const Align(
                                          alignment: Alignment.topCenter,
                                          child: LinearProgressIndicator(
                                              minHeight: 2)),
                                    Positioned.fill(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _toggleControls,
                                        onVerticalDragUpdate: (d) {
                                          setState(() {
                                            _dragDy = (_dragDy + d.delta.dy)
                                                .clamp(
                                                    -120.0,
                                                    MediaQuery.of(context)
                                                        .size
                                                        .height);
                                          });
                                        },
                                        onVerticalDragEnd: (details) async {
                                          final h = MediaQuery.of(context)
                                              .size
                                              .height;
                                          final threshold = h * 0.22;
                                          final vel =
                                              details.primaryVelocity ?? 0.0;
                                          if ((-_dragDy) > 60 || vel < -900) {
                                            await _enterFullscreen();
                                            setState(() {
                                              _dragDy = 0.0;
                                            });
                                            return;
                                          }
                                          final shouldClose =
                                              _dragDy > threshold || vel > 900;
                                          if (shouldClose) {
                                            HapticFeedback.lightImpact();
                                            _dragDy = 0.0;
                                            Navigator.of(context).maybePop();
                                          } else {
                                            setState(() {
                                              _dragDy = 0.0;
                                            });
                                          }
                                        },
                                        child: AnimatedOpacity(
                                          opacity: _showControls ? 1.0 : 0.0,
                                          duration:
                                              const Duration(milliseconds: 150),
                                          child: IgnorePointer(
                                            ignoring: !_showControls,
                                            child: Container(
                                              color: Colors.black45,
                                              child: Column(
                                                children: [
                                                  const Spacer(),
                                                  Center(
                                                    child: IconButton(
                                                      iconSize: 64,
                                                      color: Colors.white,
                                                      icon: Icon((c?.value
                                                                  .isPlaying ??
                                                              false)
                                                          ? Icons.pause_circle
                                                          : Icons.play_circle),
                                                      onPressed: () async {
                                                        if (c == null) return;
                                                        setState(() {
                                                          if (c.value
                                                              .isPlaying) {
                                                            c.pause();
                                                          } else {
                                                            c.play();
                                                          }
                                                        });
                                                        _kickControlsTimer();
                                                      },
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: IconButton(
                                        tooltip: 'Back',
                                        icon: const Icon(Icons.arrow_back,
                                            color: Colors.white),
                                        onPressed: () =>
                                            Navigator.of(context).maybePop(),
                                      ),
                                    ),
                                    if (_variantOptions.isNotEmpty)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: IconButton(
                                          tooltip: 'Quality ($_currentQuality)',
                                          icon: const Icon(Icons.settings,
                                              color: Colors.white),
                                          onPressed: _showQualityPicker,
                                        ),
                                      ),
                                    Positioned(
                                      left: 8,
                                      bottom: 8,
                                      child: IconButton(
                                        tooltip: _muted ? 'Unmute' : 'Mute',
                                        icon: Icon(
                                            _muted
                                                ? Icons.volume_off
                                                : Icons.volume_up,
                                            color: Colors.white),
                                        onPressed: () async {
                                          setState(() => _muted = !_muted);
                                          try {
                                            await c
                                                ?.setVolume(_muted ? 0.0 : 1.0);
                                          } catch (_) {}
                                          _kickControlsTimer();
                                        },
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.topCenter,
                                      child: Container(
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                            color: Colors.redAccent
                                                .withOpacity(0.9),
                                            borderRadius:
                                                BorderRadius.circular(6)),
                                        child: const Text('LIVE',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11)),
                                      ),
                                    ),
                                    Positioned(
                                      right: 8,
                                      bottom: 8,
                                      child: IconButton(
                                        tooltip: (isLandscape || _fullscreen)
                                            ? 'Exit fullscreen'
                                            : 'Fullscreen',
                                        icon: Icon(
                                            (isLandscape || _fullscreen)
                                                ? Icons.fullscreen_exit
                                                : Icons.fullscreen,
                                            color: Colors.white),
                                        onPressed: () async {
                                          if (isLandscape || _fullscreen) {
                                            await _exitFullscreen();
                                          } else {
                                            await _enterFullscreen();
                                          }
                                        },
                                      ),
                                    ),
                                    if (_qualityToast != null)
                                      Positioned(
                                        top: 44,
                                        right: 8,
                                        child: AnimatedOpacity(
                                          duration:
                                              const Duration(milliseconds: 150),
                                          opacity: 1,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                                color: Colors.black87,
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: Text(_qualityToast!,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (isLandscape)
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Transform.translate(
                              offset: Offset(0, animDy),
                              child: Transform.scale(
                                scale: animScale,
                                alignment: Alignment.topCenter,
                                child: AspectRatio(
                                  aspectRatio: (c?.value.aspectRatio ?? 0) == 0
                                      ? 16 / 9
                                      : c!.value.aspectRatio,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (c != null)
                                        VideoPlayer(c)
                                      else
                                        const ColoredBox(color: Colors.black12),
                                      if (c == null ||
                                          !(c.value.isInitialized) ||
                                          (c.value.isBuffering))
                                        const Center(
                                            child: CircularProgressIndicator()),
                                      if (_switchingQuality)
                                        const Align(
                                            alignment: Alignment.topCenter,
                                            child: LinearProgressIndicator(
                                                minHeight: 2)),
                                      Positioned.fill(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _toggleControls,
                                          onVerticalDragUpdate: (d) {
                                            setState(() {
                                              _dragDy = (_dragDy + d.delta.dy)
                                                  .clamp(
                                                      -120.0,
                                                      MediaQuery.of(context)
                                                          .size
                                                          .height);
                                            });
                                          },
                                          onVerticalDragEnd: (details) async {
                                            final h = MediaQuery.of(context)
                                                .size
                                                .height;
                                            final threshold = h * 0.22;
                                            final vel =
                                                details.primaryVelocity ?? 0.0;
                                            if ((-_dragDy) > 60 || vel < -900) {
                                              await _enterFullscreen();
                                              setState(() {
                                                _dragDy = 0.0;
                                              });
                                              return;
                                            }
                                            final shouldClose =
                                                _dragDy > threshold ||
                                                    vel > 900;
                                            if (shouldClose) {
                                              HapticFeedback.lightImpact();
                                              _dragDy = 0.0;
                                              Navigator.of(context).maybePop();
                                            } else {
                                              setState(() {
                                                _dragDy = 0.0;
                                              });
                                            }
                                          },
                                          child: AnimatedOpacity(
                                            opacity: _showControls ? 1.0 : 0.0,
                                            duration: const Duration(
                                                milliseconds: 150),
                                            child: IgnorePointer(
                                              ignoring: !_showControls,
                                              child: Container(
                                                color: Colors.black45,
                                                child: Column(
                                                  children: [
                                                    const Spacer(),
                                                    Center(
                                                      child: IconButton(
                                                        iconSize: 64,
                                                        color: Colors.white,
                                                        icon: Icon((c?.value
                                                                    .isPlaying ??
                                                                false)
                                                            ? Icons.pause_circle
                                                            : Icons
                                                                .play_circle),
                                                        onPressed: () async {
                                                          if (c == null) return;
                                                          setState(() {
                                                            if (c.value
                                                                .isPlaying) {
                                                              c.pause();
                                                            } else {
                                                              c.play();
                                                            }
                                                          });
                                                          _kickControlsTimer();
                                                        },
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                          top: 8,
                                          left: 8,
                                          child: IconButton(
                                              tooltip: 'Back',
                                              icon: const Icon(Icons.arrow_back,
                                                  color: Colors.white),
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .maybePop())),
                                      if (_variantOptions.isNotEmpty)
                                        Positioned(
                                            top: 8,
                                            right: 8,
                                            child: IconButton(
                                                tooltip:
                                                    'Quality ($_currentQuality)',
                                                icon: const Icon(Icons.settings,
                                                    color: Colors.white),
                                                onPressed: _showQualityPicker)),
                                      Positioned(
                                          left: 8,
                                          bottom: 8,
                                          child: IconButton(
                                              tooltip:
                                                  _muted ? 'Unmute' : 'Mute',
                                              icon: Icon(
                                                  _muted
                                                      ? Icons.volume_off
                                                      : Icons.volume_up,
                                                  color: Colors.white),
                                              onPressed: () async {
                                                setState(
                                                    () => _muted = !_muted);
                                                try {
                                                  await c?.setVolume(
                                                      _muted ? 0.0 : 1.0);
                                                } catch (_) {}
                                                _kickControlsTimer();
                                              })),
                                      Align(
                                          alignment: Alignment.topCenter,
                                          child: Container(
                                              margin:
                                                  const EdgeInsets.only(top: 8),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                  color: Colors.redAccent
                                                      .withOpacity(0.9),
                                                  borderRadius:
                                                      BorderRadius.circular(6)),
                                              child: const Text('LIVE',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 11)))),
                                      Positioned(
                                          right: 8,
                                          bottom: 8,
                                          child: IconButton(
                                              tooltip:
                                                  (isLandscape || _fullscreen)
                                                      ? 'Exit fullscreen'
                                                      : 'Fullscreen',
                                              icon: Icon(
                                                  (isLandscape || _fullscreen)
                                                      ? Icons.fullscreen_exit
                                                      : Icons.fullscreen,
                                                  color: Colors.white),
                                              onPressed: () async {
                                                if (isLandscape ||
                                                    _fullscreen) {
                                                  await _exitFullscreen();
                                                } else {
                                                  await _enterFullscreen();
                                                }
                                              })),
                                      if (_qualityToast != null)
                                        Positioned(
                                            top: 44,
                                            right: 8,
                                            child: AnimatedOpacity(
                                                duration: const Duration(
                                                    milliseconds: 150),
                                                opacity: 1,
                                                child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                        color: Colors.black87,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8)),
                                                    child: Text(_qualityToast!,
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600))))),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!isLandscape) const Divider(height: 1),
                      if (!isLandscape)
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (_metaLoading)
                                      Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                              color: Colors.white24,
                                              borderRadius:
                                                  BorderRadius.circular(8)))
                                    else if ((_channelLogoUrl ?? '').isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: _channelLogoUrl!,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: Colors.white24,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          httpHeaders: {
                                            if ((ApiClient().getAccessToken() ??
                                                    '')
                                                .isNotEmpty)
                                              'Authorization':
                                                  'Bearer ${ApiClient().getAccessToken()}',
                                            if ((ApiClient().tenant ?? '')
                                                .isNotEmpty)
                                              'X-Tenant-Id':
                                                  ApiClient().tenant!,
                                          },
                                          errorWidget: (_, __, ___) =>
                                              const Icon(Icons.live_tv,
                                                  size: 28),
                                        ),
                                      )
                                    else
                                      const Icon(Icons.live_tv, size: 28),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (_metaLoading)
                                            Container(
                                                height: 16,
                                                margin: const EdgeInsets.only(
                                                    right: 40),
                                                decoration: BoxDecoration(
                                                    color: Colors.white24,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4)))
                                          else
                                            Text(
                                                ((_titleText ?? '').isNotEmpty
                                                    ? _titleText!
                                                    : _channelName ??
                                                        'Live TV'),
                                                style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight:
                                                        FontWeight.w700),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          if ((_channelName ?? '').isNotEmpty)
                                            Text(_channelName!,
                                                style: TextStyle(
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.color),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  if ((_playbackType ?? '').isNotEmpty)
                                    Chip(
                                        avatar:
                                            const Icon(Icons.waves, size: 16),
                                        label: Text((_playbackType ?? '')
                                            .toUpperCase())),
                                  if (_listenerCount != null)
                                    Chip(
                                        avatar: const Icon(Icons.headphones,
                                            size: 16),
                                        label:
                                            Text('Listeners: $_listenerCount')),
                                  if (_totalListens != null)
                                    Chip(
                                        avatar: const Icon(Icons.equalizer,
                                            size: 16),
                                        label: Text('Total: $_totalListens')),
                                  if (_variantOptions.isNotEmpty)
                                    Chip(
                                        avatar: const Icon(Icons.settings,
                                            size: 16),
                                        label: Text(_variantOptions
                                            .map((e) => e.label)
                                            .join(' · '))),
                                ]),
                                const SizedBox(height: 8),
                                if ((_description ?? '').isNotEmpty)
                                  Text(_description!,
                                      style: const TextStyle(fontSize: 13)),
                                const SizedBox(height: 8),
                                if (_allowedUpstream.isNotEmpty) ...[
                                  Text('Upstream hosts',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _allowedUpstream
                                        .map((h) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                  color: Colors.blueGrey
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              child: Text(h,
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                            ))
                                        .toList(),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                if (_tags.isNotEmpty)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _tags
                                        .map((t) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                  color: Colors.deepPurple
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                  border: Border.all(
                                                      color: Colors.deepPurple
                                                          .withOpacity(0.4))),
                                              child: Text(t.toUpperCase(),
                                                  style: const TextStyle(
                                                      color: Colors.deepPurple,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ))
                                        .toList(),
                                  ),
                              ],
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
      ),
    );
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _kickControlsTimer();
  }

  void _kickControlsTimer() {
    try {
      _controlsTimer?.cancel();
    } catch (_) {}
    _controlsTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => _showControls = false);
    });
  }

  Future<void> _showQualityPicker() async {
    if (_variantOptions.isEmpty || _masterUrl == null) return;
    final options = ['Auto', ..._variantOptions.map((v) => v.label)];
    final sel = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return ListView.builder(
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (_, i) {
            final label = options[i];
            final selected = label == _currentQuality;
            return ListTile(
              title: Text(label),
              trailing: selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(ctx).pop(label),
            );
          },
        );
      },
    );
    if (sel == null) return;
    if (sel == 'Auto') {
      await _switchToUrl(_masterUrl!);
      _setQualityToast('Auto');
      return;
    }
    final v = _variantOptions.firstWhere((e) => e.label == sel,
        orElse: () => _variantOptions.first);
    await _switchToUrl(v.url);
    _setQualityToast(v.label);
  }

  Future<void> _switchToUrl(String url) async {
    setState(() => _switchingQuality = true);
    try {
      await TvController.instance.startPlayback(
          slug: widget.slug, title: 'Live TV', url: url, sessionId: null);
    } finally {
      if (mounted) setState(() => _switchingQuality = false);
    }
  }

  void _setQualityToast(String label) {
    if (!mounted) return;
    setState(() {
      _currentQuality = label;
      _qualityToast = label;
    });
    try {
      _qualityToastTimer?.cancel();
    } catch (_) {}
    _qualityToastTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _qualityToast = null);
    });
  }

  // HLS helpers
  List<_Variant> _parseHlsVariantUrls(String masterUrl, String master) {
    final base = Uri.parse(masterUrl);
    final out = <_Variant>[];
    final lines = master.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      if (l.startsWith('#EXT-X-STREAM-INF')) {
        String? res;
        String? bw;
        final attrs = l.split(',');
        for (final a in attrs) {
          final kv = a.split('=');
          if (kv.length < 2) continue;
          final k = kv[0];
          final v = kv.sublist(1).join('=');
          if (k.contains('RESOLUTION')) res = v.replaceAll('"', '');
          if (k.contains('BANDWIDTH')) bw = v.replaceAll('"', '');
        }
        String? uri;
        for (var j = i + 1; j < lines.length; j++) {
          final nl = lines[j].trim();
          if (nl.isEmpty || nl.startsWith('#')) continue;
          uri = nl;
          break;
        }
        if (uri != null) {
          final u = base.resolve(uri).toString();
          int? width;
          int? height;
          int? bandwidth;
          if (res != null && res.contains('x')) {
            final parts = res.split('x');
            width = int.tryParse(parts[0]);
            height = int.tryParse(parts[1]);
          }
          if (bw != null) bandwidth = int.tryParse(bw);
          final label = [
            if (res != null) res,
            if (bandwidth != null) '${(bandwidth / 1000).round()}kbps'
          ].join(' ');
          out.add(_Variant(
              label: label.isNotEmpty ? label : 'Variant ${out.length + 1}',
              url: u,
              width: width,
              height: height,
              bandwidth: bandwidth));
        }
      }
    }
    return out;
  }
}

class _Variant {
  final String label;
  final String url;
  final int? width;
  final int? height;
  final int? bandwidth;
  const _Variant(
      {required this.label,
      required this.url,
      this.width,
      this.height,
      this.bandwidth});
}
