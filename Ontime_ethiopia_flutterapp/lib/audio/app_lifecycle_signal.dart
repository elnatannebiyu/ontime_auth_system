import 'dart:async';

import 'package:flutter/widgets.dart';

class AppLifecycleSignal with WidgetsBindingObserver {
  AppLifecycleSignal._();

  static final AppLifecycleSignal I = AppLifecycleSignal._();

  bool _started = false;
  final StreamController<AppLifecycleState> _ctrl =
      StreamController<AppLifecycleState>.broadcast();

  Stream<AppLifecycleState> get stream => _ctrl.stream;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _ctrl.add(state);
  }

  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    try {
      _ctrl.close();
    } catch (_) {}
  }
}
