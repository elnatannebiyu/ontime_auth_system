import 'package:flutter/material.dart';

class SocialAuthButtons extends StatelessWidget {
  final VoidCallback? onGoogle;
  final VoidCallback? onApple;
  final bool showApple;

  const SocialAuthButtons({
    super.key,
    this.onGoogle,
    this.onApple,
    this.showApple = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: onGoogle,
            icon: const Icon(Icons.g_mobiledata),
            label: const Text('Continue with Google'),
          ),
        ),
        if (showApple) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: onApple,
              icon: const Icon(Icons.apple),
              label: const Text('Continue with Apple'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Divider(color: theme.dividerColor.withOpacity(.4)) ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text('or', style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Divider(color: theme.dividerColor.withOpacity(.4)) ),
        ])
      ],
    );
  }
}
