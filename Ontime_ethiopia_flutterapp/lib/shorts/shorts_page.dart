import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_client.dart';
import '../auth/tenant_auth_client.dart';
import 'shorts_player_page.dart';
import '../core/widgets/offline_banner.dart';
import '../core/localization/l10n.dart';

class ShortsPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final List<Map<String, dynamic>>? initialItems;
  final LocalizationController? localizationController;

  const ShortsPage({
    super.key,
    required this.api,
    required this.tenantId,
    this.initialItems,
    this.localizationController,
  });

  @override
  State<ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<ShortsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Set<String> _watchedShortIds = <String>{};
  bool _watchedLoaded = false;

  LocalizationController get _lc =>
      widget.localizationController ?? LocalizationController();
  String _t(String key) => _lc.t(key);

  @override
  void initState() {
    super.initState();
    _loadWatched();
    final initial = widget.initialItems;
    if (initial != null && initial.isNotEmpty) {
      _items = List<Map<String, dynamic>>.from(initial);
      _loading = false;
      _error = null;
      _offline = false;
      // Always refresh from network to get full, up-to-date shorts feed.
      // This replaces the initial 15 "New releases" teaser with the
      // complete list when the request completes.
      unawaited(_load());
    } else {
      _load();
    }

    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final isOffline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (!mounted) return;
      setState(() {
        _offline = isOffline;
        if (!isOffline && _items.isEmpty && !_loading) {
          _load();
        }
      });
    });
  }

  Future<void> _loadWatched() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('watched_shorts_job_ids');
      if (list != null && list.isNotEmpty) {
        setState(() {
          _watchedShortIds = list.toSet();
          _watchedLoaded = true;
        });
      } else {
        setState(() {
          _watchedLoaded = true;
        });
      }
    } catch (_) {
      setState(() {
        _watchedLoaded = true;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    try {
      // Ensure tenant is set on auth/api layer
      widget.api.setTenant(widget.tenantId);
      final client = ApiClient();
      final res =
          await client.get('/channels/shorts/ready/feed/', queryParameters: {
        // Ask backend for a large cap so we effectively get all available shorts.
        // Backend defaults to 100 if limit is omitted; using a high value here
        // keeps behaviour explicit while relying on server-side safety caps.
        'limit': '1000',
        'recent_bias_count': '15',
      });
      final data = res.data;
      final List<Map<String, dynamic>> list = data is List
          ? List<Map<String, dynamic>>.from(
              data.map((e) => Map<String, dynamic>.from(e as Map)))
          : (data is Map && data['results'] is List)
              ? List<Map<String, dynamic>>.from((data['results'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map)))
              : const [];
      setState(() => _items = list);
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        setState(() => _offline = true);
      } else {
        setState(() => _error = 'Failed to load Shorts');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = _items.isNotEmpty;

    int computeInitialIndex() {
      if (!hasItems) return 0;
      if (!_watchedLoaded || _watchedShortIds.isEmpty) return 0;
      for (var i = 0; i < _items.length; i++) {
        final id = (_items[i]['job_id'] ?? '').toString();
        if (id.isEmpty) continue;
        if (!_watchedShortIds.contains(id)) {
          return i;
        }
      }
      // All watched: loop from first
      return 0;
    }

    void onShortIndexChanged(int index) {
      if (index < 0 || index >= _items.length) return;
      final id = (_items[index]['job_id'] ?? '').toString();
      if (id.isEmpty) return;
      if (_watchedShortIds.add(id)) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setStringList(
              'watched_shorts_job_ids', _watchedShortIds.toList());
        });
      }
    }

    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          if (_offline || _error != null)
            OfflineBanner(
              title: _t('you_are_offline'),
              subtitle: _t('some_actions_offline'),
              onRetry: _load,
            ),
          Expanded(
            child: _loading && !hasItems
                ? const Center(child: CircularProgressIndicator())
                : hasItems
                    // Immediate player when we have items
                    ? ShortsPlayerPage(
                        videos: _items,
                        initialIndex: computeInitialIndex(),
                        isOffline: _offline,
                        onIndexChanged: onShortIndexChanged,
                      )
                    // No items yet: show a simple player placeholder so page feels like a player
                    : Container(
                        color: Colors.black,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.smart_display,
                                  size: 64, color: Colors.white54),
                              const SizedBox(height: 8),
                              Text(
                                _offline
                                    ? _t('you_are_offline')
                                    : _t('coming_soon'),
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
