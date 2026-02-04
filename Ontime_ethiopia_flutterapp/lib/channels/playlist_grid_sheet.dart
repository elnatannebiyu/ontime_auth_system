import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../core/cache/channel_cache.dart';
import '../core/localization/l10n.dart';
import 'channel_playlist_cache.dart';
import 'channel_service.dart';
import 'channel_ui_utils.dart';
import 'playlist_detail_page.dart';

class PlaylistGridSheet extends StatefulWidget {
  final String channelSlug;
  final Map<String, dynamic>? channel;

  const PlaylistGridSheet({super.key, required this.channelSlug, this.channel});

  @override
  State<PlaylistGridSheet> createState() => _PlaylistGridSheetState();
}

class _PlaylistGridSheetState extends State<PlaylistGridSheet> {
  final ChannelsService _service = ChannelsService();
  final LocalizationController _lc = LocalizationController();

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  final List<Map<String, dynamic>> _playlists = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = true;
  int _page = 1;

  bool _offline = false;
  String? _error;

  Map<String, dynamic>? _channel;
  bool _loadingChannel = true;

  Timer? _debounce;
  String _query = '';

  final _cachedPlaylistsBySlug = ChannelPlaylistCache.playlistsBySlug;
  final _cachedChannelBySlug = ChannelPlaylistCache.channelBySlug;

  String _t(String key) => _lc.t(key);

  @override
  void initState() {
    super.initState();
    _lc.load();
    _primeChannel();
    _loadPage(1);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    try {
      _debounce?.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _primeChannel() {
    if (widget.channel != null) {
      _channel = widget.channel;
      _cachedChannelBySlug[widget.channelSlug] =
          Map<String, dynamic>.from(widget.channel!);
      _loadingChannel = false;
      return;
    }
    final cached = _cachedChannelBySlug[widget.channelSlug];
    if (cached != null) {
      _channel = Map<String, dynamic>.from(cached);
      _loadingChannel = false;
      return;
    }
    _primeChannelFromDiskCache();
  }

  Future<void> _primeChannelFromDiskCache() async {
    try {
      final client = ApiClient();
      final tenant = client.tenant;
      if (tenant == null || tenant.isEmpty) {
        await _loadChannel();
        return;
      }
      final cachedList = await ChannelCache.load(tenant);
      if (cachedList.isNotEmpty) {
        final slug = widget.channelSlug;
        for (final dynamic raw in cachedList) {
          if (raw is Map<String, dynamic>) {
            final s = (raw['id_slug'] ?? '').toString();
            if (s == slug) {
              if (!mounted) return;
              setState(() {
                _channel = Map<String, dynamic>.from(raw);
                _loadingChannel = false;
              });
              _cachedChannelBySlug[slug] = Map<String, dynamic>.from(raw);
              return;
            }
          }
        }
      }
      await _loadChannel();
    } catch (_) {
      await _loadChannel();
    }
  }

  Future<void> _loadChannel() async {
    try {
      final m = await _service.getChannel(widget.channelSlug);
      if (!mounted) return;
      setState(() {
        _channel = m;
        _loadingChannel = false;
      });
      if (m != null) {
        _cachedChannelBySlug[widget.channelSlug] = Map<String, dynamic>.from(m);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingChannel = false;
      });
    }
  }

  void _onScroll() {
    if (!_hasNext || _loadingMore || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadPage(int page) async {
    setState(() {
      _loading = page == 1;
      _error = null;
    });

    try {
      final connResults = await Connectivity().checkConnectivity();
      final bool isOffline = connResults.contains(ConnectivityResult.none);
      if (isOffline) {
        final cached = _cachedPlaylistsBySlug[widget.channelSlug] ?? const [];
        if (!mounted) return;
        setState(() {
          _offline = true;
          _playlists
            ..clear()
            ..addAll(cached);
          _loading = false;
          _loadingMore = false;
          _hasNext = false;
          _error = cached.isEmpty ? _t('you_are_offline') : null;
        });
        return;
      }

      final res = await _service.getPlaylists(widget.channelSlug, page: page);
      final results = List<Map<String, dynamic>>.from(res['results'] as List);
      if (!mounted) return;
      setState(() {
        if (page == 1) {
          _playlists
            ..clear()
            ..addAll(results);
        } else {
          _playlists.addAll(results);
        }
        _page = page;
        _hasNext = res['next'] != null;
        _loading = false;
        _loadingMore = false;
        _offline = false;
      });
      _cachedPlaylistsBySlug[widget.channelSlug] =
          List<Map<String, dynamic>>.from(_playlists);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
        _offline = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasNext) return;
    setState(() {
      _loadingMore = true;
    });
    await _loadPage(_page + 1);
  }

  String _channelDisplayName() {
    final ch = _channel;
    if (ch == null) return '';
    final String defLoc = (ch['default_locale'] ?? '').toString();
    final String nameAm = (ch['name_am'] ?? '').toString();
    final String nameEn = (ch['name_en'] ?? '').toString();
    final String idSlug = (ch['id_slug'] ?? '').toString();
    if (defLoc == 'am' && nameAm.isNotEmpty) return nameAm;
    if (nameEn.isNotEmpty) return nameEn;
    if (nameAm.isNotEmpty) return nameAm;
    return idSlug;
  }

  String _channelSubtitle() {
    final ch = _channel;
    if (ch == null) return '';
    final String handle = (ch['handle'] ?? '').toString();
    final String country = (ch['country'] ?? '').toString();
    final String language = (ch['language'] ?? '').toString();
    if (handle.isNotEmpty) return handle;
    final parts = <String>[];
    if (language.isNotEmpty) parts.add(language);
    if (country.isNotEmpty) parts.add(country);
    return parts.join(' • ');
  }

  Widget _buildHeaderRow() {
    final displayName = _channelDisplayName();
    final subtitle = _channelSubtitle();
    final logoUrl =
        (_channel != null ? (_channel!['logo_url'] ?? '').toString() : '');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          if (_loadingChannel)
            const SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (logoUrl.isNotEmpty)
            ClipOval(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CachedNetworkImage(
                  imageUrl: logoUrl,
                  fit: BoxFit.cover,
                  httpHeaders: authHeadersFor(logoUrl),
                ),
              ),
            )
          else
            const CircleAvatar(
                radius: 18, child: Icon(Icons.live_tv, size: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName.isNotEmpty
                      ? displayName
                      : (widget.channelSlug.isNotEmpty
                          ? widget.channelSlug
                          : _t('playlists')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: _t('close'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) {
          try {
            _debounce?.cancel();
          } catch (_) {}
          _debounce = Timer(const Duration(milliseconds: 250), () {
            if (!mounted) return;
            setState(() => _query = v.trim());
          });
        },
        decoration: InputDecoration(
          hintText: _t('search_playlists'),
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> visible) {
    if (_loading && _playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _playlists.isEmpty) {
      final String msg = _offline
          ? _t('you_are_offline')
          : (kDebugMode
              ? (_error ?? 'Unknown error')
              : _t('something_went_wrong'));
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(msg, textAlign: TextAlign.center),
        ),
      );
    }

    if (visible.isEmpty) {
      return Center(
        child: Text(_query.isNotEmpty ? _t('no_results') : _t('no_playlists')),
      );
    }

    return GridView.builder(
      controller: _scroll,
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 0,
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final pl = visible[i];
        final title = (pl['title'] ?? '').toString();
        final thumb = thumbFromMap(pl);
        final id = pl['id']?.toString() ?? '';
        final dynamic countRaw =
            pl['item_count'] ?? pl['videos_count'] ?? pl['video_count'];
        final int? count = (countRaw is int)
            ? countRaw
            : int.tryParse(countRaw?.toString() ?? '');
        return GestureDetector(
          onTap: id.isEmpty
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      settings: RouteSettings(name: '/playlist/$id'),
                      builder: (_) =>
                          PlaylistDetailPage(playlistId: id, title: title),
                    ),
                  );
                },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      thumb != null && thumb.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              httpHeaders: authHeadersFor(thumb),
                              placeholder: (_, __) =>
                                  Container(color: Colors.black26),
                              errorWidget: (_, __, ___) =>
                                  Container(color: Colors.black26),
                            )
                          : Container(color: Colors.black26),
                      if (count != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title.isNotEmpty ? title : id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? _playlists
        : _playlists.where((p) {
            final t = (p['title'] ?? '').toString().toLowerCase();
            return t.contains(_query.toLowerCase()) ||
                (p['id']?.toString() ?? '').contains(_query);
          }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Column(
        children: [
          _buildHeaderRow(),
          _buildSearchField(),
          Expanded(child: _buildBody(visible)),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
    );
  }
}
