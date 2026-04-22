import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class IdeaVaultPalette {
  const IdeaVaultPalette._();

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color background(BuildContext context) {
    return isDark(context) ? const Color(0xFF0F1412) : const Color(0xFFF9F9F9);
  }

  static Color surface(BuildContext context) {
    return isDark(context) ? const Color(0xFF18201C) : const Color(0xFFFFFFFF);
  }

  static Color surfaceLow(BuildContext context) {
    return isDark(context) ? const Color(0xFF131A17) : const Color(0xFFF2F4F4);
  }

  static Color surfaceHigh(BuildContext context) {
    return isDark(context) ? const Color(0xFF22302A) : const Color(0xFFDDE4E5);
  }

  static Color outline(BuildContext context) {
    return isDark(context) ? const Color(0xFF3A4541) : const Color(0xFFADB3B4);
  }

  static Color outlineSoft(BuildContext context) {
    return outline(context).withValues(alpha: 0.16);
  }

  static Color primary(BuildContext context) {
    return isDark(context) ? const Color(0xFFB8DDCA) : const Color(0xFF446556);
  }

  static Color onPrimary(BuildContext context) {
    return isDark(context) ? const Color(0xFF112019) : const Color(0xFFE0FFEE);
  }

  static Color text(BuildContext context) {
    return isDark(context) ? const Color(0xFFF3F6F4) : const Color(0xFF2D3435);
  }

  static Color textMuted(BuildContext context) {
    return isDark(context) ? const Color(0xFFA3AEAA) : const Color(0xFF5A6061);
  }

  static Color accentTint(BuildContext context) {
    return primary(context).withValues(alpha: 0.12);
  }
}

TextStyle ideaVaultHeadline(
  BuildContext context, {
  double size = 32,
  FontWeight weight = FontWeight.w800,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? IdeaVaultPalette.text(context),
  );
}

TextStyle ideaVaultBody(
  BuildContext context, {
  double size = 16,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? height,
}) {
  return GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color ?? IdeaVaultPalette.text(context),
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
  return GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? IdeaVaultPalette.textMuted(context),
  );
}
