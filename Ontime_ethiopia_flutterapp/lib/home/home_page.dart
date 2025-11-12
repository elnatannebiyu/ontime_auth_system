// ignore_for_file: unused_field

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../live/audio_controller.dart';
import '../live/tv_controller.dart';
import '../auth/tenant_auth_client.dart';
import '../channels/channels_page.dart';
import '../core/localization/l10n.dart';
import '../features/home/widgets/hero_carousel.dart';
import '../features/home/widgets/section_header.dart';
import '../features/home/widgets/poster_row.dart';
// import '../features/home/widgets/mini_player_bar.dart';
import '../features/series/series_service.dart';
import '../features/series/pages/series_seasons_page.dart';
import '../features/series/pages/series_episodes_page.dart';
import '../features/home/widgets/channel_bubbles.dart';
import '../core/widgets/brand_title.dart';
import '../features/series/pages/series_shows_page.dart';
import '../api_client.dart';
import '../core/cache/channel_cache.dart';
import '../live/live_page.dart';
import '../core/notifications/notification_permission_manager.dart';
import '../shorts/shorts_page.dart';
import '../shorts/shorts_player_page.dart';

// Overflow menu actions for Home AppBar
enum _HomeMenuAction { profile, settings, about, switchLanguage }

class HomePage extends StatefulWidget {
  final AuthApi api;
  final TokenStore tokenStore;
  final String tenantId;
  final LocalizationController localizationController;

  const HomePage({
    super.key,
    required this.api,
    required this.tokenStore,
    required this.tenantId,
    required this.localizationController,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _me;
  bool _loading = true;
  String? _error;
  bool _offline = false;
  // Preview list for channel bubbles: [{name, slug, thumbUrl}]
  List<Map<String, String>> _bubbleChannels = const [];
  // For You data
  late final SeriesService _series;
  List<Map<String, dynamic>> _trendingShows = const [];
  List<Map<String, dynamic>> _newShorts = const [];
  bool _tabListenerAttached = false;

  // Lightweight language toggle (session only)
  // Localization is now centralized

  String _t(String key) => widget.localizationController.t(key);

  // (demo channel list removed; now using live data)

  // Mini player now handled globally via MiniPlayerManager

  @override
  void initState() {
    super.initState();
    _load();
    // Ask for notification permission gracefully after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationPermissionManager().ensurePermissionFlow(context);
    });
    _series = SeriesService(api: widget.api, tenantId: widget.tenantId);
    _loadTrendingNew();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    try {
      widget.api.setTenant(widget.tenantId);
      // Prefer a fresh cached me to avoid duplicate call right after login/register
      final cached = ApiClient().getFreshMe();
      if (cached != null) {
        setState(() {
          _me = cached;
        });
      } else {
        final me = await widget.api.me();
        setState(() {
          _me = me;
        });
      }
      // Load channel preview for bubbles (non-blocking for rest of UI)
      unawaited(_loadChannelBubbles());
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        setState(() {
          _offline = true;
        });
      } else {
        setState(() {
          _error = 'Failed to load profile';
        });
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // --- Channels preview (icons) for bubbles ---
  String? _thumbFromMap(Map<String, dynamic> m) {
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
      'cover_image',
      'channel_logo_url',
    ];
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    final t = m['thumbnails'];
    if (t is Map) {
      for (final size in ['high', 'medium', 'default', 'standard']) {
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

  Future<void> _loadChannelBubbles() async {
    final client = ApiClient();
    final tenant = client.tenant ?? widget.tenantId;
    // 1) Prime from cache quickly
    try {
      final cached = await ChannelCache.load(tenant);
      if (cached.isNotEmpty) {
        final mapped = cached.map<Map<String, String>>((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final slug = (m['id_slug'] ?? '').toString();
          final display = (m['name_en'] ?? m['name_am'] ?? slug).toString();
          final thumb =
              _thumbFromMap(m) ?? '$kApiBase/api/channels/$slug/logo/';
          return {'name': display, 'slug': slug, 'thumbUrl': thumb};
        }).toList();
        if (mounted) {
          setState(() => _bubbleChannels = mapped);
        }
      }
    } catch (_) {}
    // 2) Refresh from network (first page)
    try {
      final res = await client.get('/channels/', queryParameters: {
        'ordering': 'sort_order',
        'page': '1',
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
      final List<Map<String, String>> mapped = pageData.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final slug = (m['id_slug'] ?? '').toString();
        final display = (m['name_en'] ?? m['name_am'] ?? slug).toString();
        final thumb = _thumbFromMap(m) ?? '$kApiBase/api/channels/$slug/logo/';
        return {'name': display, 'slug': slug, 'thumbUrl': thumb};
      }).toList();
      if (mounted) {
        setState(() => _bubbleChannels = mapped);
      }
    } catch (_) {
      // Non-fatal for home; ignore errors
    }
  }

  // Load trending and new releases for For You
  Future<void> _loadTrendingNew() async {
    try {
      final trending = await _series.getTrendingShows();
      // Load shorts feed for "New releases"
      widget.api.setTenant(widget.tenantId);
      final client = ApiClient();
      final res =
          await client.get('/channels/shorts/ready/feed/', queryParameters: {
        'limit': '30',
        'recent_bias_count': '15',
      });
      final raw = res.data;
      final List<Map<String, dynamic>> shorts = raw is List
          ? List<Map<String, dynamic>>.from(
              raw.map((e) => Map<String, dynamic>.from(e as Map)))
          : (raw is Map && raw['results'] is List)
              ? List<Map<String, dynamic>>.from((raw['results'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map)))
              : const [];
      if (mounted) {
        setState(() {
          _trendingShows = trending;
          _newShorts = shorts;
        });
      }
    } catch (_) {
      // Non-fatal for home; leave placeholders if fetch fails
    }
  }

  // Open a show: if single season, go to episodes; else go to seasons list
  Future<void> _openShow(String slug, String title) async {
    try {
      final seasons = await _series.getSeasons(slug);
      if (!mounted) return;
      if (seasons.length == 1) {
        final s = seasons.first;
        final seasonId = s['id'] as int;
        final number = s['number']?.toString() ?? '';
        final rawTitle = (s['title'] as String?)?.trim() ?? '';
        final seasonTitle = rawTitle.isNotEmpty ? rawTitle : 'Season $number';
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeriesEpisodesPage(
              api: widget.api,
              tenantId: widget.tenantId,
              seasonId: seasonId,
              title: '$seasonTitle · $title',
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeriesSeasonsPage(
              api: widget.api,
              tenantId: widget.tenantId,
              showSlug: slug,
              showTitle: title,
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open show')),
      );
    }
  }

  // (_logout removed – not used on Home streaming UI)

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.localizationController,
      builder: (_, __) => DefaultTabController(
        length: 4,
        child: Builder(
          builder: (context) {
            final tc = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: tc,
              builder: (_, __) {
                final onShorts = tc.index == 3;
                return Scaffold(
          floatingActionButton: Builder(
            builder: (ctx) {
              final tc = DefaultTabController.of(ctx);
              if (!_tabListenerAttached) {
                _tabListenerAttached = true;
                tc.addListener(() {
                  if (tc.index == 3) {
                    // Shorts tab selected: stop radio and clear TV mini session
                    AudioController.instance.stop();
                    TvController.instance.clear();
                  }
                });
              }
              return AnimatedBuilder(
                animation: tc,
                builder: (_, __) {
                  final onShorts = tc.index == 3; // Shorts tab
                  final onLiveTab = tc.index == 2; // Live tab
                  if (onShorts || onLiveTab) return const SizedBox.shrink();
                  return FloatingActionButton.extended(
                    onPressed: () {
                      // Switch to Live tab instead of opening PlayerPage
                      tc.animateTo(2);
                    },
                    icon: const Icon(Icons.live_tv),
                    label: Text(_t('go_live')),
                  );
                },
              );
            },
          ),
          appBar: onShorts
              ? null
              : AppBar(
                  title: const BrandTitle(),
                  bottom: TabBar(
                    labelPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    isScrollable: true,
                    tabs: [
                      Tab(text: _t('for_you')),
                      Tab(text: _t('Shows')),
                      Tab(text: _t('Live')),
                      Tab(text: _t('Shorts')),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: _t('search'),
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Search ${_t('coming_soon')}')),
                        );
                      },
                    ),
                    PopupMenuButton<_HomeMenuAction>(
                      tooltip: _t('menu'),
                      itemBuilder: (context) {
                        final lang = widget.localizationController.language;
                        final switchTo = lang == AppLanguage.en ? 'AM' : 'EN';
                        return <PopupMenuEntry<_HomeMenuAction>>[
                          PopupMenuItem(
                            value: _HomeMenuAction.profile,
                            height: kMinInteractiveDimension,
                            child: SizedBox(
                              height: kMinInteractiveDimension,
                              child: Row(
                                children: [
                                  const Icon(Icons.account_circle_outlined),
                                  const SizedBox(width: 12),
                                  Text(_t('profile')),
                                ],
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: _HomeMenuAction.settings,
                            height: kMinInteractiveDimension,
                            child: SizedBox(
                              height: kMinInteractiveDimension,
                              child: Row(
                                children: [
                                  const Icon(Icons.settings_outlined),
                                  const SizedBox(width: 12),
                                  Text(_t('settings')),
                                ],
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: _HomeMenuAction.about,
                            height: kMinInteractiveDimension,
                            child: SizedBox(
                              height: kMinInteractiveDimension,
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline),
                                  const SizedBox(width: 12),
                                  Text(_t('about')),
                                ],
                              ),
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: _HomeMenuAction.switchLanguage,
                            height: kMinInteractiveDimension,
                            child: SizedBox(
                              height: kMinInteractiveDimension,
                              child: Row(
                                children: [
                                  const Icon(Icons.translate),
                                  const SizedBox(width: 12),
                                  Text('${_t('switch_language')} ($switchTo)'),
                                ],
                              ),
                            ),
                          ),
                        ];
                      },
                      onSelected: (value) {
                        switch (value) {
                          case _HomeMenuAction.profile:
                            Navigator.of(context).pushNamed('/profile');
                            break;
                          case _HomeMenuAction.settings:
                            Navigator.of(context).pushNamed('/settings');
                            break;
                          case _HomeMenuAction.about:
                            Navigator.of(context).pushNamed('/about');
                            break;
                          case _HomeMenuAction.switchLanguage:
                            widget.localizationController.toggleLanguage();
                            break;
                        }
                      },
                    ),
                  ],
                ),
          body: SafeArea(
            top: !onShorts,
            child: TabBarView(
              children: [
                // For You tab
                _buildForYou(context),
                // Shows tab
                SeriesShowsPage(api: widget.api, tenantId: widget.tenantId),
                const LivePage(),
                ShortsPage(api: widget.api, tenantId: widget.tenantId),
              ],
            ),
          ),
          // Global mini-player is handled by inner pages (e.g., LivePage)
          bottomSheet: null,
        );
              },
            );
          },
        ),
      ),
    );
  }

  // For You main content with pull-to-refresh
  Widget _buildForYou(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await _loadTrendingNew();
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_offline)
                          Card(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: ListTile(
                              leading: const Icon(Icons.wifi_off),
                              title: Text(_t('you_are_offline')),
                              subtitle: Text(_t('some_actions_offline')),
                            ),
                          )
                        else if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red)),
                          ),
                        // Hero carousel (extracted)
                        HeroCarousel(
                          liveLabel: _t('live'),
                          playLabel: _t('play'),
                          onPlay: () {},
                        ),
                        const SizedBox(height: 12),
                        // Browse Channels section header (extracted)
                        SectionHeader(
                          title: _t('browse_channels'),
                          actionLabel: _t('see_all'),
                          onAction: _loading
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ChannelsPage(
                                          tenantId: widget.tenantId,
                                          localizationController:
                                              widget.localizationController),
                                    ),
                                  );
                                  widget.api.setTenant(widget.tenantId);
                                },
                        ),
                        ChannelBubbles(
                          channels: _bubbleChannels,
                          onSeeAll: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChannelsPage(
                                  tenantId: widget.tenantId,
                                  localizationController:
                                      widget.localizationController,
                                ),
                              ),
                            );
                          },
                          onTapChannel: (slug) {
                            // For now, open full ChannelsPage; future: deep-link to slug
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChannelsPage(
                                  tenantId: widget.tenantId,
                                  localizationController:
                                      widget.localizationController,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        // Trending Now
                        SectionHeader(
                          title: _t('trending_now'),
                          actionLabel: _t('see_all'),
                          onAction: () {
                            final tc = DefaultTabController.of(context);
                            tc.animateTo(1); // Shows tab
                          },
                        ),
                        const SizedBox(height: 8),
                        PosterRow(
                          items: List<Map<String, dynamic>>.generate(
                              _trendingShows.length, (i) {
                            final s = _trendingShows[i];
                            return {
                              'title': (s['title'] ?? '').toString(),
                              'cover_image': _thumbFromMap(s) ?? '',
                              'slug': (s['slug'] ?? '').toString(),
                            };
                          }),
                          count: 10,
                          onTap: (m) => _openShow(
                            (m['slug'] ?? '').toString(),
                            (m['title'] ?? '').toString(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // New Releases (Shorts)
                        SectionHeader(
                          title: _t('new_releases'),
                          actionLabel: _t('see_all'),
                          onAction: () {
                            final tc = DefaultTabController.of(context);
                            tc.animateTo(3); // Shorts tab
                          },
                        ),
                        const SizedBox(height: 8),
                        PosterRow(
                          // Map shorts into poster items (title + cover_image)
                          items: List<Map<String, dynamic>>.generate(
                              _newShorts.length, (i) {
                            final v = _newShorts[i];
                            return {
                              'title': (v['title'] ?? v['name'] ?? 'Short')
                                  .toString(),
                              'cover_image': _thumbFromMap(v) ?? '',
                              'originalIndex': i,
                            };
                          }),
                          count: 12,
                          tall: true,
                          onTap: (m) {
                            final idx = (m['originalIndex'] ?? 0) as int;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ShortsPlayerPage(
                                  videos: _newShorts,
                                  initialIndex: idx,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(
                            height:
                                70), // space for mini-player above FAB notch
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
