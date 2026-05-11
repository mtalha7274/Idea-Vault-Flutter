import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import '../core/extensions/int.dart';
import '../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';

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
                child: Text(
                  'Cloud backup found',
                  style: ideaVaultBody(
                    context,
                    size: 15,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: _isRestoring ? null : _restore,
                child: Text(
                  _isRestoring ? 'Restoring' : 'Restore',
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
    setState(() => _isRestoring = true);
    try {
      final snapshot =
          await context.read<CloudBackupProvider>().fetchRestoreSnapshot();
      if (snapshot == null || !mounted) {
        return;
      }
      await context.read<IdeasProvider>().replaceIdeas(snapshot.ideas);
      if (!mounted) {
        return;
      }
      context.read<CloudBackupProvider>().dismissRestorePrompt();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }
}
