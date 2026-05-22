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
    this.autofocus = false,
    this.onMultilineChanged,
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
  final bool autofocus;
  final ValueChanged<bool>? onMultilineChanged;

  @override
  State<IdeaVaultPillTextField> createState() => _IdeaVaultPillTextFieldState();
}

class _IdeaVaultPillTextFieldState extends State<IdeaVaultPillTextField> {
  late final FocusNode _focusNode;
  double? _textMaxWidth;
  bool _isMultiline = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_scheduleMultilineCheck);
  }

  @override
  void didUpdateWidget(covariant IdeaVaultPillTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleMultilineCheck);
      widget.controller.addListener(_scheduleMultilineCheck);
      _scheduleMultilineCheck();
    }
  }

  void _onFocusChange() {
    setState(() {});
  }

  void _scheduleMultilineCheck() {
    if (widget.onMultilineChanged == null || widget.maxLines <= 1) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkMultiline();
      }
    });
  }

  void _checkMultiline() {
    if (widget.onMultilineChanged == null || widget.maxLines <= 1) {
      return;
    }

    final maxWidth = _textMaxWidth;
    if (maxWidth == null) {
      return;
    }

    final nextIsMultiline = _computeIsMultiline(maxWidth);
    if (nextIsMultiline == _isMultiline) {
      return;
    }

    _isMultiline = nextIsMultiline;
    widget.onMultilineChanged!.call(nextIsMultiline);
  }

  bool _computeIsMultiline(double maxWidth) {
    final text = widget.controller.text;
    if (text.isEmpty) {
      return false;
    }
    if (text.contains('\n')) {
      return true;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: ideaVaultBody(
          context,
          size: 15,
          weight: FontWeight.w600,
          height: 1.35,
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: widget.maxLines,
    )..layout(maxWidth: maxWidth);

    return painter.computeLineMetrics().length > 1;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleMultilineCheck);
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (_textMaxWidth != constraints.maxWidth) {
                    _textMaxWidth = constraints.maxWidth;
                    _scheduleMultilineCheck();
                  }
                  return TextField(
                    key: widget.fieldKey,
                    controller: widget.controller,
                    focusNode: _focusNode,
                    autofocus: widget.autofocus,
                    minLines: widget.minLines,
                    maxLines: widget.maxLines,
                    textCapitalization: widget.textCapitalization,
                    textInputAction: widget.textInputAction,
                    onChanged: widget.onMultilineChanged == null
                        ? null
                        : (_) => _scheduleMultilineCheck(),
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
                  );
                },
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
