import 'dart:async';
import 'dart:math';

import '../api_client.dart';

class ListenTracker {
  String _sessionId = _genSessionId();
  Timer? _hbTimer;
  String? _slug;
  bool _heartbeatEnabled = false;

  static String _genSessionId() {
    final r = Random.secure();
    final t = DateTime.now().millisecondsSinceEpoch;
    final a = r.nextInt(1 << 32);
    final b = r.nextInt(1 << 32);
    return 'r${t.toRadixString(36)}-${a.toRadixString(36)}${b.toRadixString(36)}';
  }

  Future<void> start(String slug) async {
    _slug = slug;
    _sessionId = _genSessionId();
    await _sendStart(slug);
    setHeartbeatEnabled(_heartbeatEnabled);
  }

  Future<void> stop([String? slug]) async {
    final s = slug ?? _slug;
    if (s != null) {
      await _sendStop(s);
    }
    _slug = null;
    setHeartbeatEnabled(false);
  }

  void setHeartbeatEnabled(bool enabled) {
    _heartbeatEnabled = enabled;
    if (!_heartbeatEnabled) {
      _cancelHeartbeat();
      return;
    }
    final s = _slug;
    if (s == null) return;
    if (_hbTimer != null) return;
    _hbTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      final slug = _slug;
      if (!_heartbeatEnabled || slug == null) return;
      await _sendHeartbeat(slug);
    });
  }

  void dispose() {
    _cancelHeartbeat();
  }

  Future<void> _sendStart(String slug) async {
    try {
      await ApiClient().post('/live/radio/$slug/listen/start/', data: {
        'session_id': _sessionId,
      });
    } catch (_) {}
  }

  Future<void> _sendHeartbeat(String slug) async {
    try {
      await ApiClient().post('/live/radio/$slug/listen/heartbeat/', data: {
        'session_id': _sessionId,
      });
    } catch (_) {}
  }

  Future<void> _sendStop(String slug) async {
    try {
      await ApiClient().post('/live/radio/$slug/listen/stop/', data: {
        'session_id': _sessionId,
      });
    } catch (_) {}
  }

  void _cancelHeartbeat() {
    try {
      _hbTimer?.cancel();
    } catch (_) {}
    _hbTimer = null;
  }
}
