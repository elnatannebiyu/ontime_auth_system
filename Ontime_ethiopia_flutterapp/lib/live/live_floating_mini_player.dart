import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'tv_controller.dart';

class LiveFloatingMiniPlayer extends StatelessWidget {
  const LiveFloatingMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final tv = TvController.instance;
    return AnimatedBuilder(
      animation: tv,
      builder: (context, _) {
        final err = tv.playbackError;
        final c = tv.controller;
        final slug = tv.slug;
        if (err != null && slug != null && slug.isNotEmpty) {
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black26),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // Retry in background; mini player stays visible.
                    tv.startPlaybackBySlug(slug);
                  },
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Connection problem',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap to retry',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        if (c == null) {
          return Stack(
            fit: StackFit.expand,
            children: const [
              ColoredBox(color: Colors.black26),
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ],
          );
        }
        return AnimatedBuilder(
          animation: c,
          builder: (context, _) {
            final initialized = c.value.isInitialized;
            final buffering = c.value.isBuffering;
            final ar =
                (c.value.aspectRatio > 0) ? c.value.aspectRatio : (16 / 9);
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: ar,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (initialized)
                      VideoPlayer(c)
                    else
                      Container(color: Colors.black26),
                    if (!initialized || buffering)
                      const Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
