import 'package:flutter/foundation.dart';

/// Simple global refresh bus so a single Retry action can trigger
/// reloads across multiple pages (Home, Channels, Live, Shows, Shorts).
class GlobalRefreshBus extends ChangeNotifier {
  GlobalRefreshBus._internal();
  static final GlobalRefreshBus instance = GlobalRefreshBus._internal();

  int _tick = 0;
  int get tick => _tick;

  /// Triggers a global refresh event. Listeners can compare [tick]
  /// or just call their local reload logic when this is invoked.
  void triggerAll() {
    _tick++;
    notifyListeners();
  }
}
