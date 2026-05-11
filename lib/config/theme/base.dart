import 'package:flutter/material.dart';

abstract class BaseTheme {
  Color get primary;
  Color get secondary;
  Color get onPrimary;
  Color get background;
  Color get primaryText;
  Color get surface;
  Color get onSurface;
  Color get overlay;
  Color get surfaceLow;
  Color get surfaceHigh;
  Color get outline;
  Color get textMuted;
  Color get accentTint;
  Color get outlineSoft;
  Color get warning;
  SettingsColors get settings;

  ThemeData get themeData;
}

abstract class SettingsColors {
  Color get iconBackground;
  Color get icon;
  Color get tileTitle;
  Color get switchThumb;
}
