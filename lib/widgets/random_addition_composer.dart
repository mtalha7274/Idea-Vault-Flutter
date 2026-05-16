import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/view_constants.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';

class RandomAdditionComposer extends StatelessWidget {
  const RandomAdditionComposer({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.fieldKey,
    this.sendButtonKey,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final Key? fieldKey;
  final Key? sendButtonKey;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.outlineSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: ViewConstants.randomAdditionsComposerHint.tr(),
                  border: InputBorder.none,
                  isDense: true,
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
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: sendButtonKey,
              onPressed: onSubmit,
              style: IconButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: theme.onPrimary,
                fixedSize: const Size(44, 44),
              ),
              icon: const Icon(Icons.arrow_upward_rounded),
              tooltip: ViewConstants.randomAdditionsSendTooltip.tr(),
            ),
          ],
        ),
      ),
    );
  }
}
