import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';
import '../idea_vault_action_button.dart';
import '../translated_text.dart';

Future<IdeaEditorOptionsSheetAction?> showIdeaEditorOptionsSheet(
  BuildContext context,
) {
  return showModalBottomSheet<IdeaEditorOptionsSheetAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (sheetContext) {
      final sheetTheme = sheetContext.watch<ThemeProvider>().baseTheme;
      final errorColor = Theme.of(sheetContext).colorScheme.error;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: sheetTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: sheetTheme.outline.withValues(alpha: 0.12),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: sheetTheme.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TranslatedText(
                  ViewConstants.ideaEditorOptionsSheetTitle,
                  style: ideaVaultHeadline(
                    sheetContext,
                    size: 22,
                    weight: FontWeight.w800,
                    height: 1.2,
                    color: sheetTheme.primaryText,
                  ),
                ),
                const Gap(20),
                IdeaVaultActionButton(
                  key: const Key('idea-editor-option-export-ai'),
                  label: ViewConstants.exportForAiScreenTitle,
                  useTranslatedLabel: true,
                  backgroundColor: sheetTheme.surfaceLow,
                  foregroundColor: sheetTheme.primary,
                  height: 48,
                  textSize: 14,
                  onPressed: () => Navigator.of(sheetContext).pop(
                    IdeaEditorOptionsSheetAction.exportForAI,
                  ),
                ),
                const Gap(10),
                IdeaVaultActionButton(
                  key: const Key('idea-editor-option-export-pdf'),
                  label: ViewConstants.exportToPdfButton,
                  useTranslatedLabel: true,
                  backgroundColor: sheetTheme.surfaceLow,
                  foregroundColor: sheetTheme.primary,
                  height: 48,
                  textSize: 14,
                  onPressed: () => Navigator.of(sheetContext).pop(
                    IdeaEditorOptionsSheetAction.exportToPDF,
                  ),
                ),
                const Gap(10),
                IdeaVaultActionButton(
                  key: const Key('idea-editor-option-delete-idea'),
                  label: ViewConstants.ideaEditorOptionsDeleteIdea,
                  useTranslatedLabel: true,
                  backgroundColor: errorColor.withValues(alpha: 0.1),
                  foregroundColor: errorColor,
                  height: 48,
                  textSize: 14,
                  onPressed: () => Navigator.of(sheetContext).pop(
                    IdeaEditorOptionsSheetAction.deleteIdea,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

enum IdeaEditorOptionsSheetAction {
  exportForAI,
  exportToPDF,
  deleteIdea,
}
