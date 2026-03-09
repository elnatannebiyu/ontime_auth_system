import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'channel_service.dart';
import 'channel_ui_utils.dart';
import 'player/channel_mini_player_manager.dart';
import 'player/channel_now_playing.dart';
import 'player/channel_youtube_player.dart';
import '../main.dart' show appNavigatorKey;
import '../core/navigation/route_stack_observer.dart';

enum PlaylistOpenOrigin {
  normal,
  maximizeFromMini,
}

class PlaylistDetailPageDummy extends StatefulWidget {
  final String playlistId;
  final String title;
  final PlaylistOpenOrigin origin;

  const PlaylistDetailPageDummy({
    super.key,
    required this.playlistId,
    required this.title,
    this.origin = PlaylistOpenOrigin.normal,
  });

  @override
  State<PlaylistDetailPageDummy> createState() =>
      _PlaylistDetailPageDummyState();
}

class _PlaylistDetailPageDummyState extends State<PlaylistDetailPageDummy> {
  final ChannelsService _service = ChannelsService();
  final GlobalKey _playerSurfaceKey = GlobalKey();
  final List<Map<String, dynamic>> _videos = [];
  final ScrollController _scroll = ScrollController();
  Map<String, dynamic>? _currentVideo;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  String? _heroThumb;
  bool _hideMainPlayer = false;
  bool _allowNowPlayingSync = true;
  bool _didSuppressMini = false;
  bool _handledPendingOpen = false;
  bool _didShowNullVideoToast = false;
  String? _lastFloatingVideoId;

  void _openCurrentPlaylistRoute() {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final target = '/playlist/${widget.playlistId}';
    if (appRouteStackObserver.containsName(target)) {
      nav.popUntil((route) => route.settings.name == target);
      return;
    }
    nav.push(
      MaterialPageRoute(
        settings: RouteSettings(name: target),
        builder: (_) => PlaylistDetailPageDummy(
          playlistId: widget.playlistId,
          title: widget.title,
        ),
      ),
    );
  }

  void _setMainPlayerVisible() {
    _allowNowPlayingSync = true;
    _hideMainPlayer = false;
    _didSuppressMini = true;
  }

  Map<String, dynamic>? _fallbackVideoFromSession() {
    final nowPlaying = ChannelMiniPlayerManager.I.nowPlaying.value;
    final nowVideo = _videoFromNowPlaying(nowPlaying);
    if (nowVideo != null) return nowVideo;
    final controllerVideoId = ChannelMiniPlayerManager.I.currentVideoId ?? '';
    if (controllerVideoId.isEmpty) return null;
    return <String, dynamic>{
      'youtube_id': controllerVideoId,
      'title': _currentVideo?['title'] ?? widget.title,
      if (((_currentVideo?['thumbnail_url'] ?? '').toString().isNotEmpty))
        'thumbnail_url': _currentVideo?['thumbnail_url'],
    };
  }

  Map<String, dynamic>? _videoFromNowPlaying(ChannelNowPlaying? nowPlaying) {
    if (nowPlaying == null) return null;
    return <String, dynamic>{
      'youtube_id': nowPlaying.videoId,
      'title': nowPlaying.title,
      if ((nowPlaying.thumbnailUrl ?? '').isNotEmpty)
        'thumbnail_url': nowPlaying.thumbnailUrl,
    };
  }

  ChannelYoutubePlayer _buildChannelPlayer({
    required Map<String, dynamic>? video,
  }) {
    final existing = ChannelMiniPlayerManager.I.floatingPlayer.value;
    final videoMap = video;
    final targetId = videoMap == null ? '' : _videoIdFromMap(videoMap);
    final currentSessionId = ChannelMiniPlayerManager.I.currentVideoId ?? '';
    if (existing is ChannelYoutubePlayer &&
        targetId.isNotEmpty &&
        currentSessionId == targetId) {
      return existing;
    }
    final player = ChannelYoutubePlayer(
      key: _playerSurfaceKey,
      video: video,
      playlistId: widget.playlistId,
      playlistTitle: widget.title,
      onExpand: _openCurrentPlaylistRoute,
      onClose: () {
        if (!mounted) return;
        setState(() {
          _currentVideo = null;
        });
      },
      onPlayingChanged: (playing) {
        if (!mounted || !playing) return;
        setState(() {});
      },
      onAutoPlayNext: () {},
      fallback: _heroPlaceholder(),
    );
    if (targetId.isNotEmpty) {
      _lastFloatingVideoId = targetId;
    }
    ChannelMiniPlayerManager.I.setFloatingPlayer(player);
    return player;
  }

  @override
  void initState() {
    super.initState();
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    final effectivePlaylistId =
        (now?.playlistId ?? ChannelMiniPlayerManager.I.lastPlaylistId ?? '')
            .trim();
    final samePlaylist =
        now != null && effectivePlaylistId == widget.playlistId;
    final fromMini = widget.origin == PlaylistOpenOrigin.maximizeFromMini ||
        ChannelMiniPlayerManager.I
            .consumePendingOpenFromMini(widget.playlistId);
    final isMiniActive =
        now != null && ChannelMiniPlayerManager.I.isMinimized.value;
    final isMiniDifferent = isMiniActive && !samePlaylist;
    _allowNowPlayingSync = (!fromMini || samePlaylist) && !isMiniDifferent;
    _hideMainPlayer = (fromMini && !samePlaylist) || isMiniDifferent;
    _didSuppressMini = !isMiniDifferent && (!fromMini || samePlaylist);
    if (_didSuppressMini) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ChannelMiniPlayerManager.I.setSuppressed(true);
      });
    }
    // If this playlist is opened while the unified mini-player is active for the
    // same playlist, restore the in-page player by default. (User can still
    // manually minimize again.)
    if (samePlaylist && isMiniActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ChannelMiniPlayerManager.I.isMinimized.value) {
          ChannelMiniPlayerManager.I.setMinimized(false);
        }
      });
    }
    _loadPage();
    _loadDetail();
    _scroll.addListener(_onScroll);
    ChannelMiniPlayerManager.I.nowPlaying.addListener(_syncFromNowPlaying);
    ChannelMiniPlayerManager.I.isMinimized.addListener(_onMinimizedChanged);
    _syncFromNowPlaying();
    if (fromMini && samePlaylist) {
      final fallbackVideo =
          _videoFromNowPlaying(ChannelMiniPlayerManager.I.nowPlaying.value);
      _currentVideo ??= fallbackVideo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ChannelMiniPlayerManager.I.isMinimized.value) {
          ChannelMiniPlayerManager.I.setMinimized(false);
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateFloatingPlayer();
    });
  }

  Widget _buildNowPlayingSummary() {
    return ValueListenableBuilder<ChannelNowPlaying?>(
      valueListenable: ChannelMiniPlayerManager.I.nowPlaying,
      builder: (context, now, _) {
        if (now == null || (now.playlistId ?? '') != widget.playlistId) {
          return Text(
            'Nothing playing',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        final thumb = now.thumbnailUrl;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 84,
                height: 48,
                child: (thumb ?? '').isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumb!,
                        fit: BoxFit.cover,
                        httpHeaders: authHeadersFor(thumb),
                      )
                    : Container(color: Colors.black26),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    now.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    now.isPlaying ? 'Playing' : 'Paused',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _videoIdFromMap(Map<String, dynamic> video) {
    return [
      video['youtube_id'],
      video['youtube_video_id'],
      video['yt_video_id'],
      video['video_id'],
    ].whereType<String>().firstWhere((v) => v.isNotEmpty, orElse: () => '');
  }

  void _setNowPlayingFromVideo(Map<String, dynamic> video,
      {bool openIfSame = false}) {
    final id = _videoIdFromMap(video);
    final title = (video['title'] ?? '').toString();
    if (id.isEmpty || title.isEmpty) return;
    ChannelMiniPlayerManager.I.setVideo(
      videoId: id,
      title: title,
      playlistId: widget.playlistId,
      playlistTitle: widget.title,
      thumbnailUrl: thumbFromMap(video),
      openIfSame: openIfSame,
    );
  }

  @override
  void dispose() {
    ChannelMiniPlayerManager.I.nowPlaying.removeListener(_syncFromNowPlaying);
    ChannelMiniPlayerManager.I.isMinimized.removeListener(_onMinimizedChanged);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    if (_didSuppressMini) {
      ChannelMiniPlayerManager.I.setSuppressed(false);
    }
    super.dispose();
  }

  void _onMinimizedChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateFloatingPlayer();
    });
  }

  void _updateFloatingPlayer() {
    final minimized = ChannelMiniPlayerManager.I.isMinimized.value;
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    final effectiveVideo = _currentVideo ?? _videoFromNowPlaying(now);
    if (effectiveVideo == null) {
      _lastFloatingVideoId = null;
      ChannelMiniPlayerManager.I.setFloatingPlayer(null);
      return;
    }
    if (!minimized && ChannelMiniPlayerManager.I.floatingPlayer.value != null) {
      return;
    }
    final floatingVideoId = _videoIdFromMap(effectiveVideo);
    if (!minimized &&
        floatingVideoId.isNotEmpty &&
        floatingVideoId == _lastFloatingVideoId) {
      return;
    }
    _buildChannelPlayer(video: effectiveVideo);
  }

  void _syncFromNowPlaying() {
    if (!_allowNowPlayingSync) return;
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    if (!mounted) return;
    if (now == null) return;
    final effectivePlaylistId =
        (now.playlistId ?? ChannelMiniPlayerManager.I.lastPlaylistId ?? '')
            .trim();
    if (effectivePlaylistId != widget.playlistId) return;
    final currentVideo = _currentVideo;
    if (currentVideo != null && _videoIdFromMap(currentVideo) == now.videoId) {
      return;
    }
    final match = _videos.isEmpty
        ? <String, dynamic>{
            'youtube_id': now.videoId,
            'title': now.title,
            if ((now.thumbnailUrl ?? '').isNotEmpty)
              'thumbnail_url': now.thumbnailUrl,
          }
        : _videos.firstWhere(
            (v) {
              final direct = [
                v['youtube_id'],
                v['youtube_video_id'],
                v['yt_video_id'],
                v['video_id'],
              ]
                  .whereType<String>()
                  .firstWhere((id) => id.isNotEmpty, orElse: () => '');
              return direct.isNotEmpty && direct == now.videoId;
            },
            orElse: () => <String, dynamic>{
              'youtube_id': now.videoId,
              'title': now.title,
              if ((now.thumbnailUrl ?? '').isNotEmpty)
                'thumbnail_url': now.thumbnailUrl,
            },
          );
    if (match.isEmpty) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _currentVideo = match;
        });
        _updateFloatingPlayer();
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _currentVideo = match;
      });
      _updateFloatingPlayer();
    });
  }

  Future<bool> _handleBackPress() async {
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    if (now != null || _currentVideo != null) {
      if (now == null && _currentVideo != null) {
        _setNowPlayingFromVideo(_currentVideo!);
      }
      ChannelMiniPlayerManager.I.setSuppressed(false);
      _didSuppressMini = false;
      ChannelMiniPlayerManager.I.setMinimized(true);
      _updateFloatingPlayer();
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
      }
      return false;
    }
    return true;
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await _service.getPlaylistDetail(widget.playlistId);
      final Map<String, dynamic> map =
          detail is Map<String, dynamic> ? detail : <String, dynamic>{};
      final thumb =
          (map['thumbnail_url'] ?? map['thumbnail'])?.toString().trim();
      if (!mounted) return;
      if (thumb != null && thumb.isNotEmpty) {
        setState(() => _heroThumb = thumb);
      }
    } catch (_) {
      // ignore
    }
  }

  String? _resolveHeroThumb() {
    if (_heroThumb != null && _heroThumb!.isNotEmpty) return _heroThumb;
    if (_videos.isNotEmpty) return thumbFromMap(_videos.first);
    return null;
  }

  void _onScroll() {
    if (!_hasNext || _loadingMore || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadPage({int page = 1}) async {
    setState(() {
      _loading = page == 1;
      if (page > 1) _loadingMore = true;
    });
    try {
      final res =
          await _service.getPlaylistVideos(widget.playlistId, page: page);
      final results = List<Map<String, dynamic>>.from(res['results'] as List);
      if (!mounted) return;
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasNext) return;
    await _loadPage(page: _page + 1);
  }

  Widget _heroPlaceholder() {
    final thumb = _resolveHeroThumb();
    final hero = (thumb != null && thumb.isNotEmpty)
        ? CachedNetworkImage(
            imageUrl: thumb,
            fit: BoxFit.cover,
            httpHeaders: authHeadersFor(thumb),
          )
        : Container(color: Colors.black26);
    return Stack(
      fit: StackFit.expand,
      children: [
        hero,
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
                  child: hero,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumbForRow() {
    if (_currentVideo == null) {
      return Container(color: Colors.black26);
    }
    final thumb = thumbFromMap(_currentVideo!);
    if (thumb != null && thumb.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: thumb,
        fit: BoxFit.cover,
        httpHeaders: authHeadersFor(thumb),
      );
    }
    return Container(color: Colors.black26);
  }

  Widget _buildListSection() {
    return Expanded(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _videos.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index >= _videos.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final video = _videos[index];
                final title = (video['title'] ?? '').toString();
                final thumb = thumbFromMap(video);
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 72,
                      height: 44,
                      child: thumb != null && thumb.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              httpHeaders: authHeadersFor(thumb),
                            )
                          : Container(color: Colors.black26),
                    ),
                  ),
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.play_circle_outline),
                  onTap: () {
                    final id = _videoIdFromMap(video);
                    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
                    final isSame = now != null && now.videoId == id;
                    if (isSame) {
                      ChannelMiniPlayerManager.I.setSuppressed(true);
                      ChannelMiniPlayerManager.I.setMinimized(false);
                    }
                    setState(() {
                      _setMainPlayerVisible();
                      _currentVideo = video;
                    });
                    _setNowPlayingFromVideo(video, openIfSame: isSame);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _updateFloatingPlayer();
                    });
                  },
                );
              },
            ),
    );
  }

  Widget _buildHeaderPlayer() {
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    final effectiveVideo = _currentVideo ?? _videoFromNowPlaying(now);
    if (effectiveVideo == null && !_didShowNullVideoToast) {
      _didShowNullVideoToast = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video not available yet.')),
        );
      });
    }
    final player = _buildChannelPlayer(
      video: effectiveVideo,
    );
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: effectiveVideo == null
          ? _heroPlaceholder()
          : Stack(
              fit: StackFit.expand,
              children: [
                player,
                ValueListenableBuilder<ChannelNowPlaying?>(
                  valueListenable: ChannelMiniPlayerManager.I.nowPlaying,
                  builder: (context, now, _) {
                    final isPlaying = now?.isPlaying == true;
                    return IgnorePointer(
                      ignoring: true,
                      child: Opacity(
                        opacity: isPlaying ? 0 : 1,
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
                                      child: _thumbForRow(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      widget.title,
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
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_handledPendingOpen &&
        ChannelMiniPlayerManager.I
            .consumePendingOpenFromMini(widget.playlistId)) {
      _handledPendingOpen = true;
      final now = ChannelMiniPlayerManager.I.nowPlaying.value;
      final effectivePlaylistId =
          (now?.playlistId ?? ChannelMiniPlayerManager.I.lastPlaylistId ?? '')
              .trim();
      final samePlaylist = effectivePlaylistId == widget.playlistId;
      if (samePlaylist) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final fallbackVideo = _fallbackVideoFromSession();
          setState(() {
            _setMainPlayerVisible();
            _currentVideo ??= fallbackVideo;
          });
          ChannelMiniPlayerManager.I.setSuppressed(true);
          ChannelMiniPlayerManager.I.setMinimized(false);
        });
      }
    }
    return ValueListenableBuilder<bool>(
      valueListenable: ChannelMiniPlayerManager.I.isMinimized,
      builder: (context, minimized, _) {
        final bool isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        if (kDebugMode) {
          final now = ChannelMiniPlayerManager.I.nowPlaying.value;
          debugPrint(
              '[PlaylistDummy] build minimized=$minimized hideMain=$_hideMainPlayer currentVideo=${_currentVideo?['"' "'youtube_id'" '"']} now=${now?.videoId}');
        }
        if (!minimized &&
            isLandscape &&
            _currentVideo != null &&
            !_hideMainPlayer) {
          final player = _buildChannelPlayer(
            video: _currentVideo,
          );
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: null,
            body: SafeArea(
              top: true,
              bottom: false,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: player,
                ),
              ),
            ),
          );
        }
        final bool showHeader = !isLandscape && !minimized && !_hideMainPlayer;
        return WillPopScope(
          onWillPop: _handleBackPress,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.title.isNotEmpty ? widget.title : 'Playlist'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  final allow = await _handleBackPress();
                  if (!mounted) return;
                  if (allow) {
                    Navigator.of(context, rootNavigator: true).maybePop();
                  }
                },
              ),
            ),
            body: SafeArea(
              top: true,
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showHeader) _buildHeaderPlayer(),
                  if (showHeader) const Divider(height: 1),
                  if (showHeader)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withOpacity(0.6),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Now Playing',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              _buildNowPlayingSummary(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (showHeader) const Divider(height: 1),
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
                  _buildListSection(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
