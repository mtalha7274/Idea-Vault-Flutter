import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/view_constants.dart';
import '../viewmodels/providers/theme_provider.dart';
import 'idea_vault_pill_text_field.dart';

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
    return IdeaVaultPillTextField(
      fieldKey: fieldKey,
      controller: controller,
      hintText: ViewConstants.randomAdditionsComposerHint.tr(),
      minLines: 1,
      maxLines: 2,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.newline,
      useShadow: true,
      trailing: IconButton.filled(
        key: sendButtonKey,
        onPressed: onSubmit,
        style: IconButton.styleFrom(
          backgroundColor: theme.primary,
          foregroundColor: theme.onPrimary,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(38, 38),
          fixedSize: const Size(38, 38),
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.arrow_upward_rounded, size: 20),
        tooltip: ViewConstants.randomAdditionsSendTooltip.tr(),
      ),
    );
  }
}
