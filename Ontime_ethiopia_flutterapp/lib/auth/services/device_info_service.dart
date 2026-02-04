import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter/services.dart';

class DeviceInfoService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const MethodChannel _platform = MethodChannel('ontime/device');
  static const _storage = FlutterSecureStorage();
  static const _kDeviceIdKey = 'device_id';
  static const _kDeviceNameKey = 'device_name';

  static Future<String?> _getAndroidIdViaChannel() async {
    try {
      final v = await _platform.invokeMethod<String>('getAndroidId');
      final s = (v ?? '').trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  static String? _extractUserKeyFromMe(Map<String, dynamic> me) {
    try {
      final candidates = [
        me['id'],
        me['user_id'],
        me['pk'],
        me['username'],
        me['email'],
      ];
      for (final c in candidates) {
        if (c == null) continue;
        final s = c.toString().trim();
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return null;
  }

  static String? _extractUserKeyFromAccessToken(String? accessToken) {
    try {
      if (accessToken == null || accessToken.isEmpty) return null;
      final decoded = JwtDecoder.decode(accessToken);
      final candidates = [
        decoded['user_id'],
        decoded['id'],
        decoded['sub'],
        decoded['username'],
        decoded['email'],
      ];
      for (final c in candidates) {
        if (c == null) continue;
        final s = c.toString().trim();
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return null;
  }

  static Future<String> getScopedDeviceId({
    Map<String, dynamic>? cachedMe,
    String? accessToken,
  }) async {
    final baseId = (await getDeviceId()).trim();
    if (baseId.isEmpty) return baseId;
    if (baseId.contains(':')) return baseId;
    String? userKey;
    if (cachedMe != null) {
      userKey = _extractUserKeyFromMe(cachedMe);
    }
    userKey ??= _extractUserKeyFromAccessToken(accessToken);
    if (userKey == null || userKey.isEmpty) return baseId;
    return '$baseId:$userKey';
  }

  /// Get comprehensive device information
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    Map<String, dynamic> deviceData = {
      'app_name': packageInfo.appName,
      'package_name': packageInfo.packageName,
      'version': packageInfo.version,
      'build_number': packageInfo.buildNumber,
      'platform': Platform.operatingSystem,
    };

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final stableId = await getDeviceId();
        deviceData.addAll({
          'device_model': androidInfo.model,
          'device_brand': androidInfo.brand,
          'device_manufacturer': androidInfo.manufacturer,
          'android_version': androidInfo.version.release,
          'android_sdk': androidInfo.version.sdkInt,
          'device_id': stableId,
          'is_physical_device': androidInfo.isPhysicalDevice,
        });
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceData.addAll({
          'device_model': iosInfo.model,
          'device_name': iosInfo.name,
          'system_name': iosInfo.systemName,
          'system_version': iosInfo.systemVersion,
          'device_id': iosInfo.identifierForVendor ?? 'unknown',
          'is_physical_device': iosInfo.isPhysicalDevice,
        });
      }
    } catch (e) {
      // Fallback if device info fails
      deviceData['device_info_error'] = e.toString();
    }

    return deviceData;
  }

  /// Get device fingerprint for session binding
  static Future<String> getDeviceFingerprint() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final stableId = await getDeviceId();
        return '${androidInfo.brand}_${androidInfo.model}_$stableId';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return '${iosInfo.model}_${iosInfo.identifierForVendor ?? "unknown"}';
      }
    } catch (e) {
      // Return a fallback fingerprint
      return 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    }

    return 'unknown_platform';
  }

  /// Returns a stable device ID persisted across app restarts.
  /// On Android uses Android ID; on iOS uses identifierForVendor; falls back to generated value.
  static Future<String> getDeviceId() async {
    // Return cached if present
    final existing = await _storage.read(key: _kDeviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    String generated;
    try {
      if (Platform.isAndroid) {
        // Use Settings.Secure.ANDROID_ID via native channel. Stable across reinstalls
        // for the same signing key (unless factory reset).
        generated = (await _getAndroidIdViaChannel()) ?? '';
        if (generated.isEmpty) {
          final info = await _deviceInfo.androidInfo;
          generated = info.id;
        }
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        generated = info.identifierForVendor ??
            'ios_unknown_${DateTime.now().millisecondsSinceEpoch}';
      } else {
        generated =
            'device_${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (_) {
      generated = 'device_unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
    await _storage.write(key: _kDeviceIdKey, value: generated);
    return generated;
  }

  /// Returns a human-readable device name persisted across restarts.
  static Future<String> getDeviceName() async {
    final existing = await _storage.read(key: _kDeviceNameKey);
    if (existing != null && existing.isNotEmpty) return existing;

    String name = 'Unknown Device';
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        name = '${info.brand} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        name = info.name;
      } else {
        name = 'Device ${Platform.operatingSystem}';
      }
    } catch (_) {}
    await _storage.write(key: _kDeviceNameKey, value: name);
    return name;
  }

  /// Returns a stable device type string used across the whole system.
  ///
  /// IMPORTANT: keep this aligned with backend expectations and DB values.
  /// We intentionally use platform identifiers here (android/ios/web) rather
  /// than generic buckets like "mobile" to avoid duplicate device/session rows.
  static Future<String> getDeviceType() async {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'web';
  }

  /// Human-readable OS name (e.g., Android, iOS)
  static Future<String> getOSName() async {
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
    } catch (_) {}
    return Platform.operatingSystem;
  }

  /// OS version string (e.g., 14, 13)
  static Future<String> getOSVersion() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return info.version.release;
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.systemVersion;
      }
    } catch (_) {}
    return 'unknown';
  }

  /// Standard headers expected by backend for device identification
  static Future<Map<String, String>> getStandardDeviceHeaders() async {
    final id = await getDeviceId();
    final name = await getDeviceName();
    final type = await getDeviceType();
    final osName = await getOSName();
    final osVersion = await getOSVersion();
    return {
      'X-Device-Id': id,
      'X-Device-Name': name,
      'X-Device-Type': type,
      'X-OS-Name': osName,
      'X-OS-Version': osVersion,
    };
  }

  /// Get platform-specific headers for API requests
  static Future<Map<String, String>> getDeviceHeaders() async {
    final deviceInfo = await getDeviceInfo();
    final fingerprint = await getDeviceFingerprint();

    return {
      'X-Device-Platform': Platform.operatingSystem,
      'X-Device-Fingerprint': fingerprint,
      'X-App-Version': deviceInfo['version'] ?? 'unknown',
      'X-App-Build': deviceInfo['build_number'] ?? 'unknown',
      if (deviceInfo['device_model'] != null)
        'X-Device-Model': deviceInfo['device_model'],
    };
  }
}
