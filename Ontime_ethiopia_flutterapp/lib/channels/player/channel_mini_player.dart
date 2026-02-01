import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'channel_mini_player_manager.dart';
import 'channel_now_playing.dart';
import '../playlist_detail_page.dart';
import '../../core/navigation/route_stack_observer.dart';
import '../../live/tv_controller.dart';

class ChannelMiniPlayer extends StatefulWidget {
  const ChannelMiniPlayer({super.key});

  @override
  State<ChannelMiniPlayer> createState() => _ChannelMiniPlayerState();
}

class _ChannelMiniPlayerState extends State<ChannelMiniPlayer> {
  Offset _offset = const Offset(16, 100);
  bool _positionInitialized = false;
  final double _scale = 1.6;
  Size? _lastSize;
  double? _baseWidth;
  bool? _lastMinimized;
  static const double _edgePadding = 8.0;
  static const double _topPadding = 80.0;
  static const double _rightPadding = 12.0;
  static const double _minWidth = 160.0;
  static const double _aspectRatio = 16 / 9;
  static const double _bottomPadding = 8.0;
  static const double _dragBottomPadding = 8.0;

  double _bottomInset(BuildContext context) {
    return MediaQuery.of(context).padding.bottom;
  }

  Offset _anchorBottomRight(
    BuildContext context,
    Size size,
    double miniWidth,
    double miniHeight,
  ) {
    final bottom = _bottomInset(context);
    final dx = _safeClamp(size.width - miniWidth - _rightPadding, _edgePadding,
        size.width - miniWidth - _edgePadding);
    final dy = _safeClamp(
      size.height - miniHeight - (bottom + _bottomPadding),
      _topPadding,
      size.height - miniHeight - (bottom + _bottomPadding),
    );
    return Offset(dx, dy);
  }

  double _safeClamp(double value, double min, double max) {
    if (max < min) return min;
    return value.clamp(min, max);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottom = _bottomInset(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        ChannelMiniPlayerManager.I.isSuppressed,
        ChannelMiniPlayerManager.I.isMinimized,
        ChannelMiniPlayerManager.I.nowPlaying,
        ChannelMiniPlayerManager.I.floatingPlayer,
      ]),
      builder: (context, _) {
        final suppressed = ChannelMiniPlayerManager.I.isSuppressed.value;
        final minimized = ChannelMiniPlayerManager.I.isMinimized.value;
        final now = ChannelMiniPlayerManager.I.nowPlaying.value;
        final floatingPlayer = ChannelMiniPlayerManager.I.floatingPlayer.value;
        if (kDebugMode) {
          debugPrint(
              '[ChannelMiniPlayer] suppressed=$suppressed minimized=$minimized nowPlaying=${now != null}');
        }
        if (suppressed || !minimized || now == null) {
          return const SizedBox.shrink();
        }

        _baseWidth ??= size.width * 0.40;
        final baseWidth = _baseWidth!;
        final miniWidth =
            (baseWidth * _scale).clamp(_minWidth, size.width * 0.7);
        final miniHeight = miniWidth / _aspectRatio;
        final prevMin = _lastMinimized;
        _lastMinimized = minimized;
        if (prevMin != true && minimized) {
          _offset = _anchorBottomRight(context, size, miniWidth, miniHeight);
          _positionInitialized = true;
          _lastSize = size;
        }
        if (_lastSize != size && _positionInitialized) {
          final dx = _safeClamp(
              _offset.dx, _edgePadding, size.width - miniWidth - _edgePadding);
          final dy = _safeClamp(
            _offset.dy,
            _topPadding,
            size.height - miniHeight - (bottom + _dragBottomPadding),
          );
          _offset = Offset(dx, dy);
          if (!_positionInitialized) {
            _offset = _anchorBottomRight(context, size, miniWidth, miniHeight);
            _positionInitialized = true;
          } else if (_lastSize != null && _lastSize != size) {
            _offset = _anchorBottomRight(context, size, miniWidth, miniHeight);
          }
          _lastSize = size;
        }
        return Positioned(
          left: _offset.dx,
          top: _offset.dy,
          child: AnimatedScale(
            scale: minimized ? 1.0 : 0.9,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: minimized ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanUpdate: (details) {
                  final dx = _safeClamp(_offset.dx + details.delta.dx,
                      _edgePadding, size.width - miniWidth - _edgePadding);
                  final dy = _safeClamp(
                      _offset.dy + details.delta.dy,
                      _topPadding,
                      size.height - miniHeight - (bottom + _dragBottomPadding));
                  setState(() {
                    _offset = Offset(dx, dy);
                  });
                },
                child: _miniPlayer(now, floatingPlayer, miniWidth, miniHeight),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _miniPlayer(
    ChannelNowPlaying now,
    Widget? floatingPlayer,
    double miniWidth,
    double miniHeight,
  ) {
    final isLiveSession = now.videoId.startsWith('live:');
    final livePlaying = isLiveSession ? TvController.instance.isPlaying : false;
    final showLiveBadge = isLiveSession && livePlaying;
    return Material(
      color: const Color(0xFF1E1E1E),
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: miniWidth,
        height: miniHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              floatingPlayer ??
                  (now.thumbnailUrl != null && now.thumbnailUrl!.isNotEmpty
                      ? Image.network(
                          now.thumbnailUrl!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.black26,
                          child: const Icon(Icons.play_circle_fill,
                              color: Colors.white54, size: 40),
                        )),
              if (showLiveBadge)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              if (isLiveSession)
                Positioned.fill(
                  child: Center(
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          if (livePlaying) {
                            TvController.instance.pausePlayback();
                            ChannelMiniPlayerManager.I.update(isPlaying: false);
                          } else {
                            TvController.instance.resumePlayback();
                            ChannelMiniPlayerManager.I.update(isPlaying: true);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            livePlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 6,
                top: 6,
                child: _miniControlButton(
                  icon: Icons.open_in_full,
                  onTap: () {
                    ChannelMiniPlayerManager.I.setMinimized(false);
                    // Prefer context-specific navigation when available
                    // (e.g., series/show pages).
                    final cb = now.onExpand;
                    if (cb != null) {
                      cb();
                      return;
                    }
                    // Fallback: open the playlist page if this is playlist-backed.
                    if (now.playlistId != null && now.playlistId!.isNotEmpty) {
                      final nav = Navigator.of(context, rootNavigator: true);
                      final target = '/playlist/${now.playlistId!}';
                      if (appRouteStackObserver.containsName(target)) {
                        nav.popUntil((route) => route.settings.name == target);
                      } else {
                        nav.push(
                          MaterialPageRoute(
                            settings: RouteSettings(name: target),
                            builder: (_) => PlaylistDetailPage(
                              playlistId: now.playlistId!,
                              title: now.playlistTitle ?? now.title,
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: _miniControlButton(
                  icon: Icons.close,
                  onTap: () {
                    final isLive = now.videoId.startsWith('live:');
                    ChannelMiniPlayerManager.I.clear();
                    if (isLive) {
                      TvController.instance.setUseUnifiedMiniPlayer(false);
                      TvController.instance.stop();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniControlButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 22,
  }) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}
