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
  final GlobalKey _playerKey = GlobalKey();
  final List<Map<String, dynamic>> _videos = [];
  final ScrollController _scroll = ScrollController();
  Map<String, dynamic>? _currentVideo;
  bool _playOnInit = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;
  String? _heroThumb;
  bool _skipDetailUpdates = false;
  bool _hideMainPlayer = false;
  bool _allowNowPlayingSync = true;
  bool _didSuppressMini = false;
  bool _handledPendingOpen = false;
  bool _didShowNullVideoToast = false;
  bool _didForceUnminimize = false;
  bool _didSyncNowPlayingFallback = false;

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
    _skipDetailUpdates = fromMini;
    _allowNowPlayingSync = (!fromMini || samePlaylist) && !isMiniDifferent;
    _hideMainPlayer = (fromMini && !samePlaylist) || isMiniDifferent;
    _didSuppressMini = !isMiniDifferent && (!fromMini || samePlaylist);
    if (_didSuppressMini) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ChannelMiniPlayerManager.I.setSuppressed(true);
      });
    }
    _loadPage();
    _loadDetail();
    _scroll.addListener(_onScroll);
    ChannelMiniPlayerManager.I.nowPlaying.addListener(_syncFromNowPlaying);
    _syncFromNowPlaying();
    if (fromMini && samePlaylist) {
      final nowPlaying = ChannelMiniPlayerManager.I.nowPlaying.value;
      final fallbackVideo = nowPlaying == null
          ? null
          : <String, dynamic>{
              'youtube_id': nowPlaying.videoId,
              'title': nowPlaying.title,
              if ((nowPlaying.thumbnailUrl ?? '').isNotEmpty)
                'thumbnail_url': nowPlaying.thumbnailUrl,
            };
      _currentVideo ??= fallbackVideo;
      _playOnInit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ChannelMiniPlayerManager.I.isMinimized.value) {
          ChannelMiniPlayerManager.I.setMinimized(false);
        }
      });
    }
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

  void _setNowPlayingFromVideo(Map<String, dynamic> video) {
    final id = [
      video['youtube_id'],
      video['youtube_video_id'],
      video['yt_video_id'],
      video['video_id'],
    ].whereType<String>().firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final title = (video['title'] ?? '').toString();
    if (id.isEmpty || title.isEmpty) return;
    ChannelMiniPlayerManager.I.setNowPlaying(
      ChannelNowPlaying(
        videoId: id,
        title: title,
        playlistId: widget.playlistId,
        playlistTitle: widget.title,
        thumbnailUrl: thumbFromMap(video),
        isPlaying: true,
      ),
    );
  }

  @override
  void dispose() {
    ChannelMiniPlayerManager.I.nowPlaying.removeListener(_syncFromNowPlaying);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    if (_didSuppressMini) {
      ChannelMiniPlayerManager.I.setSuppressed(false);
    }
    super.dispose();
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
    if (_currentVideo == null && !_didSyncNowPlayingFallback) {
      _didSyncNowPlayingFallback = true;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _currentVideo = match;
          _playOnInit = _playOnInit || _didSyncNowPlayingFallback;
        });
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _currentVideo = match;
        _playOnInit = _playOnInit || _didSyncNowPlayingFallback;
      });
    });
  }

  Future<bool> _handleBackPress() async {
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    final isPlaying = now?.isPlaying == true;
    if (isPlaying) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ChannelMiniPlayerManager.I.setSuppressed(false);
        _didSuppressMini = false;
        ChannelMiniPlayerManager.I.setMinimized(true);
      });
      return false;
    }
    return true;
  }

  Future<void> _handleHeaderBack() async {
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    final isPlaying = now?.isPlaying == true;
    if (isPlaying) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
      }
      await Future.delayed(const Duration(milliseconds: 80));
      ChannelMiniPlayerManager.I.setSuppressed(false);
      _didSuppressMini = false;
      ChannelMiniPlayerManager.I.setMinimized(true);
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  Future<void> _loadDetail() async {
    if (_skipDetailUpdates) return;
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
        _currentVideo = _currentVideo;
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
                    ChannelMiniPlayerManager.I.clear(disposeController: false);
                    ChannelMiniPlayerManager.I.setSuppressed(true);
                    ChannelMiniPlayerManager.I.setMinimized(false);
                    setState(() {
                      _skipDetailUpdates = false;
                      _allowNowPlayingSync = true;
                      _hideMainPlayer = false;
                      _didSuppressMini = true;
                      _currentVideo = video;
                      _playOnInit = true;
                    });
                    _setNowPlayingFromVideo(video);
                  },
                );
              },
            ),
    );
  }

  Widget _buildHeaderPlayer() {
    final now = ChannelMiniPlayerManager.I.nowPlaying.value;
    final effectiveVideo = _currentVideo ??
        (now == null
            ? null
            : <String, dynamic>{
                'youtube_id': now.videoId,
                'title': now.title,
                if ((now.thumbnailUrl ?? '').isNotEmpty)
                  'thumbnail_url': now.thumbnailUrl,
              });
    if (effectiveVideo == null && !_didShowNullVideoToast) {
      _didShowNullVideoToast = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video not available yet.')),
        );
      });
    }
    final player = ChannelYoutubePlayer(
      key: _playerKey,
      video: effectiveVideo,
      playlistId: widget.playlistId,
      playlistTitle: widget.title,
      playOnInit: _playOnInit,
      onExpand: () {
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
      },
      onClose: () {
        if (!mounted) return;
        setState(() {
          _currentVideo = null;
          _playOnInit = false;
        });
      },
      onPlayingChanged: (playing) {
        if (!mounted) return;
        setState(() {
          if (playing) {
            _playOnInit = false;
          }
        });
      },
      onAutoPlayNext: () {},
      fallback: _heroPlaceholder(),
    );
    ChannelMiniPlayerManager.I.setFloatingPlayer(player);
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
      final samePlaylist =
          now != null && effectivePlaylistId == widget.playlistId;
      if (samePlaylist) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final nowPlaying = ChannelMiniPlayerManager.I.nowPlaying.value;
          final fallbackVideo = nowPlaying == null
              ? null
              : <String, dynamic>{
                  'youtube_id': nowPlaying.videoId,
                  'title': nowPlaying.title,
                  if ((nowPlaying.thumbnailUrl ?? '').isNotEmpty)
                    'thumbnail_url': nowPlaying.thumbnailUrl,
                };
          setState(() {
            _skipDetailUpdates = true;
            _allowNowPlayingSync = true;
            _hideMainPlayer = false;
            _didSuppressMini = true;
            _currentVideo ??= fallbackVideo;
            _playOnInit = true;
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
        if (!_didForceUnminimize &&
            minimized &&
            !_hideMainPlayer &&
            ChannelMiniPlayerManager.I.nowPlaying.value != null) {
          _didForceUnminimize = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (ChannelMiniPlayerManager.I.isMinimized.value) {
              ChannelMiniPlayerManager.I.setMinimized(false);
            }
          });
        }
        if (kDebugMode) {
          final now = ChannelMiniPlayerManager.I.nowPlaying.value;
          debugPrint(
              '[PlaylistDummy] build minimized=$minimized hideMain=$_hideMainPlayer currentVideo=${_currentVideo?['"' "'youtube_id'" '"']} now=${now?.videoId}');
        }
        if (!minimized &&
            isLandscape &&
            _currentVideo != null &&
            !_hideMainPlayer) {
          final player = ChannelYoutubePlayer(
            key: _playerKey,
            video: _currentVideo,
            playlistId: widget.playlistId,
            playlistTitle: widget.title,
            playOnInit: _playOnInit,
            onExpand: () {
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
            },
            onClose: () {
              if (!mounted) return;
              setState(() {
                _currentVideo = null;
                _playOnInit = false;
              });
            },
            onPlayingChanged: (playing) {
              if (!mounted) return;
              setState(() {
                if (playing) {
                  _playOnInit = false;
                }
              });
            },
            onAutoPlayNext: () {},
            fallback: _heroPlaceholder(),
          );
          ChannelMiniPlayerManager.I.setFloatingPlayer(player);
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
                    await _handleHeaderBack();
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
