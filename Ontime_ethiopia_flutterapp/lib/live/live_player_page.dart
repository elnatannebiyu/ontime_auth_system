import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../api_client.dart';

class LivePlayerPage extends StatefulWidget {
  final String slug;
  const LivePlayerPage({super.key, required this.slug});

  @override
  State<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends State<LivePlayerPage> {
  VideoPlayerController? _controller;
  bool _initing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _initing = true;
      _error = null;
    });
    try {
      final manifestUrl = '${kApiBase}/api/live/proxy/${widget.slug}/manifest/';
      final c = VideoPlayerController.networkUrl(Uri.parse(manifestUrl));
      await c.initialize();
      await c.play();
      c.setLooping(true);
      setState(() {
        _controller = c;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to start live playback';
      });
    } finally {
      if (mounted) setState(() => _initing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live')),
      body: _initing
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio == 0
                        ? 16 / 9
                        : _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                ),
      floatingActionButton: _controller == null
          ? null
          : FloatingActionButton(
              onPressed: () {
                setState(() {
                  if (_controller!.value.isPlaying) {
                    _controller!.pause();
                  } else {
                    _controller!.play();
                  }
                });
              },
              child: Icon(
                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
    );
  }
}
