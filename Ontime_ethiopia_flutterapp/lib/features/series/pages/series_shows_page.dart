// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../auth/tenant_auth_client.dart';
import '../series_service.dart';
import 'series_seasons_page.dart';
import 'series_episodes_page.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/localization/l10n.dart';

class SeriesShowsPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final LocalizationController? localizationController;

  const SeriesShowsPage({
    super.key,
    required this.api,
    required this.tenantId,
    this.localizationController,
  });

  @override
  State<SeriesShowsPage> createState() => _SeriesShowsPageState();
}

class _SeriesShowsPageState extends State<SeriesShowsPage>
    with AutomaticKeepAliveClientMixin<SeriesShowsPage> {
  late final SeriesService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _categories = const [];
  String? _selectedCategorySlug;
  List<Map<String, dynamic>> _allShows = const [];
  List<Map<String, dynamic>> _categoryShows = const [];
  bool _navigating = false; // guard against multiple rapid taps
  bool _offline = false;

  LocalizationController get _lc =>
      widget.localizationController ?? LocalizationController();
  String _t(String key) => _lc.t(key);

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
      _offline = false;
    });
    try {
      final cats = await _service.getCategories();
      final all = await _service.getShows();
      setState(() {
        _categories = cats;
        _allShows = all;
      });
      if (_selectedCategorySlug != null) {
        final list = await _service.getShowsByCategory(_selectedCategorySlug!);
        if (mounted) {
          setState(() {
            _categoryShows = list;
          });
        }
      }
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        setState(() {
          _offline = true;
        });
      } else {
        setState(() {
          _error = 'Failed to load shows';
        });
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _openShow(String slug, String title) async {
    // Guard: prevent multiple rapid navigations
    if (_navigating) return;
    _navigating = true;
    // Fetch seasons; if exactly one, push episodes directly
    try {
      final seasons = await _service.getSeasons(slug);
      if (!mounted) return;
      if (seasons.length == 1) {
        final s = seasons.first;
        final seasonId = s['id'] as int;
        final number = s['number']?.toString() ?? '';
        final rawTitle = (s['title'] as String?)?.trim() ?? '';
        final seasonTitle = rawTitle.isNotEmpty ? rawTitle : 'Season $number';
        await Navigator.of(context).push(
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
        await Navigator.of(context).push(
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
    } finally {
      if (mounted) {
        setState(() => _navigating = false);
      } else {
        _navigating = false;
      }
    }
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null) return null;
    final v = hex.trim();
    if (v.isEmpty || !v.startsWith('#')) return null;
    final h = v.substring(1);
    if (h.length == 6) {
      final val = int.tryParse('FF$h', radix: 16);
      if (val == null) return null;
      return Color(val);
    }
    if (h.length == 8) {
      final val = int.tryParse(h, radix: 16);
      if (val == null) return null;
      return Color(val);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // for AutomaticKeepAliveClientMixin
    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                if (_offline || _error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: OfflineBanner(
                      title: _t('you_are_offline'),
                      subtitle: _t('some_actions_offline'),
                      onRetry: _load,
                    ),
                  ),
                _Section(
                  title: _t('categories'),
                  child: SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _categories.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          final selected = _selectedCategorySlug == null;
                          return ChoiceChip(
                            label: const Text('All'),
                            selected: selected,
                            onSelected: (val) async {
                              setState(() {
                                _selectedCategorySlug = null;
                              });
                              // No extra load; grid uses _allShows
                            },
                          );
                        }
                        final c = _categories[i - 1];
                        final name = (c['name'] ?? '').toString();
                        final slug = (c['slug'] ?? '').toString();
                        final color = _parseHexColor(c['color']?.toString());
                        final selected = slug == _selectedCategorySlug;
                        return ChoiceChip(
                          label: Text(name),
                          selected: selected,
                          selectedColor:
                              (color ?? Theme.of(context).colorScheme.primary)
                                  .withOpacity(0.2),
                          side: BorderSide(
                              color: color ?? Theme.of(context).dividerColor),
                          onSelected: (val) async {
                            if (!val) {
                              setState(() {
                                _selectedCategorySlug = null;
                              });
                              return;
                            }
                            setState(() {
                              _selectedCategorySlug = slug;
                            });
                            final list =
                                await _service.getShowsByCategory(slug);
                            if (!mounted) return;
                            setState(() {
                              _categoryShows = list;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: _ShowsGrid(
                    items: _selectedCategorySlug == null
                        ? _allShows
                        : _categoryShows,
                    onTap: (s) => _openShow(s['slug']?.toString() ?? '',
                        s['title']?.toString() ?? ''),
                    service: _service,
                  ),
                ),
              ],
            ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _ShowCard extends StatefulWidget {
  final String title;
  final String imageUrl;
  final String slug;
  final SeriesService service;
  final VoidCallback? onTap;
  const _ShowCard({
    required this.title,
    required this.imageUrl,
    required this.slug,
    required this.service,
    this.onTap,
  });

  @override
  State<_ShowCard> createState() => _ShowCardState();
}

class _ShowCardState extends State<_ShowCard> {
  bool _loadingStatus = false;
  bool _hasReminder = false;
  bool _isActive = false;
  int? _reminderId;

  bool get _isOn => _hasReminder && _isActive;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loadingStatus = true;
    });
    try {
      final res = await widget.service.getReminderStatus(widget.slug);
      final has = res['has_reminder'] == true;
      final active = res['is_active'] == true;
      final id = res['id'];
      if (!mounted) return;
      setState(() {
        _hasReminder = has;
        _isActive = active;
        _reminderId = (id is int) ? id : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasReminder = false;
        _isActive = false;
        _reminderId = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingStatus = false;
        });
      }
    }
  }

  Future<void> _toggleReminder() async {
    if (_loadingStatus) return;
    setState(() {
      _loadingStatus = true;
    });
    try {
      if (!_isOn) {
        final res = await widget.service.createReminder(widget.slug);
        final id = res['id'];
        final active = res['is_active'] == true;
        if (!mounted) return;
        setState(() {
          _hasReminder = true;
          _isActive = active;
          _reminderId = (id is int) ? id : null;
        });
      } else {
        final id = _reminderId;
        if (id != null) {
          await widget.service.deleteReminder(id);
        }
        if (!mounted) return;
        setState(() {
          _hasReminder = false;
          _isActive = false;
          _reminderId = null;
        });
      }
    } catch (_) {
      // ignore errors for now; UI will stay in previous state
    } finally {
      if (mounted) {
        setState(() {
          _loadingStatus = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: widget.imageUrl.isNotEmpty
                  ? Image.network(widget.imageUrl, fit: BoxFit.cover)
                  : Container(
                      color: Colors.black12,
                      child: const Icon(Icons.tv, size: 40),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(
                      _isOn
                          ? Icons.notifications_active
                          : Icons.notifications_none_outlined,
                      color: _isOn
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).iconTheme.color?.withOpacity(0.7),
                    ),
                    onPressed: _toggleReminder,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        child,
      ],
    );
  }
}

class _ShowsGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic>) onTap;
  final SeriesService service;

  const _ShowsGrid(
      {required this.items, required this.onTap, required this.service});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.7,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final s = items[i];
        final title = (s['title'] ?? '').toString();
        final cover = (s['cover_image'] ?? '').toString();
        final slug = (s['slug'] ?? '').toString();
        return _ShowCard(
          title: title,
          imageUrl: cover,
          slug: slug,
          service: service,
          onTap: () => onTap({'slug': slug, 'title': title}),
        );
      },
    );
  }
}
