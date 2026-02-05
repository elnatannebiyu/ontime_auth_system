import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:ontime_ethiopia_flutterapp/live/audio_controller.dart';
import 'package:ontime_ethiopia_flutterapp/core/localization/l10n.dart';

class MiniAudioBar extends StatefulWidget {
  const MiniAudioBar({super.key});

  @override
  State<MiniAudioBar> createState() => _MiniAudioBarState();
}

class _MiniAudioBarState extends State<MiniAudioBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _eqCtrl;

  String _nowPlayingPrefix() {
    switch (LocalizationController.currentLanguage) {
      case AppLanguage.am:
        return 'አሁን እየተጫወተ ነው';
      case AppLanguage.om:
        return 'Amma taphachaa jira';
      case AppLanguage.en:
        return 'Now playing';
    }
  }

  @override
  void initState() {
    super.initState();
    _eqCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _eqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioController>(
      builder: (context, ctrl, _) {
        final show = ctrl.isActive || ctrl.hasSource || ctrl.isPlaying;
        if (!show) return const SizedBox.shrink();

        return Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.radio, size: 20),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  height: 16,
                  child: CustomPaint(
                    painter: _EqBars(
                      animation: _eqCtrl,
                      active: ctrl.isPlaying,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AutoMarqueeText(
                    text: '${_nowPlayingPrefix()} ${ctrl.title ?? 'Radio'}',
                    isPlaying: ctrl.isPlaying,
                  ),
                ),
                IconButton(
                  tooltip: ctrl.isPlaying ? 'Pause' : 'Play',
                  icon: Icon(
                      ctrl.isPlaying ? Icons.pause_circle : Icons.play_circle),
                  iconSize: 30,
                  onPressed: () async {
                    if (ctrl.isPlaying) {
                      await ctrl.pause();
                    } else {
                      await ctrl.play();
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Stop',
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    await ctrl.stop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AutoMarqueeText extends StatefulWidget {
  final String text;
  final bool isPlaying;

  const _AutoMarqueeText({
    required this.text,
    required this.isPlaying,
  });

  @override
  State<_AutoMarqueeText> createState() => _AutoMarqueeTextState();
}

class _AutoMarqueeTextState extends State<_AutoMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _offset;
  double _overflow = 0;
  double _maxWidth = 0;
  String _lastText = '';

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    _offset = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.linear),
    );
  }

  @override
  void didUpdateWidget(covariant _AutoMarqueeText old) {
    super.didUpdateWidget(old);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontWeight: FontWeight.w600);
    const gap = 24.0;

    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        ellipsis: '…',
      )..layout();
      final rawOverflow = painter.width - maxWidth;
      final nextOverflow = rawOverflow > 0 ? rawOverflow + gap : 0.0;
      final shouldAnimate = nextOverflow > 0 && widget.isPlaying;

      final needsUpdate = nextOverflow != _overflow ||
          maxWidth != _maxWidth ||
          _lastText != widget.text;
      if (needsUpdate) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _overflow = nextOverflow;
            _maxWidth = maxWidth;
            _lastText = widget.text;
          });
          if (shouldAnimate) {
            if (!_ctrl.isAnimating) _ctrl.repeat();
          } else {
            if (_ctrl.isAnimating) _ctrl.stop();
          }
        });
      } else {
        if (shouldAnimate) {
          if (!_ctrl.isAnimating) _ctrl.repeat();
        } else {
          if (_ctrl.isAnimating) _ctrl.stop();
        }
      }

      if (nextOverflow <= 0) {
        return Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      }

      return ClipRect(
        child: AnimatedBuilder(
          animation: _offset,
          builder: (_, __) {
            return Transform.translate(
              offset: Offset(-_offset.value * nextOverflow, 0),
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: style,
              ),
            );
          },
        ),
      );
    });
  }
}

class _EqBars extends CustomPainter {
  final Animation<double> animation;
  final bool active;
  final Color color;

  _EqBars({
    required this.animation,
    required this.active,
    required this.color,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = active ? color : color.withOpacity(0.4)
      ..strokeWidth = size.width / 10
      ..strokeCap = StrokeCap.round;

    final t = animation.value;

    for (int i = 0; i < 4; i++) {
      final x = (i + 0.5) * (size.width / 4);
      final amp =
          active ? (0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 6 + i))) : 0.25;

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
