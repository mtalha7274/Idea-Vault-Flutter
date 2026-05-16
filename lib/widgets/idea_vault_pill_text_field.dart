import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';

class IdeaVaultPillTextField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: theme.primary.withValues(alpha: 0.6)),
        boxShadow: useShadow
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
          leading != null ? 12 : 14,
          8,
          trailing != null ? 8 : 12,
          8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: controller,
                minLines: minLines,
                maxLines: maxLines,
                textCapitalization: textCapitalization,
                textInputAction: textInputAction,
                decoration: InputDecoration(
                  hintText: hintText,
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
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
