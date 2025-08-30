import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

/// AuthLayout provides a modern auth screen scaffold with:
/// - Animated gradient background
/// - Centered, responsive frosted-glass card container
/// - Optional header (title/subtitle) and footer areas
class AuthLayout extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final List<Widget>? actions;
  final Widget? bottom;

  const AuthLayout({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.actions,
    this.bottom,
  });

  @override
  State<AuthLayout> createState() => _AuthLayoutState();
}

class _AuthLayoutState extends State<AuthLayout> {
  double _phase = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      setState(() => _phase = (_phase + .01) % 1.0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;

    Color lerp(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;
    final c1 = lerp(color.primary, color.secondary, (_phase + 0.0) % 1);
    final c2 = lerp(color.tertiary, color.primaryContainer, (_phase + 0.33) % 1);
    final c3 = lerp(color.secondaryContainer, color.surfaceContainerHighest, (_phase + 0.66) % 1);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c1.withOpacity(0.12),
            c2.withOpacity(0.10),
            c3.withOpacity(0.08),
          ],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.dividerColor.withOpacity(.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: color.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.lock_outline, color: color.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          widget.subtitle!,
                                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (widget.actions != null) ...[
                                const SizedBox(width: 8),
                                Row(mainAxisSize: MainAxisSize.min, children: widget.actions!),
                              ],
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Body
                          widget.child,

                          if (widget.footer != null) ...[
                            const SizedBox(height: 16),
                            Divider(height: 20, color: theme.dividerColor.withOpacity(.3)),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: widget.footer!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ),
            ),
            if (widget.bottom != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: widget.bottom!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
