import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/providers/theme_provider.dart';

TextStyle ideaVaultHeadline(
  BuildContext context, {
  double size = 32,
  FontWeight weight = FontWeight.w800,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  final theme = context.watch<ThemeProvider>().baseTheme;
  if (!GoogleFonts.config.allowRuntimeFetching) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color ?? theme.primaryText,
    );
  }

  return GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? theme.primaryText,
  );
}

TextStyle ideaVaultBody(
  BuildContext context, {
  double size = 16,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? height,
}) {
  final theme = context.watch<ThemeProvider>().baseTheme;
  if (!GoogleFonts.config.allowRuntimeFetching) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color ?? theme.primaryText,
    );
  }

  return GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color ?? theme.primaryText,
  );
}

TextStyle ideaVaultLabel(
  BuildContext context, {
  double size = 14,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  final theme = context.watch<ThemeProvider>().baseTheme;
  if (!GoogleFonts.config.allowRuntimeFetching) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color ?? theme.textMuted,
    );
  }

  return GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? theme.textMuted,
  );
}
