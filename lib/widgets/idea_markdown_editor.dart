import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:provider/provider.dart';

import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';

class IdeaMarkdownEditor extends StatefulWidget {
  const IdeaMarkdownEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.placeholder,
    required this.initialPreviewMode,
    required this.onPreviewModeChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final bool initialPreviewMode;
  final ValueChanged<bool> onPreviewModeChanged;

  @override
  State<IdeaMarkdownEditor> createState() => IdeaMarkdownEditorState();
}

class IdeaMarkdownEditorState extends State<IdeaMarkdownEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late bool isPreviewMode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    isPreviewMode = widget.initialPreviewMode;
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant IdeaMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text &&
        widget.initialValue != oldWidget.initialValue) {
      final cursorOffset = math.min(
        widget.initialValue.length,
        math.max(0, _controller.selection.extentOffset),
      );
      _controller.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: cursorOffset),
      );
    }

    if (widget.initialPreviewMode != oldWidget.initialPreviewMode &&
        widget.initialPreviewMode != isPreviewMode) {
      setState(() {
        isPreviewMode = widget.initialPreviewMode;
      });

      if (isPreviewMode) {
        _focusNode.unfocus();
      }
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Column(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IdeaEditorToolbar(
                    controller: _controller,
                    focusNode: _focusNode,
                    isPreviewMode: isPreviewMode,
                    onPreviewToggle: _togglePreviewMode,
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: isPreviewMode
                        ? _PreviewPane(
                            markdown: _controller.text,
                            placeholder: widget.placeholder,
                          )
                        : TextField(
                            key: const Key('idea-markdown-text-field'),
                            controller: _controller,
                            focusNode: _focusNode,
                            expands: true,
                            minLines: null,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            style: ideaVaultBody(
                              context,
                              size: 18,
                              weight: FontWeight.w500,
                              color: theme.primaryText,
                              height: 1.72,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.placeholder,
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleTextChanged() {
    widget.onChanged(_controller.text);
  }

  void insertRecognizedText(String dictatedText) {
    final normalizedText = dictatedText.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    final selection = _controller.selection;
    final currentText = _controller.text;
    final canInsertAtCursor = !isPreviewMode &&
        _focusNode.hasFocus &&
        selection.isValid &&
        selection.start >= 0 &&
        selection.end >= 0;

    if (canInsertAtCursor) {
      final before = currentText.substring(0, selection.start);
      final after = currentText.substring(selection.end);
      final middle = _dictatedTextOnOwnLine(before, after, normalizedText);
      final updatedText = before + middle + after;
      final nextOffset = before.length + middle.length;
      _controller.value = TextEditingValue(
        text: updatedText,
        selection: TextSelection.collapsed(offset: nextOffset),
      );
      return;
    }

    final middle = _dictatedTextOnOwnLine(currentText, '', normalizedText);
    final updatedText = currentText + middle;
    _controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: updatedText.length),
    );
  }

  void _togglePreviewMode() {
    final nextMode = !isPreviewMode;
    setState(() {
      isPreviewMode = nextMode;
    });
    widget.onPreviewModeChanged(nextMode);

    if (nextMode) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }
}

/// Builds the dictated chunk so it always starts on its own line.
///
/// [before] and [after] are the document segments around the insertion point.
String _dictatedTextOnOwnLine(String before, String after, String dictated) {
  if (before.isEmpty && after.isEmpty) {
    return dictated;
  }
  if (before.isEmpty && after.isNotEmpty) {
    return '$dictated\n';
  }
  if (before.isNotEmpty && !before.endsWith('\n')) {
    return '\n$dictated';
  }
  return dictated;
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
    if (markdown.trim().isEmpty) {
      final theme = context.watch<ThemeProvider>().baseTheme;
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          placeholder,
          style: ideaVaultBody(
            context,
            size: 18,
            weight: FontWeight.w500,
            color: theme.outline,
            height: 1.72,
          ),
        ),
      );
    }

    return MarkdownWidget(
      data: markdown,
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
    final foregroundColor = enabled
        ? theme.primary
        : theme.textMuted.withValues(alpha: 0.55);

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
