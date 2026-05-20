import 'package:flutter/material.dart';

import '../config.dart';
import 'base.dart';

class DarkTheme implements BaseTheme {
  @override
  final Color primary = const Color(0xFF81B39C);
  @override
  final Color secondary = const Color(0xFFC5BAFF);
  @override
  final Color onPrimary = const Color(0xFF1A2421);
  @override
  final Color background = const Color(0xFF121416);
  @override
  final Color primaryText = const Color(0xFFE3E5E5);
  @override
  final Color surface = const Color(0xFF1C1F22);
  @override
  final Color onSurface = const Color(0xFFAFB3B7);
  @override
  final Color overlay = const Color(0xFFFFFFFF).withValues(alpha: 0.08);
  @override
  final Color surfaceLow = const Color(0xFF23272A);
  @override
  final Color surfaceHigh = const Color(0xFF2D3236);
  @override
  final Color outline = const Color(0xFF3D444A);
  @override
  final Color textMuted = const Color(0xFF8E9499);

  @override
  Color get accentTint => primary.withValues(alpha: 0.12);

  @override
  Color get outlineSoft => outline.withValues(alpha: 0.16);

  @override
  final Color warning = const Color(0xFFFFD966);
  @override
  final SettingsColors settings = SettingsColorsImpl();

  @override
  late final ThemeData themeData = ThemeData(
    brightness: Brightness.dark,
    fontFamily: Config.fontFamily,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
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
  final iconBackground = const Color(0xFF2D3236);
  @override
  final icon = const Color(0xFF81B39C);

  @override
  Color get tileTitle => const Color(0xFFE3E5E5);

  @override
  Color get switchThumb => const Color(0xFFFFFFFF);
}
