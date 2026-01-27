import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/tenant_prefs.dart';
import '../core/localization/l10n.dart';
import '../features/series/series_service.dart';
import '../auth/tenant_auth_client.dart';
import 'channel_service.dart';
import 'channel_ui_utils.dart';
import 'playlist_detail_page_view.dart';
import 'player/channel_mini_player_manager.dart';
import 'player/channel_now_playing.dart';
import 'player/channel_youtube_player.dart';

class PlaylistDetailPage extends StatefulWidget {
  final String playlistId;
  final String title;
  const PlaylistDetailPage(
      {super.key, required this.playlistId, required this.title});

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  final ChannelsService _service = ChannelsService();
  final LocalizationController _lc = LocalizationController();
  final List<Map<String, dynamic>> _videos = [];
  Map<String, dynamic>? _currentVideo;
  bool _isPlaying = false;
  final Set<String> _watchedVideoIds = <String>{};
  SeriesService? _seriesService;
  String? _showSlug;
  bool _loadingReminder = false;
  bool _hasReminder = false;
  bool _isReminderActive = false;
  int? _reminderId;
  final GlobalKey _playerKey = GlobalKey();
  Timer? _autoFullscreenTimer;
  bool _nowPlayingExpanded = false;
  bool _loading = true;
  int _page = 1;
  bool _hasNext = true;
  bool _loadingMore = false;
  final ScrollController _scroll = ScrollController();
  Map<String, dynamic>? _playlist;
  bool _loadingDetail = true;
  bool _allowMiniPlayerOverride = false;
  bool _playOnInit = false;
  int _currentVideoVersion = 0;
  int _lastFloatingVersion = -1;
  bool? _lastFloatingMinimized;
  ChannelNowPlaying? _lastNowPlaying;
  bool _fillViewportScheduled = false;

  String _t(String key) => _lc.t(key);

  void _onMiniStateChanged() {
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    final minimized = ChannelMiniPlayerManager.I.isMinimized.value;
    if (_lastNowPlaying != null && now == null) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _currentVideo = null;
          _playOnInit = false;
          _currentVideoVersion += 1;
          _allowMiniPlayerOverride = false;
        });
      });
    }
    _lastNowPlaying = now;

    if (!minimized && mounted) {
      _playOnInit = false;
    }
  }

  @override
  void initState() {
    super.initState();
    ChannelMiniPlayerManager.I.setHideGlobalBottomOverlays(false);
    _lc.load();
    _loadPrefs();
    _loadPage(1);
    _loadDetail();
    ChannelMiniPlayerManager.I.nowPlaying.addListener(_onMiniStateChanged);
    ChannelMiniPlayerManager.I.isMinimized.addListener(_onMiniStateChanged);
    _scroll.addListener(_onScroll);
  }

  String _watchedKey(String playlistId) => 'playlist_watched_$playlistId';

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final watched = prefs.getStringList(_watchedKey(widget.playlistId)) ??
          const <String>[];
      if (!mounted) return;
      setState(() {
        _watchedVideoIds
          ..clear()
          ..addAll(watched);
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _toggleWatched(String videoId) async {
    if (videoId.isEmpty) return;
    setState(() {
      if (_watchedVideoIds.contains(videoId)) {
        _watchedVideoIds.remove(videoId);
      } else {
        _watchedVideoIds.add(videoId);
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _watchedKey(widget.playlistId), _watchedVideoIds.toList());
    } catch (_) {}
  }

  bool get _remindAvailable => _showSlug != null && _showSlug!.isNotEmpty;

  bool get _remindOn => _hasReminder && _isReminderActive;

  String? _extractShowSlug(Map<String, dynamic>? playlist) {
    if (playlist == null) return null;
    const keys = [
      'show_slug',
      'show',
      'showSlug',
      'series_show',
      'series',
    ];
    for (final k in keys) {
      final v = playlist[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map) {
        final slug = v['slug'];
        if (slug is String && slug.trim().isNotEmpty) return slug.trim();
      }
    }
    return null;
  }

  Future<void> _ensureSeriesService() async {
    if (_seriesService != null) return;
    final tenant = await TenantPrefs.getTenant();
    if (tenant == null || tenant.trim().isEmpty) return;
    _seriesService = SeriesService(api: AuthApi(), tenantId: tenant.trim());
  }

  Future<void> _loadReminderStatus() async {
    final slug = _showSlug;
    if (slug == null || slug.isEmpty) return;
    await _ensureSeriesService();
    final service = _seriesService;
    if (service == null) return;
    setState(() => _loadingReminder = true);
    try {
      final res = await service.getReminderStatus(slug);
      final has = res['has_reminder'] == true;
      final active = res['is_active'] == true;
      final id = res['id'];
      if (!mounted) return;
      setState(() {
        _hasReminder = has;
        _isReminderActive = active;
        _reminderId = (id is int) ? id : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasReminder = false;
        _isReminderActive = false;
        _reminderId = null;
      });
    } finally {
      if (mounted) setState(() => _loadingReminder = false);
    }
  }

  Future<void> _toggleShowReminder() async {
    if (_loadingReminder) return;
    final slug = _showSlug;
    if (slug == null || slug.isEmpty) return;
    await _ensureSeriesService();
    final service = _seriesService;
    if (service == null) return;
    setState(() => _loadingReminder = true);
    try {
      if (!_remindOn) {
        final res = await service.createReminder(slug);
        final id = res['id'];
        final active = res['is_active'] == true;
        if (!mounted) return;
        setState(() {
          _hasReminder = true;
          _isReminderActive = active;
          _reminderId = (id is int) ? id : null;
        });
      } else {
        final id = _reminderId;
        if (id != null) {
          await service.deleteReminder(id);
        }
        if (!mounted) return;
        setState(() {
          _hasReminder = false;
          _isReminderActive = false;
          _reminderId = null;
        });
      }
    } catch (_) {
      // keep previous state
    } finally {
      if (mounted) setState(() => _loadingReminder = false);
    }
  }

  @override
  void dispose() {
    ChannelMiniPlayerManager.I.nowPlaying.removeListener(_onMiniStateChanged);
    ChannelMiniPlayerManager.I.isMinimized.removeListener(_onMiniStateChanged);
    _scroll.removeListener(_onScroll);
    try {
      _autoFullscreenTimer?.cancel();
    } catch (_) {}
    ChannelMiniPlayerManager.I.setHideGlobalBottomOverlays(false);
    super.dispose();
  }

  Future<bool> _handleWillPop() async {
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    final minimized = ChannelMiniPlayerManager.I.isMinimized.value;
    final isPlaying = (now?.isPlaying == true) || _isPlaying;

    if (isPlaying && !minimized) {
      ChannelMiniPlayerManager.I.setMinimized(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return true;
  }

  void _onScroll() {
    if (!_hasNext || _loadingMore || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  void _scheduleFillViewport() {
    if (_fillViewportScheduled) return;
    _fillViewportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _fillViewportScheduled = false;
      if (!mounted) return;
      if (!_scroll.hasClients) return;
      if (!_hasNext || _loadingMore || _loading) return;

      final pos = _scroll.position;
      final notScrollableYet = pos.maxScrollExtent < 24;
      if (!notScrollableYet) return;

      final beforeCount = _videos.length;
      await _loadMore();
      if (!mounted) return;
      if (_videos.length == beforeCount) return;
      _scheduleFillViewport();
    });
  }

  Future<void> _loadPage(int page) async {
    setState(() {
      _loading = page == 1;
    });
    try {
      final res =
          await _service.getPlaylistVideos(widget.playlistId, page: page);
      final results = List<Map<String, dynamic>>.from(res['results'] as List);
      setState(() {
        if (page == 1) {
          _videos
            ..clear()
            ..addAll(results);
        } else {
          _videos.addAll(results);
        }
        _page = page;
        _hasNext = res['next'] != null;
        _loading = false;
        _loadingMore = false;
      });
      _scheduleFillViewport();
    } catch (_) {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasNext) return;
    setState(() {
      _loadingMore = true;
    });
    await _loadPage(_page + 1);
  }

  @override
  Widget build(BuildContext context) {
    final String appBarTitle =
        widget.title.isNotEmpty ? widget.title : 'Playlist';
    final bool showSpinner = (_loading && _videos.isEmpty) && _loadingDetail;
    if (showSpinner) {
      return Scaffold(
        appBar: AppBar(title: Text(appBarTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final String title = (_playlist != null && _playlist!['title'] != null)
        ? _playlist!['title'].toString()
        : widget.title;
    final dynamic chField = _playlist != null ? _playlist!['channel'] : null;
    final String? channelSlug =
        (chField is String && chField.isNotEmpty) ? chField : null;
    final int itemCount = (_playlist != null && _playlist!['item_count'] is int)
        ? (_playlist!['item_count'] as int)
        : (_videos.isNotEmpty ? _videos.length : 0);
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool hasNowPlaying =
        ChannelMiniPlayerManager.I.nowPlaying.value != null;
    final String? heroThumb = (_playlist != null &&
            _playlist!['thumbnail_url'] is String &&
            (_playlist!['thumbnail_url'] as String).isNotEmpty)
        ? (_playlist!['thumbnail_url'] as String)
        : (_videos.isNotEmpty ? thumbFromMap(_videos.first) : null);
    final String overviewText = _extractOverview(_playlist);
    final Map<String, dynamic>? headerVideo =
        (isLandscape && !hasNowPlaying && _currentVideo == null)
            ? null
            : (_currentVideo ?? (_videos.isNotEmpty ? _videos.first : null));
    final String? thumb =
        headerVideo != null ? thumbFromMap(headerVideo) : null;
    final String meta = [
      if (itemCount > 0) '$itemCount videos',
      if (channelSlug != null && channelSlug.isNotEmpty) channelSlug,
    ].join(' • ');
    final bool shouldShowHeaderPlayer =
        !isLandscape || hasNowPlaying || _currentVideo != null;

    final Widget? headerPlayer = (shouldShowHeaderPlayer &&
            heroThumb != null &&
            heroThumb.isNotEmpty)
        ? ValueListenableBuilder<bool>(
            valueListenable: ChannelMiniPlayerManager.I.isMinimized,
            builder: (context, minimized, _) {
              final player = ChannelYoutubePlayer(
                key: _playerKey,
                video: _currentVideo,
                playlistId: widget.playlistId,
                playlistTitle: widget.title,
                autoRotateFullscreenHint: _t('enable_auto_rotate_fullscreen'),
                playOnInit: _playOnInit,
                onAutoPlayNext: () {
                  if (!mounted) return;
                  if (_videos.isEmpty) return;

                  final current = _currentVideo ?? _videos.first;
                  final currentId = (current['id'] ?? '').toString();
                  int idx = -1;
                  if (currentId.isNotEmpty) {
                    idx = _videos.indexWhere(
                        (v) => (v['id'] ?? '').toString() == currentId);
                  }
                  if (idx < 0) {
                    idx = 0;
                  }
                  final nextIdx = idx + 1;
                  if (nextIdx >= _videos.length) {
                    return;
                  }
                  setState(() {
                    _currentVideo = _videos[nextIdx];
                    _currentVideoVersion += 1;
                    _playOnInit = true;
                    if (ChannelMiniPlayerManager.I.isMinimized.value) {
                      _allowMiniPlayerOverride = true;
                    }
                  });
                },
                onPlayingChanged: (playing) {
                  if (!mounted || _isPlaying == playing) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _isPlaying = playing);
                  });
                },
                fallback: heroThumb.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: heroThumb,
                        fit: BoxFit.cover,
                        httpHeaders: authHeadersFor(heroThumb),
                      )
                    : Container(color: Colors.black26),
              );
              final shouldOverride = !minimized || _allowMiniPlayerOverride;
              if (_lastFloatingMinimized != minimized ||
                  _lastFloatingVersion != _currentVideoVersion ||
                  _allowMiniPlayerOverride) {
                _lastFloatingMinimized = minimized;
                _lastFloatingVersion = _currentVideoVersion;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !shouldOverride) return;
                  ChannelMiniPlayerManager.I.floatingPlayer.value = player;
                  _allowMiniPlayerOverride = false;
                });
              }
              if (minimized) {
                return const SizedBox.shrink();
              }
              return AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!minimized) player,
                    if (!isLandscape && !minimized)
                      IgnorePointer(
                        ignoring: true,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: _isPlaying ? 0 : 1,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(.15),
                                      Colors.black.withOpacity(.65),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 16,
                                bottom: 12,
                                right: 16,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 96,
                                        height: 54,
                                        child: thumb != null && thumb.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: thumb,
                                                fit: BoxFit.cover,
                                                httpHeaders:
                                                    authHeadersFor(thumb),
                                              )
                                            : Container(color: Colors.black26),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          if (meta.isNotEmpty)
                                            Text(
                                              meta,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color: Colors.white70),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      )
                  ],
                ),
              );
            },
          )
        : null;

    return ValueListenableBuilder<bool>(
      valueListenable: ChannelMiniPlayerManager.I.isMinimized,
      builder: (context, minimized, _) {
        final List<Widget> listHeader = [
          if (overviewText.isNotEmpty) const Divider(height: 1),
          if (overviewText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'Overview',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          if (overviewText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                overviewText,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'Videos',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ];

        final int headerCount = listHeader.length;
        final navBottom = MediaQuery.of(context).padding.bottom;
        final listBottomPad = navBottom + 8;

        return PlaylistDetailPageView(
          appBarTitle: appBarTitle,
          isLandscape: isLandscape,
          minimized: minimized,
          onWillPop: _handleWillPop,
          headerPlayer: headerPlayer,
          headerVideo: headerVideo,
          watchedVideoIds: _watchedVideoIds,
          onToggleNowPlayingExpanded: () {
            setState(() {
              _nowPlayingExpanded = !_nowPlayingExpanded;
            });
          },
          nowPlayingExpanded: _nowPlayingExpanded,
          remindAvailable: _remindAvailable,
          loadingReminder: _loadingReminder,
          remindOn: _remindOn,
          onToggleReminder: _toggleShowReminder,
          listHeader: listHeader,
          headerCount: headerCount,
          listBottomPad: listBottomPad,
          videos: _videos,
          loadingMore: _loadingMore,
          hasNext: _hasNext,
          scrollController: _scroll,
          onRefresh: () async {
            await _loadDetail();
            await _loadPage(1);
          },
          onTapVideo: (v) {
            setState(() {
              _currentVideo = v;
              _currentVideoVersion += 1;
              _playOnInit = true;
              if (ChannelMiniPlayerManager.I.isMinimized.value) {
                _allowMiniPlayerOverride = true;
              }
            });
          },
          onToggleWatched: _toggleWatched,
        );
      },
    );
  }

  String _extractOverview(Map<String, dynamic>? m) {
    if (m == null) return '';
    final keys = [
      'overview',
      'description',
      'summary',
      'about',
      'details',
      'overview_en',
      'overview_am',
    ];
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  Future<void> _loadDetail() async {
    setState(() => _loadingDetail = true);
    try {
      final m = await _service.getPlaylistDetail(widget.playlistId);
      final showSlug = _extractShowSlug(m);
      setState(() {
        _playlist = m;
        _showSlug = showSlug;
        _loadingDetail = false;
      });
      if (showSlug != null && showSlug.isNotEmpty) {
        await _ensureSeriesService();
        if (mounted) setState(() {});
        await _loadReminderStatus();
      }
    } catch (_) {
      setState(() => _loadingDetail = false);
    }
  }
}
