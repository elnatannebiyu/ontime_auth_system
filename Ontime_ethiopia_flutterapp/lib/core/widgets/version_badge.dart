import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class VersionBadge extends StatelessWidget {
  const VersionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final info = snap.data!;
        final text = 'v${info.version}+${info.buildNumber}';
        final style = Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
            );
        return Text(text, textAlign: TextAlign.center, style: style);
      },
    );
  }
}
