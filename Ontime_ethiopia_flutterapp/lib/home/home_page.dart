// ignore_for_file: unused_field

import 'dart:async' show StreamSubscription, unawaited;
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../live/audio_controller.dart';
import '../live/tv_controller.dart';
import '../auth/tenant_auth_client.dart';
import '../channels/channels_page.dart';
import '../channels/player/channel_mini_player_manager.dart';
import '../core/localization/l10n.dart';
import '../features/home/widgets/hero_carousel.dart';
import '../channels/playlist_grid_sheet.dart';
import '../features/home/widgets/section_header.dart';
import '../features/home/widgets/poster_row.dart';
import '../features/home/widgets/lazy_categories_sections.dart';
// import '../features/home/widgets/mini_player_bar.dart';
import '../features/series/series_service.dart';
import '../features/series/pages/series_seasons_page.dart';
import '../features/series/pages/series_episodes_page.dart';
import '../features/home/widgets/channel_bubbles.dart';
import '../core/widgets/brand_title.dart';
import '../core/widgets/offline_banner.dart';
import '../features/series/pages/series_shows_page.dart';
import '../api_client.dart';
import '../core/cache/channel_cache.dart';
import '../core/cache/home_trending_cache.dart';
import '../live/live_page.dart';
import '../core/notifications/fcm_manager.dart';
import '../shorts/shorts_page.dart';
import '../shorts/shorts_player_page.dart';

// Overflow menu actions for Home AppBar
enum _HomeMenuAction { profileSettings, settings, about, switchLanguage }

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
  List<Map<String, dynamic>> _heroShows = const [];
  bool _tabListenerAttached = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  int _unreadCount = 0;
  StreamSubscription<void>? _notifSub;
  late final ScrollController _scrollController;
  late final ValueNotifier<String?> _showsCategorySelector;
  bool _navigatingShow = false;
  bool _openingShorts = false;
  late final String _launchSeed;
  bool _openingChannelSheet = false;

  // Lightweight language toggle (session only)
  // Localization is now centralized

  String _t(String key) => widget.localizationController.t(key);

  // (demo channel list removed; now using live data)

  // Mini player now handled globally via MiniPlayerManager

  @override
  void initState() {
    super.initState();
    _launchSeed =
        '${DateTime.now().millisecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}';
    _load();
    _series = SeriesService(api: widget.api, tenantId: widget.tenantId);
    _loadHeroRandom();
    _loadTrendingNew();
    _loadUnreadCount();
    _scrollController = ScrollController();
    _showsCategorySelector = ValueNotifier<String?>(null);
    // FCM-based notification stream is temporarily disabled on iOS while
    // Firebase/FCM are not configured.
    if (!Platform.isIOS) {
      _notifSub = FcmManager().notificationStream.listen((_) {
        if (mounted) {
          _loadUnreadCount();
        }
      });
    }
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final isOffline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (!mounted) return;
      setState(() {
        _offline = isOffline;
        if (!isOffline && _error == null && !_loading) {
          // Came back online: auto refresh For You once
          _load();
          _loadTrendingNew();
        }
      });
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _notifSub?.cancel();
    _scrollController.dispose();
    _showsCategorySelector.dispose();
    super.dispose();
  }

  // category lazy loading moved to LazyCategoriesSections widget

  Future<void> _loadUnreadCount() async {
    try {
      final res =
          await ApiClient().get('/channels/notifications/unread-count/');
      final data = res.data;
      int count = 0;
      if (data is Map && data['count'] is int) {
        count = data['count'] as int;
      }
      if (!mounted) return;
      setState(() {
        _unreadCount = count;
      });
    } catch (_) {
      // Silently ignore; bell will just show no badge on failure.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    try {
      widget.api.setTenant(widget.tenantId);
      // Always fetch the latest profile so flags like email_verified are
      // immediately reflected after changes (e.g., verification link).
      final me = await widget.api.me();
      if (!mounted) return;
      setState(() {
        _me = me;
      });
      // Load channel preview for bubbles (non-blocking for rest of UI)
      unawaited(_loadChannelBubbles());
    } catch (e) {
      if (!mounted) return;
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
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
    final client = ApiClient();
    final tenant = client.tenant ?? widget.tenantId;
    // 1) Prime from disk cache so Home feels instant after relaunch/offline
    try {
      final cachedTrending = await HomeTrendingCache.loadTrending(tenant);
      final cachedShorts = await HomeTrendingCache.loadShorts(tenant);
      if (mounted && (cachedTrending.isNotEmpty || cachedShorts.isNotEmpty)) {
        setState(() {
          if (cachedTrending.isNotEmpty) {
            _trendingShows = cachedTrending;
          }
          if (cachedShorts.isNotEmpty) {
            _newShorts = cachedShorts;
          }
        });
      }
    } catch (_) {}

    // 2) Refresh from network
    try {
      final trending = await _series.getTrendingShows();
      // Load shorts feed for "New releases"
      widget.api.setTenant(widget.tenantId);
      final res =
          await client.get('/channels/shorts/ready/feed/', queryParameters: {
        'limit': '15',
        'recent_bias_count': '15',
        'seed': _launchSeed,
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
      // Persist latest data for fast next startup
      try {
        unawaited(HomeTrendingCache.saveTrending(tenant, trending));
        unawaited(HomeTrendingCache.saveShorts(tenant, shorts));
      } catch (_) {}
    } catch (_) {
      // Non-fatal for home; leave placeholders if fetch fails
    }
  }

  // Load random hero shows for the hero carousel (no disk cache so it
  // naturally refreshes on full app restarts).
  Future<void> _loadHeroRandom() async {
    try {
      final items = await _series.getHeroRandomShows(limit: 5);
      if (!mounted) return;
      setState(() {
        _heroShows = items;
      });
    } catch (_) {
      // Non-fatal; HeroCarousel will fall back to placeholder items.
    }
  }

  // Open a show: if single season, go to episodes; else go to seasons list
  Future<void> _openShow(String slug, String title) async {
    if (_navigatingShow) {
      debugPrint('[Home] Ignored duplicate tap: openShow($slug)');
      return;
    }
    _navigatingShow = true;
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
    } finally {
      if (mounted) {
        setState(() => _navigatingShow = false);
      } else {
        _navigatingShow = false;
      }
    }
  }

  String _profileInitial() {
    final name = (_me?['name'] ?? _me?['first_name'] ?? _me?['email'] ?? '')
        .toString()
        .trim();
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  bool get _isEmailVerified {
    final v = _me?['email_verified'];
    if (v is bool) return v;
    if (v is String) {
      return v.toLowerCase() == 'true';
    }
    return false;
  }

  void _showProfileSheet() {
    // Dismiss any active text input so the keyboard doesn't overlap the sheet
    FocusScope.of(context).unfocus();
    showModalBottomSheet<_HomeMenuAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return AnimatedBuilder(
          animation: widget.localizationController,
          builder: (_, __) {
            final lang = widget.localizationController.language;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.account_circle_outlined),
                          if (!_isEmailVerified)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .scaffoldBackgroundColor,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(_t('profile_settings')),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await Navigator.of(context).pushNamed('/profile');
                        if (mounted) {
                          _load();
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: Text(_t('settings')),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pushNamed('/settings');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(_t('about')),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pushNamed('/about');
                      },
                    ),
                    const Divider(),
                    ExpansionTile(
                      leading: const Icon(Icons.translate),
                      title: Text(_t('switch_language')),
                      children: [
                        RadioListTile<AppLanguage>(
                          value: AppLanguage.en,
                          groupValue: lang,
                          title: Text(_t('english')),
                          onChanged: (v) {
                            if (v == null) return;
                            widget.localizationController.setLanguage(v);
                          },
                        ),
                        RadioListTile<AppLanguage>(
                          value: AppLanguage.am,
                          groupValue: lang,
                          title: Text(_t('amharic')),
                          onChanged: (v) {
                            if (v == null) return;
                            widget.localizationController.setLanguage(v);
                          },
                        ),
                        RadioListTile<AppLanguage>(
                          value: AppLanguage.om,
                          groupValue: lang,
                          title: Text(_t('oromo')),
                          onChanged: (v) {
                            if (v == null) return;
                            widget.localizationController.setLanguage(v);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
                          // Hide keyboard when switching tabs so focused
                          // TextFields (e.g., search) don't keep the
                          // keyboard open on other tabs.
                          FocusManager.instance.primaryFocus?.unfocus();
                          if (tc.index == 3) {
                            // Shorts tab selected: pause and hide floating mini-player.
                            ChannelMiniPlayerManager.I.setSuppressed(true);
                            ChannelMiniPlayerManager.I.pause();
                            ChannelMiniPlayerManager.I.update(isPlaying: false);
                            AudioController.instance.stop();
                            try {
                              TvController.instance.pausePlayback();
                            } catch (_) {}
                          } else if (tc.previousIndex == 3) {
                            // Leaving Shorts tab: show mini-player again (still paused).
                            ChannelMiniPlayerManager.I.setSuppressed(false);
                          }
                        });
                      }
                      return AnimatedBuilder(
                        animation: tc,
                        builder: (_, __) {
                          final onShorts = tc.index == 3; // Shorts tab
                          final onLiveTab = tc.index == 2; // Live tab
                          if (onShorts || onLiveTab) {
                            return const SizedBox.shrink();
                          }
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
                              Tab(text: _t('live')),
                              Tab(text: _t('Shorts')),
                            ],
                          ),
                          actions: [
                            IconButton(
                              tooltip: 'Notifications',
                              onPressed: () async {
                                await Navigator.of(context).pushNamed('/inbox');
                                // Refresh count after returning from inbox
                                if (mounted) {
                                  _loadUnreadCount();
                                }
                              },
                              icon: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.notifications_outlined),
                                  if (_unreadCount > 0)
                                    Positioned(
                                      right: -2,
                                      top: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                          minHeight: 16,
                                        ),
                                        child: Text(
                                          _unreadCount > 9
                                              ? '9+'
                                              : _unreadCount.toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: _showProfileSheet,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      child: Text(
                                        _profileInitial(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (!_isEmailVerified)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .scaffoldBackgroundColor,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
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
                        SeriesShowsPage(
                          api: widget.api,
                          tenantId: widget.tenantId,
                          localizationController: widget.localizationController,
                          categorySelector: _showsCategorySelector,
                        ),
                        LivePage(
                          localizationController: widget.localizationController,
                        ),
                        ShortsPage(
                          api: widget.api,
                          tenantId: widget.tenantId,
                          initialItems: _newShorts,
                          localizationController: widget.localizationController,
                        ),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth < 700 ? 640.0 : 900.0;
    return RefreshIndicator(
      onRefresh: () async {
        // If we're clearly offline, avoid spamming network calls and
        // just surface the offline banner immediately.
        final results = await Connectivity().checkConnectivity();
        final isOffline = results.isEmpty ||
            results.every((r) => r == ConnectivityResult.none);
        if (isOffline) {
          if (mounted) {
            setState(() {
              _offline = true;
              // Keep any existing data; just show offline banner.
            });
          }
          return;
        }
        await _load();
        await _loadTrendingNew();
        await _loadHeroRandom();
      },
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_offline)
                          OfflineBanner(
                            title: _t('you_are_offline'),
                            subtitle: _t('some_actions_offline'),
                            onRetry: () async {
                              await _load();
                              await _loadTrendingNew();
                              await _loadHeroRandom();
                            },
                          )
                        else if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red)),
                          ),
                        if (_me != null && !_isEmailVerified)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.amber.withOpacity(0.6),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _t('email_not_verified_banner'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await Navigator.of(context)
                                        .pushNamed('/profile');
                                    if (mounted) {
                                      _load();
                                    }
                                  },
                                  child: Text(_t('verify_now')),
                                ),
                              ],
                            ),
                          ),
                        // Hero carousel (extracted)
                        HeroCarousel(
                          liveLabel: _t('live'),
                          playLabel: _t('play'),
                          items: List<Map<String, dynamic>>.generate(
                            _heroShows.length,
                            (i) {
                              final s = _heroShows[i];
                              return {
                                'title': (s['title'] ?? '').toString(),
                                'cover_image': _thumbFromMap(s) ??
                                    (s['cover_image'] ?? ''),
                                'channel_name':
                                    (s['channel_name'] ?? s['channel'] ?? '')
                                        .toString(),
                                'slug': (s['slug'] ?? '').toString(),
                              };
                            },
                          ),
                          onTapShow: (item) {
                            final slug = (item['slug'] ?? '').toString();
                            final title = (item['title'] ?? '').toString();
                            if (slug.isEmpty) return;
                            _openShow(slug, title);
                          },
                          onPlay: () {
                            // Jump to Live tab in the main Home tab controller
                            final tc = DefaultTabController.of(context);
                            tc.animateTo(2);
                          },
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
                            if (_openingChannelSheet) return;
                            _openingChannelSheet = true;
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder: (_) => PlaylistGridSheet(
                                channelSlug: slug,
                              ),
                            ).whenComplete(() {
                              _openingChannelSheet = false;
                            });
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
                              _trendingShows.length > 10
                                  ? 10
                                  : _trendingShows.length, (i) {
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
                              _newShorts.length > 12 ? 12 : _newShorts.length,
                              (i) {
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
                          onTap: (m) async {
                            final idx = (m['originalIndex'] ?? 0) as int;
                            if (_openingShorts) {
                              debugPrint(
                                  '[Home] Ignored duplicate tap: openShorts(index=$idx)');
                              return;
                            }
                            _openingShorts = true;
                            try {
                              // Fetch a fuller shorts feed so player has more than the 12–15 teaser items
                              final clicked = _newShorts.isNotEmpty &&
                                      idx < _newShorts.length
                                  ? _newShorts[idx]
                                  : null;
                              List<Map<String, dynamic>> fullList = _newShorts;
                              int startIndex = idx;
                              try {
                                final res = await ApiClient().get(
                                    '/channels/shorts/ready/feed/',
                                    queryParameters: {
                                      'limit': '200',
                                      'recent_bias_count': '15',
                                      'seed': _launchSeed,
                                    });
                                final data = res.data;
                                final List<Map<String, dynamic>> list = data
                                        is List
                                    ? List<Map<String, dynamic>>.from(data.map(
                                        (e) => Map<String, dynamic>.from(
                                            e as Map)))
                                    : (data is Map && data['results'] is List)
                                        ? List<Map<String, dynamic>>.from(
                                            (data['results'] as List).map((e) =>
                                                Map<String, dynamic>.from(
                                                    e as Map)))
                                        : const [];
                                if (list.isNotEmpty) {
                                  fullList = list;
                                  // Try to locate the clicked item in the full list by job_id
                                  final clickedId = (clicked?['job_id'] ??
                                          clicked?['id'] ??
                                          clicked?['video_id'] ??
                                          '')
                                      .toString();
                                  if (clickedId.isNotEmpty) {
                                    final found = fullList.indexWhere((e) =>
                                        (e['job_id'] ??
                                                e['id'] ??
                                                e['video_id'] ??
                                                '')
                                            .toString() ==
                                        clickedId);
                                    if (found >= 0) {
                                      startIndex = found;
                                    }
                                  }
                                }
                              } catch (_) {}

                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ShortsPlayerPage(
                                    videos: fullList,
                                    initialIndex: startIndex,
                                    isOffline: _offline,
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _openingShorts = false);
                              } else {
                                _openingShorts = false;
                              }
                            }
                          },
                        ),
                        LazyCategoriesSections(
                          series: _series,
                          localizationController: widget.localizationController,
                          scrollController: _scrollController,
                          onOpenShow: (slug, title) => _openShow(slug, title),
                          onSeeAll: (slug) {
                            _showsCategorySelector.value = slug;
                            final tc = DefaultTabController.of(context);
                            tc.animateTo(1);
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
