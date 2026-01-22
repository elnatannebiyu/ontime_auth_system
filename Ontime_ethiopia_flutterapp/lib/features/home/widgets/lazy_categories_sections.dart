// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../api_client.dart';
import '../../../core/localization/l10n.dart';
import '../../series/series_service.dart';
import 'section_header.dart';

class LazyCategoriesSections extends StatefulWidget {
  final SeriesService series;
  final LocalizationController localizationController;
  final ScrollController scrollController;
  final void Function(String slug, String title) onOpenShow;
  final void Function(String slug) onSeeAll;

  const LazyCategoriesSections({
    super.key,
    required this.series,
    required this.localizationController,
    required this.scrollController,
    required this.onOpenShow,
    required this.onSeeAll,
  });

  @override
  State<LazyCategoriesSections> createState() => _LazyCategoriesSectionsState();
}

class _LazyCategoriesSectionsState extends State<LazyCategoriesSections>
    with AutomaticKeepAliveClientMixin<LazyCategoriesSections> {
  static List<Map<String, dynamic>>? _cachedCategories;
  static final Map<String, List<Map<String, dynamic>>> _cachedShowsBySlug = {};
  final GlobalKey _topSentinelKey = GlobalKey();
  bool _fetchingCategories = false;
  List<Map<String, dynamic>> _categories = const [];
  final Map<String, GlobalKey> _sentinels = {};
  final Map<String, List<Map<String, dynamic>>> _showsBySlug = {};
  final Set<String> _attempted = {};
  final Set<String> _visible = {};
  final List<String> _pendingSlugs = [];
  final Set<String> _queuedSlugs = {};
  String? _loadingSlug;

  String _t(String key) => widget.localizationController.t(key);

  @override
  void initState() {
    super.initState();
    // Hydrate from in-memory cache if available
    if (_cachedCategories != null && _cachedCategories!.isNotEmpty) {
      _categories = List<Map<String, dynamic>>.from(_cachedCategories!);
      for (final c in _categories) {
        final slug = (c['slug'] ?? '').toString();
        if (slug.isEmpty) continue;
        _sentinels.putIfAbsent(slug, () => GlobalKey());
        final cachedShows = _cachedShowsBySlug[slug];
        if (cachedShows != null && cachedShows.isNotEmpty) {
          _showsBySlug[slug] = List<Map<String, dynamic>>.from(cachedShows);
        }
      }
    }
    widget.scrollController.addListener(_checkVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_checkVisibility);
    super.dispose();
  }

  void _checkVisibility() {
    if (!_fetchingCategories && _categories.isEmpty) {
      final ctx = _topSentinelKey.currentContext;
      if (ctx != null) {
        final obj = ctx.findRenderObject();
        if (obj is RenderBox) {
          final pos = obj.localToGlobal(Offset.zero);
          final h = MediaQuery.of(context).size.height;
          final visible = pos.dy >= 0 && pos.dy <= h;
          if (visible) {
            _fetchCategories();
          }
        }
      }
    }
    if (_categories.isNotEmpty) {
      for (final c in _categories) {
        final slug = (c['slug'] ?? '').toString();
        if (slug.isEmpty) continue;
        if (_attempted.contains(slug)) continue;
        final key = _sentinels[slug];
        if (key == null) continue;
        final ctx = key.currentContext;
        if (ctx == null) continue;
        final obj = ctx.findRenderObject();
        if (obj is RenderBox) {
          final pos = obj.localToGlobal(Offset.zero);
          final h = MediaQuery.of(context).size.height;
          final visible = pos.dy >= 0 && pos.dy <= h;
          if (visible) {
            if (!_queuedSlugs.contains(slug)) {
              _queuedSlugs.add(slug);
              _pendingSlugs.add(slug);
              setState(() {
                _visible.add(slug);
              });
              _startNextCategoryLoad();
            }
          }
        }
      }
    }
  }

  void _startNextCategoryLoad() {
    if (_loadingSlug != null) return;
    if (_pendingSlugs.isEmpty) return;
    final next = _pendingSlugs.removeAt(0);
    _loadingSlug = next;
    _attempted.add(next);
    _fetchShowsFor(next);
  }

  Future<void> _fetchCategories() async {
    try {
      setState(() {
        _fetchingCategories = true;
      });
      final cats = await widget.series.getCategories();
      debugPrint('[Home] Lazy category: categories=${cats.length}');
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _cachedCategories = List<Map<String, dynamic>>.from(cats);
        for (final c in cats) {
          final slug = (c['slug'] ?? '').toString();
          if (slug.isEmpty) continue;
          _sentinels.putIfAbsent(slug, () => GlobalKey());
        }
        _fetchingCategories = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    } catch (e) {
      debugPrint('[Home] Lazy category load failed: $e');
      if (mounted) {
        setState(() {
          _fetchingCategories = false;
        });
      }
    }
  }

  Future<void> _fetchShowsFor(String slug) async {
    try {
      final shows = await widget.series.getShowsByCategory(slug);
      debugPrint('[Home] Category loaded slug=$slug shows=${shows.length}');
      if (!mounted) return;
      setState(() {
        if (_loadingSlug == slug) _loadingSlug = null;
        if (shows.isNotEmpty) {
          _showsBySlug[slug] = shows;
          _cachedShowsBySlug[slug] = List<Map<String, dynamic>>.from(shows);
        }
      });
      _startNextCategoryLoad();
    } catch (e) {
      debugPrint('[Home] Category load failed slug=$slug error=$e');
      if (mounted) {
        setState(() {
          if (_loadingSlug == slug) _loadingSlug = null;
        });
      }
      _startNextCategoryLoad();
    }
  }

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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(key: _topSentinelKey, height: 1),
        if (_fetchingCategories)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
        for (final c in _categories)
          Builder(builder: (context) {
            final slug = (c['slug'] ?? '').toString();
            final title = (c['name'] ?? c['title'] ?? slug).toString();
            if (slug.isEmpty) {
              return const SizedBox.shrink();
            }
            final shows = _showsBySlug[slug];
            final animateIn = _visible.contains(slug);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(key: _sentinels[slug], height: 1),
                if (_loadingSlug == slug && (shows == null || shows.isEmpty))
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: animateIn ? 1 : 0,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  ),
                if (shows != null && shows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionHeader(
                    title: title,
                    actionLabel: _t('see_all'),
                    onAction: () => widget.onSeeAll(slug),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    offset: animateIn ? Offset.zero : const Offset(0, 0.05),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      opacity: animateIn ? 1 : 0,
                      child: _CategoryPosterRow(
                        items: List<Map<String, dynamic>>.generate(
                          shows.length > 10 ? 10 : shows.length,
                          (i) {
                            final s = shows[i];
                            return {
                              'title': (s['title'] ?? '').toString(),
                              'cover_image': _thumbFromMap(s) ?? '',
                              'slug': (s['slug'] ?? '').toString(),
                            };
                          },
                        ),
                        onTap: (m) => widget.onOpenShow(
                          (m['slug'] ?? '').toString(),
                          (m['title'] ?? '').toString(),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          }),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _CategoryPosterRow extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic>) onTap;
  const _CategoryPosterRow({required this.items, required this.onTap});

  @override
  State<_CategoryPosterRow> createState() => _CategoryPosterRowState();
}

class _CategoryPosterRowState extends State<_CategoryPosterRow> {
  final ScrollController _controller = ScrollController();
  bool _atStart = true;
  bool _atEnd = false;
  bool _nudged = false;

  Map<String, String>? _authHeadersFor(String url) {
    if (!url.startsWith(kApiBase)) return null;
    final client = ApiClient();
    final token = client.getAccessToken();
    final tenant = client.tenant;
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (tenant != null && tenant.isNotEmpty) {
      headers['X-Tenant-Id'] = tenant;
    }
    return headers.isEmpty ? null : headers;
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final atStart = pos.pixels <= pos.minScrollExtent + 2;
    final atEnd = pos.pixels >= pos.maxScrollExtent - 2;
    if (atStart != _atStart || atEnd != _atEnd) {
      if (atStart && !_atStart) {
        HapticFeedback.selectionClick();
      }
      if (atEnd && !_atEnd) {
        HapticFeedback.selectionClick();
      }
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeNudge());
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _maybeNudge() {
    if (!mounted || _nudged || !_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.maxScrollExtent > 8) {
      _nudged = true;
      _controller
          .animateTo(12,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut)
          .then((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.animateTo(0,
            duration: const Duration(milliseconds: 200), curve: Curves.easeIn);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const posterSize = Size(120, 180); // 2:3 aspect
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fadeColor = isDark
        ? Colors.black.withOpacity(0.7)
        : scheme.surface.withOpacity(0.9);
    return SizedBox(
      height: posterSize.height + 36, // image + title + spacing
      child: Stack(
        children: [
          ListView.separated(
            controller: _controller,
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: widget.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final m = widget.items[i];
              final title = (m['title'] ?? '').toString();
              final cover = (m['cover_image'] ?? '').toString();
              return SizedBox(
                width: posterSize.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onTap(m),
                        borderRadius: BorderRadius.circular(12),
                        child: Ink(
                          width: posterSize.width,
                          height: posterSize.height,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 6),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: cover.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: cover,
                                          fit: BoxFit.cover,
                                          httpHeaders: _authHeadersFor(cover),
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
                                          Colors.black.withOpacity(.30),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            },
          ),
          // Left fade indicator
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _atStart ? 0 : 1,
                child: Container(
                  width: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        fadeColor,
                        fadeColor.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Right fade indicator
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _atEnd ? 0 : 1,
                child: Container(
                  width: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        fadeColor,
                        fadeColor.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
