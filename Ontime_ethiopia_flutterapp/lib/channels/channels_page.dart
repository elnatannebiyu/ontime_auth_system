import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'dart:async' show StreamSubscription, unawaited;
import '../api_client.dart';
import '../core/widgets/brand_title.dart';
import '../core/localization/l10n.dart';
import '../core/cache/channel_cache.dart';
import '../core/cache/logo_probe_cache.dart';
import '../core/widgets/offline_banner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
  final Set<String> _expandedChannels = <String>{};
  bool _offline = false;
  // Playlist counts per channel, set when that channel's playlists are fetched
  final Map<String, int> _playlistCounts = {};
  bool _hideEmpty = false;
  // Logo availability cache for fallback /logo/ URLs per channel slug
  final Map<String, bool> _logoAvailable = {};
  StreamSubscription<List<ConnectivityResult>>? _connSub;

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

  Future<void> _probeLogo(String slug, String url) async {
    try {
      final headers = _authHeadersFor(url);
      final ok = await LogoProbeCache.instance
          .ensureAvailable(url, headers: headers ?? const {});
      if (!mounted) return;
      setState(() {
        _logoAvailable[slug] = ok;
      });
    } catch (_) {}
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
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final isOffline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (!mounted) return;
      setState(() {
        _offline = isOffline;
        if (!isOffline && _channels.isEmpty && !_loading) {
          _loadChannels(clearCaches: false);
        }
      });
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  // ---- Channel details modal ----

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

  Widget _buildOfflineCard() {
    return OfflineBanner(
      title: _t('you_are_offline'),
      subtitle: _t('some_actions_offline'),
      onRetry: _loading ? null : () => _loadChannels(clearCaches: false),
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
      // Prime logo availability for channels that rely on fallback /logo/ URLs
      for (final dynamic raw in all) {
        final ch = raw as Map<String, dynamic>;
        final slug = (ch['id_slug'] ?? '').toString();
        if (slug.isEmpty) continue;
        final primary = _thumbFromMap(ch);
        if (primary != null && primary.isNotEmpty) continue;
        final logoUrl = '$kApiBase/api/channels/$slug/logo/';
        unawaited(_probeLogo(slug, logoUrl));
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
                                String? thumbUrl = thumbUrlPrimary;
                                if (thumbUrl == null || thumbUrl.isEmpty) {
                                  final avail = _logoAvailable[slug];
                                  if (avail != false) {
                                    thumbUrl =
                                        '$kApiBase/api/channels/$slug/logo/';
                                  }
                                }
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
