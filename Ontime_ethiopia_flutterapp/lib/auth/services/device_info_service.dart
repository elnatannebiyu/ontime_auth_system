import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DeviceInfoService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
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
        deviceData.addAll({
          'device_model': androidInfo.model,
          'device_brand': androidInfo.brand,
          'device_manufacturer': androidInfo.manufacturer,
          'android_version': androidInfo.version.release,
          'android_sdk': androidInfo.version.sdkInt,
          'device_id': androidInfo.id,
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
        return '${androidInfo.brand}_${androidInfo.model}_${androidInfo.id}';
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
