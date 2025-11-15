import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import '../api_client.dart';
import '../core/widgets/brand_title.dart';
import '../core/localization/l10n.dart';
import '../core/cache/channel_cache.dart';

class ChannelsPage extends StatefulWidget {
  final String tenantId;
  final LocalizationController? localizationController;
  const ChannelsPage(
      {super.key, required this.tenantId, this.localizationController});

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
  // Playlist counts per channel, set when that channel's playlists are fetched
  final Map<String, int> _playlistCounts = {};
  bool _hideEmpty = false;

  // Simple in-memory cache of last successful channels fetch (per app session)
  static List<dynamic> _cachedChannels = const [];

  LocalizationController get _lc =>
      widget.localizationController ?? LocalizationController();
  String _t(String key) => _lc.t(key);
  String get _langCode {
    try {
      return Localizations.localeOf(context).languageCode.toLowerCase();
    } catch (_) {
      return 'en';
    }
  }

  String _channelDisplayName(Map<String, dynamic> ch) {
    final am = (ch['name_am'] ?? '').toString().trim();
    final en = (ch['name_en'] ?? '').toString().trim();
    final slug = (ch['id_slug'] ?? '').toString();
    if (_langCode == 'am' && am.isNotEmpty) return am;
    if (en.isNotEmpty) return en;
    if (am.isNotEmpty) return am;
    return slug;
  }

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
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
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

  void _showChannelPlaylists(String channelSlug, Map<String, dynamic> ch) {
    final playlists = _playlistsByChannel[channelSlug] ?? const [];
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _channelDisplayName(ch),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _t('close'),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(_t('no_playlists')),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final pl = playlists[index] as Map<String, dynamic>;
                        final title = (pl['title'] ?? '').toString();
                        final thumb = _thumbFromMap(pl);
                        return ListTile(
                          leading: _buildThumb(thumb, size: 40),
                          title: Text(title.isNotEmpty
                              ? title
                              : pl['id']?.toString() ?? ''),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _logChannelDetails(Map<String, dynamic> ch) {
    if (!kDebugMode) return;
    final slug = (ch['id_slug'] ?? '').toString();
    final pretty = const JsonEncoder.withIndent('  ').convert(ch);
    const max = 800;
    int parts = (pretty.length / max).ceil();
    if (parts == 0) parts = 1;
    for (int i = 0; i < parts; i++) {
      final start = i * max;
      final end = start + max > pretty.length ? pretty.length : start + max;
      debugPrint(
          '[ChannelsPage] channel:$slug part ${i + 1}/$parts\n${pretty.substring(start, end)}');
    }
  }

  void _showChannelDetails(Map<String, dynamic> ch) {
    _logChannelDetails(ch);
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
                      Expanded(
                          child: Text(_t('channel_details'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16))),
                      IconButton(
                        tooltip: _t('close'),
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  _kv(_t('tenant_label'),
                      ch['tenant'] ?? _client.tenant ?? widget.tenantId),
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
                  onPressed:
                      _loading ? null : () => _loadChannels(clearCaches: false),
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
                              Text(_t('connection_details'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text('${_t('server')}:'),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(kApiBase,
                                          style: const TextStyle(
                                              fontFamily: 'monospace'))),
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
        debugPrint(
            '[ChannelsPage] ApiClient initialized. hasAccessToken=${_client.getAccessToken() != null}');
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
      'thumbnail',
      'thumbnail_url',
      'thumb',
      'thumb_url',
      'image',
      'image_url',
      'logo',
      'logo_url',
      'poster',
      'poster_url',
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
            size: size * 0.6, color: Theme.of(context).colorScheme.outline),
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
              size: size * 0.6, color: Theme.of(context).colorScheme.outline),
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
      debugPrint(
          '[ChannelsPage] Loading channels... (clearCaches=$clearCaches)');
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
        final int sample = all.length < 3 ? all.length : 3;
        for (int i = 0; i < sample; i++) {
          final ch = all[i] as Map<String, dynamic>;
          debugPrint(
              '[ChannelsPage] ch[$i] slug=${ch['id_slug']} name_en=${ch['name_en']} name_am=${ch['name_am']} lang=${ch['language']} active=${ch['is_active']}');
          debugPrint(
              '[ChannelsPage] ch[$i] images=${ch['images']} sources=${ch['sources']} handle=${ch['handle']} yt_handle=${ch['youtube_handle']}');
        }
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
        _playlistCounts[channelSlug] = data.length;
      });
      if (kDebugMode) {
        debugPrint(
            '[ChannelsPage] Playlists loaded for $channelSlug: count=${data.length}');
        final int sample = data.length < 3 ? data.length : 3;
        for (int i = 0; i < sample; i++) {
          final p = data[i] as Map<String, dynamic>;
          debugPrint(
              '[ChannelsPage] pl[$i] id=${p['id']} title=${p['title']} thumbs=${p['thumbnails'] ?? p['thumbnail'] ?? p['image']}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[ChannelsPage] Failed to load playlists for $channelSlug: $e');
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
        debugPrint(
            '[ChannelsPage] Videos loaded for $playlistId: count=${data.length}');
        final int sample = data.length < 3 ? data.length : 3;
        for (int i = 0; i < sample; i++) {
          final v = data[i] as Map<String, dynamic>;
          debugPrint(
              '[ChannelsPage] v[$i] video_id=${v['video_id']} title=${v['title']} thumbs=${v['thumbnails'] ?? v['thumbnail'] ?? v['image']}');
        }
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
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'toggle_hide_empty') {
                  setState(() => _hideEmpty = !_hideEmpty);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem<String>(
                  value: 'toggle_hide_empty',
                  child: Row(
                    children: [
                      Icon(_hideEmpty
                          ? Icons.check_box
                          : Icons.check_box_outline_blank),
                      const SizedBox(width: 8),
                      Text(_t('hide_empty_channels')),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)))
                : RefreshIndicator(
                    onRefresh: () => _loadChannels(clearCaches: true),
                    child: Builder(builder: (context) {
                      // Prepare visible channels with optional hide-empty filtering
                      final List<Map<String, dynamic>> allCh =
                          _channels.cast<Map<String, dynamic>>();
                      List<Map<String, dynamic>> visible = allCh;
                      if (_hideEmpty) {
                        visible = allCh.where((ch) {
                          final slug = (ch['id_slug'] ?? '').toString();
                          if (_playlistsByChannel.containsKey(slug)) {
                            return (_playlistCounts[slug] ?? 0) > 0;
                          }
                          return true;
                        }).toList();
                      }
                      return ListView(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        children: [
                          if (_offline) _buildOfflineCard(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.82,
                              ),
                              itemCount: visible.length,
                              itemBuilder: (context, i) {
                                final ch = visible[i];
                                final slug = (ch['id_slug'] ?? '').toString();
                                final title = _channelDisplayName(ch);
                                String? thumbUrlPrimary = _thumbFromMap(ch);
                                String thumbUrl = thumbUrlPrimary ??
                                    '$kApiBase/api/channels/$slug/logo/';
                                final int? count = _playlistCounts[slug];
                                final lang = (ch['language'] ?? '').toString();
                                return InkWell(
                                  onTap: () async {
                                    await _ensurePlaylists(slug);
                                    if (!mounted) return;
                                    _showChannelPlaylists(slug, ch);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color:
                                              Theme.of(context).dividerColor),
                                      borderRadius: BorderRadius.zero,
                                    ),
                                    child: Stack(
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              child: _buildThumb(thumbUrl,
                                                  size: double.infinity,
                                                  radius: BorderRadius.zero),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(title,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600)),
                                                  if (lang.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 4),
                                                      child: Text(
                                                          lang.toUpperCase(),
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .labelSmall),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (count != null)
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              child: Text('$count',
                                                  style: const TextStyle(
                                                      fontSize: 11)),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
      ),
    );
  }
}
