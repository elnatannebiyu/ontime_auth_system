// ignore_for_file: unused_element_parameter, unused_element, prefer_interpolation_to_compose_strings, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../api_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'dart:async';

class ShortsPlayerPage extends StatefulWidget {
  final List<Map<String, dynamic>>
      videos; // expects at least fields: video_id, title
  final int initialIndex;
  final bool isOffline;
  final void Function(int index)? onIndexChanged;

  const ShortsPlayerPage(
      {super.key,
      required this.videos,
      this.initialIndex = 0,
      this.isOffline = false,
      this.onIndexChanged});

  @override
  State<ShortsPlayerPage> createState() => _ShortsPlayerPageState();
}

class _ShortsPlayerPageState extends State<ShortsPlayerPage> {
  late final PageController _pageCtrl;
  late int _index;
  final Map<String, _Reaction> _reactions = {}; // by job_id
  // In-app HLS playback using video_player only
  final Map<int, VideoPlayerController> _hlsControllers = {};
  bool _muted = false; // default sound ON
  // Track items that failed to initialize (e.g., offline/network error)
  final Map<int, bool> _initFailed = {};
  bool _effectiveOffline = false;
  static String get _mediaBase {
    if (Platform.isAndroid) return 'http://10.0.2.2:8080';
    if (Platform.isIOS || Platform.isMacOS) return 'http://127.0.0.1:8080';
    return 'http://127.0.0.1:8080';
  }

  // Try to extract a reasonable thumbnail/preview URL from a shorts item
  String? _thumbFromItem(Map<String, dynamic> m) {
    const keys = [
      'thumbnail',
      'thumbnail_url',
      'thumb',
      'thumb_url',
      'image',
      'image_url',
      'poster',
      'poster_url',
      'cover_image',
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

  /// Normalize HLS URLs to be reachable from real devices:
  /// - If url host is 127.0.0.1 or localhost, replace host with the API base host.
  /// - Preserve the original port if present; default to 8080 for media.
  /// - If url is relative, prefix with platform media base.
  String _normalizeHls(String url) {
    if (url.isEmpty) return url;
    try {
      // Relative path -> prefix
      if (!url.startsWith('http')) {
        url = '$_mediaBase$url';
      }
      final u = Uri.parse(url);
      // Determine desired host from ApiClient base
      final api = Uri.parse(kApiBase);
      final apiHost = api.host.isNotEmpty ? api.host : u.host;
      final isLoopback = u.host == '127.0.0.1' || u.host == 'localhost';
      if (isLoopback) {
        final port = u.hasPort ? u.port : 8080;
        final normalized = u.replace(host: apiHost, port: port);
        return normalized.toString();
      }
      return url;
    } catch (_) {
      return url;
    }
  }

  @override
  void initState() {
    super.initState();
    _effectiveOffline = widget.isOffline;
    // One-time connectivity check to avoid race where parent still thinks we're online
    Connectivity().checkConnectivity().then((results) {
      if (!mounted) return;
      final list = results;
      final actuallyOffline =
          list.isEmpty || list.every((r) => r == ConnectivityResult.none);
      if (actuallyOffline != _effectiveOffline) {
        setState(() {
          _effectiveOffline = actuallyOffline;
        });
      }
    }).catchError((_) {});
    // Show system safe zones (status/navigation bars)
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    // Lock orientation to portrait while on Shorts
    try {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } catch (_) {}
    _index = widget.initialIndex.clamp(0, widget.videos.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    // Always use our stored HLS (absolute_hls or hls_master_url)
    _ensureHlsController(_index);
    _ensureHlsController(_index + 1);
    _prefetchReactions(_index);
  }

  Future<void> _ensureHlsController(int i) async {
    if (_effectiveOffline) {
      // When offline, don’t try to create controllers at all – just show thumbnails
      if (mounted) {
        setState(() {
          _initFailed[i] = true;
        });
      }
      return;
    }
    if (i < 0 || i >= widget.videos.length) return;
    if (_hlsControllers[i] != null) return;
    final absFromItem = (widget.videos[i]['absolute_hls'] ?? '').toString();
    final rel = (widget.videos[i]['hls_master_url'] ?? '').toString();
    String url = '';
    if (absFromItem.isNotEmpty) {
      url = _normalizeHls(absFromItem);
    } else if (rel.isNotEmpty) {
      url = _normalizeHls(rel);
    }
    if (url.isEmpty) {
      // No HLS available for this short – mark as failed and show placeholder
      if (mounted) {
        setState(() {
          _initFailed[i] = true;
        });
      }
      return;
    }
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _hlsControllers[i] = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true); // loop on finish
      await ctrl.setVolume(_muted ? 0.0 : 1.0);
      if (i == _index) ctrl.play();
      setState(() {
        _initFailed.remove(i);
      });
    } catch (_) {
      // Unplayable stream (often offline). Show placeholder instead of skipping.
      if (mounted) {
        setState(() {
          _initFailed[i] = true;
        });
      }
    }
  }

  @override
  void dispose() {
    // Restore normal system UI when leaving Shorts
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    try {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
    for (final v in _hlsControllers.values) {
      v.dispose();
    }
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    widget.onIndexChanged?.call(i);
    // Preload neighbors
    _ensureHlsController(i - 1);
    _ensureHlsController(i + 1);
    _prefetchReactions(i);
    // Pause others, play current
    _hlsControllers.forEach((k, v) {
      if (k == i) {
        if (v.value.isInitialized) v.play();
      } else {
        if (v.value.isInitialized) v.pause();
      }
    });
  }

  void _jumpToNext() {
    if (_index + 1 < widget.videos.length) {
      _pageCtrl.animateToPage(
        _index + 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  String _shareUrlForIndex(int i) {
    final item = widget.videos[i];
    final abs = (item['absolute_hls'] ?? '').toString();
    if (abs.isNotEmpty) return _normalizeHls(abs);
    final rel = (item['hls_master_url'] ?? '').toString();
    if (rel.isNotEmpty) return _normalizeHls(rel);
    return '';
  }

  Future<void> _share() async {
    // Placeholder: integrate share_plus if desired; for now open the URL
    final url = _shareUrlForIndex(_index);
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _jobIdForIndex(int i) => (widget.videos[i]['job_id'] ?? '').toString();

  Future<void> _prefetchReactions(int i) async {
    if (_effectiveOffline) return; // skip reaction calls when offline
    final jobId = _jobIdForIndex(i);
    if (jobId.isEmpty || _reactions.containsKey(jobId)) return;
    try {
      final res = await ApiClient().get('/channels/shorts/$jobId/reaction/');
      final data = res.data as Map;
      final r = _Reaction(
        user: data['user'] as String?,
        likes: (data['likes'] as num?)?.toInt() ?? 0,
        dislikes: (data['dislikes'] as num?)?.toInt() ?? 0,
      );
      setState(() => _reactions[jobId] = r);
    } catch (_) {}
  }

  Future<void> _setReaction(int i, String? val) async {
    final jobId = _jobIdForIndex(i);
    if (jobId.isEmpty) return;
    final cur =
        _reactions[jobId] ?? _Reaction(user: null, likes: 0, dislikes: 0);
    // Optimistic update
    _Reaction next = cur;
    if (val == null) {
      if (cur.user == 'like') {
        next = _Reaction(
            user: null,
            likes: (cur.likes - 1).clamp(0, 1 << 31),
            dislikes: cur.dislikes);
      } else if (cur.user == 'dislike') {
        next = _Reaction(
            user: null,
            likes: cur.likes,
            dislikes: (cur.dislikes - 1).clamp(0, 1 << 31));
      }
    } else if (val == 'like') {
      if (cur.user == 'like') {
        next = _Reaction(
            user: null,
            likes: (cur.likes - 1).clamp(0, 1 << 31),
            dislikes: cur.dislikes);
      } else if (cur.user == 'dislike') {
        next = _Reaction(
            user: 'like',
            likes: cur.likes + 1,
            dislikes: (cur.dislikes - 1).clamp(0, 1 << 31));
      } else {
        next = _Reaction(
            user: 'like', likes: cur.likes + 1, dislikes: cur.dislikes);
      }
    } else if (val == 'dislike') {
      if (cur.user == 'dislike') {
        next = _Reaction(
            user: null,
            likes: cur.likes,
            dislikes: (cur.dislikes - 1).clamp(0, 1 << 31));
      } else if (cur.user == 'like') {
        next = _Reaction(
            user: 'dislike',
            likes: (cur.likes - 1).clamp(0, 1 << 31),
            dislikes: cur.dislikes + 1);
      } else {
        next = _Reaction(
            user: 'dislike', likes: cur.likes, dislikes: cur.dislikes + 1);
      }
    }
    setState(() => _reactions[jobId] = next);
    try {
      await ApiClient()
          .post('/channels/shorts/$jobId/reaction/', data: {'value': val});
    } catch (_) {
      // On error, refetch to reconcile
      _reactions.remove(jobId);
      _prefetchReactions(i);
    }
  }

  Future<void> _openComments(int i) async {
    final jobId = _jobIdForIndex(i);
    if (jobId.isEmpty) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _CommentsSheet(jobId: jobId);
      },
    );
  }

  Widget _buildPage(int i) {
    // Defer controller initialization to after the current frame to avoid
    // calling setState synchronously during the build phase, which can cause
    // errors in Sliver/viewport layouts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureHlsController(i);
    });
    final vc = _hlsControllers[i];
    final failed = _initFailed[i] == true;
    final title = (widget.videos[i]['title'] ?? '').toString();
    final thumb = _thumbFromItem(widget.videos[i]);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed video with safe overlays
        ColoredBox(
          color: Colors.black,
          child: (vc == null || !vc.value.isInitialized)
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb != null && thumb.isNotEmpty)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: Image.network(
                          thumb,
                          errorBuilder: (_, __, ___) =>
                              Container(color: Colors.black),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    if (!failed)
                      const Center(
                        child: CircularProgressIndicator(),
                      ),
                  ],
                )
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!vc.value.isInitialized) return;
                    if (vc.value.isPlaying) {
                      vc.pause();
                    } else {
                      vc.play();
                    }
                    setState(() {});
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Cover-fit rendering for edge-to-edge video
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: vc.value.size.width == 0
                              ? 1
                              : vc.value.size.width,
                          height: vc.value.size.height == 0
                              ? 1
                              : vc.value.size.height,
                          child: VideoPlayer(vc),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        // Offline helper message when the whole player is marked offline
        if (_effectiveOffline)
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: SafeArea(
              top: true,
              bottom: false,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Offline · Connect to load shorts',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0x00000000),
                    Color(0x66000000)
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),
        // Center play icon when paused
        if (vc != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: vc,
                builder: (_, value, __) {
                  final show = value.isInitialized && !value.isPlaying;
                  return AnimatedOpacity(
                    opacity: show ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: const Center(
                      child: Icon(Icons.play_circle_filled,
                          color: Colors.white70, size: 72),
                    ),
                  );
                },
              ),
            ),
          ),
        // Bottom column: title then time/slider (auto adjusts height)
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title.isEmpty ? 'Untitled' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (vc != null)
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: vc,
                    builder: (_, value, __) {
                      final pos = value.position;
                      final dur = value.duration;
                      final max = dur.inMilliseconds.clamp(1, 1 << 31);
                      final cur = pos.inMilliseconds.clamp(0, max);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Slider(
                            value: cur.toDouble(),
                            min: 0,
                            max: max.toDouble(),
                            onChanged: (v) {
                              final ms = v.round();
                              vc.seekTo(Duration(milliseconds: ms));
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(pos),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Text(_formatDuration(dur),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        // Side action column centered vertically on the right, above navigator
        if (!widget.isOffline)
          Positioned.fill(
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CircleIconButton(
                        icon: Icons.favorite_border,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Save coming soon')),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _CircleIconButton(
                        icon: (_reactions[_jobIdForIndex(i)]?.user == 'like')
                            ? Icons.thumb_up
                            : Icons.thumb_up_alt_outlined,
                        color: (_reactions[_jobIdForIndex(i)]?.user == 'like')
                            ? Colors.lightBlueAccent
                            : Colors.white,
                        label: (_reactions[_jobIdForIndex(i)]?.likes ?? 0)
                            .toString(),
                        onTap: () {
                          final current = _reactions[_jobIdForIndex(i)]?.user;
                          _setReaction(i, current == 'like' ? null : 'like');
                        },
                      ),
                      const SizedBox(height: 12),
                      _CircleIconButton(
                        icon: (_reactions[_jobIdForIndex(i)]?.user == 'dislike')
                            ? Icons.thumb_down
                            : Icons.thumb_down_alt_outlined,
                        color:
                            (_reactions[_jobIdForIndex(i)]?.user == 'dislike')
                                ? Colors.redAccent
                                : Colors.white,
                        label: (_reactions[_jobIdForIndex(i)]?.dislikes ?? 0)
                            .toString(),
                        onTap: () {
                          final current = _reactions[_jobIdForIndex(i)]?.user;
                          _setReaction(
                              i, current == 'dislike' ? null : 'dislike');
                        },
                      ),
                      const SizedBox(height: 12),
                      _CircleIconButton(
                        icon: _muted ? Icons.volume_off : Icons.volume_up,
                        onTap: () {
                          setState(() {
                            _muted = !_muted;
                            for (final v in _hlsControllers.values) {
                              if (v.value.isInitialized) {
                                v.setVolume(_muted ? 0.0 : 1.0);
                              }
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Top-left back button rendered last, with glass style like other buttons
        Positioned(
          left: 8,
          top: 8,
          child: SafeArea(
            child: _CircleIconButton(
              icon: Icons.arrow_back,
              onTap: () {
                final nav = Navigator.maybeOf(context);
                bool popped = false;
                if (nav != null && nav.canPop()) {
                  debugPrint('[Shorts] Back: popping current route');
                  nav.pop();
                  popped = true;
                }
                if (!popped) {
                  final tc = DefaultTabController.maybeOf(context);
                  if (tc != null) {
                    final prev = tc.previousIndex;
                    final cur = tc.index;
                    int target = prev;
                    if (prev < 0 || prev >= tc.length || prev == cur) {
                      target = 0; // fallback to For You
                    }
                    debugPrint(
                        '[Shorts] Back: no route to pop, switching tab to index ' +
                            target.toString());
                    try {
                      tc.animateTo(target);
                    } catch (_) {}
                  } else {
                    debugPrint(
                        '[Shorts] Back: no route to pop and no TabController');
                  }
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: PageView.builder(
          controller: _pageCtrl,
          scrollDirection: Axis.vertical,
          onPageChanged: _onPageChanged,
          itemCount: widget.videos.length,
          itemBuilder: (_, i) => _buildPage(i),
        ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final String? label;
  const _CircleIconButton(
      {required this.icon, required this.onTap, this.color, this.label});
  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Colors.white;
    final hasLabel = (label != null && label!.isNotEmpty);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white24,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: iconColor),
            ),
          ),
        ),
        if (hasLabel) ...[
          const SizedBox(height: 4),
          Text(label!,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ],
    );
  }
}

class _Reaction {
  final String? user; // 'like' | 'dislike' | null
  final int likes;
  final int dislikes;
  const _Reaction(
      {required this.user, required this.likes, required this.dislikes});
}

class _CommentsSheet extends StatefulWidget {
  final String jobId;
  const _CommentsSheet({required this.jobId});
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient()
          .get('/channels/shorts/${widget.jobId}/comments/', queryParameters: {
        'limit': '50',
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
      setState(() => _error = 'Failed to load comments');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    try {
      final res = await ApiClient()
          .post('/channels/shorts/${widget.jobId}/comments/', data: {
        'text': text,
      });
      final Map<String, dynamic> obj =
          Map<String, dynamic>.from(res.data as Map);
      setState(() {
        _items = [obj, ..._items];
        _ctrl.clear();
      });
    } catch (_) {}
  }

  Future<void> _delete(int id) async {
    try {
      await ApiClient().delete('/channels/shorts/comments/$id/');
      setState(() {
        _items = _items.where((e) => (e['id'] as int?) != id).toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator()))
        : _error != null
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red))))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemBuilder: (_, i) {
                  final it = _items[i];
                  final id = it['id'] as int?;
                  final user = (it['user_display'] ?? 'User').toString();
                  final text = (it['text'] ?? '').toString();
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.person,
                              size: 16, color: Colors.white70)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(text,
                                style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                      if (id != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.white38, size: 18),
                          onPressed: () => _delete(id),
                        ),
                    ],
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: _items.length,
              );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 12),
            Expanded(child: body),
            Padding(
              padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Color(0x22000000),
                        border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius:
                                BorderRadius.all(Radius.circular(24))),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _send,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder()),
                    child: const Text('Send'),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
