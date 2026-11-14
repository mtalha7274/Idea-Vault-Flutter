import 'package:flutter/material.dart';

import '../../config/theme/base.dart';

Color selectionBandColor(BaseTheme theme) {
  final isDark = theme.themeData.brightness == Brightness.dark;
  return theme.primary.withValues(alpha: isDark ? 0.24 : 0.18);
}

Color selectionCardFillColor(BaseTheme theme) {
  final isDark = theme.themeData.brightness == Brightness.dark;
  return Color.alphaBlend(
    theme.primary.withValues(alpha: isDark ? 0.16 : 0.10),
    theme.surface,
  );
}
