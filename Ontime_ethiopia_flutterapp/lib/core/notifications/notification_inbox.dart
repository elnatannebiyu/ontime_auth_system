import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationItem {
  final String title;
  final String body;
  final DateTime timestamp;
  final String? link;

  NotificationItem({required this.title, required this.body, required this.timestamp, this.link});

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        if (link != null) 'link': link,
      };

  static NotificationItem fromJson(Map<String, dynamic> json) => NotificationItem(
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        link: json['link'] as String?,
      );
}

class NotificationInbox {
  static const String _kInboxKey = 'notification_inbox_v1';
  static const int _maxItems = 100;

  static Future<List<NotificationItem>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kInboxKey);
    if (raw == null || raw.isEmpty) return <NotificationItem>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return <NotificationItem>[];
  }

  static Future<void> add(NotificationItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await list();
    items.insert(0, item);
    if (items.length > _maxItems) {
      items.removeRange(_maxItems, items.length);
    }
    final encoded = json.encode(items.map((e) => e.toJson()).toList());
    await prefs.setString(_kInboxKey, encoded);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kInboxKey);
  }
}
