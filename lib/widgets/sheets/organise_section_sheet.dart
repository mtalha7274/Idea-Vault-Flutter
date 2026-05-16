import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';
import '../translated_text.dart';

Future<bool> showOrganizeSectionSheet(
  BuildContext context, {
  required int warningCharacterLimit,
  required int maxCharacterLimit,
  required bool exceedsWarningLimit,
  required bool exceedsMaxLimit,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (sheetContext) {
      return _OrganizeSectionSheet(
        warningCharacterLimit: warningCharacterLimit,
        maxCharacterLimit: maxCharacterLimit,
        exceedsWarningLimit: exceedsWarningLimit,
        exceedsMaxLimit: exceedsMaxLimit,
      );
    },
  );

  return result ?? false;
}

class _OrganizeSectionSheet extends StatelessWidget {
  const _OrganizeSectionSheet({
    required this.warningCharacterLimit,
    required this.maxCharacterLimit,
    required this.exceedsWarningLimit,
    required this.exceedsMaxLimit,
  });

  final int warningCharacterLimit;
  final int maxCharacterLimit;
  final bool exceedsWarningLimit;
  final bool exceedsMaxLimit;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: theme.outline.withValues(alpha: 0.12)),
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
                      color: theme.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_fix_high_rounded,
                      size: 28,
                      color: theme.primary,
                    ),
                    const Gap(14),
                    Expanded(
                      child: TranslatedText(
                        ViewConstants.organizeSectionSheetTitle,
                        style: ideaVaultHeadline(
                          context,
                          size: 22,
                          weight: FontWeight.w800,
                          height: 1.2,
                          color: theme.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TranslatedText(
                  ViewConstants.organizeSectionSheetDescription,
                  style: ideaVaultBody(
                    context,
                    size: 15,
                    weight: FontWeight.w500,
                    color: theme.primaryText,
                    height: 1.45,
                  ),
                ),
                if (exceedsWarningLimit || exceedsMaxLimit) ...[
                  const SizedBox(height: 16),
                  TranslatedText(
                    exceedsMaxLimit
                        ? ViewConstants.organizeMaxLimitDialogBody
                        : ViewConstants.organizeOverLimitDialogBody,
                    key: Key(
                      exceedsMaxLimit
                          ? 'idea-editor-max-limit-warning'
                          : 'idea-editor-soft-limit-warning',
                    ),
                    namedArgs: {
                      'limit': NumberFormat.decimalPattern(
                        Localizations.localeOf(context).toString(),
                      ).format(
                        exceedsMaxLimit
                            ? maxCharacterLimit
                            : warningCharacterLimit,
                      ),
                    },
                    style: ideaVaultBody(
                      context,
                      size: 15,
                      weight: FontWeight.w500,
                      color: theme.warning,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        key: const Key('organize-over-limit-cancel'),
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: TranslatedText(
                          ViewConstants.cancel,
                          textAlign: TextAlign.center,
                          style: ideaVaultLabel(
                            context,
                            size: 14,
                            weight: FontWeight.w600,
                            color: theme.outline,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        key: const Key('organize-over-limit-confirm'),
                        onPressed: exceedsMaxLimit
                            ? null
                            : () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          minimumSize: const Size(0, 44),
                          tapTargetSize: MaterialTapTargetSize.padded,
                          backgroundColor: theme.surfaceLow,
                          foregroundColor: theme.primary,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_fix_high_rounded,
                              size: 18,
                              color: theme.primary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: TranslatedText(
                                ViewConstants.organizeSectionSheetConfirmButton,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: ideaVaultLabel(
                                  context,
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: theme.primary,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
