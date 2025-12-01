// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/theme/theme_controller.dart';
import '../core/localization/l10n.dart';
import '../core/widgets/brand_title.dart';

class SettingsPage extends StatelessWidget {
  final ThemeController themeController;
  final LocalizationController localizationController;
  const SettingsPage(
      {super.key,
      required this.themeController,
      required this.localizationController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AnimatedBuilder(
          animation: localizationController,
          builder: (_, __) =>
              BrandTitle(section: localizationController.t('settings')),
        ),
      ),
      body: SafeArea(
        bottom: true,
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AnimatedBuilder(
              animation: localizationController,
              builder: (_, __) => Text(
                localizationController.t('appearance'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
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
                        builder: (_, __) =>
                            Text(localizationController.t('system')),
                      ),
                      onChanged: (v) =>
                          v != null ? themeController.setThemeMode(v) : null,
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.light,
                      groupValue: mode,
                      title: AnimatedBuilder(
                        animation: localizationController,
                        builder: (_, __) =>
                            Text(localizationController.t('light')),
                      ),
                      onChanged: (v) =>
                          v != null ? themeController.setThemeMode(v) : null,
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      groupValue: mode,
                      title: AnimatedBuilder(
                        animation: localizationController,
                        builder: (_, __) =>
                            Text(localizationController.t('dark')),
                      ),
                      onChanged: (v) =>
                          v != null ? themeController.setThemeMode(v) : null,
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
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
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
                      title: Text(localizationController.t('english')),
                      onChanged: (v) => v != null
                          ? localizationController.setLanguage(v)
                          : null,
                    ),
                    RadioListTile<AppLanguage>(
                      value: AppLanguage.am,
                      groupValue: lang,
                      title: Text(localizationController.t('amharic')),
                      onChanged: (v) => v != null
                          ? localizationController.setLanguage(v)
                          : null,
                    ),
                    RadioListTile<AppLanguage>(
                      value: AppLanguage.om,
                      groupValue: lang,
                      title: Text(localizationController.t('oromo')),
                      onChanged: (v) => v != null
                          ? localizationController.setLanguage(v)
                          : null,
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 32),
            AnimatedBuilder(
              animation: localizationController,
              builder: (_, __) => Text(
                localizationController.t('security'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.devices),
              title: AnimatedBuilder(
                animation: localizationController,
                builder: (_, __) => Text(
                  localizationController.t('active_sessions'),
                ),
              ),
              subtitle: AnimatedBuilder(
                animation: localizationController,
                builder: (_, __) => Text(
                  localizationController.t('active_sessions_subtitle'),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/session-management'),
            ),
            ListTile(
              leading: const Icon(Icons.security),
              title: AnimatedBuilder(
                animation: localizationController,
                builder: (_, __) => Text(
                  localizationController.t('session_security'),
                ),
              ),
              subtitle: AnimatedBuilder(
                animation: localizationController,
                builder: (_, __) => Text(
                  localizationController.t('session_security_subtitle'),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/session-security'),
            ),
            const Divider(height: 32),
            AnimatedBuilder(
              animation: localizationController,
              builder: (_, __) => Text(
                localizationController.t('notifications_section'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: AnimatedBuilder(
                animation: localizationController,
                builder: (_, __) => Text(
                  localizationController.t('notification_inbox'),
                ),
              ),
              subtitle: AnimatedBuilder(
                animation: localizationController,
                builder: (_, __) => Text(
                  localizationController.t('notification_inbox_subtitle'),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/inbox'),
            ),
            const Divider(height: 32),
            if (kDebugMode) ...[
              Text('Developer',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('Dev: Dynamic Login Form'),
                subtitle: const Text('/dev/forms/login'),
                trailing: const Icon(Icons.chevron_right),
                isThreeLine: true,
                onTap: () =>
                    Navigator.of(context).pushNamed('/dev/forms/login'),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('Dev: Dynamic Register Form'),
                subtitle: const Text('/dev/forms/register'),
                trailing: const Icon(Icons.chevron_right),
                isThreeLine: true,
                onTap: () =>
                    Navigator.of(context).pushNamed('/dev/forms/register'),
              ),
              const Divider(height: 32),
            ],
          ],
        ),
      ),
    );
  }
}
