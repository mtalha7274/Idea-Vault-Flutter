import 'package:flutter/material.dart';

import '../config.dart';
import 'base.dart';

class LightTheme implements BaseTheme {
  @override
  final Color primary = const Color(0xFF3D5C4E);
  @override
  final Color secondary = const Color(0xFF9BA4FF);
  @override
  final Color onPrimary = const Color(0xFFFFFFFF);
  @override
  final Color background = const Color(0xFFF3F4F6);
  @override
  final Color primaryText = const Color(0xFF1A1C1E);
  @override
  final Color surface = const Color(0xFFFFFFFF);
  @override
  final Color onSurface = const Color(0xFF5C6166);
  @override
  final Color overlay = const Color(0xFF000000).withValues(alpha: 0.06);
  @override
  final Color surfaceLow = const Color(0xFFF2F4F5);
  @override
  final Color surfaceHigh = const Color(0xFFE8EBED);
  @override
  final Color outline = const Color(0xFFD1D5D8);
  @override
  final Color textMuted = const Color(0xFF757B80);

  @override
  Color get accentTint => primary.withValues(alpha: 0.12);

  @override
  Color get outlineSoft => outline.withValues(alpha: 0.16);

  @override
  final Color warning = const Color(0xFFF4BD2B);
  @override
  final SettingsColors settings = SettingsColorsImpl();

  @override
  late final ThemeData themeData = ThemeData(
    brightness: Brightness.light,
    fontFamily: Config.fontFamily,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      secondary: secondary,
      surface: surface,
      onSurface: primaryText,
      onPrimary: onPrimary,
    ),
  );
}

class SettingsColorsImpl implements SettingsColors {
  @override
  final iconBackground = const Color(0xFFF2F4F5);
  @override
  final icon = const Color(0xFF3D5C4E);

  @override
  Color get tileTitle => const Color(0xFF1A1C1E);

  @override
  Color get switchThumb => const Color(0xFFFFFFFF);
}
