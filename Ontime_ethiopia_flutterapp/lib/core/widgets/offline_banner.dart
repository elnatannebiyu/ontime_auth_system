import 'package:flutter/material.dart';

class OfflineBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  const OfflineBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      color: colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.wifi_off),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: onRetry == null
            ? null
            : TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
      ),
    );
  }
}
