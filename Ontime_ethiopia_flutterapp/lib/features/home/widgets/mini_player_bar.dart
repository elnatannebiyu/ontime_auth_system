import 'dart:ui';
import 'package:flutter/material.dart';

class MiniPlayerBar extends StatelessWidget {
  final VoidCallback onClose;
  final String nowPlayingLabel;
  const MiniPlayerBar({super.key, required this.onClose, required this.nowPlayingLabel});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: InkWell(
              onTap: () {},
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
                      width: 0.8,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 72,
                child: Row(
                  children: [
                    // Grabber
                    SizedBox(
                      width: 16,
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(color: Colors.black26),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        nowPlayingLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
