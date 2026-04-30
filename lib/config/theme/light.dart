import 'package:flutter/material.dart';

import '../config.dart';
import 'base.dart';

class LightTheme implements BaseTheme {
  @override
  final Color primary = const Color(0xFF446556);
  @override
  final Color secondary = const Color(0xFFd7ccfe);
  @override
  final Color onPrimary = const Color(0xFFE0FFEE);
  @override
  final Color background = const Color(0xFFF9F9F9);
  @override
  final Color primaryText = const Color(0xFF2D3435);
  @override
  final Color surface = const Color(0xFFFFFFFF);
  @override
  final Color onSurface = const Color(0xFF5A6061);
  @override
  final Color overlay = const Color(0xFF000000).withOpacity(0.1);
  @override
  final Color surfaceLow = const Color(0xFFF2F4F4);
  @override
  final Color surfaceHigh = const Color(0xFFDDE4E5);
  @override
  final Color outline = const Color(0xFFADB3B4);
  @override
  final Color textMuted = const Color(0xFF5A6061);

  @override
  Color get accentTint => primary.withValues(alpha: 0.12);

  @override
  Color get outlineSoft => outline.withValues(alpha: 0.16);

  @override
  final Color warning = Color(0xFFF4BD2B);
  @override
  final SettingsColors settings = SettingsColorsImpl();
  @override
  final BottomNavBarColors bottomNavBar = BottomNavBarColorsImpl();

  @override
  late final ThemeData themeData = ThemeData(
    fontFamily: Config.fontFamily,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(seedColor: primary),
  );
}

class SettingsColorsImpl implements SettingsColors {
  @override
  final iconBackground = const Color(0xFFF2F3F6);
  @override
  final icon = const Color(0xFF5E6984);

  @override
  Color get tileTitle => const Color(0xFF000000);

  @override
  Color get switchThumb => const Color(0xFFFFFFFF);
}

class BottomNavBarColorsImpl implements BottomNavBarColors {
  @override
  Color get background => const Color(0xFF2DAE77).withOpacity(0.08);
  @override
  Color get foreground => const Color(0xFF2DAE77);
  @override
  Color get indicator => const Color(0xFF2DAE77);
}
