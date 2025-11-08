import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'audio_controller.dart';
import 'tv_controller.dart';
import 'live_player_overlay_page.dart';
import '../main.dart' show appNavigatorKey;
import 'dart:developer' as dev;

class GlobalMiniBar extends StatefulWidget {
  const GlobalMiniBar({super.key});

  @override
  State<GlobalMiniBar> createState() => _GlobalMiniBarState();
}

class _GlobalMiniBarState extends State<GlobalMiniBar>
    with SingleTickerProviderStateMixin {
  final audio = AudioController.instance;
  final tv = TvController.instance;
  late final AnimationController _eqCtrl;
  double _tvDragDy = 0.0; // negative when dragging upward
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    audio.addListener(_onChanged);
    tv.addListener(_onChanged);
    _eqCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    audio.removeListener(_onChanged);
    tv.removeListener(_onChanged);
    _eqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Priority: TV if has current; else Radio if active.
    final showTv = tv.hasCurrent && tv.playbackUrl != null && tv.controller != null && !tv.inFullPlayer;
    final showRadio = !showTv && audio.isActive;
    if (!showTv && !showRadio) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (showTv) ...[
                // Drag-up or tap to expand to full player
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_navigating) return;
                      final slug = tv.slug;
                      if (slug == null || slug.isEmpty) {
                        dev.log('Mini Tap: missing TV slug', name: 'GlobalMini');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Unable to open: missing channel')),
                        );
                        return;
                      }
                      final nav = appNavigatorKey.currentState;
                      if (nav == null) {
                        dev.log('Mini Tap: navigator not ready', name: 'GlobalMini');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Navigation not ready')),
                        );
                        return;
                      }
                      // Hide mini while full player is active
                      _navigating = true;
                      tv.setInFullPlayer(true);
                      nav.push(PageRouteBuilder(
                        pageBuilder: (_, __, ___) => LivePlayerOverlayPage(slug: slug),
                        transitionDuration: const Duration(milliseconds: 280),
                        reverseTransitionDuration: const Duration(milliseconds: 220),
                        transitionsBuilder: (_, animation, secondary, child) {
                          const begin = Offset(0.0, 1.0);
                          const end = Offset.zero;
                          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeOutCubic));
                          return SlideTransition(position: animation.drive(tween), child: child);
                        },
                      )).whenComplete(() { if (mounted) setState(() { _navigating = false; }); });
                    },
                    onVerticalDragUpdate: (details) {
                      setState(() {
                        _tvDragDy = (_tvDragDy + details.delta.dy).clamp(-120.0, 0.0);
                      });
                    },
                    onVerticalDragEnd: (details) {
                      final upward = -_tvDragDy; // positive if dragged up
                      final velocityUp = (details.primaryVelocity ?? 0) < -900; // fast upward fling
                      final shouldOpen = upward > 60 || velocityUp;
                      if (shouldOpen) {
                        // Reset and open full player
                        setState(() { _tvDragDy = 0.0; });
                        final slug = tv.slug;
                        final nav = appNavigatorKey.currentState;
                        if (!_navigating && slug != null && slug.isNotEmpty && nav != null) {
                          HapticFeedback.lightImpact();
                          _navigating = true;
                          tv.setInFullPlayer(true);
                          nav.push(PageRouteBuilder(
                            pageBuilder: (_, __, ___) => LivePlayerOverlayPage(slug: slug),
                            transitionDuration: const Duration(milliseconds: 280),
                            reverseTransitionDuration: const Duration(milliseconds: 220),
                            transitionsBuilder: (_, animation, secondary, child) {
                              const begin = Offset(0.0, 1.0);
                              const end = Offset.zero;
                              final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeOutCubic));
                              return SlideTransition(position: animation.drive(tween), child: child);
                            },
                          )).whenComplete(() { if (mounted) setState(() { _navigating = false; }); });
                        }
                      } else {
                        // Snap back
                        setState(() { _tvDragDy = 0.0; });
                      }
                    },
                    child: Semantics(
                      button: true,
                      label: 'Mini TV preview. Drag up to expand. Double tap to open.',
                      child: Transform.translate(
                        offset: Offset(0, _tvDragDy),
                        child: Builder(builder: (context) {
                          final p = (-_tvDragDy / 120.0).clamp(0.0, 1.0);
                          final scale = 1.0 + (0.03 * p);
                          return Transform.scale(
                            scale: scale,
                            alignment: Alignment.centerLeft,
                            child: Row(
                      children: [
                        SizedBox(
                          width: 96,
                          height: 54,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: tv.controller != null
                                ? VideoPlayer(tv.controller!)
                                : const ColoredBox(color: Colors.black12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tv.title ?? 'Live TV',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tv.isPlaying ? 'Pause' : 'Play',
                  icon: Icon(tv.isPlaying ? Icons.pause_circle : Icons.play_circle),
                  iconSize: 34,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () async {
                    if (tv.isPlaying) {
                      await tv.pausePlayback();
                    } else {
                      await tv.resumePlayback();
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Stop',
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    await tv.stop();
                  },
                ),
              ] else ...[
                const Icon(Icons.radio, size: 20),
                const SizedBox(width: 8),
                // Simple equalizer animation
                SizedBox(
                  width: 24,
                  height: 16,
                  child: CustomPaint(
                    painter: _EqBars(animation: _eqCtrl, active: audio.player.playing),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Now playing ${audio.title ?? 'Radio'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: audio.player.playing ? 'Pause' : 'Play',
                  icon: Icon(audio.player.playing ? Icons.pause_circle : Icons.play_circle),
                  iconSize: 30,
                  onPressed: () async {
                    if (audio.player.playing) {
                      await audio.pause();
                    } else {
                      await audio.play();
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Stop',
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    await audio.stop();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EqBars extends CustomPainter {
  final Animation<double> animation;
  final bool active;
  _EqBars({required this.animation, required this.active}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = size.width / 10
      ..strokeCap = StrokeCap.round;
    final t = animation.value;
    // 4 bars
    for (int i = 0; i < 4; i++) {
      final x = (i + 0.5) * (size.width / 4);
      final amp = active ? (0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 6 + i))) : 0.2;
      final h = amp * size.height;
      final y1 = (size.height - h) / 2;
      final y2 = y1 + h;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EqBars oldDelegate) => oldDelegate.active != active;
}
