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
import 'playlist_grid_sheet.dart';
import 'player/channel_mini_player_manager.dart';
import 'channel_ui_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  bool _offline = false;
  // Logo availability cache for fallback /logo/ URLs per channel slug
  final Map<String, bool> _logoAvailable = {};
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _openingPlaylistSheet = false;

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
      final headers = authHeadersFor(url);
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

  // (legacy bottom sheet removed; channel tap now opens PlaylistGridSheet)

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
    // Prefer in-memory session cache if present
    if (_cachedChannels.isNotEmpty) {
      setState(() {
        _channels = _cachedChannels;
        _loading = false;
      });
      return;
    }
    // Else try disk cache for a quick render
    final tenant = _client.tenant ?? widget.tenantId;
    try {
      final cached = await ChannelCache.load(tenant);
      if (cached.isNotEmpty) {
        setState(() {
          _channels = cached;
          _cachedChannels = cached;
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    // No cache → fetch from network
    await _loadChannels();
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
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        httpHeaders: authHeadersFor(url),
        placeholder: (_, __) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: radius,
          ),
        ),
        errorWidget: (_, __, ___) => Container(
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
        final primary = thumbFromMap(ch);
        if (primary != null && primary.isNotEmpty) continue;
        final logoUrl = '$kApiBase/api/channels/$slug/logo/';
        unawaited(_probeLogo(slug, logoUrl));
      }
      // (removed legacy expanded-channel playlist refresh)
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

  // (legacy playlist/video handlers removed)

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _lc,
      builder: (_, __) => Scaffold(
        appBar: AppBar(
          title: BrandTitle(section: _t('channels')),
        ),
        body: SafeArea(
          top: true,
          bottom: false,
          child: Stack(
            children: [
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.red)))
                      : RefreshIndicator(
                          onRefresh: () => _loadChannels(clearCaches: true),
                          child: Builder(builder: (context) {
                            final List<Map<String, dynamic>> visible =
                                _channels.cast<Map<String, dynamic>>();
                            return ValueListenableBuilder<double>(
                              valueListenable:
                                  ChannelMiniPlayerManager.I.miniPlayerHeight,
                              builder: (context, miniHeight, _) {
                                final mediaPadding =
                                    MediaQuery.of(context).padding;
                                final bottomPad =
                                    miniHeight + mediaPadding.bottom;
                                return ListView(
                                  padding:
                                      EdgeInsets.fromLTRB(0, 12, 0, bottomPad),
                                  children: [
                                    if (_offline) _buildOfflineCard(),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 8, 12, 12),
                                      child: GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
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
                                          final slug =
                                              (ch['id_slug'] ?? '').toString();
                                          final title = _channelDisplayName(ch);
                                          String? thumbUrlPrimary =
                                              thumbFromMap(ch);
                                          String? thumbUrl = thumbUrlPrimary;
                                          if (thumbUrl == null ||
                                              thumbUrl.isEmpty) {
                                            final avail = _logoAvailable[slug];
                                            if (avail != false) {
                                              thumbUrl =
                                                  '$kApiBase/api/channels/$slug/logo/';
                                            }
                                          }
                                          final lang =
                                              (ch['language'] ?? '').toString();
                                          return InkWell(
                                            onTap: () {
                                              if (_openingPlaylistSheet) return;
                                              setState(() {
                                                _openingPlaylistSheet = true;
                                              });
                                              showModalBottomSheet(
                                                context: context,
                                                isScrollControlled: true,
                                                showDragHandle: true,
                                                builder: (_) =>
                                                    PlaylistGridSheet(
                                                  channelSlug: slug,
                                                  channel: ch,
                                                ),
                                              ).whenComplete(() {
                                                if (!mounted) {
                                                  _openingPlaylistSheet = false;
                                                  return;
                                                }
                                                setState(() {
                                                  _openingPlaylistSheet = false;
                                                });
                                              });
                                            },
                                            child: Container(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: Theme.of(context)
                                                        .dividerColor),
                                                borderRadius: BorderRadius.zero,
                                              ),
                                              child: Stack(
                                                children: [
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Expanded(
                                                        child: _buildThumb(
                                                            thumbUrl,
                                                            size:
                                                                double.infinity,
                                                            radius: BorderRadius
                                                                .zero),
                                                      ),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(8.0),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(title,
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600)),
                                                            if (lang.isNotEmpty)
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top: 4),
                                                                child: Text(
                                                                    lang
                                                                        .toUpperCase(),
                                                                    style: Theme.of(
                                                                            context)
                                                                        .textTheme
                                                                        .labelSmall),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  // (removed playlist count badge in simplified page)
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          }),
                        ),
              // Series mini player overlay
            ],
          ),
        ),
      ),
    );
  }
}
