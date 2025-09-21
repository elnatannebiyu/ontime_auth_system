// ignore_for_file: unused_field, unused_element

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../auth/tenant_auth_client.dart';
import '../series_service.dart';
import 'player_page.dart';

class SeriesEpisodesPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final int seasonId;
  final String title;
  final String? coverImage; // preferred hero banner
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
  final bool _showMini = false;
  int? _nowPlayingEpisodeId;
  String? _nowPlayingTitle;

  @override
  void initState() {
    super.initState();
    _service = SeriesService(api: widget.api, tenantId: widget.tenantId);
    _load();
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
      await _loadContinueWatching();
    } catch (e) {
      setState(() {
        _error = 'Failed to load episodes';
      });
    } finally {
      setState(() {
        _loading = false;
      });
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

  void _play(int episodeId, {String? title, String? thumb}) async {
    if (!mounted) return;
    _nowPlayingEpisodeId = episodeId;
    _nowPlayingTitle = title ?? widget.title;
    // Open the full player page (primary experience). Mini can be reached by minimizing there.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          api: widget.api,
          tenantId: widget.tenantId,
          episodeId: episodeId,
          seasonId: widget.seasonId,
          title: _nowPlayingTitle ?? widget.title,
          // If PlayerPage suggests next episodes and wants to autoplay next in full, wire this callback.
          onPlayEpisode: (nextId, nextTitle, nextThumb) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _play(nextId, title: nextTitle, thumb: nextThumb);
            });
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildNextUpBar(int currentId) {
    // Find next episode by position
    int idx = _episodes.indexWhere((e) => e['id'] == currentId);
    if (idx == -1 || idx + 1 >= _episodes.length) {
      return const SizedBox.shrink();
    }
    final next = _episodes[idx + 1];
    final nextId = next['id'] as int;
    final title = (next['display_title'] ?? next['title'] ?? '').toString();
    final thumbs = next['thumbnails'] as Map<String, dynamic>?;
    final thumb = _pickThumb(thumbs);
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (thumb.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(thumb,
                  width: 72, height: 40, fit: BoxFit.cover),
            )
          else
            const SizedBox(width: 72, height: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Next up',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              // Defer to next frame to show the next player sheet
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _play(nextId, title: title, thumb: thumb);
              });
            },
            icon: const Icon(Icons.skip_next),
            label: const Text('Play'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heroImage = (widget.coverImage != null &&
            widget.coverImage!.isNotEmpty)
        ? widget.coverImage!
        : _episodes.isNotEmpty
            ? _pickThumb(_episodes.first['thumbnails'] as Map<String, dynamic>?)
            : '';

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        )
      ]);
    } else {
      content = NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              pinned: true,
              expandedHeight: 220,
              backgroundColor: Colors.black,
              title: Text(widget.title),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (heroImage.isNotEmpty)
                      Image.network(heroImage, fit: BoxFit.cover)
                    else
                      Container(color: Colors.black45),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black54,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_resumeEpisodeId != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _buildContinueWatchingCard(),
              ),
            ),
        ],
        body: Builder(
          builder: (context) => CustomScrollView(
            key: const PageStorageKey<String>('episodes_scroll'),
            slivers: [
              SliverOverlapInjector(
                handle:
                    NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              ),
              SliverList(
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
                    final epNum = e['episode_number'];
                    return Padding(
                      padding: EdgeInsets.fromLTRB(12, i == 0 ? 12 : 8, 12, 8),
                      child: EpisodeCard(
                        title: title,
                        subtitle: epNum != null ? 'Episode $epNum' : null,
                        description: desc,
                        imageUrl: cover,
                        onPlay: () => _play(id, title: title, thumb: cover),
                      ),
                    );
                  },
                  childCount: _episodes.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: content,
      ),
      bottomSheet: null,
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
            _play(epId);
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
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 160,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.cover)
                      : Container(
                          color: Colors.black12, child: const Icon(Icons.tv)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null)
                    Text(subtitle!,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Colors.white70)),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6)),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.info_outline)),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
