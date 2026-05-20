import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';

class IdeaVaultPillTextField extends StatefulWidget {
  const IdeaVaultPillTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.fieldKey,
    this.leading,
    this.trailing,
    this.minLines = 1,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.sentences,
    this.textInputAction,
    this.useShadow = false,
  });

  final TextEditingController controller;
  final String hintText;
  final Key? fieldKey;
  final Widget? leading;
  final Widget? trailing;
  final int minLines;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final bool useShadow;

  @override
  State<IdeaVaultPillTextField> createState() => _IdeaVaultPillTextFieldState();
}

class _IdeaVaultPillTextFieldState extends State<IdeaVaultPillTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final borderColor = _focusNode.hasFocus
        ? theme.primary.withValues(alpha: 0.6)
        : theme.primary.withValues(alpha: 0.2);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: borderColor),
        boxShadow: widget.useShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.leading != null ? 12 : 14,
          8,
          widget.trailing != null ? 8 : 12,
          8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.leading != null) ...[
              widget.leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                key: widget.fieldKey,
                controller: widget.controller,
                focusNode: _focusNode,
                minLines: widget.minLines,
                maxLines: widget.maxLines,
                textCapitalization: widget.textCapitalization,
                textInputAction: widget.textInputAction,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.all(8),
                  hintStyle: ideaVaultBody(
                    context,
                    size: 15,
                    weight: FontWeight.w500,
                    color: theme.outline,
                  ),
                ),
                style: ideaVaultBody(
                  context,
                  size: 15,
                  weight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 8),
              widget.trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
