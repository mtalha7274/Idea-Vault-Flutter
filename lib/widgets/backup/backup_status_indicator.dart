import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../core/extensions/int.dart';
import '../../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';
import '../translated_text.dart';

class BackupStatusIndicator extends StatelessWidget {
  const BackupStatusIndicator({
    super.key,
    required this.onTap,
  });

  static const Key offKey = Key('homepage-backup-off-indicator');
  static const Key attentionKey = Key('homepage-backup-attention-indicator');

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final backupProvider = context.watch<CloudBackupProvider>();
    final backupState = backupProvider.state;
    final bool isOff = !backupState.enabled;
    if (!isOff && !backupProvider.needsAttention) {
      return const SizedBox.shrink();
    }

    final isDarkMode = theme.themeData.brightness == Brightness.dark;
    final indicatorColor = theme.warning.withValues(
      alpha: isDarkMode ? 0.18 : 0.14,
    );
    final borderColor = theme.warning.withValues(
      alpha: isDarkMode ? 0.38 : 0.32,
    );
    final foregroundColor = isDarkMode ? theme.warning : theme.primaryText;

    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 12.h),
      child: Material(
        key: isOff ? offKey : attentionKey,
        color: indicatorColor,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: borderColor),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14.w, 10.h, 12.w, 10.h),
              child: Row(
                children: [
                  Icon(
                    isOff
                        ? Icons.cloud_off_rounded
                        : Icons.sync_problem_rounded,
                    color: foregroundColor,
                    size: 20.d,
                  ),
                  Gap(10.w),
                  Expanded(
                    child: TranslatedText(
                      isOff
                          ? ViewConstants.homepageBackupOffIndicator
                          : ViewConstants.backupNeedsAttention,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ideaVaultBody(
                        context,
                        size: 14,
                        weight: FontWeight.w700,
                        color: theme.primaryText,
                      ),
                    ),
                  ),
                  Gap(10.w),
                  TranslatedText(
                    isOff
                        ? ViewConstants.homepageBackupOffAction
                        : ViewConstants.backupNeedsAttentionAction,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ideaVaultLabel(
                      context,
                      size: 13,
                      weight: FontWeight.w800,
                      color: foregroundColor,
                    ),
                  ),
                  Gap(2.w),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: foregroundColor,
                    size: 20.d,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
