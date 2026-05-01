import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';
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
      final groupBorder = sheetTheme.outline.withValues(alpha: 0.12);
      final dividerColor = sheetTheme.outline.withValues(alpha: 0.1);
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
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: sheetTheme.surfaceLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: groupBorder),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SheetOptionRow(
                          key: const Key('idea-editor-option-export-ai'),
                          icon: Icons.auto_awesome_rounded,
                          labelKey: ViewConstants.exportForAiScreenTitle,
                          iconBackgroundColor:
                              sheetTheme.primary.withValues(alpha: 0.12),
                          iconColor: sheetTheme.primary,
                          labelColor: sheetTheme.primaryText,
                          onTap: () => Navigator.of(sheetContext).pop(
                            IdeaEditorOptionsSheetAction.exportForAI,
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: dividerColor),
                        _SheetOptionRow(
                          key: const Key('idea-editor-option-export-pdf'),
                          icon: Icons.picture_as_pdf_rounded,
                          labelKey: ViewConstants.exportToPdfButton,
                          iconBackgroundColor:
                              sheetTheme.primary.withValues(alpha: 0.12),
                          iconColor: sheetTheme.primary,
                          labelColor: sheetTheme.primaryText,
                          onTap: () => Navigator.of(sheetContext).pop(
                            IdeaEditorOptionsSheetAction.exportToPDF,
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: dividerColor),
                        _SheetOptionRow(
                          key: const Key('idea-editor-option-delete-idea'),
                          icon: Icons.delete_outline_rounded,
                          labelKey: ViewConstants.ideaEditorOptionsDeleteIdea,
                          iconBackgroundColor:
                              errorColor.withValues(alpha: 0.12),
                          iconColor: errorColor,
                          labelColor: errorColor,
                          onTap: () => Navigator.of(sheetContext).pop(
                            IdeaEditorOptionsSheetAction.deleteIdea,
                          ),
                        ),
                      ],
                    ),
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

class _SheetOptionRow extends StatelessWidget {
  const _SheetOptionRow({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.iconBackgroundColor,
    required this.iconColor,
    required this.labelColor,
    required this.onTap,
  });

  final IconData icon;
  final String labelKey;
  final Color iconBackgroundColor;
  final Color iconColor;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 38.d,
                height: 38.d,
                child: Icon(icon, size: 20.d, color: iconColor),
              ),
              Gap(2.d),
              Expanded(
                child: TranslatedText(
                  labelKey,
                  style: ideaVaultBody(
                    context,
                    size: 15.f,
                    weight: FontWeight.w600,
                    height: 1.3,
                    color: labelColor,
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
