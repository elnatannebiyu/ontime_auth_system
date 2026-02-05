import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'channel_mini_player_manager.dart';
import 'channel_now_playing.dart';
import '../playlist_detail_page.dart';
import '../../core/navigation/route_stack_observer.dart';
import '../../live/live_floating_mini_player.dart';
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
  bool _dragging = false;
  bool _showControls = true;
  Timer? _controlsTimer;
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

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    // Avoid setState() during build/layout/paint phases.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(fn);
      });
      return;
    }
    setState(fn);
  }

  void _scheduleHideControls() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _safeSetState(() {
          _showControls = false;
        });
      });
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    super.dispose();
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
        // IMPORTANT: live mini-player loading/buffering state is driven by TvController.
        // Without listening to it, the spinner can remain visible even after playback starts.
        TvController.instance,
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
          // Entry animation: start slightly off-screen bottom-right, then
          // animate into the anchored position.
          final target =
              _anchorBottomRight(context, size, miniWidth, miniHeight);
          final start = Offset(size.width + 12, size.height + 12);
          _offset = start;
          _positionInitialized = true;
          _lastSize = size;
          _showControls = true;
          _scheduleHideControls();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _safeSetState(() {
              _offset = target;
            });
          });
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
        return AnimatedPositioned(
          left: _offset.dx,
          top: _offset.dy,
          duration:
              _dragging ? Duration.zero : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
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
                onPanStart: (_) {
                  _safeSetState(() {
                    _dragging = true;
                  });
                },
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
                onPanEnd: (_) {
                  _safeSetState(() {
                    _dragging = false;
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
    final tv = TvController.instance;
    final livePlaying = isLiveSession ? tv.isPlaying : false;
    final liveLoading =
        isLiveSession && (tv.isIniting || !tv.isInitialized || tv.isBuffering);
    final showLiveBadge = isLiveSession && livePlaying;
    final canToggle =
        isLiveSession ? !liveLoading : now.onTogglePlayPause != null;
    final isPlayingEffective = isLiveSession ? livePlaying : (now.isPlaying);
    final showLiveLoadingSpinner = _showControls &&
        liveLoading &&
        (floatingPlayer is! LiveFloatingMiniPlayer);
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
              floatingPlayer != null
                  ? IgnorePointer(
                      child: floatingPlayer,
                    )
                  : (now.thumbnailUrl != null && now.thumbnailUrl!.isNotEmpty
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
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _safeSetState(() {
                      _showControls = !_showControls;
                    });
                    if (_showControls) {
                      _scheduleHideControls();
                    } else {
                      _controlsTimer?.cancel();
                    }
                  },
                ),
              ),
              // Center play/pause overlay (like YouTube). Kept separate from
              // expand/close, and hidden while loading.
              if (_showControls && canToggle)
                Positioned.fill(
                  child: Center(
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          if (isLiveSession) {
                            if (livePlaying) {
                              tv.pausePlayback();
                              ChannelMiniPlayerManager.I
                                  .update(isPlaying: false);
                            } else {
                              tv.resumePlayback();
                              ChannelMiniPlayerManager.I
                                  .update(isPlaying: true);
                            }
                          } else {
                            now.onTogglePlayPause?.call();
                          }
                          _scheduleHideControls();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            isPlayingEffective
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (showLiveLoadingSpinner)
                const Positioned(
                  right: 8,
                  bottom: 8,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              if (_showControls)
                Positioned(
                  left: 6,
                  right: 6,
                  top: 6,
                  child: Row(
                    children: [
                      _miniControlButton(
                        icon: Icons.open_in_full,
                        onTap: () {
                          ChannelMiniPlayerManager.I.setMinimized(false);
                          final cb = now.onExpand;
                          if (cb != null) {
                            cb();
                            return;
                          }
                          if (now.playlistId != null &&
                              now.playlistId!.isNotEmpty) {
                            final nav =
                                Navigator.of(context, rootNavigator: true);
                            final target = '/playlist/${now.playlistId!}';
                            if (appRouteStackObserver.containsName(target)) {
                              nav.popUntil(
                                  (route) => route.settings.name == target);
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
                      const Spacer(),
                      _miniControlButton(
                        icon: Icons.close,
                        onTap: () {
                          final isLive = now.videoId.startsWith('live:');
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            ChannelMiniPlayerManager.I.clear();
                            if (isLive) {
                              TvController.instance
                                  .setUseUnifiedMiniPlayer(false);
                              TvController.instance.stop();
                            }
                          });
                        },
                      ),
                    ],
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
