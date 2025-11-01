// ignore_for_file: unused_element_parameter

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../api_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'dart:async';

class ShortsPlayerPage extends StatefulWidget {
  final List<Map<String, dynamic>>
      videos; // expects at least fields: video_id, title
  final int initialIndex;

  const ShortsPlayerPage(
      {super.key, required this.videos, this.initialIndex = 0});

  @override
  State<ShortsPlayerPage> createState() => _ShortsPlayerPageState();
}

class _ShortsPlayerPageState extends State<ShortsPlayerPage> {
  late final PageController _pageCtrl;
  late int _index;
  final Map<String, _Reaction> _reactions = {}; // by job_id
  // In-app HLS playback using video_player only
  final Map<int, VideoPlayerController> _hlsControllers = {};
  bool _muted = true;
  static String get _mediaBase {
    if (Platform.isAndroid) return 'http://10.0.2.2:8080';
    if (Platform.isIOS || Platform.isMacOS) return 'http://127.0.0.1:8080';
    return 'http://127.0.0.1:8080';
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.videos.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    // Always use our stored HLS (absolute_hls or hls_master_url)
    _ensureHlsController(_index);
    _ensureHlsController(_index + 1);
    _prefetchReactions(_index);
  }

  Future<void> _ensureHlsController(int i) async {
    if (i < 0 || i >= widget.videos.length) return;
    if (_hlsControllers[i] != null) return;
    final absFromItem = (widget.videos[i]['absolute_hls'] ?? '').toString();
    final rel = (widget.videos[i]['hls_master_url'] ?? '').toString();
    final url = absFromItem.isNotEmpty
        ? absFromItem
        : (rel.isNotEmpty
            ? (rel.startsWith('http') ? rel : '$_mediaBase$rel')
            : '');
    if (url.isEmpty) return;
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _hlsControllers[i] = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setVolume(_muted ? 0.0 : 1.0);
      if (i == _index) ctrl.play();
      setState(() {});
    } catch (_) {
      // keep UI; user can navigate manually
    }
  }

  @override
  void dispose() {
    for (final v in _hlsControllers.values) {
      v.dispose();
    }
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
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
    if (abs.isNotEmpty) return abs;
    final rel = (item['hls_master_url'] ?? '').toString();
    if (rel.isNotEmpty) {
      return rel.startsWith('http') ? rel : '$_mediaBase$rel';
    }
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
    final cur = _reactions[jobId] ?? _Reaction(user: null, likes: 0, dislikes: 0);
    // Optimistic update
    _Reaction next = cur;
    if (val == null) {
      if (cur.user == 'like') {
        next = _Reaction(user: null, likes: (cur.likes - 1).clamp(0, 1 << 31), dislikes: cur.dislikes);
      } else if (cur.user == 'dislike') {
        next = _Reaction(user: null, likes: cur.likes, dislikes: (cur.dislikes - 1).clamp(0, 1 << 31));
      }
    } else if (val == 'like') {
      if (cur.user == 'like') {
        next = _Reaction(user: null, likes: (cur.likes - 1).clamp(0, 1 << 31), dislikes: cur.dislikes);
      } else if (cur.user == 'dislike') {
        next = _Reaction(user: 'like', likes: cur.likes + 1, dislikes: (cur.dislikes - 1).clamp(0, 1 << 31));
      } else {
        next = _Reaction(user: 'like', likes: cur.likes + 1, dislikes: cur.dislikes);
      }
    } else if (val == 'dislike') {
      if (cur.user == 'dislike') {
        next = _Reaction(user: null, likes: cur.likes, dislikes: (cur.dislikes - 1).clamp(0, 1 << 31));
      } else if (cur.user == 'like') {
        next = _Reaction(user: 'dislike', likes: (cur.likes - 1).clamp(0, 1 << 31), dislikes: cur.dislikes + 1);
      } else {
        next = _Reaction(user: 'dislike', likes: cur.likes, dislikes: cur.dislikes + 1);
      }
    }
    setState(() => _reactions[jobId] = next);
    try {
      await ApiClient().post('/channels/shorts/$jobId/reaction/', data: {'value': val});
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
    _ensureHlsController(i);
    final vc = _hlsControllers[i];
    final title = (widget.videos[i]['title'] ?? '').toString();
    return Stack(
      fit: StackFit.expand,
      children: [
        // Top header
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Align(
              alignment: Alignment.topLeft,
              child: _GlassChip(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.play_circle_fill, size: 18, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Shorts',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
        ColoredBox(
          color: Colors.black,
          child: Center(
            child: (vc == null || !vc.value.isInitialized)
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () {
                      if (!vc.value.isInitialized) return;
                      if (vc.value.isPlaying) {
                        vc.pause();
                      } else {
                        vc.play();
                      }
                      setState(() {});
                    },
                    child: AspectRatio(
                      aspectRatio: vc.value.aspectRatio == 0
                          ? 9 / 16
                          : vc.value.aspectRatio,
                      child: VideoPlayer(vc),
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
        Positioned(
          left: 12,
          right: 12,
          bottom: 96,
          child: Text(
            title.isEmpty ? 'Untitled' : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        if (vc != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 60,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: vc,
              builder: (_, value, __) {
                final pos = value.position;
                final dur = value.duration;
                final max = dur.inMilliseconds.clamp(1, 1 << 31);
                final cur = pos.inMilliseconds.clamp(0, max);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
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
          ),
        Positioned(
          right: 12,
          bottom: 24,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
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
                  label: (_reactions[_jobIdForIndex(i)]?.likes ?? 0).toString(),
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
                  color: (_reactions[_jobIdForIndex(i)]?.user == 'dislike')
                      ? Colors.redAccent
                      : Colors.white,
                  label:
                      (_reactions[_jobIdForIndex(i)]?.dislikes ?? 0).toString(),
                  onTap: () {
                    final current = _reactions[_jobIdForIndex(i)]?.user;
                    _setReaction(i, current == 'dislike' ? null : 'dislike');
                  },
                ),
                const SizedBox(height: 12),
                _CircleIconButton(
                  icon: Icons.chat_bubble_outline,
                  onTap: () => _openComments(i),
                ),
                const SizedBox(height: 12),
                _CircleIconButton(
                  icon: _muted ? Icons.volume_off : Icons.volume_up,
                  onTap: () {
                    setState(() {
                      _muted = !_muted;
                      for (final v in _hlsControllers.values) {
                        if (v.value.isInitialized)
                          v.setVolume(_muted ? 0.0 : 1.0);
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                _CircleIconButton(icon: Icons.ios_share, onTap: _share),
              ],
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
  const _CircleIconButton({required this.icon, required this.onTap, this.color, this.label});
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
          Text(label!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ],
    );
  }
}

class _Reaction {
  final String? user; // 'like' | 'dislike' | null
  final int likes;
  final int dislikes;
  const _Reaction({required this.user, required this.likes, required this.dislikes});
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
      final res = await ApiClient().get('/channels/shorts/${widget.jobId}/comments/', queryParameters: {
        'limit': '50',
      });
      final data = res.data;
      final List<Map<String, dynamic>> list = data is List
          ? List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e as Map)))
          : (data is Map && data['results'] is List)
              ? List<Map<String, dynamic>>.from((data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
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
      final res = await ApiClient().post('/channels/shorts/${widget.jobId}/comments/', data: {
        'text': text,
      });
      final Map<String, dynamic> obj = Map<String, dynamic>.from(res.data as Map);
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
        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        : _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))))
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
                      const CircleAvatar(radius: 14, backgroundColor: Colors.white24, child: Icon(Icons.person, size: 16, color: Colors.white70)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(text, style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                      if (id != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
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
            Container(height: 4, width: 48, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 12),
            Expanded(child: body),
            Padding(
              padding: EdgeInsets.only(left: 12, right: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 8),
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
                        border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(24))),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _send,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white, shape: const StadiumBorder()),
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
