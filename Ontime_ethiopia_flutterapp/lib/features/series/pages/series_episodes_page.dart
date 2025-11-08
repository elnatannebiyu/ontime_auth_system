import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

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

class _SeriesEpisodesPageState extends State<SeriesEpisodesPage> {
  late final SeriesService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _episodes = const [];

  int? _resumeEpisodeId;
  String? _resumeTitle;

  int? _nowPlayingEpisodeId;
  String? _nowPlayingTitle;
  String? _currentVideoKey;
  String? _heroImageUrl;
  // removed _ytListenerAttached; using a single listener reference instead
  bool _autoNextEnabled = true;

  YoutubePlayerController? _yt;
  bool _isFullScreen = false;
  VoidCallback? _ytListener;

  @override
  void initState() {
    super.initState();
    _service = SeriesService(api: widget.api, tenantId: widget.tenantId);
    _allowBothOrientations();
    _load();
  }

  @override
  void dispose() {
    try {
      if (_ytListener != null && _yt != null) _yt!.removeListener(_ytListener!);
      try {
        _yt?.pause();
      } catch (_) {}
      _yt?.dispose();
    } catch (_) {}

    // Safety reset: allow both orientations and restore UI mode when leaving
    _allowBothOrientations();
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    super.dispose();
  }

  void _allowBothOrientations() {
    try {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getEpisodes(widget.seasonId);
      setState(() {
        _episodes = data;
      });
      if (mounted) {
        final img = (widget.coverImage != null && widget.coverImage!.isNotEmpty)
            ? widget.coverImage!
            : _episodes.isNotEmpty
                ? _pickThumb(
                    _episodes.first['thumbnails'] as Map<String, dynamic>?)
                : '';
        setState(() => _heroImageUrl = img);
      }
      await _loadContinueWatching();
    } catch (e) {
      setState(() => _error = 'Failed to load episodes');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadContinueWatching() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'cw_season_${widget.seasonId}';
      final jsonStr = prefs.getString(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
        final epId = obj['episode_id'] as int?;
        final title = (obj['title'] ?? '') as String;
        if (epId != null && _episodes.any((e) => e['id'] == epId)) {
          setState(() {
            _resumeEpisodeId = epId;
            _resumeTitle = title;
          });
        }
      }
    } catch (_) {}
  }

  String _pickThumb(Map<String, dynamic>? thumbs) {
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

  Future<void> _playInline(int episodeId,
      {String? title, String? thumb}) async {
    if (!mounted) return;
    widget.api.setTenant(widget.tenantId);
    try {
      final play = await widget.api.seriesEpisodePlay(episodeId);
      final raw = (play['video_id'] ?? '').toString();
      final videoId = _extractVideoId(raw);
      debugPrint('[EpisodesPage] inline play: ep=$episodeId videoId=$videoId');
      _nowPlayingEpisodeId = episodeId;
      _nowPlayingTitle = title ?? widget.title;

      final oldCtrl = _yt;
      final newCtrl = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          controlsVisibleAtStart: true,
          enableCaption: false,
          forceHD: false,
          loop: false,
        ),
      );

      // remove listener from old controller if present
      try {
        if (_ytListener != null && _yt != null) {
          _yt!.removeListener(_ytListener!);
        }
      } catch (_) {}

      // create and attach listener to update fullscreen state and auto-next
      _ytListener = () {
        if (!mounted) return;
        final isFs = newCtrl.value.isFullScreen;
        if (isFs != _isFullScreen) {
          setState(() {
            _isFullScreen = isFs;
          });
        }
        final v = newCtrl.value;
        if (v.playerState == PlayerState.ended &&
            _nowPlayingEpisodeId != null &&
            _autoNextEnabled) {
          _autoPlayNext(fromEpisodeId: _nowPlayingEpisodeId!);
        }
      };
      newCtrl.addListener(_ytListener!);

      setState(() {
        _currentVideoKey = videoId;
        _yt = newCtrl;
      });
      Future.microtask(() {
        try {
          oldCtrl?.pause();
        } catch (_) {}
        try {
          oldCtrl?.dispose();
        } catch (_) {}
      });
      // No delayed calls; will start playback in onReady.
    } catch (e) {
      setState(() {
        _yt = null;
      });
    }
  }

  void _autoPlayNext({required int fromEpisodeId}) {
    final idx = _episodes.indexWhere((e) => e['id'] == fromEpisodeId);
    if (idx == -1 || idx + 1 >= _episodes.length) return;
    final next = _episodes[idx + 1];
    final nextId = next['id'] as int;
    final title = (next['display_title'] ?? next['title'] ?? '').toString();
    final thumbs = next['thumbnails'] as Map<String, dynamic>?;
    final thumb = _pickThumb(thumbs);
    _playInline(nextId, title: title, thumb: thumb);
  }

  void _playPrev({required int fromEpisodeId}) {
    final idx = _episodes.indexWhere((e) => e['id'] == fromEpisodeId);
    if (idx <= 0) return;
    final prev = _episodes[idx - 1];
    final prevId = prev['id'] as int;
    final title = (prev['display_title'] ?? prev['title'] ?? '').toString();
    final thumbs = prev['thumbnails'] as Map<String, dynamic>?;
    final thumb = _pickThumb(thumbs);
    _playInline(prevId, title: title, thumb: thumb);
  }

  @override
  Widget build(BuildContext context) {
    final heroImage =
        (widget.coverImage != null && widget.coverImage!.isNotEmpty)
            ? widget.coverImage!
            : (_heroImageUrl ?? '');

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: ListView(children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          )
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _yt != null
                      ? KeyedSubtree(
                          key: ValueKey(_currentVideoKey ?? ''),
                          child: YoutubePlayerBuilder(
                            player: YoutubePlayer(
                              controller: _yt!,
                              bottomActions: const [
                                SizedBox(width: 8),
                                CurrentPosition(),
                                ProgressBar(isExpanded: true),
                                RemainingDuration(),
                                FullScreenButton(),
                              ],
                            ),
                            builder: (context, playerWidget) {
                              // We already wrap with ClipRRect + AspectRatio here, just return the player
                              return playerWidget;
                            },
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            if (heroImage.isNotEmpty)
                              Image.network(heroImage, fit: BoxFit.cover)
                            else
                              Container(color: Colors.black12),
                            Positioned.fill(
                              child: Center(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    if (_episodes.isNotEmpty) {
                                      final e = _episodes.first;
                                      final id = e['id'] as int;
                                      final t = (e['display_title'] ??
                                              e['title'] ??
                                              '')
                                          .toString();
                                      final thumbs = e['thumbnails']
                                          as Map<String, dynamic>?;
                                      final th = _pickThumb(thumbs);
                                      _playInline(id, title: t, thumb: th);
                                    }
                                  },
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Play'),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

            // Controls row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 4,
                    spacing: 6,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        tooltip: 'Previous episode',
                        onPressed: () {
                          final cur = _nowPlayingEpisodeId;
                          if (cur == null) return;
                          _playPrev(fromEpisodeId: cur);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay_10),
                        tooltip: 'Back 10s',
                        onPressed: () {
                          try {
                            final c = _yt;
                            if (c == null) return;
                            final pos = c.value.position;
                            final newPos = pos - const Duration(seconds: 10);
                            c.seekTo(newPos < Duration.zero
                                ? Duration.zero
                                : newPos);
                          } catch (_) {}
                        },
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Auto next'),
                          const SizedBox(width: 6),
                          Switch(
                            value: _autoNextEnabled,
                            onChanged: (v) =>
                                setState(() => _autoNextEnabled = v),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10),
                        tooltip: 'Forward 10s',
                        onPressed: () {
                          try {
                            final c = _yt;
                            if (c == null) return;
                            final pos = c.value.position;
                            final total = c.value.metaData.duration;
                            final newPos = pos + const Duration(seconds: 10);
                            c.seekTo(newPos > total ? total : newPos);
                          } catch (_) {}
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        tooltip: 'Next episode',
                        onPressed: () {
                          final cur = _nowPlayingEpisodeId;
                          if (cur == null) return;
                          _autoPlayNext(fromEpisodeId: cur);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen),
                        tooltip: 'Fullscreen',
                        onPressed: () {
                          try {
                            _yt?.toggleFullScreenMode();
                          } catch (_) {}
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Next up
            Builder(builder: (context) {
              final cur = _nowPlayingEpisodeId;
              if (cur == null) return const SizedBox.shrink();
              final idx = _episodes.indexWhere((e) => e['id'] == cur);
              if (idx == -1 || idx + 1 >= _episodes.length)
                return const SizedBox.shrink();
              final next = _episodes[idx + 1];
              final title =
                  (next['display_title'] ?? next['title'] ?? '').toString();
              final thumbs = next['thumbnails'] as Map<String, dynamic>?;
              final thumb = _pickThumb(thumbs);
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: thumb.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(thumb,
                                width: 72, height: 40, fit: BoxFit.cover),
                          )
                        : const SizedBox(width: 72, height: 40),
                    title: const Text('Next up'),
                    subtitle: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: FilledButton.icon(
                      onPressed: () => _autoPlayNext(fromEpisodeId: cur),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                  ),
                ),
              );
            }),

            if (_resumeEpisodeId != null) const SizedBox(height: 8),
            if (_resumeEpisodeId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _buildContinueWatchingCard(),
              ),

            // Episodes list
            ...List.generate(_episodes.length, (i) {
              final e = _episodes[i];
              final id = e['id'] as int;
              final title = (e['display_title'] ?? e['title'] ?? '').toString();
              final desc = (e['description_override'] ?? e['description'] ?? '')
                  .toString();
              final thumbs = e['thumbnails'] as Map<String, dynamic>?;
              final cover = _pickThumb(thumbs);
              final epNum = e['episode_number'];
              return Padding(
                padding: EdgeInsets.fromLTRB(12, i == 0 ? 8 : 8, 12, 8),
                child: EpisodeCard(
                  title: title,
                  subtitle: epNum != null ? 'Episode $epNum' : null,
                  description: desc,
                  imageUrl: cover,
                  onPlay: () => _playInline(id, title: title, thumb: cover),
                ),
              );
            }),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueWatchingCard() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text('Continue watching'),
        subtitle: Text(_resumeTitle ?? ''),
        trailing: const Icon(Icons.play_arrow),
        onTap: () {
          final epId = _resumeEpisodeId;
          if (epId != null) {
            _playInline(epId);
          }
        },
      ),
    );
  }
}

class EpisodeCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String description;
  final String imageUrl;
  final VoidCallback onPlay;

  const EpisodeCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.description,
    required this.imageUrl,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlay,
      child: Card(
        elevation: 6,
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
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
                          onPressed: () {},
                          icon: const Icon(Icons.info_outline),
                          tooltip: 'Details',
                        ),
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
