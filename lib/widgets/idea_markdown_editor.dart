import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:provider/provider.dart';

import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';

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
                style: ideaVaultBody(
                  context,
                  size: 18,
                  weight: FontWeight.w500,
                  color: theme.primaryText,
                  height: 1.72,
                ),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: ideaVaultBody(
                    context,
                    size: 18,
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isPreviewMode;
  final VoidCallback onPreviewToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        child: IdeaEditorToolbar(
          controller: controller,
          focusNode: focusNode,
          isPreviewMode: isPreviewMode,
          onPreviewToggle: onPreviewToggle,
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isPreviewMode;
  final VoidCallback onPreviewToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ToolbarIconButton(
                  icon: Icons.title,
                  tooltip: 'Text',
                  enabled: !isPreviewMode,
                  onPressed: () => _wrapSelection(controller, '# ', '', true),
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
                  onPressed: () => _wrapSelection(controller, '_', '_', false),
                ),
                _ToolbarIconButton(
                  icon: Icons.format_list_bulleted,
                  tooltip: 'Bullet List',
                  enabled: !isPreviewMode,
                  onPressed: () => _wrapSelection(controller, '- ', '', true),
                ),
                _ToolbarIconButton(
                  icon: Icons.code,
                  tooltip: 'Code Block',
                  enabled: !isPreviewMode,
                  onPressed: () =>
                      _wrapSelection(controller, '```\n', '\n```', false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ToolbarIconButton(
          key: const Key('idea-markdown-preview-toggle'),
          icon: isPreviewMode ? Icons.edit_rounded : Icons.remove_red_eye,
          tooltip: isPreviewMode ? 'Edit' : 'Preview',
          onPressed: onPreviewToggle,
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
      final cursorOffset = selection.start < 0 ? text.length : selection.start;
      final lineBreakIndex =
          text.lastIndexOf('\n', cursorOffset == 0 ? 0 : cursorOffset - 1);
      final lineStart = lineBreakIndex == -1 ? 0 : lineBreakIndex + 1;
      final hasPrefix = text.startsWith(prefix, lineStart);
      final updatedText = hasPrefix
          ? text.replaceRange(lineStart, lineStart + prefix.length, '')
          : text.replaceRange(lineStart, lineStart, prefix);
      final offsetDelta = hasPrefix ? -prefix.length : prefix.length;
      final baseOffset = selection.baseOffset >= lineStart
          ? selection.baseOffset + offsetDelta
          : selection.baseOffset;
      final extentOffset = selection.extentOffset >= lineStart
          ? selection.extentOffset + offsetDelta
          : selection.extentOffset;

      controller.value = TextEditingValue(
        text: updatedText,
        selection: TextSelection(
          baseOffset: math.max(0, math.min(updatedText.length, baseOffset)),
          extentOffset: math.max(0, math.min(updatedText.length, extentOffset)),
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
      size: 18,
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

    return MarkdownBlock(
      data: markdown,
      config: _previewMarkdownConfig(bodyStyle),
    );
  }

  MarkdownConfig _previewMarkdownConfig(TextStyle bodyStyle) {
    final headingStyle = bodyStyle.copyWith(fontWeight: FontWeight.w700);

    return MarkdownConfig(
      configs: [
        PConfig(textStyle: bodyStyle),
        H1Config(style: headingStyle),
        H2Config(style: headingStyle),
        H3Config(style: headingStyle),
        H4Config(style: headingStyle),
        H5Config(style: headingStyle),
        H6Config(style: headingStyle),
      ],
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final foregroundColor =
        enabled ? theme.primary : theme.textMuted.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
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
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}
