import 'package:flutter/material.dart';

/// A reusable brand title for AppBars across the app.
/// Renders a compact logo placeholder and the app name "Ontime",
/// with an optional section label to the right.
class BrandTitle extends StatelessWidget {
  final String? section;
  const BrandTitle({super.key, this.section});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.play_circle_fill, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Ontime',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        if (section != null && section!.isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(
            section!,
            style: textTheme.titleMedium,
          ),
        ],
      ],
    );
  }
}
