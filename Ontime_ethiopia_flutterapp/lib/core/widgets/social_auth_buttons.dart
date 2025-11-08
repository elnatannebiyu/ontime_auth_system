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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: onGoogle,
            icon: const Icon(Icons.g_mobiledata),
            label: const Text('Sign in or Sign up with Google'),
          ),
        ),
        if (showApple) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: onApple,
              icon: const Icon(Icons.apple),
              label: const Text('Sign in or Sign up with Apple'),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}
