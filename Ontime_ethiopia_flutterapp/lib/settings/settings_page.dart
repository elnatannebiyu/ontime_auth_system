import 'package:flutter/material.dart';
import '../core/theme/theme_controller.dart';
import '../core/localization/l10n.dart';
import '../core/widgets/brand_title.dart';

class SettingsPage extends StatelessWidget {
  final ThemeController themeController;
  final LocalizationController localizationController;
  const SettingsPage({super.key, required this.themeController, required this.localizationController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AnimatedBuilder(
          animation: localizationController,
          builder: (_, __) => BrandTitle(section: localizationController.t('settings')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AnimatedBuilder(
            animation: localizationController,
            builder: (_, __) => Text(
              localizationController.t('appearance'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: themeController,
            builder: (context, _) {
              final mode = themeController.themeMode;
              return Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    groupValue: mode,
                    title: AnimatedBuilder(
                      animation: localizationController,
                      builder: (_, __) => Text(localizationController.t('system')),
                    ),
                    onChanged: (v) => v != null ? themeController.setThemeMode(v) : null,
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    groupValue: mode,
                    title: AnimatedBuilder(
                      animation: localizationController,
                      builder: (_, __) => Text(localizationController.t('light')),
                    ),
                    onChanged: (v) => v != null ? themeController.setThemeMode(v) : null,
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    groupValue: mode,
                    title: AnimatedBuilder(
                      animation: localizationController,
                      builder: (_, __) => Text(localizationController.t('dark')),
                    ),
                    onChanged: (v) => v != null ? themeController.setThemeMode(v) : null,
                  ),
                ],
              );
            },
          ),
          const Divider(height: 32),
          AnimatedBuilder(
            animation: localizationController,
            builder: (_, __) => Text(
              localizationController.t('language'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: localizationController,
            builder: (context, _) {
              final lang = localizationController.language;
              return Column(
                children: [
                  RadioListTile<AppLanguage>(
                    value: AppLanguage.en,
                    groupValue: lang,
                    title: const Text('English'),
                    onChanged: (v) => v != null ? localizationController.setLanguage(v) : null,
                  ),
                  RadioListTile<AppLanguage>(
                    value: AppLanguage.am,
                    groupValue: lang,
                    title: const Text('Amharic'),
                    onChanged: (v) => v != null ? localizationController.setLanguage(v) : null,
                  ),
                ],
              );
            },
          ),
          const Divider(height: 32),
          Text('Security', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.devices),
            title: const Text('Active Sessions'),
            subtitle: const Text('View and manage your active sessions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/session-management'),
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Session Security'),
            subtitle: const Text('Configure security settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/session-security'),
          ),
          const Divider(height: 32),
          Text('About', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: const Text('1.0.0'),
          ),
        ],
      ),
    );
  }
}
