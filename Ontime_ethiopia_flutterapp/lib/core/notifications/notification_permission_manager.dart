// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'notification_service.dart';

/// Enterprise-grade notification permission flow:
/// - Gentle pre-prompt explaining value
/// - System prompt request
/// - Post-prompt handling (granted: show confirmation; denied: soft fallback)
/// - Permanently denied: offer deep-link to Settings
class NotificationPermissionManager {
  static final NotificationPermissionManager _instance =
      NotificationPermissionManager._internal();
  factory NotificationPermissionManager() => _instance;
  NotificationPermissionManager._internal();

  bool _askedThisSession = false;

  Future<bool> requestPermissionFlow(BuildContext context) async {
    // Only relevant on mobile
    if (!(Platform.isAndroid || Platform.isIOS)) return false;

    // Android < 13: permission is not required
    if (Platform.isAndroid) {
      // On Android 13+ we need POST_NOTIFICATIONS runtime permission
      final androidInfo = await Permission.notification.status;
      if (androidInfo.isGranted) return true;
    }

    // Avoid nagging repeatedly in one session
    if (_askedThisSession) {
      final st = await Permission.notification.status;
      return st.isGranted;
    }

    _askedThisSession = true;

    final shouldAsk = await _showPrePrompt(context);
    if (!shouldAsk) return false;

    // Request system permission
    final status = await Permission.notification.request();

    if (status.isGranted) {
      // Initialize local notifications and show a friendly confirmation
      await NotificationService().initialize();
      await NotificationService().showBasic(
        title: 'Notifications enabled',
        body: 'We\'ll keep you informed about important updates.',
      );
      return true;
    }

    if (status.isPermanentlyDenied) {
      await _showGoToSettings(context);
      return false;
    }

    // Denied but not permanent: show a soft nudge (non-blocking)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Notifications are off. You can enable them later in Settings.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
    return false;
  }

  Future<bool> _showPrePrompt(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Enable notifications?'),
            content: const Text(
                'Allow notifications to get updates about new episodes, account security alerts, and service announcements.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Allow'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showGoToSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn on notifications'),
        content: const Text(
            'Notifications are disabled. You can enable them in your system Settings to receive important updates.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
