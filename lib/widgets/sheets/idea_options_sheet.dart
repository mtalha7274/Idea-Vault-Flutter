import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';
import '../translated_text.dart';

Future<IdeaEditorOptionsSheetAction?> showIdeaEditorOptionsSheet(
  BuildContext context, {
  bool isUnsavedDraft = false,
  bool? isNoteLocked,
}) {
  return showModalBottomSheet<IdeaEditorOptionsSheetAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (sheetContext) {
      final sheetTheme = sheetContext.watch<ThemeProvider>().baseTheme;
      final errorColor = Theme.of(sheetContext).colorScheme.error;
      _SheetOptionRow row({
        required Key key,
        required IconData icon,
        required String labelKey,
        required IdeaEditorOptionsSheetAction action,
        bool isDestructive = false,
      }) {
        return _SheetOptionRow(
          key: key,
          icon: icon,
          labelKey: labelKey,
          color: isDestructive ? errorColor : sheetTheme.primaryText,
          iconColor: isDestructive ? errorColor : sheetTheme.primary,
          onTap: () => Navigator.of(sheetContext).pop(action),
        );
      }

      return DecoratedBox(
        decoration: BoxDecoration(
          color: sheetTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12),
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
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TranslatedText(
                    ViewConstants.ideaEditorOptionsSheetTitle,
                    style: ideaVaultHeadline(
                      sheetContext,
                      size: 20,
                      weight: FontWeight.w800,
                      height: 1.2,
                      color: sheetTheme.primaryText,
                    ),
                  ),
                ),
                const Gap(8),
                if (isUnsavedDraft)
                  row(
                    key: const Key('idea-editor-option-discard'),
                    icon: Icons.delete_sweep_outlined,
                    labelKey: ViewConstants.editorDraftDiscard,
                    action: IdeaEditorOptionsSheetAction.discardDraft,
                    isDestructive: true,
                  )
                else ...[
                  if (isNoteLocked != null)
                    row(
                      key: const Key('idea-editor-option-lock'),
                      icon: isNoteLocked
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline_rounded,
                      labelKey: isNoteLocked
                          ? ViewConstants.ideaEditorOptionsUnlockNote
                          : ViewConstants.ideaEditorOptionsLockNote,
                      action: isNoteLocked
                          ? IdeaEditorOptionsSheetAction.unlockNote
                          : IdeaEditorOptionsSheetAction.lockNote,
                    ),
                  row(
                    key: const Key('idea-editor-option-export-ai'),
                    icon: Icons.auto_awesome_rounded,
                    labelKey: ViewConstants.exportForAiScreenTitle,
                    action: IdeaEditorOptionsSheetAction.exportForAI,
                  ),
                  row(
                    key: const Key('idea-editor-option-export-pdf'),
                    icon: Icons.picture_as_pdf_rounded,
                    labelKey: ViewConstants.exportToPdfButton,
                    action: IdeaEditorOptionsSheetAction.exportToPDF,
                  ),
                  row(
                    key: const Key('idea-editor-option-delete-idea'),
                    icon: Icons.delete_outline_rounded,
                    labelKey: ViewConstants.ideaEditorOptionsDeleteIdea,
                    action: IdeaEditorOptionsSheetAction.deleteIdea,
                    isDestructive: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

enum IdeaEditorOptionsSheetAction {
  lockNote,
  unlockNote,
  exportForAI,
  exportToPDF,
  deleteIdea,
  discardDraft,
}

class _SheetOptionRow extends StatelessWidget {
  const _SheetOptionRow({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String labelKey;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22.d, color: iconColor),
              Gap(16.d),
              Expanded(
                child: TranslatedText(
                  labelKey,
                  style: ideaVaultBody(
                    context,
                    size: 16.f,
                    weight: FontWeight.w600,
                    height: 1.3,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
