import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api_client.dart';
import 'channel_service.dart';
import '../core/localization/l10n.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class _VideoHit {
  final String playlistId;
  final String playlistTitle;
  final Map<String, dynamic> video;
  const _VideoHit({
    required this.playlistId,
    required this.playlistTitle,
    required this.video,
  });
}

class PlaylistGridSheet extends StatefulWidget {
  final String channelSlug;
  const PlaylistGridSheet({super.key, required this.channelSlug});

  @override
  State<PlaylistGridSheet> createState() => _PlaylistGridSheetState();
}

class _PlaylistGridSheetState extends State<PlaylistGridSheet> {
  final ChannelsService _service = ChannelsService();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _playlists = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasNext = true;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  final Map<String, List<Map<String, dynamic>>> _videosByPlaylist = {};
  final Set<String> _fetchingVideos = {};
  final LocalizationController _lc = LocalizationController();
  bool _offline = false;
  // In-memory caches to enable offline reopen and counts
  static final Map<String, List<Map<String, dynamic>>> _cachedPlaylistsBySlug =
      {};
  static final Map<String, List<Map<String, dynamic>>> _cachedVideosByPlaylist =
      {};

  String _t(String key) => _lc.t(key);

  Map<String, String>? _authHeadersFor(String url) {
    if (!url.startsWith(kApiBase)) return null;
    final client = ApiClient();
    final token = client.getAccessToken();
    final tenant = client.tenant;
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (tenant != null && tenant.isNotEmpty) headers['X-Tenant-Id'] = tenant;
    return headers.isEmpty ? null : headers;
  }

  String? _thumbFromMap(Map<String, dynamic> m) {
    const keys = [
      'thumbnail',
      'thumbnail_url',
      'thumb',
      'thumb_url',
      'image',
      'image_url',
      'poster',
      'poster_url'
    ];
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    final t = m['thumbnails'];
    if (t is Map) {
      for (final size in ['maxres', 'standard', 'high', 'medium', 'default']) {
        final s = t[size];
        if (s is Map && s['url'] is String && (s['url'] as String).isNotEmpty) {
          return s['url'] as String;
        }
      }
      if (t['url'] is String && (t['url'] as String).isNotEmpty) {
        return t['url'] as String;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadPage(1);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasNext || _loadingMore || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 300) {
      _loadMore();
    }
    // Also backfill counts for the newest items near the bottom
    _ensureCountsForRecent(recentCount: 15);
  }

  Future<void> _loadPage(int page) async {
    setState(() {
      _loading = page == 1;
      _error = null;
    });
    try {
      // Early offline detection to avoid unnecessary network calls/logs
      final conn = await Connectivity().checkConnectivity();
      // ignore: unrelated_type_equality_checks
      final bool isOffline = conn == ConnectivityResult.none;
      if (isOffline) {
        if (page == 1) {
          final cached = _cachedPlaylistsBySlug[widget.channelSlug] ?? const [];
          setState(() {
            _offline = true;
            _playlists
              ..clear()
              ..addAll(cached);
            _loading = false;
            _loadingMore = false;
            _hasNext = false;
            _error = cached.isEmpty ? _t('you_are_offline') : null;
          });
          // Restore cached video lists to surface counts
          for (final pl in _playlists) {
            final id = pl['id']?.toString() ?? '';
            final cachedV = _cachedVideosByPlaylist[id];
            if (id.isNotEmpty &&
                cachedV != null &&
                !_videosByPlaylist.containsKey(id)) {
              _videosByPlaylist[id] = List<Map<String, dynamic>>.from(cachedV);
            }
          }
        } else {
          setState(() {
            _offline = true;
            _loadingMore = false;
          });
        }
        return;
      }
      final res = await _service.getPlaylists(widget.channelSlug, page: page);
      final results = List<Map<String, dynamic>>.from(res['results'] as List);
      setState(() {
        if (page == 1) {
          _playlists
            ..clear()
            ..addAll(results);
        } else {
          _playlists.addAll(results);
        }
        _page = page;
        _hasNext = res['next'] != null;
        _loading = false;
        _loadingMore = false;
        _offline = false;
      });
      // Cache playlists for offline reopen
      _cachedPlaylistsBySlug[widget.channelSlug] =
          List<Map<String, dynamic>>.from(_playlists);
      if (page == 1) {
        _ensureCountsForVisible(
            cap: _playlists.length < 15 ? _playlists.length : 15);
      } else {
        _ensureCountsForRecent(
            recentCount: results.length < 15 ? 15 : results.length);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
        _offline = true;
      });
      // If we have cached playlists, show them instead of error-only view
      final cached = _cachedPlaylistsBySlug[widget.channelSlug];
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _playlists
            ..clear()
            ..addAll(cached);
          _hasNext = false;
          _error = null;
        });
        // Restore cached videos for counts
        for (final pl in _playlists) {
          final id = pl['id']?.toString() ?? '';
          final cachedV = _cachedVideosByPlaylist[id];
          if (id.isNotEmpty &&
              cachedV != null &&
              !_videosByPlaylist.containsKey(id)) {
            _videosByPlaylist[id] = List<Map<String, dynamic>>.from(cachedV);
          }
        }
      }
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
    final List<Map<String, dynamic>> visible = _query.isEmpty
        ? _playlists
        : _playlists
            .where((p) =>
                ((p['title'] ?? '') as String)
                    .toLowerCase()
                    .contains(_query.toLowerCase()) ||
                (p['id']?.toString() ?? '').contains(_query))
            .toList();

    // Prepare video search results
    final List<_VideoHit> videoHits = _buildVideoHits(_query);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_t('playlists'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  IconButton(
                    tooltip: _t('close'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) {
                  setState(() => _query = v.trim());
                  // schedule limited video prefetch for search
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _ensureVideosForSearch();
                  });
                },
                decoration: InputDecoration(
                  hintText: _t('search_playlists'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_offline)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t('you_are_offline'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (_loading && _playlists.isEmpty)
              Expanded(child: _buildSkeletonGrid())
            else if (_error != null && _playlists.isEmpty)
              Expanded(child: _buildInitialError())
            else ...[
              if (_query.isNotEmpty && videoHits.isNotEmpty)
                SizedBox(
                  height: 200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                        child: Text(_t('videos'),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Expanded(child: _buildVideoResults(videoHits)),
                    ],
                  ),
                ),
              if (_query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Column(
                    children: [
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _t('playlists'),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (visible.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      _query.isNotEmpty ? _t('no_results') : _t('no_playlists'),
                    ),
                  ),
                )
              else
                Expanded(child: _buildGrid(visible)),
            ],
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: 9,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildGrid(List<Map<String, dynamic>> list) {
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final pl = list[i];
        final title = (pl['title'] ?? '').toString();
        final thumb = _thumbFromMap(pl);
        final id = pl['id']?.toString() ?? '';
        int? videoCount;
        final dynamic c1 = pl['videos_count'] ?? pl['video_count'];
        if (c1 is int) {
          videoCount = c1;
        } else if (_videosByPlaylist.containsKey(id)) {
          videoCount = _videosByPlaylist[id]!.length;
        }
        return GestureDetector(
          onTap: id.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PlaylistDetailPage(playlistId: id, title: title),
                    ),
                  );
                },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: thumb != null && thumb.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: thumb,
                                fit: BoxFit.cover,
                                httpHeaders: _authHeadersFor(thumb),
                                placeholder: (_, __) =>
                                    Container(color: Colors.black26),
                                errorWidget: (_, __, ___) =>
                                    Container(color: Colors.black26),
                              )
                            : Container(color: Colors.black26),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(.25),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (videoCount != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$videoCount',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title.isNotEmpty ? title : id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInitialError() {
    final String message = _offline
        ? _t('you_are_offline')
        : (kDebugMode
            ? (_error?.isNotEmpty == true ? _error! : 'Unknown error')
            : _t('something_went_wrong'));
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          if (!kDebugMode)
            ElevatedButton.icon(
              onPressed: () => _loadPage(1),
              icon: const Icon(Icons.refresh),
              label: Text(_t('retry')),
            ),
        ],
      ),
    );
  }

  void _ensureVideosForSearch() {
    if (_query.isEmpty || _offline) return;
    // Prefetch first page of videos for up to 6 playlists to enable search
    const int cap = 6;
    int fetched = 0;
    for (final pl in _playlists) {
      if (fetched >= cap) break;
      final id = pl['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (_videosByPlaylist.containsKey(id) || _fetchingVideos.contains(id)) {
        continue;
      }
      // Use cached first to avoid network (and works offline)
      final cachedV = _cachedVideosByPlaylist[id];
      if (cachedV != null) {
        setState(() {
          _videosByPlaylist[id] = List<Map<String, dynamic>>.from(cachedV);
        });
        fetched += 1;
        continue;
      }
      _fetchingVideos.add(id);
      _service
          .getPlaylistVideos(id, page: 1)
          .then((res) {
            final results =
                List<Map<String, dynamic>>.from(res['results'] as List);
            // Attach parent id for quick navigation
            for (final m in results) {
              m['playlist_id'] = id;
            }
            if (mounted) {
              setState(() {
                _videosByPlaylist[id] = results;
              });
            } else {
              _videosByPlaylist[id] = results;
            }
            _cachedVideosByPlaylist[id] =
                List<Map<String, dynamic>>.from(results);
          })
          .catchError((_) {})
          .whenComplete(() {
            _fetchingVideos.remove(id);
          });
      fetched += 1;
    }
  }

  void _ensureCountsForVisible({int cap = 12}) {
    if (_offline) return;
    if (cap <= 0) return;
    int fetched = 0;
    for (final pl in _playlists) {
      if (fetched >= cap) break;
      final id = pl['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final dynamic c1 = pl['videos_count'] ?? pl['video_count'];
      if (c1 is int && c1 >= 0) {
        fetched += 1;
        continue;
      }
      if (_videosByPlaylist.containsKey(id) || _fetchingVideos.contains(id)) {
        fetched += 1;
        continue;
      }
      // Use cached video list if available
      final cachedV = _cachedVideosByPlaylist[id];
      if (cachedV != null) {
        _videosByPlaylist[id] = List<Map<String, dynamic>>.from(cachedV);
        fetched += 1;
        continue;
      }
      _fetchingVideos.add(id);
      _service
          .getPlaylistVideos(id, page: 1)
          .then((res) {
            final results =
                List<Map<String, dynamic>>.from(res['results'] as List);
            for (final m in results) {
              m['playlist_id'] = id;
            }
            if (mounted) {
              setState(() {
                _videosByPlaylist[id] = results;
              });
            } else {
              _videosByPlaylist[id] = results;
            }
            _cachedVideosByPlaylist[id] =
                List<Map<String, dynamic>>.from(results);
          })
          .catchError((_) {})
          .whenComplete(() {
            _fetchingVideos.remove(id);
          });
      fetched += 1;
    }
  }

  void _ensureCountsForRecent({required int recentCount}) {
    if (_offline) return;
    if (recentCount <= 0) return;
    int fetched = 0;
    for (int i = _playlists.length - 1; i >= 0; i--) {
      if (fetched >= recentCount) break;
      final pl = _playlists[i];
      final id = pl['id']?.toString() ?? '';
      if (id.isEmpty) {
        fetched += 1;
        continue;
      }
      final dynamic c1 = pl['videos_count'] ?? pl['video_count'];
      if (c1 is int && c1 >= 0) {
        fetched += 1;
        continue;
      }
      if (_videosByPlaylist.containsKey(id) || _fetchingVideos.contains(id)) {
        fetched += 1;
        continue;
      }
      // Use cached video list if available
      final cachedV = _cachedVideosByPlaylist[id];
      if (cachedV != null) {
        _videosByPlaylist[id] = List<Map<String, dynamic>>.from(cachedV);
        fetched += 1;
        continue;
      }
      _fetchingVideos.add(id);
      _service
          .getPlaylistVideos(id, page: 1)
          .then((res) {
            final results =
                List<Map<String, dynamic>>.from(res['results'] as List);
            for (final m in results) {
              m['playlist_id'] = id;
            }
            if (mounted) {
              setState(() {
                _videosByPlaylist[id] = results;
              });
            } else {
              _videosByPlaylist[id] = results;
            }
            _cachedVideosByPlaylist[id] =
                List<Map<String, dynamic>>.from(results);
          })
          .catchError((_) {})
          .whenComplete(() {
            _fetchingVideos.remove(id);
          });
      fetched += 1;
    }
  }

  List<_VideoHit> _buildVideoHits(String query) {
    if (query.isEmpty) return const [];
    final q = query.toLowerCase();
    final List<_VideoHit> hits = [];
    _videosByPlaylist.forEach((playlistId, videos) {
      for (final v in videos) {
        final title = (v['title'] ?? '').toString();
        if (title.toLowerCase().contains(q) ||
            (v['id']?.toString() ?? '').contains(query)) {
          final pl = _playlists.firstWhere(
              (p) => (p['id']?.toString() ?? '') == playlistId,
              orElse: () => const {});
          hits.add(_VideoHit(
            playlistId: playlistId,
            playlistTitle: (pl['title'] ?? '').toString(),
            video: v,
          ));
        }
      }
    });
    // Limit to avoid overlong list
    if (hits.length > 12) return hits.sublist(0, 12);
    return hits;
  }

  Widget _buildVideoResults(List<_VideoHit> hits) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemBuilder: (context, index) {
        final h = hits[index];
        final title = (h.video['title'] ?? '').toString();
        final thumb = _thumbFromMap(h.video);
        return GestureDetector(
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaylistDetailPage(
                  playlistId: h.playlistId,
                  title: h.playlistTitle,
                ),
              ),
            );
          },
          child: SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: thumb != null && thumb.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                            httpHeaders: _authHeadersFor(thumb),
                          )
                        : Container(color: Colors.black26),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  h.playlistTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemCount: hits.length,
    );
  }
}

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
  final List<Map<String, dynamic>> _videos = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  bool _hasNext = true;
  bool _loadingMore = false;
  final ScrollController _scroll = ScrollController();

  Map<String, String>? _authHeadersFor(String url) {
    if (!url.startsWith(kApiBase)) return null;
    final client = ApiClient();
    final token = client.getAccessToken();
    final tenant = client.tenant;
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (tenant != null && tenant.isNotEmpty) headers['X-Tenant-Id'] = tenant;
    return headers.isEmpty ? null : headers;
  }

  String? _thumbFromMap(Map<String, dynamic> m) {
    const keys = [
      'thumbnail',
      'thumbnail_url',
      'thumb',
      'thumb_url',
      'image',
      'image_url',
      'poster',
      'poster_url'
    ];
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    final t = m['thumbnails'];
    if (t is Map) {
      for (final size in ['maxres', 'standard', 'high', 'medium', 'default']) {
        final s = t[size];
        if (s is Map && s['url'] is String && (s['url'] as String).isNotEmpty) {
          return s['url'] as String;
        }
      }
      if (t['url'] is String && (t['url'] as String).isNotEmpty) {
        return t['url'] as String;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadPage(1);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasNext || _loadingMore || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadPage(int page) async {
    setState(() {
      _loading = page == 1;
      _error = null;
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
    } catch (e) {
      setState(() {
        _error = 'Failed to load videos';
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
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.title.isNotEmpty ? widget.title : 'Playlist')),
      body: _loading && _videos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: () => _loadPage(1),
                  child: ListView.separated(
                    controller: _scroll,
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
                      final v = _videos[index];
                      final title = (v['title'] ?? '').toString();
                      final thumb = _thumbFromMap(v);
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 64,
                            height: 40,
                            child: thumb != null && thumb.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: thumb,
                                    fit: BoxFit.cover,
                                    httpHeaders: _authHeadersFor(thumb),
                                  )
                                : Container(color: Colors.black26),
                          ),
                        ),
                        title: Text(title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.play_circle_outline),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Player integration coming soon')),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
