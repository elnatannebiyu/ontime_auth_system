import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
      useMaterial3: true,
    );
    return base.copyWith(
      cardTheme: base.cardTheme.copyWith(clipBehavior: Clip.antiAlias),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
      useMaterial3: true,
    );
    return base.copyWith(
      cardTheme: base.cardTheme.copyWith(clipBehavior: Clip.antiAlias),
    );
  }
}
