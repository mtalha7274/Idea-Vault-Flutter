import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:provider/provider.dart';

import '../core/constants/view_constants.dart';
import '../core/extensions/int.dart';
import '../viewmodels/providers/theme_provider.dart';
import 'translated_text.dart';
import '../views/ideas/idea_vault_theme.dart';

const double _editorBodyTextSize = 17;
const double _previewH2Scale = 1.15;

/// Width of the fade strip before the Organize control (toolbar surface → opaque).
const double _toolbarScrollFadeWidth = 44;

/// Slightly larger than format tools so AI organise reads as the primary toolbar action.
const double _toolbarOrganizeIconSize = 24;

class IdeaMarkdownEditor extends StatelessWidget {
  const IdeaMarkdownEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.isPreviewMode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final bool isPreviewMode;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: isPreviewMode
            ? ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  return _PreviewPane(
                    markdown: value.text,
                    placeholder: placeholder,
                  );
                },
              )
            : TextField(
                key: const Key('idea-markdown-text-field'),
                controller: controller,
                focusNode: focusNode,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                scrollPhysics: const NeverScrollableScrollPhysics(),
                inputFormatters: [_BulletListFormatter()],
                style: ideaVaultBody(
                  context,
                  size: _editorBodyTextSize,
                  weight: FontWeight.w500,
                  color: theme.primaryText,
                  height: 1.72,
                ),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: ideaVaultBody(
                    context,
                    size: _editorBodyTextSize,
                    weight: FontWeight.w500,
                    color: theme.outline,
                    height: 1.72,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
      ),
    );
  }
}

class IdeaEditorToolbarContainer extends StatelessWidget {
  const IdeaEditorToolbarContainer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isPreviewMode,
    required this.onPreviewToggle,
    required this.onOrganize,
    required this.onImageText,
    this.organizeEnabled = true,
    this.imageTextEnabled = true,
    this.exceedsAiCharacterLimit = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isPreviewMode;
  final VoidCallback onPreviewToggle;
  final VoidCallback onOrganize;
  final VoidCallback onImageText;
  final bool organizeEnabled;
  final bool imageTextEnabled;
  final bool exceedsAiCharacterLimit;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
        child: IdeaEditorToolbar(
          controller: controller,
          focusNode: focusNode,
          isPreviewMode: isPreviewMode,
          onPreviewToggle: onPreviewToggle,
          onOrganize: onOrganize,
          onImageText: onImageText,
          organizeEnabled: organizeEnabled,
          imageTextEnabled: imageTextEnabled,
          exceedsAiCharacterLimit: exceedsAiCharacterLimit,
        ),
      ),
    );
  }
}

class IdeaEditorToolbar extends StatelessWidget {
  const IdeaEditorToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isPreviewMode,
    required this.onPreviewToggle,
    required this.onOrganize,
    required this.onImageText,
    this.organizeEnabled = true,
    this.imageTextEnabled = true,
    this.exceedsAiCharacterLimit = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isPreviewMode;
  final VoidCallback onPreviewToggle;
  final VoidCallback onOrganize;
  final VoidCallback onImageText;
  final bool organizeEnabled;
  final bool imageTextEnabled;
  final bool exceedsAiCharacterLimit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final theme = context.watch<ThemeProvider>().baseTheme;
              final fadeColor = theme.surface;
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ToolbarIconButton(
                          icon: Icons.title,
                          tooltip: 'Heading',
                          iconSize: 26,
                          enabled: !isPreviewMode,
                          onPressed: () =>
                              _wrapSelection(controller, '## ', '', true),
                        ),
                        _ToolbarIconButton(
                          icon: Icons.format_bold,
                          tooltip: 'Bold',
                          enabled: !isPreviewMode,
                          onPressed: () =>
                              _wrapSelection(controller, '**', '**', false),
                        ),
                        _ToolbarIconButton(
                          icon: Icons.format_italic,
                          tooltip: 'Italic',
                          enabled: !isPreviewMode,
                          onPressed: () =>
                              _wrapSelection(controller, '_', '_', false),
                        ),
                        _ToolbarIconButton(
                          key: const Key('idea-editor-image-text'),
                          icon: Icons.camera_alt_rounded,
                          tooltip:
                              ViewConstants.ideaEditorImageTextTooltip.tr(),
                          enabled: imageTextEnabled && !isPreviewMode,
                          onPressed: onImageText,
                        ),
                        _ToolbarIconButton(
                          icon: Icons.format_list_bulleted,
                          tooltip: 'Bullet List',
                          enabled: !isPreviewMode,
                          onPressed: () =>
                              _wrapSelection(controller, '- ', '', true),
                        ),
                        _ToolbarIconButton(
                          icon: Icons.code,
                          tooltip: 'Code Block',
                          enabled: !isPreviewMode,
                          onPressed: () => _wrapSelection(
                              controller, '```\n', '\n```', false),
                        ),
                        const SizedBox(width: 18),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: _toolbarScrollFadeWidth,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              fadeColor.withValues(alpha: 0),
                              fadeColor,
                            ],
                            stops: const [0.15, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 6),
        _ToolbarOrganizeButton(
          onPressed: onOrganize,
          enabled: organizeEnabled,
          exceedsCharacterLimit: exceedsAiCharacterLimit,
        ),
        const SizedBox(width: 8),
        _ToolbarIconButton(
          key: const Key('idea-markdown-preview-toggle'),
          icon: isPreviewMode ? Icons.edit_rounded : Icons.remove_red_eye,
          tooltip: isPreviewMode ? 'Edit' : 'Preview',
          onPressed: onPreviewToggle,
          rightPadding: 2,
        ),
      ],
    );
  }

  void _wrapSelection(
    TextEditingController controller,
    String prefix,
    String suffix,
    bool linePrefix,
  ) {
    final value = controller.value;
    final text = value.text;
    final selection = value.selection;

    if (linePrefix) {
      final start = selection.start < 0 ? text.length : selection.start;
      final end = selection.end < 0 ? text.length : selection.end;

      final lineStartIndex = text.lastIndexOf('\n', start == 0 ? 0 : start - 1);
      final lineStart = lineStartIndex == -1 ? 0 : lineStartIndex + 1;

      final lineEndIndex = end < text.length ? text.indexOf('\n', end) : -1;
      final lineEnd = lineEndIndex == -1 ? text.length : lineEndIndex;

      final selectedLines = text.substring(lineStart, lineEnd);
      final lines = selectedLines.split('\n');

      final allHavePrefix = lines.every((line) => line.startsWith(prefix));

      final transformedLines = lines.map((line) {
        if (allHavePrefix) {
          return line.startsWith(prefix) ? line.substring(prefix.length) : line;
        } else {
          return line.startsWith(prefix) ? line : '$prefix$line';
        }
      }).toList();

      final transformedText = transformedLines.join('\n');
      final updatedText =
          text.replaceRange(lineStart, lineEnd, transformedText);

      final offsetDelta = allHavePrefix ? -prefix.length : prefix.length;
      final newStart = start + (start >= lineStart ? offsetDelta : 0);
      final newEnd = end + (lines.length * offsetDelta);

      controller.value = TextEditingValue(
        text: updatedText,
        selection: TextSelection(
          baseOffset: math.max(0, math.min(updatedText.length, newStart)),
          extentOffset: math.max(0, math.min(updatedText.length, newEnd)),
        ),
      );
      focusNode.requestFocus();
      return;
    }

    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final selectedText = text.substring(start, end);
    final replacement = '$prefix$selectedText$suffix';
    final updatedText = text.replaceRange(start, end, replacement);
    final nextOffset = selectedText.isEmpty
        ? start + prefix.length
        : start + replacement.length;

    controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    focusNode.requestFocus();
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.markdown,
    required this.placeholder,
  });

  final String markdown;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final bodyStyle = ideaVaultBody(
      context,
      size: _editorBodyTextSize,
      weight: FontWeight.w500,
      color: theme.primaryText,
      height: 1.72,
    );
    if (markdown.trim().isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          placeholder,
          style: bodyStyle.copyWith(color: theme.outline),
        ),
      );
    }

    // Count only leading newlines (not other whitespace)
    var leadingNewlines = 0;
    for (var i = 0; i < markdown.length; i++) {
      if (markdown[i] == '\n') {
        leadingNewlines++;
      } else {
        break;
      }
    }

    // Remove leading newlines from original markdown and replace with preserved version
    final markdownWithoutLeadingNewlines = markdown.substring(leadingNewlines);
    final leadingSpacing = '\u200B\n' * leadingNewlines;

    // Preserve double newlines throughout the content
    final preservedMarkdown = leadingSpacing +
        markdownWithoutLeadingNewlines.replaceAll('\n\n', '\n\u200B\n');

    return Align(
      alignment: Alignment.topLeft,
      child: MarkdownBlock(
        data: preservedMarkdown,
        config: _previewMarkdownConfig(bodyStyle),
        generator: MarkdownGenerator(linesMargin: EdgeInsets.zero),
      ),
    );
  }

  MarkdownConfig _previewMarkdownConfig(TextStyle bodyStyle) {
    return MarkdownConfig(
      configs: [
        PConfig(textStyle: bodyStyle),
        _PreviewHeadingConfig(MarkdownTag.h1.name, bodyStyle),
        _PreviewHeadingConfig(
          MarkdownTag.h2.name,
          bodyStyle,
          fontScale: _previewH2Scale,
        ),
        _PreviewHeadingConfig(MarkdownTag.h3.name, bodyStyle),
        _PreviewHeadingConfig(MarkdownTag.h4.name, bodyStyle),
        _PreviewHeadingConfig(MarkdownTag.h5.name, bodyStyle),
        _PreviewHeadingConfig(MarkdownTag.h6.name, bodyStyle),
      ],
    );
  }
}

class _PreviewHeadingConfig extends HeadingConfig {
  const _PreviewHeadingConfig(
    this.tag,
    this.baseStyle, {
    this.fontScale = 1,
  });

  @override
  final String tag;

  final TextStyle baseStyle;
  final double fontScale;

  @override
  TextStyle get style {
    final baseSize = baseStyle.fontSize ?? _editorBodyTextSize;
    return baseStyle.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: baseSize * fontScale,
    );
  }

  @override
  EdgeInsets get padding => EdgeInsets.zero;
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize,
    this.enabled = true,
    this.rightPadding = 8,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final double? iconSize;
  final bool enabled;
  final double rightPadding;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final foregroundColor =
        enabled ? theme.primary : theme.textMuted.withValues(alpha: 0.55);

    return Padding(
      padding: EdgeInsets.only(right: rightPadding),
      child: Tooltip(
        message: tooltip,
        child: IgnorePointer(
          ignoring: !enabled,
          child: IconButton(
            onPressed: enabled ? onPressed : () {},
            style: IconButton.styleFrom(
              backgroundColor: theme.surfaceLow,
              foregroundColor: foregroundColor,
            ),
            icon: Icon(icon, size: iconSize),
          ),
        ),
      ),
    );
  }
}

class _ToolbarOrganizeButton extends StatelessWidget {
  const _ToolbarOrganizeButton({
    required this.onPressed,
    required this.enabled,
    required this.exceedsCharacterLimit,
  });

  final VoidCallback onPressed;
  final bool enabled;
  final bool exceedsCharacterLimit;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final overLimit = exceedsCharacterLimit;
    final foregroundColor = !enabled
        ? theme.textMuted.withValues(alpha: 0.55)
        : overLimit
            ? theme.warning
            : theme.primary;
    final backgroundColor = enabled && overLimit
        ? theme.warning.withValues(alpha: 0.08)
        : theme.surfaceLow;

    return Tooltip(
      message: exceedsCharacterLimit
          ? 'Long text — review before organizing'
          : 'Organise with AI',
      child: IgnorePointer(
        ignoring: !enabled,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            IconButton(
              key: const Key('idea-editor-organize'),
              onPressed: enabled ? onPressed : () {},
              style: IconButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
              ),
              icon: Icon(
                overLimit
                    ? Icons.warning_amber_rounded
                    : Icons.auto_fix_high_rounded,
                size: _toolbarOrganizeIconSize,
              ),
            ),
            Positioned(
              top: 3.d,
              left: 3.d,
              child: IgnorePointer(
                child: Container(
                  width: 16.d,
                  height: 16.d,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.purple,
                    shape: BoxShape.circle,
                  ),
                  child: TranslatedText(
                    ViewConstants.organizeToolbarAiBadge,
                    style: TextStyle(
                      fontSize: 8.f,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletListFormatter extends TextInputFormatter {
  static final _bulletPattern = RegExp(r'^(\s*)(- )(.*)$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) {
      return newValue;
    }

    final oldText = oldValue.text;
    final newText = newValue.text;

    if (newText.length <= oldText.length) {
      return newValue;
    }

    final insertedText = newText.substring(
      oldValue.selection.start,
      oldValue.selection.start + (newText.length - oldText.length),
    );

    if (insertedText != '\n') {
      return newValue;
    }

    final cursorOffset = oldValue.selection.start;
    final lineStart = newText.lastIndexOf('\n', cursorOffset - 1) + 1;
    final lineEnd = newText.indexOf('\n', cursorOffset);
    final actualLineEnd = lineEnd == -1 ? newText.length : lineEnd;
    final previousLine = newText.substring(lineStart, cursorOffset);

    final match = _bulletPattern.firstMatch(previousLine);
    if (match == null) {
      return newValue;
    }

    final indent = match.group(1) ?? '';
    final bullet = match.group(2) ?? '';
    final content = match.group(3) ?? '';

    if (content.trim().isEmpty) {
      final beforeBullet = newText.substring(0, lineStart);
      final afterLine = actualLineEnd < newText.length
          ? newText.substring(actualLineEnd)
          : '';
      final updatedText = beforeBullet + afterLine;
      final newCursor = lineStart;

      return TextEditingValue(
        text: updatedText,
        selection: TextSelection.collapsed(offset: newCursor),
      );
    }

    final beforeCursor = newText.substring(0, cursorOffset + 1);
    final afterCursor = newText.substring(cursorOffset + 1);
    final updatedText = '$beforeCursor$indent$bullet$afterCursor';
    final newCursor = cursorOffset + 1 + indent.length + bullet.length;

    return TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}
