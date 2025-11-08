import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../api_client.dart';
import '../core/widgets/brand_title.dart';
import '../core/localization/l10n.dart';
import '../core/cache/channel_cache.dart';

class ChannelsPage extends StatefulWidget {
  final String tenantId;
  final LocalizationController? localizationController;
  const ChannelsPage({super.key, required this.tenantId, this.localizationController});

  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  final ApiClient _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<dynamic> _channels = const [];
  final Map<String, List<dynamic>> _playlistsByChannel = {};
  final Map<String, List<dynamic>> _videosByPlaylist = {};
  // In-flight fetch caches to avoid duplicate network calls on rebuilds
  final Map<String, Future<void>> _playlistsFetching = {};
  final Map<String, Future<void>> _videosFetching = {};
  final Set<String> _expandedChannels = <String>{};
  bool _offline = false;

  // Simple in-memory cache of last successful channels fetch (per app session)
  static List<dynamic> _cachedChannels = const [];

  LocalizationController get _lc =>
      widget.localizationController ?? LocalizationController();
  String _t(String key) => _lc.t(key);

  @override
  void initState() {
    super.initState();
    _client.setTenant(widget.tenantId);
    if (kDebugMode) {
      debugPrint('[ChannelsPage] init for tenant=${widget.tenantId}');
    }
    // Ensure ApiClient has restored cookies and access token so image headers can be attached
    _initializeClient();
    _primeFromCacheThenLoad();
  }

  // ---- Channel details modal ----
  String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is String) return v.isEmpty ? '—' : v;
    if (v is bool) return v.toString();
    if (v is num) return v.toString();
    if (v is List) {
      if (v.isEmpty) return '[]';
      return '[${v.map((e) => e is Map ? e.toString() : e.toString()).join(', ')}]';
    }
    if (v is Map) {
      return v.isEmpty ? '{}' : v.toString();
    }
    return v.toString();
  }

  Widget _kv(String label, dynamic value) {
    final val = _fmt(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              val,
              style: const TextStyle(fontFamily: 'monospace'),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  void _showChannelDetails(Map<String, dynamic> ch) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(_t('channel_details'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                      IconButton(
                        tooltip: _t('close'),
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  _kv(_t('tenant_label'), ch['tenant'] ?? _client.tenant ?? widget.tenantId),
                  _kv(_t('id_slug'), ch['id_slug']),
                  _kv(_t('default_locale'), ch['default_locale']),
                  _kv(_t('name_am'), ch['name_am']),
                  _kv(_t('name_en'), ch['name_en']),
                  _kv(_t('aliases'), ch['aliases']),
                  _kv(_t('youtube_handle'), ch['youtube_handle']),
                  _kv(_t('channel_handle'), ch['handle']),
                  _kv(_t('youtube_channel_id'), ch['youtube_channel_id']),
                  _kv(_t('resolved_channel_id'), ch['resolved_channel_id']),
                  _kv(_t('images'), ch['images']),
                  _kv(_t('sources'), ch['sources']),
                  _kv(_t('genres'), ch['genres']),
                  _kv(_t('language_label'), ch['language']),
                  _kv(_t('country'), ch['country']),
                  _kv(_t('tags'), ch['tags']),
                  _kv(_t('is_active'), ch['is_active']),
                  _kv(_t('platforms'), ch['platforms']),
                  _kv(_t('drm_required'), ch['drm_required']),
                  _kv(_t('sort_order'), ch['sort_order']),
                  _kv(_t('featured'), ch['featured']),
                  _kv(_t('rights'), ch['rights']),
                  _kv(_t('audit'), ch['audit']),
                  _kv(_t('uid'), ch['uid']),
                  _kv(_t('created_at'), ch['created_at']),
                  _kv(_t('updated_at'), ch['updated_at']),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOfflineCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final tenant = _client.tenant ?? widget.tenantId;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.wifi_off, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('offline_mode'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(_t('showing_cached')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _loading ? null : () => _loadChannels(clearCaches: false),
                  icon: const Icon(Icons.refresh),
                  label: Text(_t('retry')),
                ),
                TextButton.icon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      showDragHandle: true,
                      builder: (ctx) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_t('connection_details'), style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text('${_t('server')}:'),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(kApiBase, style: const TextStyle(fontFamily: 'monospace'))),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('${_t('tenant')}:'),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(tenant)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(_t('tip_pull_refresh')),
                              const SizedBox(height: 8),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  icon: const Icon(Icons.info_outline),
                  label: Text(_t('details')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initializeClient() async {
    try {
      await _client.ensureInitialized();
      if (kDebugMode) {
        debugPrint('[ChannelsPage] ApiClient initialized. hasAccessToken=${_client.getAccessToken() != null}');
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _primeFromCacheThenLoad() async {
    // Load cached channels immediately if present
    final tenant = _client.tenant ?? widget.tenantId;
    try {
      final cached = await ChannelCache.load(tenant);
      if (cached.isNotEmpty) {
        setState(() {
          _channels = cached;
        });
      }
    } catch (_) {}
    // Then load fresh from network
    await _loadChannels();
  }

  // ---- Thumbnail helpers ----
  String? _thumbFromMap(Map<String, dynamic> m) {
    // Common flat fields
    const keys = [
      'thumbnail', 'thumbnail_url', 'thumb', 'thumb_url',
      'image', 'image_url', 'logo', 'logo_url', 'poster', 'poster_url',
    ];
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    // Nested: m['thumbnails'] can be Map like YouTube ({medium: {url: ...}})
    final t = m['thumbnails'];
    if (t is Map) {
      // try well-known sizes (prefer highest quality first)
      for (final size in ['maxres', 'standard', 'high', 'medium', 'default']) {
        final s = t[size];
        if (s is Map && s['url'] is String && (s['url'] as String).isNotEmpty) {
          return s['url'] as String;
        }
      }
      // or direct url
      if (t['url'] is String && (t['url'] as String).isNotEmpty) {
        return t['url'] as String;
      }
    }
    return null;
  }

  Map<String, String>? _authHeadersFor(String url) {
    // Only add headers for our backend origin
    if (!url.startsWith(kApiBase)) return null;
    final token = _client.getAccessToken();
    final tenant = _client.tenant;
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (tenant != null && tenant.isNotEmpty) {
      headers['X-Tenant-Id'] = tenant;
    }
    return headers.isEmpty ? null : headers;
  }

  Widget _buildThumb(String? url, {double size = 40, BorderRadius? radius}) {
    radius ??= BorderRadius.circular(8);
    if (url == null || url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: radius,
        ),
        child: Icon(Icons.image_not_supported,
            size: size * 0.6,
            color: Theme.of(context).colorScheme.outline),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        headers: _authHeadersFor(url),
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: radius,
          ),
          child: Icon(Icons.broken_image,
              size: size * 0.6,
              color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }

  Future<void> _loadChannels({bool clearCaches = false}) async {
    if (clearCaches) {
      setState(() {
        _playlistsByChannel.clear();
        _videosByPlaylist.clear();
      });
    }
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    if (kDebugMode) {
      debugPrint('[ChannelsPage] Loading channels... (clearCaches=$clearCaches)');
    }
    try {
      // Fetch all pages so the user can see/select any active channel
      final List<dynamic> all = [];
      int page = 1;
      while (true) {
        final res = await _client.get('/channels/', queryParameters: {
          'ordering': 'sort_order',
          'page': page.toString(),
        });
        final raw = res.data;
        List<dynamic> pageData;
        if (raw is Map && raw['results'] is List) {
          pageData = List<dynamic>.from(raw['results'] as List);
        } else if (raw is List) {
          pageData = raw;
        } else {
          pageData = const [];
        }
        all.addAll(pageData);
        // Stop if not paginated or no next page
        if (raw is! Map || raw['next'] == null) {
          break;
        }
        page += 1;
      }
      setState(() {
        _channels = all;
        _cachedChannels = all; // update cache on success (session cache)
      });
      // Persist to disk cache per tenant
      try {
        final tenant = _client.tenant ?? widget.tenantId;
        await ChannelCache.save(tenant, all);
      } catch (_) {}
      if (kDebugMode) {
        debugPrint('[ChannelsPage] Loaded channels: count=${all.length}');
      }
      // After channels reload, for any channels currently expanded,
      // force-clear and re-fetch their playlists so UI shows fresh data
      for (final slug in _expandedChannels) {
        _playlistsByChannel.remove(slug);
        await _ensurePlaylists(slug);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChannelsPage] Error loading channels: $e');
      }
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        // Try persistent cache first
        try {
          final tenant = _client.tenant ?? widget.tenantId;
          final cached = await ChannelCache.load(tenant);
          if (cached.isNotEmpty) {
            setState(() {
              _channels = cached;
              _offline = true;
            });
          } else if (_cachedChannels.isNotEmpty) {
            setState(() {
              _channels = _cachedChannels;
              _offline = true;
            });
          } else {
            setState(() {
              _error = 'You appear to be offline. Failed to load channels.';
            });
          }
        } catch (_) {
          setState(() {
            _error = 'You appear to be offline. Failed to load channels.';
          });
        }
      } else {
        setState(() {
          _error = 'Failed to load channels';
        });
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _ensurePlaylists(String channelSlug) async {
    if (_playlistsByChannel.containsKey(channelSlug)) return;
    if (_playlistsFetching.containsKey(channelSlug)) {
      return _playlistsFetching[channelSlug]!;
    }
    final future = _doFetchPlaylists(channelSlug);
    _playlistsFetching[channelSlug] = future;
    try {
      await future;
    } finally {
      _playlistsFetching.remove(channelSlug);
    }
  }

  Future<void> _doFetchPlaylists(String channelSlug) async {
    if (kDebugMode) {
      debugPrint('[ChannelsPage] Fetching playlists for channel=$channelSlug');
    }
    try {
      final res = await _client.get('/channels/playlists/', queryParameters: {
        'channel': channelSlug,
        'is_active': 'true',
      });
      final raw = res.data;
      List<dynamic> data;
      if (raw is Map && raw['results'] is List) {
        data = List<dynamic>.from(raw['results'] as List);
      } else if (raw is List) {
        data = raw;
      } else {
        data = const [];
      }
      setState(() {
        _playlistsByChannel[channelSlug] = data;
      });
      if (kDebugMode) {
        debugPrint('[ChannelsPage] Playlists loaded for $channelSlug: count=${data.length}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChannelsPage] Failed to load playlists for $channelSlug: $e');
      }
      // Suppress SnackBar to avoid duplicate offline messaging; rely on offline UI
    }
  }

  Future<void> _ensureVideos(String playlistId) async {
    if (_videosByPlaylist.containsKey(playlistId)) return;
    if (_videosFetching.containsKey(playlistId)) {
      return _videosFetching[playlistId]!;
    }
    final future = _doFetchVideos(playlistId);
    _videosFetching[playlistId] = future;
    try {
      await future;
    } finally {
      _videosFetching.remove(playlistId);
    }
  }

  Future<void> _doFetchVideos(String playlistId) async {
    if (kDebugMode) {
      debugPrint('[ChannelsPage] Fetching videos for playlist=$playlistId');
    }
    try {
      final res = await _client.get('/channels/videos/', queryParameters: {
        'playlist': playlistId,
      });
      final raw = res.data;
      List<dynamic> data;
      if (raw is Map && raw['results'] is List) {
        data = List<dynamic>.from(raw['results'] as List);
      } else if (raw is List) {
        data = raw;
      } else {
        data = const [];
      }
      setState(() {
        _videosByPlaylist[playlistId] = data;
      });
      if (kDebugMode) {
        debugPrint('[ChannelsPage] Videos loaded for $playlistId: count=${data.length}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChannelsPage] Failed to load videos for $playlistId: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load videos')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _lc,
      builder: (_, __) => Scaffold(
      appBar: AppBar(
        title: BrandTitle(section: _t('channels')),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _loadChannels(clearCaches: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: () => _loadChannels(clearCaches: true),
                  child: ListView.builder(
                      itemCount: _channels.length + (_offline ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_offline) {
                          if (index == 0) {
                            return _buildOfflineCard();
                          }
                          index -= 1;
                        }
                        final ch = _channels[index] as Map<String, dynamic>;
                        final slug = (ch['id_slug'] ?? '').toString();
                        final title = (ch['name_en'] ?? ch['name_am'] ?? slug).toString();
                        final isActive = ch['is_active'] == true;
                        String? thumbUrlPrimary = _thumbFromMap(ch);
                        String thumbUrl = thumbUrlPrimary ?? '$kApiBase/api/channels/$slug/logo/';
                        if (kDebugMode && thumbUrlPrimary == null) {
                          debugPrint('[ChannelsPage] Using logo fallback for channel=$slug -> $thumbUrl');
                        }
                        return ExpansionTile(
                          key: PageStorageKey('ch:$slug'),
                          title: Row(
                            children: [
                              _buildThumb(thumbUrl, size: 36, radius: BorderRadius.circular(18)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(title)),
                            ],
                          ),
                          subtitle: Text(slug + (isActive ? '' : ' (inactive)')),
                          initiallyExpanded: _expandedChannels.contains(slug),
                          onExpansionChanged: (expanded) {
                            setState(() {
                              if (expanded) {
                                _expandedChannels.add(slug);
                              } else {
                                _expandedChannels.remove(slug);
                              }
                            });
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: _t('info'),
                                icon: const Icon(Icons.info_outline),
                                onPressed: () => _showChannelDetails(ch),
                              ),
                              IconButton(
                                tooltip: _t('refresh_playlists'),
                                icon: const Icon(Icons.refresh),
                                onPressed: () async {
                                  setState(() {
                                    _playlistsByChannel.remove(slug);
                                    _videosByPlaylist.clear(); // clear dependent videos cache
                                  });
                                  await _ensurePlaylists(slug);
                                },
                              ),
                            ],
                          ),
                          children: [
                            FutureBuilder(
                              future: _ensurePlaylists(slug),
                              builder: (context, snapshot) {
                                final playlists = _playlistsByChannel[slug];
                                if (playlists == null) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: LinearProgressIndicator(),
                                  );
                                }
                                if (playlists.isEmpty) {
                                  return ListTile(title: Text(_t('no_playlists')));
                                }
                                return Column(
                                  children: playlists.map((pl) {
                                    final p = pl as Map<String, dynamic>;
                                    final pid = (p['id'] ?? '').toString();
                                    final ptitle = (p['title'] ?? pid).toString();
                                    final pthumb = _thumbFromMap(p);
                                    final String channelLogo =
                                        (p['channel_logo_url'] is String && (p['channel_logo_url'] as String).isNotEmpty)
                                            ? p['channel_logo_url'] as String
                                            : '$kApiBase/api/channels/$slug/logo/';
                                    return ExpansionTile(
                                      key: PageStorageKey('pl:$pid'),
                                      title: Row(
                                        children: [
                                          _buildThumb(channelLogo, size: 24, radius: BorderRadius.circular(12)),
                                          const SizedBox(width: 8),
                                          _buildThumb(pthumb, size: 32),
                                          const SizedBox(width: 10),
                                          Expanded(child: Text(ptitle)),
                                        ],
                                      ),
                                      children: [
                                        FutureBuilder(
                                          future: _ensureVideos(pid),
                                          builder: (context, snapshot) {
                                            final vids = _videosByPlaylist[pid];
                                            if (vids == null) {
                                              return const Padding(
                                                padding: EdgeInsets.all(12),
                                                child: LinearProgressIndicator(),
                                              );
                                            }
                                            if (vids.isEmpty) {
                                              return ListTile(title: Text(_t('no_videos')));
                                            }
                                            return Column(
                                              children: vids.map((v) {
                                                final vv = v as Map<String, dynamic>;
                                                final vid = (vv['video_id'] ?? '').toString();
                                                final vtitle = (vv['title'] ?? vid).toString();
                                                final vthumb = _thumbFromMap(vv);
                                                return ListTile(
                                                  dense: true,
                                                  leading: _buildThumb(vthumb, size: 44, radius: BorderRadius.circular(6)),
                                                  title: Text(vtitle),
                                                  subtitle: Text(vid),
                                                );
                                              }).toList(),
                                            );
                                          },
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        );
                      },
                  ),
                ),
      ),
    );
  }
}
