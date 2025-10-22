import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../api_client.dart';

class VersionGate {
  static Future<void> checkAndPrompt(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final platform =
          Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
      final version = info.version; // e.g., 1.2.3
      final buildNumber = int.tryParse(info.buildNumber);

      final res = await ApiClient().post('/channels/version/check/', data: {
        'platform': platform,
        'version': version,
        'build_number': buildNumber,
      });
      final data = res.data as Map;
      final updateAvailable =
          data['update_available'] == true || data['update_required'] == true;
      final updateType = (data['update_type'] ?? '')
          .toString(); // optional | required | forced
      final message = (data['message'] ?? '');
      final storeUrl = (data['store_url'] ?? '') as String;

      if (!updateAvailable) return;

      if (updateType == 'forced' || data['blocked'] == true) {
        await _showForcedDialog(context, message, storeUrl);
      } else if (updateType == 'required') {
        await _showForcedDialog(context, message, storeUrl);
      } else {
        _showOptionalSnack(context, message, storeUrl);
      }
    } catch (_) {
      // Silent fail: do not block startup if version check fails
    }
  }

  static Future<void> _showForcedDialog(
      BuildContext context, String message, String url) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Update Required'),
          content:
              Text(message.isEmpty ? 'Please update to continue.' : message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // In production, open the store URL using url_launcher
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  static void _showOptionalSnack(
      BuildContext context, String message, String url) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.isEmpty ? 'An update is available.' : message),
        action: url.isNotEmpty
            ? SnackBarAction(
                label: 'Update',
                onPressed: () {
                  // In production, open the store URL using url_launcher
                },
              )
            : null,
      ),
    );
  }
}
