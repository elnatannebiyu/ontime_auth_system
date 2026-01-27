import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class LiveFloatingMiniPlayer extends StatelessWidget {
  final VideoPlayerController? controller;

  const LiveFloatingMiniPlayer({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) {
      return Container(color: Colors.black26);
    }

    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        if (!c.value.isInitialized) {
          return Container(color: Colors.black26);
        }
        final ar = (c.value.aspectRatio > 0) ? c.value.aspectRatio : (16 / 9);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: ar,
            child: VideoPlayer(c),
          ),
        );
      },
    );
  }
}
