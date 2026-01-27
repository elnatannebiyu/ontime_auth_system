// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../channels/player/channel_mini_player_manager.dart';
import '../../../channels/player/channel_youtube_player.dart';
import '../../../auth/tenant_auth_client.dart';
import '../series_service.dart';
import '../../../core/navigation/route_stack_observer.dart';

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

  Map<String, dynamic>? _currentVideo;
  int? _currentEpisodeId;
  bool _playOnInit = false;
  bool _isPlaying = false;
  bool _allowMiniPlayerOverride = false;
  int _currentVideoVersion = 0;
  int _lastFloatingVersion = -1;
  bool? _lastFloatingMinimized;
  final GlobalKey _playerKey = GlobalKey();

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
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    super.dispose();
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

  void _playEpisode(int episodeId, {String? title}) async {
    widget.api.setTenant(widget.tenantId);
    try {
      final play = await widget.api.seriesEpisodePlay(episodeId);
      final raw = (play['video_id'] ?? '').toString();
      final vid = _extractVideoId(raw);
      final ep = _episodes
          .cast<Map<String, dynamic>>()
          .firstWhere((e) => (e['id'] as int?) == episodeId, orElse: () => {});
      final thumbs = ep['thumbnails'] as Map<String, dynamic>?;
      final cover = _pickThumb(thumbs);

      setState(() {
        _currentEpisodeId = episodeId;
        _currentVideo = {
          'youtube_id': vid,
          'title': (title ?? widget.title).toString(),
          'thumbnail_url': cover,
        };
        _currentVideoVersion += 1;
        _playOnInit = true;
        if (ChannelMiniPlayerManager.I.isMinimized.value) {
          _allowMiniPlayerOverride = true;
        }
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
      _playEpisode(id, title: t);
    }
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
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
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

    final Widget? headerPlayer = _currentVideo == null
        ? null
        : ValueListenableBuilder<bool>(
            valueListenable: ChannelMiniPlayerManager.I.isMinimized,
            builder: (context, minimized, _) {
              final player = ChannelYoutubePlayer(
                key: _playerKey,
                video: _currentVideo,
                playlistTitle: widget.title,
                playOnInit: _playOnInit,
                onExpand: () {
                  final nav = Navigator.of(context, rootNavigator: true);
                  final target = '/series/season/${widget.seasonId}';
                  if (appRouteStackObserver.containsName(target)) {
                    nav.popUntil((route) => route.settings.name == target);
                    return;
                  }
                  nav.push(
                    MaterialPageRoute(
                      settings: RouteSettings(name: target),
                      builder: (_) => SeriesEpisodesPage(
                        api: widget.api,
                        tenantId: widget.tenantId,
                        seasonId: widget.seasonId,
                        title: widget.title,
                        coverImage: widget.coverImage,
                      ),
                    ),
                  );
                },
                onPlayingChanged: (playing) {
                  if (!mounted || _isPlaying == playing) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _isPlaying = playing);
                  });
                },
                onAutoPlayNext: _playNext,
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
                child: player,
              );
            },
          );

    return Scaffold(
      appBar: isLandscape
          ? null
          : AppBar(
              title: Text(widget.title),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: SafeArea(
        top: !isLandscape,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              if (headerPlayer != null)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PlayerHeaderDelegate(
                    minExtentHeight: math.min(
                        MediaQuery.of(context).size.width * 9 / 16,
                        MediaQuery.of(context).size.height),
                    maxExtentHeight: math.min(
                        MediaQuery.of(context).size.width * 9 / 16,
                        MediaQuery.of(context).size.height),
                    builder: (_) => SafeArea(
                      top: false,
                      bottom: false,
                      left: isLandscape,
                      right: isLandscape,
                      child: headerPlayer,
                    ),
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
                      final desc =
                          (e['description_override'] ?? e['description'] ?? '')
                              .toString();
                      final thumbs = e['thumbnails'] as Map<String, dynamic>?;
                      final cover = _pickThumb(thumbs);
                      return Padding(
                        padding: EdgeInsets.fromLTRB(12, i == 0 ? 4 : 8, 12, 8),
                        child: EpisodeCard(
                          title: title,
                          subtitle: e['episode_number'] != null
                              ? 'Episode ${e['episode_number']}'
                              : null,
                          description: desc,
                          imageUrl: cover,
                          liked: _likedEpisodes.contains(id),
                          onPlay: () => _playEpisode(id, title: title),
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
    );
  }

  static String _extractVideoId(String input) {
    final s = input.trim();
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
