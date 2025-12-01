import 'dart:io';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../api_client.dart';
import '../../auth/services/device_info_service.dart';
import 'notification_inbox.dart';

/// Handles Firebase initialization, permissions, token management, and listeners.
class FcmManager {
  static final FcmManager _instance = FcmManager._internal();
  factory FcmManager() => _instance;
  FcmManager._internal();

  bool _initialized = false;
  static const _kTokenKey = 'fcm_token';
  String? _token;

  // Broadcasts an event whenever a foreground FCM notification is received.
  static final StreamController<void> _notificationEvents =
      StreamController<void>.broadcast();

  Stream<void> get notificationStream => _notificationEvents.stream;

  // Local notifications
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();
  static const String _androidChannelId = 'fcm_default_channel';
  static const String _androidChannelName = 'Notifications';
  static const String _androidChannelDesc = 'General notifications';

  String? get token => _token;

  static Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTokenKey);
  }

  Future<void> _registerDeviceWithBackend(String token) async {
    try {
      // Require an authenticated session before attempting backend registration
      if (ApiClient().getAccessToken() == null ||
          (ApiClient().getAccessToken() ?? '').isEmpty) {
        return;
      }
      final pkg = await PackageInfo.fromPlatform();
      final deviceId = await DeviceInfoService.getDeviceId();
      final deviceName = await DeviceInfoService.getDeviceName();
      final deviceType =
          Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
      final appVersion = pkg.version;
      await ApiClient().post('/user-sessions/register-device/', data: {
        'device_id': deviceId,
        'device_type': deviceType,
        'device_name': deviceName,
        'push_token': token,
        'app_version': appVersion,
      });
    } catch (_) {
      // Silently ignore; will retry on next refresh/init
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _localNotifs.initialize(initSettings);

    // Ensure Android channel exists for 8.0+
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _androidChannelId,
      _androidChannelName,
      description: _androidChannelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    final androidPlugin = _localNotifs.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
  }

  Future<void> _showLocalNotification(String title, String body,
      {String? payload}) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _localNotifs.show(
      0,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Public helper to register the current FCM token with backend if logged in.
  Future<void> ensureRegisteredWithBackend() async {
    try {
      if (ApiClient().getAccessToken() == null ||
          (ApiClient().getAccessToken() ?? '').isEmpty) {
        return;
      }
      final t = _token ?? await FirebaseMessaging.instance.getToken();
      if (t != null && t.isNotEmpty) {
        await _registerDeviceWithBackend(t);
      }
    } catch (_) {}
  }

  Future<void> initialize(
      {BuildContext? context, bool requestPermissions = false}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return; // Mobile only
    if (_initialized) return;

    try {
      // Initialize Firebase (will no-op if already initialized)
      await Firebase.initializeApp();

      // Initialize local notifications (for foreground tray notifications)
      await _initializeLocalNotifications();

      // Request permissions only when explicitly asked. Otherwise, let the
      // app-level UX flow (NotificationPermissionManager) handle prompting.
      if (requestPermissions) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      }

      // Obtain the FCM token
      final token = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        debugPrint('FCM token: ${token ?? 'null'}');
      }
      if (token != null && token.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kTokenKey, token);
          _token = token;
        } catch (_) {}
        unawaited(_registerDeviceWithBackend(token));
      }

      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        if (kDebugMode) debugPrint('FCM token refreshed: $newToken');
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kTokenKey, newToken);
          _token = newToken;
        } catch (_) {}
        unawaited(_registerDeviceWithBackend(newToken));
      });

      // Foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint('FCM foreground message: ${message.messageId}');
          debugPrint('Data: ${message.data}');
          debugPrint('Notification title: ${message.notification?.title}');
          debugPrint('Notification body: ${message.notification?.body}');
          debugPrint('Message data keys: ${message.data.keys.toList()}');
        }
        // Show a tray notification even while app is in foreground
        final title =
            message.notification?.title ?? (message.data['title'] as String?);
        final body =
            message.notification?.body ?? (message.data['body'] as String?);
        _showLocalNotification(
          title ?? 'Notification',
          body ?? '',
          payload: message.data.isNotEmpty ? message.data.toString() : null,
        );

        // Save to in-app inbox
        final item = NotificationItem(
          title: title ?? 'Notification',
          body: body ?? '',
          timestamp: DateTime.now(),
          link: message.data['link'] as String?,
        );
        NotificationInbox.add(item);

        // Notify listeners (e.g., HomePage) that a new notification has arrived.
        _notificationEvents.add(null);
      });

      // Background/terminated: define a top-level handler in main.dart if needed
      // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM init failed: $e');
      }
      // Continue app without push; do not crash
    }
  }
}
