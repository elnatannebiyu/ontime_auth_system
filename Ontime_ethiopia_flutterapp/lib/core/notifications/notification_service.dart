import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String androidChannelId = 'updates';
  static const String androidChannelName = 'Updates & Alerts';
  static const String androidChannelDesc = 'Service updates, releases, important notices';

  Future<void> initialize() async {
    if (_initialized) return;
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _fln.initialize(initSettings);
    // Create Android channel once
    final androidPlugin = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        androidChannelId,
        androidChannelName,
        description: androidChannelDesc,
        importance: Importance.high,
      );
      await androidPlugin.createNotificationChannel(channel);
    }
    _initialized = true;
  }

  Future<void> showBasic({
    required String title,
    required String body,
    int id = 0,
  }) async {
    await initialize();
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      androidChannelId,
      androidChannelName,
      channelDescription: androidChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    const NotificationDetails details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _fln.show(id, title, body, details);
  }
}
