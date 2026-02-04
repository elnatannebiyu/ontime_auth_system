import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'audio_controller.dart';

class GlobalMiniBar extends StatefulWidget {
  const GlobalMiniBar({super.key});

  @override
  State<GlobalMiniBar> createState() => _GlobalMiniBarState();
}

class _GlobalMiniBarState extends State<GlobalMiniBar>
    with SingleTickerProviderStateMixin {
  final audio = AudioController.instance;
  late final AnimationController _eqCtrl;

  @override
  void initState() {
    super.initState();
    audio.addListener(_onChanged);
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
    _eqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showRadio = audio.isActive;
    if (!showRadio) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.radio, size: 20),
            const SizedBox(width: 8),
            // Simple equalizer animation
            SizedBox(
              width: 24,
              height: 16,
              child: CustomPaint(
                painter:
                    _EqBars(animation: _eqCtrl, active: audio.player.playing),
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
              icon: Icon(audio.player.playing
                  ? Icons.pause_circle
                  : Icons.play_circle),
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
        ),
      ),
    );
  }
}

class _EqBars extends CustomPainter {
  final Animation<double> animation;
  final bool active;
  _EqBars({required this.animation, required this.active})
      : super(repaint: animation);

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
      final amp =
          active ? (0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 6 + i))) : 0.2;
      final h = amp * size.height;
      final y1 = (size.height - h) / 2;
      final y2 = y1 + h;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EqBars oldDelegate) =>
      oldDelegate.active != active;
}
