// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unnecessary_brace_in_string_interps, control_flow_in_finally

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../api_client.dart';
import 'audio_controller.dart';
import 'tv_controller.dart';
import 'live_player_overlay_page.dart';
import '../core/widgets/offline_banner.dart';
import '../core/localization/l10n.dart';

class LivePage extends StatefulWidget {
  final LocalizationController? localizationController;

  const LivePage({super.key, this.localizationController});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage>
    with AutomaticKeepAliveClientMixin<LivePage> {
  LocalizationController get _lc =>
      widget.localizationController ?? LocalizationController();
  String _t(String key) => _lc.t(key);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _radios = const [];
  bool _offline = false;

  StreamSubscription<List<ConnectivityResult>>? _connSub;

  final TextEditingController _radioSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchRadios();
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      // Treat as offline only if ALL reported interfaces are none
      final isOffline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (!mounted) return;
      setState(() {
        _offline = isOffline;
        if (!isOffline && _error == null && _radios.isEmpty && !_loading) {
          // Came back online with no radios loaded yet: auto-refetch once
          _fetchRadios();
        }
      });
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _radioSearch.dispose();
    super.dispose();
  }

  Future<void> _fetchRadios() async {
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    try {
      final api = ApiClient();
      final res = await api.get('/live/radio/');
      List<Map<String, dynamic>> toList(dynamic raw) {
        if (raw is Map && raw['results'] is List) {
          return List<Map<String, dynamic>>.from((raw['results'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map)));
        }
        if (raw is List) {
          return List<Map<String, dynamic>>.from(
              raw.map((e) => Map<String, dynamic>.from(e as Map)));
        }
        return const [];
      }

      setState(() {
        _radios = toList(res.data);
      });
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        setState(() {
          _offline = true;
        });
      } else {
        setState(() {
          _error = 'Failed to load content';
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // for AutomaticKeepAliveClientMixin
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          title: const SizedBox.shrink(),
          toolbarHeight: 0,
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            if (_offline || _error != null)
              OfflineBanner(
                title: _t('you_are_offline'),
                subtitle: _t('some_actions_offline'),
                onRetry: _fetchRadios,
              ),
            const TabBar(
              labelPadding: EdgeInsets.symmetric(horizontal: 16),
              tabs: [
                Tab(text: 'TV'),
                Tab(text: 'Radio'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError()
                      : TabBarView(
                          children: [
                            _TvTab(),
                            RefreshIndicator(
                              onRefresh: _fetchRadios,
                              child: _RadioTab(),
                            ),
                          ],
                        ),
            ),
          ],
        ),
        bottomNavigationBar: null,
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
              onPressed: _fetchRadios,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

// ---------------- Radio Tab ----------------
class _RadioTab extends StatefulWidget {
  const _RadioTab();
  @override
  State<_RadioTab> createState() => _RadioTabState();
}

class _RadioTabState extends State<_RadioTab> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inherited = context.findAncestorStateOfType<_LivePageState>();
    final items = inherited?._radios ?? const [];

    final q = _search.text.trim().toLowerCase();
    final filtered = items.where((m) {
      final name = (m['name'] ?? '').toString().toLowerCase();
      if (q.isNotEmpty && !name.contains(q)) return false;
      return true;
    }).toList();

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      itemCount: filtered.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _toolbar();
        final m = filtered[i - 1];
        final name = (m['name'] ?? '').toString();
        final slug = (m['slug'] ?? '').toString();
        final country = (m['country'] ?? '').toString();
        final language = (m['language'] ?? '').toString();
        final bitrate = (m['bitrate']?.toString() ?? '');
        final format = (m['format'] ?? '').toString();
        final subtitle = [
          if (country.isNotEmpty) country,
          if (language.isNotEmpty) language,
          if (bitrate.isNotEmpty || format.isNotEmpty)
            '${bitrate.isNotEmpty ? '${bitrate}kbps' : ''}${bitrate.isNotEmpty && format.isNotEmpty ? ' · ' : ''}${format}',
        ].join(' · ');
        return Card(
          elevation: 1.5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: _RadioLogo(url: (m['logo'] ?? '').toString(), name: name),
            title: Text(name.isEmpty ? 'Radio' : name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle.isNotEmpty)
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (m['is_active'] == true)
                    const _BadgePill(text: 'ACTIVE', color: Colors.green),
                  if (m['is_verified'] == true)
                    const _BadgePill(text: 'VERIFIED', color: Colors.indigo),
                  if (m['listener_count'] != null)
                    _ChipOutlined(
                        icon: Icons.headphones,
                        label: '${m['listener_count']}'),
                ]),
              ],
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (bitrate.isNotEmpty)
                _ChipOutlined(label: '${bitrate}kbps', icon: Icons.speed),
              const Icon(Icons.play_arrow),
            ]),
            onTap: () async {
              if (slug.isEmpty) return;
              try {
                final nav = Navigator.of(context, rootNavigator: true);
                bool dialogShown = false;
                if (context.mounted) {
                  dialogShown = true;
                  showDialog(
                      context: context,
                      useRootNavigator: true,
                      barrierDismissible: false,
                      builder: (_) =>
                          const Center(child: CircularProgressIndicator()));
                }
                final ctrl = AudioController.instance;
                // Replacement policy: opening Radio stops TV
                try {
                  await TvController.instance.stop();
                } catch (_) {}
                final stateFuture = ctrl.player.playerStateStream
                    .firstWhere((s) => s.playing)
                    .timeout(const Duration(seconds: 12),
                        onTimeout: () => ctrl.player.playerState);
                final playFuture =
                    AudioController.instance.playRadioBySlug(slug);
                await Future.any([playFuture, stateFuture]);
                if (context.mounted) {
                  if (dialogShown && nav.canPop()) nav.pop();
                }
              } catch (_) {
                final nav = Navigator.of(context, rootNavigator: true);
                if (context.mounted && nav.canPop()) nav.pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to start radio')));
                }
              }
            },
          ),
        );
      },
    );
  }

  Widget _toolbar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4, right: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search radios',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_search.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: () {
                setState(() {
                  _search.clear();
                });
              },
              icon: const Icon(Icons.clear),
            ),
        ],
      ),
    );
  }
}

class _RadioLogo extends StatelessWidget {
  final String url;
  final String name;
  const _RadioLogo({required this.url, required this.name});
  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
        radius: 18,
        child: Text((name.isNotEmpty ? name[0] : 'R').toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold)));
    if (url.isEmpty) return fallback;
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.transparent,
      child: ClipOval(
          child: Image.network(url,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback)),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  final Color color;
  const _BadgePill({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _ChipOutlined extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipOutlined({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blueGrey.withOpacity(0.35))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon,
            size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11))
      ]),
    );
  }
}

// ---------------- TV Tab ----------------
class _TvTab extends StatefulWidget {
  const _TvTab();
  @override
  State<_TvTab> createState() => _TvTabState();
}

class _TvTabState extends State<_TvTab>
    with AutomaticKeepAliveClientMixin<_TvTab> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = true;
  int _page = 1;
  bool _hasNext = false;
  final List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        if (!_loading && _hasNext) {
          _fetch(reset: false);
        }
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool reset}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
    });
    try {
      final api = ApiClient();
      final q = _search.text.trim();
      final page = reset ? 1 : (_page + 1);
      final res = await api.get('/live/',
          queryParameters: {if (q.isNotEmpty) 'search': q, 'page': page});
      final data = res.data;
      List<Map<String, dynamic>> rows;
      bool hasNext = false;
      if (data is Map) {
        final list =
            (data['results'] is List) ? (data['results'] as List) : const [];
        rows = List<Map<String, dynamic>>.from(
            list.map((e) => Map<String, dynamic>.from(e as Map)));
        hasNext = data['next'] != null;
      } else if (data is List) {
        rows = List<Map<String, dynamic>>.from(
            data.map((e) => Map<String, dynamic>.from(e as Map)));
        hasNext = false;
      } else {
        rows = const [];
        hasNext = false;
      }
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(rows);
          _page = 1;
        } else {
          _items.addAll(rows);
          _page = page;
        }
        _hasNext = hasNext;
      });
    } catch (e) {
      if (!mounted) return;
      // Report error to parent LivePage so the shared OfflineBanner can respond
      final parent = context.findAncestorStateOfType<_LivePageState>();
      if (parent != null && parent.mounted) {
        parent.setState(() {
          if (e is DioException && e.type == DioExceptionType.connectionError) {
            parent._offline = true;
            parent._error = null;
          } else {
            parent._offline = false;
            parent._error = 'Failed to load content';
          }
        });
      }
      setState(() {});
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // for AutomaticKeepAliveClientMixin
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final size = MediaQuery.of(context).size;
    final cross = size.width > 720 ? 3 : (size.width > 480 ? 2 : 1);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(children: [
          Expanded(
              child: TextField(
            controller: _search,
            onSubmitted: (_) => _fetch(reset: true),
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search TV',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12))),
          )),
          const SizedBox(width: 8),
          ElevatedButton.icon(
              onPressed: () => _fetch(reset: true),
              icon: const Icon(Icons.search),
              label: const Text('Go'),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12))),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => _fetch(reset: true),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels >= n.metrics.maxScrollExtent - 100 &&
                  !_loading &&
                  _hasNext) {
                _fetch(reset: false);
              }
              return false;
            },
            child: GridView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  childAspectRatio: 16 / 9,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12),
              itemCount: _items.length + (_hasNext ? 1 : 0),
              itemBuilder: (context, i) {
                if (_hasNext && i == _items.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final m = _items[i];
                final title = (m['title'] ??
                        m['channel_name'] ??
                        m['channel_slug'] ??
                        m['slug'] ??
                        '')
                    .toString();
                final slug =
                    (m['channel_slug'] ?? m['slug'] ?? m['id_slug'] ?? '')
                        .toString();
                final poster = (m['poster_url'] ?? '').toString();
                final logo = (m['channel_logo_url'] ?? '').toString();
                return InkWell(
                  onTap: () async {
                    if (slug.isEmpty) return;
                    try {
                      await AudioController.instance.stop();
                    } catch (_) {}
                    Navigator.of(context).push(PageRouteBuilder(
                      pageBuilder: (_, __, ___) =>
                          LivePlayerOverlayPage(slug: slug),
                      transitionDuration: const Duration(milliseconds: 280),
                      reverseTransitionDuration:
                          const Duration(milliseconds: 220),
                      transitionsBuilder: (_, animation, __, child) {
                        const begin = Offset(0.0, 1.0);
                        const end = Offset.zero;
                        final tween = Tween(begin: begin, end: end)
                            .chain(CurveTween(curve: Curves.easeOutCubic));
                        return SlideTransition(
                            position: animation.drive(tween), child: child);
                      },
                    ));
                  },
                  child: Card(
                    elevation: 2,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Stack(children: [
                      // Background thumbnail: prefer poster_url, then channel_logo_url, else fallback icon
                      if (poster.isNotEmpty || logo.isNotEmpty)
                        Positioned.fill(
                          child: Image.network(
                            poster.isNotEmpty ? poster : logo,
                            // Show full poster/logo without cropping edges
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.black12,
                              child: const Center(
                                  child: Icon(Icons.live_tv, size: 48)),
                            ),
                          ),
                        )
                      else
                        Container(
                            color: Colors.black12,
                            child: const Center(
                                child: Icon(Icons.live_tv, size: 48))),
                      Positioned(
                          left: 8, top: 8, child: _ChannelLogo(logoUrl: logo)),
                      Positioned(
                          right: 8,
                          top: 8,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if ((m['playback_type'] ?? '')
                                .toString()
                                .isNotEmpty)
                              _InfoChip(
                                  label: (m['playback_type'] ?? '')
                                      .toString()
                                      .toUpperCase(),
                                  icon: Icons.waves),
                            if (m['listener_count'] != null)
                              const SizedBox(width: 6),
                            if (m['listener_count'] != null)
                              _InfoChip(
                                  label: ' ${m['listener_count']}',
                                  icon: Icons.headphones),
                          ])),
                      Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(title.isEmpty ? 'Live TV' : title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          )),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  bool get wantKeepAlive => true;
}

class _ChannelLogo extends StatelessWidget {
  final String logoUrl;
  const _ChannelLogo({required this.logoUrl});
  @override
  Widget build(BuildContext context) {
    final w = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35), shape: BoxShape.circle),
        child: const Icon(Icons.live_tv, color: Colors.white, size: 16));
    if (logoUrl.isEmpty) return w;
    return ClipOval(
        child: Image.network(logoUrl,
            width: 28,
            height: 28,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => w));
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _InfoChip({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 12),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))
      ]),
    );
  }
}
