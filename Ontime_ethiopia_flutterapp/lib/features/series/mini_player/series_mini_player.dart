import 'package:flutter/material.dart';
import 'mini_player_manager.dart';
import 'series_now_playing.dart';

class SeriesMiniPlayer extends StatelessWidget {
  const SeriesMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SeriesNowPlaying?>(
      valueListenable: MiniPlayerManager.I.nowPlaying,
      builder: (context, snp, _) {
        if (snp == null) return const SizedBox.shrink();
        final progress = snp.duration.inMilliseconds == 0
            ? 0.0
            : (snp.position.inMilliseconds / snp.duration.inMilliseconds)
                .clamp(0.0, 1.0);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Material(
              color: const Color(0xFF1E1E1E),
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: snp.onExpand,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 56,
                          height: 40,
                          color: Colors.black26,
                          child: snp.thumbnailUrl != null && snp.thumbnailUrl!.isNotEmpty
                              ? Image.network(snp.thumbnailUrl!, fit: BoxFit.cover)
                              : const Icon(Icons.play_circle_fill, color: Colors.white54),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              snp.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: progress.isFinite ? progress : 0.0,
                              backgroundColor: Colors.white12,
                              color: Colors.white,
                              minHeight: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          snp.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          color: Colors.white,
                        ),
                        onPressed: snp.onTogglePlayPause,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
