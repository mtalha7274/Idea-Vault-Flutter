import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import '../core/constants/view_constants.dart';
import '../core/extensions/int.dart';
import '../core/utils/helpers.dart';
import '../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/random_additions_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';
import 'translated_text.dart';

class BackupRestorePromptBanner extends StatefulWidget {
  const BackupRestorePromptBanner({super.key});

  @override
  State<BackupRestorePromptBanner> createState() =>
      _BackupRestorePromptBannerState();
}

class _BackupRestorePromptBannerState extends State<BackupRestorePromptBanner> {
  bool _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final backupProvider = context.watch<CloudBackupProvider>();

    if (!backupProvider.state.restorePromptAvailable) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 18.h),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: theme.outlineSoft),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 14.h, 12.w, 14.h),
          child: Row(
            children: [
              Icon(
                Icons.cloud_done_rounded,
                color: theme.primary,
                size: 24.d,
              ),
              Gap(12.w),
              Expanded(
                child: TranslatedText(
                  ViewConstants.backupRestorePromptFound,
                  style: ideaVaultBody(
                    context,
                    size: 15,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: _isRestoring ? null : _restore,
                child: TranslatedText(
                  _isRestoring
                      ? ViewConstants.backupRestoreRestoring
                      : ViewConstants.backupRestoreConfirmRestoreButton,
                  style: ideaVaultLabel(
                    context,
                    size: 14,
                    weight: FontWeight.w800,
                    color: theme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restore() async {
    final backupProvider = context.read<CloudBackupProvider>();
    final ideasProvider = context.read<IdeasProvider>();
    final additionsProvider = context.read<RandomAdditionsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isRestoring = true);
    try {
      final snapshot = await backupProvider.fetchRestoreSnapshot();
      if (!mounted) {
        return;
      }
      if (snapshot == null) {
        _showSnackBar(messenger, ViewConstants.backupRestoreNoBackupFound);
        return;
      }
      await ideasProvider.replaceIdeas(snapshot.ideas);
      await additionsProvider.replaceAdditions(snapshot.randomAdditions);
      await backupProvider.syncUsageMetadataFromCloud(silentAuth: false);
      backupProvider.dismissRestorePrompt();
      if (!mounted) {
        return;
      }
      _showSnackBar(messenger, ViewConstants.backupRestoreRestoredMessage);
    } catch (error, stackTrace) {
      printLog('Cloud backup prompt restore failed: $error\n$stackTrace');
      if (mounted) {
        _showSnackBar(
          messenger,
          ViewConstants.backupRestoreCloudUpdateFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  void _showSnackBar(ScaffoldMessengerState messenger, String messageKey) {
    messenger.showSnackBar(
      SnackBar(
        content: TranslatedText(messageKey),
      ),
    );
  }
}
