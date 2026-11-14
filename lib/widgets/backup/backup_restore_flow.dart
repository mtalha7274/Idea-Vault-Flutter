import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../core/utils/helpers.dart';
import '../../models/backup/cloud_backup_error.dart';
import '../../models/backup/cloud_backup_restore.dart';
import '../../models/vault/vault_lock_block.dart';
import '../../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../../viewmodels/providers/ideas_provider.dart';
import '../../viewmodels/providers/random_additions_provider.dart';
import '../note_lock_auth_dialog.dart';
import 'backup_ui.dart';

class BackupRestoreFlow {
  const BackupRestoreFlow._();

  static bool hasLocalContent(BuildContext context) {
    final ideas = context.read<IdeasProvider>().ideas;
    final additions = context.read<RandomAdditionsProvider>().additions;
    return ideas.isNotEmpty || additions.isNotEmpty;
  }

  static Future<void> refreshVault(BuildContext context) async {
    final ideasProvider = context.read<IdeasProvider>();
    final additionsProvider = context.read<RandomAdditionsProvider>();
    await ideasProvider.clearEditorState();
    await ideasProvider.reloadFromStorage();
    await additionsProvider.reloadFromStorage();
  }

  static BackupVaultKeyPrompt vaultKeyPrompt(BuildContext context) {
    return (VaultLockBlock block) async {
      if (!context.mounted) {
        return null;
      }
      return promptBackupVaultKey(context, block);
    };
  }

  static void showRestoreResult(
    ScaffoldMessengerState messenger,
    CloudBackupRestoreResult result,
  ) {
    if (result.lockedNotImported > 0) {
      showBackupSnackBar(
        messenger,
        ViewConstants.vaultRestoreNotImported,
        namedArgs: {'count': '${result.lockedNotImported}'},
      );
      return;
    }
    if (result.needsVaultUnlock) {
      showBackupSnackBar(messenger, ViewConstants.vaultRestoreNeedsPin);
      return;
    }
    final merge = result.merge;
    if (merge == null) {
      showBackupSnackBar(messenger, ViewConstants.backupRestoreRestoredMessage);
      return;
    }
    showBackupSnackBar(
      messenger,
      ViewConstants.backupMergeResult,
      namedArgs: {
        'added': '${merge.added}',
        'copies': '${merge.copies}',
        'skipped': '${merge.skippedIdentical}',
      },
    );
  }

  static Future<bool> restoreNewestFromBanner(BuildContext context) async {
    final backupProvider = context.read<CloudBackupProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final wasNeutralCard = backupProvider.restoreBannerKind(
          hasLocalContent: false,
        ) ==
        CloudBackupBannerKind.haveBackup;
    try {
      final preview = await backupProvider.prepareNewestRestore();
      if (!context.mounted) {
        return false;
      }
      if (preview == null) {
        if (wasNeutralCard) {
          await backupProvider.dismissRestorePrompt();
        }
        showBackupSnackBar(messenger, ViewConstants.backupRestoreNoBackupFound);
        return false;
      }
      var mode = CloudBackupRestoreMode.replace;
      if (hasLocalContent(context)) {
        final chosen = await showRestoreConfirmSheet(
          context,
          preview,
          hasLocalData: true,
          thisDeviceShortId: backupProvider.deviceShortId,
        );
        if (chosen == null || !context.mounted) {
          return false;
        }
        mode = chosen;
      }
      final result = await backupProvider.restore(
        preview.snapshot,
        mode,
        askBackupKey: vaultKeyPrompt(context),
      );
      if (context.mounted) {
        await refreshVault(context);
      }
      showRestoreResult(messenger, result);
      return true;
    } catch (error, stackTrace) {
      printLog('Banner restore failed: $error\n$stackTrace');
      showBackupSnackBar(messenger, backupErrorMessageKeyFor(error));
      return false;
    }
  }

  static Future<bool> restoreWithPicker(BuildContext context) async {
    final backupProvider = context.read<CloudBackupProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final entries = await backupProvider.listRestoreEntries();
      if (!context.mounted) {
        return false;
      }
      if (entries.isEmpty) {
        showBackupSnackBar(messenger, ViewConstants.backupRestoreNoBackupFound);
        return false;
      }
      final entry = await showBackupPickerSheet(
        context,
        entries,
        thisDeviceShortId: backupProvider.deviceShortId,
      );
      if (entry == null || !context.mounted) {
        return false;
      }
      final preview = await backupProvider.prepareRestore(entry);
      if (!context.mounted) {
        return false;
      }
      if (preview.snapshot.isEmpty) {
        throw const CloudBackupException(CloudBackupErrorType.emptyBackup);
      }
      final mode = await showRestoreConfirmSheet(
        context,
        preview,
        hasLocalData: hasLocalContent(context),
        thisDeviceShortId: backupProvider.deviceShortId,
      );
      if (mode == null || !context.mounted) {
        return false;
      }
      final result = await backupProvider.restore(
        preview.snapshot,
        mode,
        askBackupKey: vaultKeyPrompt(context),
      );
      if (context.mounted) {
        await refreshVault(context);
      }
      showRestoreResult(messenger, result);
      return true;
    } catch (error, stackTrace) {
      printLog('Cloud backup restore failed: $error\n$stackTrace');
      showBackupSnackBar(messenger, backupErrorMessageKeyFor(error));
      return false;
    }
  }
}
