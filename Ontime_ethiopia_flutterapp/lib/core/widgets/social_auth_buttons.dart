import 'package:flutter/material.dart';

class SocialAuthButtons extends StatelessWidget {
  final VoidCallback? onGoogle;
  final VoidCallback? onApple;
  final bool showApple;
  final String googleLabel;
  final String appleLabel;

  const SocialAuthButtons({
    super.key,
    this.onGoogle,
    this.onApple,
    this.showApple = true,
    required this.googleLabel,
    required this.appleLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: onGoogle,
            icon: const Icon(Icons.g_mobiledata),
            label: Text(googleLabel),
          ),
        ),
        if (showApple) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: onApple,
              icon: const Icon(Icons.apple),
              label: Text(appleLabel),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}
