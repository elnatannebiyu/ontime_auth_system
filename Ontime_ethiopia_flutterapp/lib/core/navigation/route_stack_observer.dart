import 'package:flutter/widgets.dart';

class RouteStackObserver extends NavigatorObserver {
  final List<String> _stack = <String>[];

  List<String> get stack => List<String>.unmodifiable(_stack);

  bool containsName(String name) => _stack.contains(name);

  String? get top => _stack.isEmpty ? null : _stack.last;

  void _push(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    _stack.add(name);
  }

  void _remove(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    _stack.remove(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _push(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _remove(oldRoute);
    _push(newRoute);
  }
}

final RouteStackObserver appRouteStackObserver = RouteStackObserver();
