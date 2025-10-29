import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

class ShortsPlayerPage extends StatefulWidget {
  final List<Map<String, dynamic>> videos; // expects at least fields: video_id, title
  final int initialIndex;

  const ShortsPlayerPage({super.key, required this.videos, this.initialIndex = 0});

  @override
  State<ShortsPlayerPage> createState() => _ShortsPlayerPageState();
}

class _ShortsPlayerPageState extends State<ShortsPlayerPage> {
  late final PageController _pageCtrl;
  late int _index;
  final Map<int, YoutubePlayerController> _controllers = {};
  final Map<int, Timer> _skipTimers = {};
  bool _muted = true;
  bool _externalOnly = false; // embed in-app by default
  final Set<int> _openedExternally = <int>{};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.videos.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    _ensureController(_index);
    _ensureController(_index + 1);
  }

  YoutubePlayerController _createController(String videoId) {
    return YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        enableCaption: false,
        strictRelatedVideos: true,
        loop: false,
        playsInline: true,
      ),
    )
      ..loadVideoById(videoId: videoId, startSeconds: 0)
      ..playVideo();
  }

  void _ensureController(int i) {
    if (_externalOnly) return;
    if (i < 0 || i >= widget.videos.length) return;
    if (_controllers[i] != null) return;
    final vid = (widget.videos[i]['video_id'] ?? '').toString();
    final c = _createController(vid);
    if (_muted) c.mute(); else c.unMute();
    _controllers[i] = c;
    // Simple timeout-based skip: if still on this page after a short delay, assume unplayable and skip
    _skipTimers[i]?.cancel();
    _skipTimers[i] = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_index == i) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video unavailable, skipping…')),
        );
        _jumpToNext();
      }
    });
  }

  @override
  void dispose() {
    if (!_externalOnly) {
      for (final c in _controllers.values) {
        c.close();
      }
      for (final t in _skipTimers.values) {
        t.cancel();
      }
    }
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    // Preload neighbors
    if (_externalOnly) {
      _openCurrentExternallyOnce();
    } else {
      _ensureController(i - 1);
      _ensureController(i + 1);
      // Pause non-current, play current
      _controllers.forEach((k, c) {
        if (k == i) {
          c.playVideo();
        } else {
          c.pauseVideo();
        }
      });
    }
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

  Future<void> _openInYouTube() async {
    final vid = (widget.videos[_index]['video_id'] ?? '').toString();
    final uri = Uri.parse('https://youtu.be/$vid');
    final ytScheme = Uri.parse('vnd.youtube://$vid');
    if (await canLaunchUrl(ytScheme)) {
      await launchUrl(ytScheme, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openCurrentExternallyOnce() {
    if (_openedExternally.contains(_index)) return;
    _openedExternally.add(_index);
    // slight delay to avoid launching during transition
    Future.delayed(const Duration(milliseconds: 150), _openInYouTube);
  }

  Future<void> _share() async {
    // Placeholder: integrate share_plus if desired; for now open the URL
    await _openInYouTube();
  }

  Widget _buildPage(int i) {
    _ensureController(i);
    final c = _controllers[i];
    final title = (widget.videos[i]['title'] ?? '').toString();
    if (_externalOnly) {
      _openCurrentExternallyOnce();
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Positioned(
            left: 16,
            right: 16,
            bottom: 80,
            child: Text(
              title.isEmpty ? 'Untitled' : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CircleIconButton(icon: Icons.ios_share, onTap: _share),
                const SizedBox(width: 16),
                _CircleIconButton(icon: Icons.open_in_new, onTap: _openInYouTube),
              ],
            ),
          ),
        ],
      );
    } else {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: c == null
                  ? const CircularProgressIndicator()
                  : YoutubePlayer(controller: c),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x66000000), Color(0x00000000), Color(0x66000000)],
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
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CircleIconButton(
                  icon: _muted ? Icons.volume_off : Icons.volume_up,
                  onTap: () {
                    setState(() {
                      _muted = !_muted;
                      _controllers.forEach((_, c) => _muted ? c.mute() : c.unMute());
                    });
                  },
                ),
                const SizedBox(height: 12),
                _CircleIconButton(icon: Icons.ios_share, onTap: _share),
                const SizedBox(height: 12),
                _CircleIconButton(icon: Icons.open_in_new, onTap: _openInYouTube),
              ],
            ),
          ),
        ],
      );
    }
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

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white24,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
