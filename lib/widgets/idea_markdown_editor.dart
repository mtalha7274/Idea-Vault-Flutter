import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../views/ideas/idea_vault_theme.dart';

class IdeaMarkdownEditor extends StatefulWidget {
  const IdeaMarkdownEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.placeholder,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;
  final String placeholder;

  @override
  State<IdeaMarkdownEditor> createState() => _IdeaMarkdownEditorState();
}

class _IdeaMarkdownEditorState extends State<IdeaMarkdownEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool isPreviewMode = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant IdeaMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue == _controller.text ||
        widget.initialValue == oldWidget.initialValue) {
      return;
    }

    final cursorOffset = math.min(
      widget.initialValue.length,
      math.max(0, _controller.selection.extentOffset),
    );
    _controller.value = TextEditingValue(
      text: widget.initialValue,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
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
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: const Key('idea-markdown-preview-toggle'),
              onPressed: _togglePreviewMode,
              style: IconButton.styleFrom(
                backgroundColor: IdeaVaultPalette.surfaceLow(context),
                foregroundColor: IdeaVaultPalette.primary(context),
              ),
              icon: Icon(
                isPreviewMode ? Icons.edit_rounded : Icons.remove_red_eye,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: IdeaVaultPalette.surface(context),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isPreviewMode) ...[
                    IdeaEditorToolbar(
                      controller: _controller,
                      focusNode: _focusNode,
                    ),
                    const SizedBox(height: 14),
                  ],
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
                              color: IdeaVaultPalette.text(context),
                              height: 1.72,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.placeholder,
                              hintStyle: ideaVaultBody(
                                context,
                                size: 18,
                                weight: FontWeight.w500,
                                color: IdeaVaultPalette.outline(context),
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

  void _togglePreviewMode() {
    setState(() {
      isPreviewMode = !isPreviewMode;
    });

    if (isPreviewMode) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }
}

class IdeaEditorToolbar extends StatelessWidget {
  const IdeaEditorToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ToolbarIconButton(
            icon: Icons.title,
            onPressed: () => _wrapSelection(controller, '# ', '', true),
          ),
          _ToolbarIconButton(
            icon: Icons.format_bold,
            onPressed: () => _wrapSelection(controller, '**', '**', false),
          ),
          _ToolbarIconButton(
            icon: Icons.format_italic,
            onPressed: () => _wrapSelection(controller, '_', '_', false),
          ),
          _ToolbarIconButton(
            icon: Icons.format_list_bulleted,
            onPressed: () => _wrapSelection(controller, '- ', '', true),
          ),
          _ToolbarIconButton(
            icon: Icons.code,
            onPressed: () =>
                _wrapSelection(controller, '```\n', '\n```', false),
          ),
        ],
      ),
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
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          placeholder,
          style: ideaVaultBody(
            context,
            size: 18,
            weight: FontWeight.w500,
            color: IdeaVaultPalette.outline(context),
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
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: IdeaVaultPalette.surfaceLow(context),
          foregroundColor: IdeaVaultPalette.primary(context),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
