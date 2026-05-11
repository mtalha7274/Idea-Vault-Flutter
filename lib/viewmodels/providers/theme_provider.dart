import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../config/config.dart';
import '../../config/theme/base.dart';
import '../../config/theme/dark.dart';
import '../../config/theme/light.dart';
import '../../data/repositories/local/theme.dart';

class ThemeProvider with ChangeNotifier {
  late BaseTheme baseTheme;
  late String themeType;
  final ThemeRepo _themeRepo;

  ThemeProvider(this._themeRepo) {
    final String? type = _themeRepo.getTheme();
    final String resolved;
    if (type == null) {
      resolved = ui.PlatformDispatcher.instance.platformBrightness ==
              ui.Brightness.dark
          ? Config.dark
          : Config.light;
    } else {
      resolved = type == Config.dark ? Config.dark : Config.light;
    }
    themeType = resolved;
    baseTheme = resolved == Config.dark ? DarkTheme() : LightTheme();
  }

  void setTheme({required String theme}) async {
    if (theme == themeType) return;
    _themeRepo.setTheme(theme: theme);

    themeType = theme;
    if (theme == Config.dark) {
      baseTheme = DarkTheme();
    } else if (theme == Config.light) {
      baseTheme = LightTheme();
    }

    notifyListeners();
  }
}
