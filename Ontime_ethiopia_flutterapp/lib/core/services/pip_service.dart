import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class PipService {
  static const MethodChannel _channel = MethodChannel('ontime/pip');

  static Future<void> setActive(bool active) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setActive', {'active': active});
    } catch (_) {}
  }

  static Future<void> enterIfActive() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('enter');
    } catch (_) {}
  }
}
