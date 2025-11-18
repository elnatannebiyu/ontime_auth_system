// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';

import '../api_client.dart';
import 'tv_controller.dart';

class LivePlayerPage extends StatefulWidget {
  final String slug;
  const LivePlayerPage({super.key, required this.slug});

  @override
  State<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends State<LivePlayerPage> {
  // TV controller reuse
  VideoPlayerController? get _c => TvController.instance.controller;

  // Drag state
  double _dragDy = 0.0;

  // Overlay controls
  bool _showControls = false;
  Timer? _controlsTimer;
  bool _muted = false;

  // Metadata + variants
  bool _metaLoading = false;
  String? _titleText;
  String? _channelName;
  String? _channelLogoUrl;
  String? _description;
  String? _playbackType;
  int? _listenerCount;
  int? _totalListens;
  List<String> _allowedUpstream = const [];
  List<String> _tags = const [];

  String? _masterUrl;
  List<_Variant> _variantOptions = const [];
  List<String> _variantChips = const [];
  String _currentQuality = 'Auto';
  String? _qualityToast;
  Timer? _qualityToastTimer;
  bool _switchingQuality = false;

  // View tracking
  String? _viewSessionId;
  Timer? _hbTimer;

  bool get _isActive => true;

  @override
  void initState() {
    super.initState();
    // Enter full player state for mini bar visibility
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TvController.instance.setInFullPlayer(true);
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // If reusing existing playback, do not restart video; just fetch metadata/variants
    final tv = TvController.instance;
    if (tv.controller != null && tv.slug == widget.slug) {
      _metaLoading = true;
      setState(() {});
      try {
        final res = await ApiClient().get('/live/by-channel/${widget.slug}/');
        final m = Map<String, dynamic>.from(res.data as Map);
        // Debug: dump full live object for this slug
        debugPrint('*** Live meta (reuse) for slug=${widget.slug}:\n'
            '${const JsonEncoder.withIndent('  ').convert(m)}');
        _viewSessionId = (m['session_id'] ?? '').toString().isNotEmpty
            ? m['session_id'].toString()
            : _viewSessionId ?? _genSessionId();
        _masterUrl = (m['playback_url'] ?? m['playbackUrl'] ?? '').toString();
        _titleText = (m['title'] ?? '').toString();
        _channelName =
            (m['channel_name'] ?? m['channel_slug'] ?? '').toString();
        _channelLogoUrl = (m['channel_logo_url'] ?? '').toString();
        _description = (m['description'] ?? '').toString();
        _playbackType = (m['playback_type'] ?? '').toString();
        _listenerCount = (m['listener_count'] as num?)?.toInt();
        _totalListens = (m['total_listens'] as num?)?.toInt();
        final meta = m['meta'];
        if (meta is Map) {
          _allowedUpstream = List<String>.from(
              (meta['allowed_upstream'] as List? ?? const [])
                  .map((e) => e.toString()));
          _tags = List<String>.from(
              (meta['tags'] as List? ?? const []).map((e) => e.toString()));
        }
        await _loadVariantsAndSetCurrent();
      } catch (_) {}
      _metaLoading = false;
      if (mounted) setState(() {});
      return;
    }
    // Cold start: fetch meta then start playback at lowest variant (auto if master only)
    setState(() => _metaLoading = true);
    try {
      final res = await ApiClient().get('/live/by-channel/${widget.slug}/');
      final m = Map<String, dynamic>.from(res.data as Map);
      // Debug: dump full live object for this slug
      debugPrint('*** Live meta (cold) for slug=${widget.slug}:\n'
          '${const JsonEncoder.withIndent('  ').convert(m)}');
      _viewSessionId = (m['session_id'] ?? '').toString().isNotEmpty
          ? m['session_id'].toString()
          : _genSessionId();
      _masterUrl = (m['playback_url'] ?? m['playbackUrl'] ?? '').toString();
      _titleText = (m['title'] ?? '').toString();
      _channelName = (m['channel_name'] ?? m['channel_slug'] ?? '').toString();
      _channelLogoUrl = (m['channel_logo_url'] ?? '').toString();
      _description = (m['description'] ?? '').toString();
      _playbackType = (m['playback_type'] ?? '').toString();
      _listenerCount = (m['listener_count'] as num?)?.toInt();
      _totalListens = (m['total_listens'] as num?)?.toInt();
      final meta = m['meta'];
      if (meta is Map) {
        _allowedUpstream = List<String>.from(
            (meta['allowed_upstream'] as List? ?? const [])
                .map((e) => e.toString()));
        _tags = List<String>.from(
            (meta['tags'] as List? ?? const []).map((e) => e.toString()));
      }
      await _loadVariantsAndSetCurrent();
      final startUrl = _variantOptions.isEmpty ? _masterUrl : _pickLowestUrl();
      if (startUrl != null && startUrl.isNotEmpty) {
        await TvController.instance.startPlayback(
            slug: widget.slug,
            title: _titleText ?? 'Live TV',
            url: startUrl,
            sessionId: _viewSessionId);
        _startHeartbeat(widget.slug);
      }
    } catch (_) {
      // swallow, UI will show defaults
    } finally {
      if (mounted) setState(() => _metaLoading = false);
    }
  }

  Future<void> _loadVariantsAndSetCurrent() async {
    _variantOptions = const [];
    _variantChips = const [];
    _currentQuality = 'Auto';
    final master = _masterUrl ?? '';
    if (master.toLowerCase().endsWith('.m3u8')) {
      try {
        final txt = await Dio().get<String>(master,
            options: Options(responseType: ResponseType.plain));
        final data = txt.data ?? '';
        _variantOptions = _parseHlsVariantUrls(master, data);
        _variantChips = _parseHlsChips(data);
        final cur = TvController.instance.playbackUrl;
        if (cur != null && cur.isNotEmpty) {
          final match = _variantOptions.where((v) => v.url == cur).toList();
          if (match.isNotEmpty) {
            _currentQuality = match.first.label;
          } else {
            _currentQuality = 'Auto';
          }
        }
      } catch (_) {}
    }
  }

  String? _pickLowestUrl() {
    if (_variantOptions.isEmpty) return null;
    _Variant best = _variantOptions.first;
    for (final v in _variantOptions) {
      final bh = best.height ?? 99999;
      final vh = v.height ?? 99999;
      if (vh < bh) best = v;
    }
    return best.url;
  }

  @override
  void dispose() {
    try {
      _controlsTimer?.cancel();
    } catch (_) {}
    try {
      _qualityToastTimer?.cancel();
    } catch (_) {}
    _cancelHeartbeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return WillPopScope(
      onWillPop: () async {
        TvController.instance.markWasPlaying(c?.value.isPlaying ?? false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          TvController.instance.setInFullPlayer(false);
        });
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onVerticalDragUpdate: (d) {
            setState(() {
              _dragDy = (_dragDy + d.delta.dy)
                  .clamp(0.0, MediaQuery.of(context).size.height);
            });
          },
          onVerticalDragEnd: (details) {
            final h = MediaQuery.of(context).size.height;
            final threshold = h * 0.22;
            final shouldClose = _dragDy > threshold ||
                (details.primaryVelocity != null &&
                    details.primaryVelocity! > 900);
            if (shouldClose) {
              HapticFeedback.lightImpact();
              _dragDy = 0.0;
              Navigator.of(context).maybePop();
            } else {
              setState(() {
                _dragDy = 0.0;
              });
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Builder(
            builder: (ctx) {
              final h = MediaQuery.of(ctx).size.height;
              final p = (h <= 0) ? 0.0 : (_dragDy / h).clamp(0.0, 1.0);
              final scale = 1.0 - (0.10 * p);
              final metaOpacity = 1.0 - (0.45 * p);
              return Transform.translate(
                offset: Offset(0, _dragDy),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      SafeArea(
                        bottom: false,
                        child: Opacity(
                          opacity: metaOpacity,
                          child: SizedBox(
                            height: kToolbarHeight,
                            child: Row(
                              children: [
                                IconButton(
                                    icon: const Icon(Icons.arrow_back),
                                    onPressed: () =>
                                        Navigator.of(context).maybePop()),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: (_metaLoading ||
                                          (_titleText ?? '').isEmpty)
                                      ? Container(
                                          height: 16,
                                          margin:
                                              const EdgeInsets.only(right: 8),
                                          decoration: BoxDecoration(
                                              color: Colors.white24,
                                              borderRadius:
                                                  BorderRadius.circular(4)))
                                      : Text(
                                          (_titleText?.isNotEmpty == true
                                              ? _titleText!
                                              : 'Live TV'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600)),
                                ),
                                if (_variantOptions.isNotEmpty)
                                  IconButton(
                                      tooltip: 'Quality ($_currentQuality)',
                                      icon: const Icon(Icons.high_quality),
                                      onPressed: _showQualityPicker),
                              ],
                            ),
                          ),
                        ),
                      ),
                      AspectRatio(
                        aspectRatio: (c?.value.aspectRatio ?? 0) == 0
                            ? 16 / 9
                            : c!.value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (c != null)
                              VideoPlayer(c)
                            else
                              const ColoredBox(color: Colors.black12),
                            if (_switchingQuality)
                              const Align(
                                  alignment: Alignment.topCenter,
                                  child: LinearProgressIndicator(minHeight: 2)),
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _toggleControls,
                                child: AnimatedOpacity(
                                  opacity: _showControls ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 150),
                                  child: IgnorePointer(
                                    ignoring: !_showControls,
                                    child: Container(
                                      color: Colors.black45,
                                      child: Column(
                                        children: [
                                          const Spacer(),
                                          Center(
                                            child: IconButton(
                                              iconSize: 64,
                                              color: Colors.white,
                                              icon: Icon(
                                                  (c?.value.isPlaying ?? false)
                                                      ? Icons.pause_circle
                                                      : Icons.play_circle),
                                              onPressed: () async {
                                                if (c == null) return;
                                                setState(() {
                                                  if (c.value.isPlaying) {
                                                    c.pause();
                                                  } else {
                                                    c.play();
                                                  }
                                                });
                                                _kickControlsTimer();
                                              },
                                            ),
                                          ),
                                          const Spacer(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Put LIVE/mute row above the overlay so it's always tappable
                            Positioned(
                              top: 8,
                              left: 8,
                              right: 8,
                              child: Row(
                                children: [
                                  if (_isActive)
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                            color: Colors.redAccent
                                                .withOpacity(0.9),
                                            borderRadius:
                                                BorderRadius.circular(6)),
                                        child: const Text('LIVE',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11))),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: _muted ? 'Unmute' : 'Mute',
                                    onPressed: () async {
                                      setState(() {
                                        _muted = !_muted;
                                      });
                                      try {
                                        await c?.setVolume(_muted ? 0.0 : 1.0);
                                      } catch (_) {}
                                      _kickControlsTimer();
                                    },
                                    icon: Icon(
                                        _muted
                                            ? Icons.volume_off
                                            : Icons.volume_up,
                                        color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            if (_qualityToast != null)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 150),
                                  opacity: 1,
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Text(_qualityToast!,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600))),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Opacity(
                            opacity: metaOpacity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (_metaLoading)
                                      Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                              color: Colors.white24,
                                              borderRadius:
                                                  BorderRadius.circular(8)))
                                    else if ((_channelLogoUrl ?? '').isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          _channelLogoUrl!,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.live_tv,
                                                  size: 28),
                                          frameBuilder: (context, child, frame,
                                              wasSynchronouslyLoaded) {
                                            if (wasSynchronouslyLoaded) {
                                              return child;
                                            }
                                            return AnimatedOpacity(
                                                opacity:
                                                    frame == null ? 0.0 : 1.0,
                                                duration: const Duration(
                                                    milliseconds: 200),
                                                child: child);
                                          },
                                        ),
                                      )
                                    else
                                      const Icon(Icons.live_tv, size: 28),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (_metaLoading)
                                            Container(
                                                height: 16,
                                                margin: const EdgeInsets.only(
                                                    right: 40),
                                                decoration: BoxDecoration(
                                                    color: Colors.white24,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4)))
                                          else
                                            Text(
                                                (_titleText?.isNotEmpty == true
                                                    ? _titleText!
                                                    : _channelName ??
                                                        'Live TV'),
                                                style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight:
                                                        FontWeight.w700),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          if ((_channelName ?? '').isNotEmpty)
                                            Text(_channelName!,
                                                style: TextStyle(
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.color),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  if ((_playbackType ?? '').isNotEmpty)
                                    Chip(
                                        avatar:
                                            const Icon(Icons.waves, size: 16),
                                        label: Text((_playbackType ?? '')
                                            .toUpperCase())),
                                  if (_listenerCount != null)
                                    Chip(
                                        avatar: const Icon(Icons.headphones,
                                            size: 16),
                                        label:
                                            Text('Listeners: $_listenerCount')),
                                  if (_totalListens != null)
                                    Chip(
                                        avatar: const Icon(Icons.equalizer,
                                            size: 16),
                                        label: Text('Total: $_totalListens')),
                                  if (_variantChips.isNotEmpty)
                                    Chip(
                                        avatar: const Icon(Icons.high_quality,
                                            size: 16),
                                        label: Text(_variantChips.join(' · '))),
                                ]),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _tags
                                      .map((t) => _pill(
                                          t.toUpperCase(), Colors.deepPurple))
                                      .toList(),
                                ),
                                const SizedBox(height: 8),
                                if ((_description ?? '').isNotEmpty)
                                  Text(_description!,
                                      style: const TextStyle(fontSize: 13)),
                                const SizedBox(height: 8),
                                if (_allowedUpstream.isNotEmpty) ...[
                                  Text('Upstream hosts',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _allowedUpstream
                                        .map((h) => Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                                color: Colors.blueGrey
                                                    .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: Text(h,
                                                style: const TextStyle(
                                                    fontSize: 12))))
                                        .toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // Quality picker
  Future<void> _showQualityPicker() async {
    if (_variantOptions.isEmpty || _masterUrl == null) return;
    final options = ['Auto', ..._variantOptions.map((v) => v.label)];
    final sel = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, i) {
              final label = options[i];
              final selected = label == _currentQuality;
              return ListTile(
                  title: Text(label),
                  trailing: selected ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(ctx).pop(label));
            },
          ),
        );
      },
    );
    if (sel == null) return;
    if (sel == 'Auto') {
      await _switchToUrl(_masterUrl!);
      _setQualityToast('Auto');
      return;
    }
    final v = _variantOptions.firstWhere((e) => e.label == sel,
        orElse: () => _variantOptions.first);
    await _switchToUrl(v.url);
    _setQualityToast(v.label);
  }

  Future<void> _switchToUrl(String url) async {
    setState(() => _switchingQuality = true);
    try {
      await TvController.instance.startPlayback(
          slug: widget.slug,
          title: _titleText ?? 'Live TV',
          url: url,
          sessionId: _viewSessionId);
    } finally {
      if (mounted) setState(() => _switchingQuality = false);
    }
  }

  void _setQualityToast(String label) {
    if (!mounted) return;
    setState(() {
      _currentQuality = label;
      _qualityToast = label;
    });
    try {
      _qualityToastTimer?.cancel();
    } catch (_) {}
    _qualityToastTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _qualityToast = null;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    _kickControlsTimer();
  }

  void _kickControlsTimer() {
    try {
      _controlsTimer?.cancel();
    } catch (_) {}
    _controlsTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  // Heartbeat
  void _startHeartbeat(String slug) {
    _cancelHeartbeat();
    _hbTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (!mounted) return;
      if ((_viewSessionId ?? '').isEmpty) return;
      try {
        await ApiClient().post('/live/$slug/listen/heartbeat/',
            data: {'session_id': _viewSessionId});
      } catch (_) {}
    });
  }

  void _cancelHeartbeat() {
    try {
      _hbTimer?.cancel();
    } catch (_) {}
    _hbTimer = null;
  }

  // Parsing helpers
  List<_Variant> _parseHlsVariantUrls(String masterUrl, String master) {
    final base = Uri.parse(masterUrl);
    final lines = master.split('\n');
    final out = <_Variant>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      if (l.startsWith('#EXT-X-STREAM-INF')) {
        String? res;
        String? bw;
        final attrs = l.split(',');
        for (final a in attrs) {
          final kv = a.split('=');
          if (kv.length < 2) continue;
          final k = kv[0];
          final v = kv.sublist(1).join('=');
          if (k.contains('RESOLUTION')) res = v.replaceAll('"', '');
          if (k.contains('BANDWIDTH')) bw = v.replaceAll('"', '');
        }
        String? uri;
        for (var j = i + 1; j < lines.length; j++) {
          final nl = lines[j].trim();
          if (nl.isEmpty || nl.startsWith('#')) continue;
          uri = nl;
          break;
        }
        if (uri != null) {
          final u = base.resolve(uri).toString();
          int? width;
          int? height;
          int? bandwidth;
          if (res != null && res.contains('x')) {
            final parts = res.split('x');
            width = int.tryParse(parts[0]);
            height = int.tryParse(parts[1]);
          }
          if (bw != null) bandwidth = int.tryParse(bw);
          final label = [
            if (res != null) res,
            if (bandwidth != null) '${(bandwidth / 1000).round()}kbps'
          ].join(' ');
          out.add(_Variant(
              label: label.isNotEmpty ? label : 'Variant ${out.length + 1}',
              url: u,
              width: width,
              height: height,
              bandwidth: bandwidth));
        }
      }
    }
    return out;
  }

  List<String> _parseHlsChips(String master) {
    final lines = master.split('\n');
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.startsWith('#EXT-X-STREAM-INF')) {
        String? res;
        String? bw;
        final attrs = l.split(',');
        for (final a in attrs) {
          final kv = a.split('=');
          if (kv.length < 2) continue;
          final k = kv[0];
          final v = kv.sublist(1).join('=');
          if (k.contains('RESOLUTION')) res = v.replaceAll('"', '');
          if (k.contains('BANDWIDTH')) bw = v.replaceAll('"', '');
        }
        final n = int.tryParse(bw ?? '0') ?? 0;
        final label = [
          if (res != null) res,
          if (bw != null) '${(n / 1000).round()}kbps'
        ].join(' ');
        if (label.isNotEmpty) out.add(label);
      }
    }
    return out;
  }

  static String _genSessionId() {
    final r = Random();
    final t = DateTime.now().millisecondsSinceEpoch;
    final a = r.nextInt(1 << 32);
    final b = r.nextInt(1 << 32);
    return 'v${t.toRadixString(36)}-${a.toRadixString(36)}${b.toRadixString(36)}';
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

class _Variant {
  final String label;
  final String url;
  final int? width;
  final int? height;
  final int? bandwidth;
  const _Variant(
      {required this.label,
      required this.url,
      this.width,
      this.height,
      this.bandwidth});
}
