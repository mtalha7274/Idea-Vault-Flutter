import 'package:flutter/material.dart';

import '../../core/editor/note_document.dart';

class NoteEditorThemeData {
  const NoteEditorThemeData({
    required this.textColor,
    required this.mutedColor,
    required this.accentColor,
    required this.codeBackground,
    Color? inlineCodeColor,
  }) : inlineCodeColor = inlineCodeColor ?? textColor;

  static const double inlineCodePadding = 4;
  static const double inlineCodeGap = inlineCodePadding + 3;

  static const Color lightInlineCodeColor = Color(0xFFC7254E);
  static const Color darkInlineCodeColor = Color(0xFFE8912D);
  static const Color lightCodeBackground = Color(0x0F000000);
  static const Color darkCodeBackground = Color(0x17FFFFFF);

  final Color textColor;
  final Color mutedColor;
  final Color accentColor;
  final Color codeBackground;
  final Color inlineCodeColor;

  static const List<String> monospaceFallback = [
    'Menlo',
    'Roboto Mono',
    'Courier New',
    'Courier',
  ];

  TextStyle lineStyle(TextStyle base, NoteEditLineKind line) {
    final size = base.fontSize ?? 17;
    switch (line.type) {
      case NoteBlockType.heading1:
        return base.copyWith(
          fontSize: size * 1.45,
          fontWeight: FontWeight.w800,
          height: 1.4,
        );
      case NoteBlockType.heading2:
        return base.copyWith(
          fontSize: size * 1.3,
          fontWeight: FontWeight.w800,
          height: 1.45,
        );
      case NoteBlockType.heading3:
        return base.copyWith(
          fontSize: size * 1.15,
          fontWeight: FontWeight.w800,
          height: 1.5,
        );
      case NoteBlockType.code:
        return monospace(base);
      case NoteBlockType.quote:
        return base.copyWith(color: mutedColor, fontStyle: FontStyle.italic);
      case NoteBlockType.checklist:
        if (line.checked) {
          return base.copyWith(
            color: mutedColor,
            decoration: TextDecoration.lineThrough,
            decorationColor: mutedColor,
          );
        }
        return base;
      case NoteBlockType.paragraph:
      case NoteBlockType.bullet:
      case NoteBlockType.numbered:
        return base;
    }
  }

  TextStyle prefixStyle(TextStyle lineStyle, NoteEditLineKind line) {
    return lineStyle.copyWith(
      color: line.type == NoteBlockType.quote ? mutedColor : accentColor,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.normal,
      decoration: TextDecoration.none,
    );
  }

  TextStyle monospace(TextStyle base) {
    final size = base.fontSize ?? 17;
    return base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: monospaceFallback,
      fontSize: size * 0.9,
    );
  }

  TextStyle inlineStyle(
    TextStyle lineStyle,
    NoteInlineStyle style, {
    required bool isLink,
  }) {
    var result = lineStyle;
    final decorations = <TextDecoration>[
      if (lineStyle.decoration != null &&
          lineStyle.decoration != TextDecoration.none)
        lineStyle.decoration!,
    ];
    if (style.bold) {
      result = result.copyWith(fontWeight: FontWeight.w800);
    }
    if (style.italic) {
      result = result.copyWith(fontStyle: FontStyle.italic);
    }
    if (style.code) {
      result = monospace(result).copyWith(color: inlineCodeColor);
    }
    if (style.strike) {
      decorations.add(TextDecoration.lineThrough);
    }
    if (isLink) {
      result =
          result.copyWith(color: accentColor, decorationColor: accentColor);
      decorations.add(TextDecoration.underline);
    }
    if (decorations.isNotEmpty) {
      result = result.copyWith(decoration: TextDecoration.combine(decorations));
    }
    return result;
  }
}

abstract class NoteEditLineKind {
  NoteBlockType get type;
  bool get checked;
}

class NoteEditorTheme extends InheritedWidget {
  const NoteEditorTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final NoteEditorThemeData data;

  static NoteEditorThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NoteEditorTheme>()?.data;
  }

  @override
  bool updateShouldNotify(NoteEditorTheme oldWidget) {
    return oldWidget.data.textColor != data.textColor ||
        oldWidget.data.mutedColor != data.mutedColor ||
        oldWidget.data.accentColor != data.accentColor ||
        oldWidget.data.codeBackground != data.codeBackground ||
        oldWidget.data.inlineCodeColor != data.inlineCodeColor;
  }
}
