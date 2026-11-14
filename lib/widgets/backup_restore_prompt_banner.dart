import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import '../core/constants/view_constants.dart';
import '../core/extensions/int.dart';
import '../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/random_additions_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';
import 'backup/backup_restore_flow.dart';
import 'translated_text.dart';

class BackupRestorePromptBanner extends StatefulWidget {
  const BackupRestorePromptBanner({super.key});

  static const Key bannerKey = Key('backup-restore-banner');
  static const Key restoreKey = Key('backup-restore-banner-restore');
  static const Key dismissKey = Key('backup-restore-banner-dismiss');

  @override
  State<BackupRestorePromptBanner> createState() =>
      _BackupRestorePromptBannerState();
}

class _BackupRestorePromptBannerState extends State<BackupRestorePromptBanner> {
  bool _isRestoring = false;
  bool _obsoleteScheduled = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final backupProvider = context.watch<CloudBackupProvider>();
    final ideasProvider = context.watch<IdeasProvider>();
    final additionsProvider = context.watch<RandomAdditionsProvider>();

    if (ideasProvider.isLoading || additionsProvider.isLoading) {
      return const SizedBox.shrink();
    }
    final hasLocalContent = ideasProvider.ideas.isNotEmpty ||
        additionsProvider.additions.isNotEmpty;
    if (hasLocalContent) {
      _scheduleObsoleteDismissal(backupProvider);
      return const SizedBox.shrink();
    }

    final kind = backupProvider.restoreBannerKind(hasLocalContent: false);
    if (kind == null) {
      return const SizedBox.shrink();
    }

    final isBusy = _isRestoring || backupProvider.isWorking;
    final messageKey = kind == CloudBackupBannerKind.backupFound
        ? ViewConstants.backupRestorePromptFound
        : ViewConstants.backupHavePrompt;

    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 18.h),
      child: DecoratedBox(
        key: BackupRestorePromptBanner.bannerKey,
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: theme.outlineSoft),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 4.w, 10.h),
          child: Row(
            children: [
              Icon(
                kind == CloudBackupBannerKind.backupFound
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_download_outlined,
                color: theme.primary,
                size: 24.d,
              ),
              Gap(12.w),
              Expanded(
                child: TranslatedText(
                  messageKey,
                  style: ideaVaultBody(
                    context,
                    size: 15,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: BackupRestorePromptBanner.restoreKey,
                onPressed: isBusy ? null : _restore,
                child: TranslatedText(
                  _isRestoring
                      ? ViewConstants.backupRestoreRestoring
                      : ViewConstants.backupRestoreConfirmRestoreButton,
                  style: ideaVaultLabel(
                    context,
                    size: 14,
                    weight: FontWeight.w800,
                    color: isBusy ? theme.textMuted : theme.primary,
                  ),
                ),
              ),
              IconButton(
                key: BackupRestorePromptBanner.dismissKey,
                tooltip: ViewConstants.backupDismiss.tr(),
                onPressed: isBusy ? null : _dismiss,
                icon: Icon(
                  Icons.close_rounded,
                  size: 20.d,
                  color: theme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scheduleObsoleteDismissal(CloudBackupProvider backupProvider) {
    if (_obsoleteScheduled ||
        backupProvider.restoreBannerKind(hasLocalContent: false) == null) {
      return;
    }
    _obsoleteScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await backupProvider.dismissRestorePrompt();
      _obsoleteScheduled = false;
    });
  }

  Future<void> _dismiss() async {
    await context.read<CloudBackupProvider>().dismissRestorePrompt();
  }

  Future<void> _restore() async {
    setState(() => _isRestoring = true);
    try {
      await BackupRestoreFlow.restoreNewestFromBanner(context);
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }
}
