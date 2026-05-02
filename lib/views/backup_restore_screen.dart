import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:idea_vault/config/theme/base.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:idea_vault/core/utils/helpers.dart';
import 'package:provider/provider.dart';

import '../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  static const String _generalCloudBackupErrorMessage =
      'Cloud backup could not be updated. Please try again.';

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final backupProvider = context.watch<CloudBackupProvider>();
    final backupState = backupProvider.state;
    final cloudOffOverlayColor = theme.background.withValues(alpha: 0.78);
    final lastBackupFormatted = backupState.lastBackupAt == null
        ? 'Never'
        : DateFormat.yMMMd(
            Localizations.localeOf(context).toString(),
          ).add_jm().format(backupState.lastBackupAt!);
    final backupSizeLabel = backupState.lastBackupSizeBytes == null
        ? 'No backup yet'
        : _formatBytes(backupState.lastBackupSizeBytes!);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: const IdeaVaultSubpageAppBar(
        titleKey: ViewConstants.backupRestoreScreenTitle,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520.w),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 28.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _settingsCard(
                    theme,
                    children: [
                      _toggleRow(
                        context,
                        theme,
                        labelKey: ViewConstants.backupRestoreCloudBackup,
                        value: backupState.enabled,
                        onChanged: backupState.isBusy
                            ? (_) {}
                            : (v) => _setCloudBackupEnabled(v),
                      ),
                    ],
                  ),
                  Gap(12.h),
                  Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _settingsCard(
                            theme,
                            children: [
                              TranslatedText(
                                ViewConstants.backupRestoreGoogleAccount,
                                style: ideaVaultLabel(
                                  context,
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: theme.textMuted,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              Gap(8.h),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      backupState.email ?? 'iCloud',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: ideaVaultBody(
                                        context,
                                        size: 16,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Gap(12.w),
                                  TextButton(
                                    onPressed: backupState.isBusy
                                        ? null
                                        : _changeAccount,
                                    style: TextButton.styleFrom(
                                      foregroundColor: theme.primary,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8.w,
                                        vertical: 6.h,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: TranslatedText(
                                      ViewConstants.backupRestoreChangeAccount,
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
                              Gap(20.h),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        TranslatedText(
                                          ViewConstants.backupRestoreAutoBackup,
                                          style: ideaVaultBody(
                                            context,
                                            size: 16,
                                            weight: FontWeight.w600,
                                          ),
                                        ),
                                        Gap(4.h),
                                        TranslatedText(
                                          ViewConstants
                                              .backupRestoreAutoBackupDescription,
                                          style: ideaVaultBody(
                                            context,
                                            size: 14,
                                            weight: FontWeight.w500,
                                            color: theme.textMuted,
                                            height: 1.45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Gap(16.w),
                                  CupertinoSwitch(
                                    value: backupState.autoBackupEnabled,
                                    onChanged: backupState.isBusy
                                        ? null
                                        : _setAutoBackupEnabled,
                                    activeTrackColor: theme.primary,
                                    thumbColor: theme.settings.switchThumb,
                                  ),
                                ],
                              ),
                              Gap(20.h),
                              _valueRow(
                                context,
                                theme,
                                labelKey: ViewConstants.backupRestoreLastBackup,
                                value: Text(
                                  lastBackupFormatted,
                                  textAlign: TextAlign.end,
                                  style: ideaVaultBody(
                                    context,
                                    size: 15,
                                    weight: FontWeight.w600,
                                    color: theme.textMuted,
                                  ),
                                ),
                                trailing: backupState.lastBackupAt == null
                                    ? null
                                    : Icon(
                                        Icons.check_circle_rounded,
                                        size: 22.d,
                                        color: theme.primary,
                                      ),
                              ),
                              Gap(16.h),
                              _valueRow(
                                context,
                                theme,
                                labelKey: ViewConstants.backupRestoreBackupSize,
                                value: Text(
                                  backupSizeLabel,
                                  textAlign: TextAlign.end,
                                  style: ideaVaultBody(
                                    context,
                                    size: 15,
                                    weight: FontWeight.w600,
                                    color: theme.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Gap(22.h),
                          SizedBox(
                            height: 56.h,
                            child: FilledButton(
                              onPressed: backupState.isBusy ? null : _backUpNow,
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.primary,
                                foregroundColor: theme.onPrimary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              child: TranslatedText(
                                ViewConstants.backupRestoreBackUpNow,
                                style: ideaVaultLabel(
                                  context,
                                  size: 15,
                                  weight: FontWeight.w800,
                                  color: theme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                          Gap(28.h),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: theme.outlineSoft,
                          ),
                          Gap(20.h),
                          TranslatedText(
                            ViewConstants.backupRestoreSectionRestore,
                            style: ideaVaultLabel(
                              context,
                              size: 12,
                              weight: FontWeight.w800,
                              color: theme.textMuted,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Gap(14.h),
                          SizedBox(
                            height: 56.h,
                            child: OutlinedButton(
                              onPressed: backupState.isBusy
                                  ? null
                                  : _confirmRestoreFromBackup,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.primaryText,
                                side: BorderSide(
                                  color: theme.outline.withValues(alpha: 0.55),
                                  width: 1.5,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              child: TranslatedText(
                                ViewConstants.backupRestoreRestoreFromBackup,
                                style: ideaVaultLabel(
                                  context,
                                  size: 15,
                                  weight: FontWeight.w800,
                                  color: theme.primaryText,
                                ),
                              ),
                            ),
                          ),
                          Gap(12.h),
                          TranslatedText(
                            ViewConstants.backupRestoreRestoreWarning,
                            textAlign: TextAlign.center,
                            style: ideaVaultBody(
                              context,
                              size: 13,
                              weight: FontWeight.w500,
                              color: theme.textMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                      if (!backupState.enabled)
                        Positioned.fill(
                          child: AbsorbPointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: cloudOffOverlayColor,
                                borderRadius: BorderRadius.circular(20.r),
                              ),
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
      ),
    );
  }

  Widget _settingsCard(BaseTheme theme, {required List<Widget> children}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: theme.outlineSoft),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(18.w, 18.h, 14.w, 18.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _toggleRow(
    BuildContext context,
    BaseTheme theme, {
    required String labelKey,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TranslatedText(
            labelKey,
            style: ideaVaultBody(
              context,
              size: 16,
              weight: FontWeight.w600,
            ),
          ),
        ),
        CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: theme.primary,
          thumbColor: theme.settings.switchThumb,
        ),
      ],
    );
  }

  Widget _valueRow(
    BuildContext context,
    BaseTheme theme, {
    required String labelKey,
    required Widget value,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TranslatedText(
            labelKey,
            style: ideaVaultBody(
              context,
              size: 16,
              weight: FontWeight.w600,
            ),
          ),
        ),
        Gap(12.w),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: value,
              ),
              if (trailing != null) ...[
                Gap(8.w),
                trailing,
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _setCloudBackupEnabled(bool enabled) async {
    final backupProvider = context.read<CloudBackupProvider>();
    try {
      if (enabled) {
        await backupProvider.enableCloudBackup();
      } else {
        await backupProvider.disableCloudBackup();
      }
    } catch (error, stackTrace) {
      printLog('Cloud backup toggle failed: $error\n$stackTrace');
      _showMessage(_generalCloudBackupErrorMessage);
    }
  }

  Future<void> _changeAccount() async {
    try {
      await context.read<CloudBackupProvider>().changeAccount();
    } catch (error, stackTrace) {
      printLog('Cloud backup account change failed: $error\n$stackTrace');
      _showMessage(_generalCloudBackupErrorMessage);
    }
  }

  Future<void> _setAutoBackupEnabled(bool enabled) async {
    try {
      await context.read<CloudBackupProvider>().setAutoBackupEnabled(enabled);
    } catch (_) {
      _showMessage('Auto Backup could not be updated.');
    }
  }

  Future<void> _backUpNow() async {
    try {
      final ideasProvider = context.read<IdeasProvider>();
      final backupProvider = context.read<CloudBackupProvider>();
      await ideasProvider.ensureLoaded();
      await backupProvider.backUpNow(ideasProvider.ideas);
      _showMessage('Backup complete.');
    } catch (error, stackTrace) {
      printLog('Manual cloud backup failed: $error\n$stackTrace');
      _showMessage(_generalCloudBackupErrorMessage);
    }
  }

  Future<void> _confirmRestoreFromBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restore from Backup?'),
          content: const Text(
            'All current data will be replaced with the ideas in your cloud backup.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final backupProvider = context.read<CloudBackupProvider>();
      final ideasProvider = context.read<IdeasProvider>();
      final snapshot = await backupProvider.fetchRestoreSnapshot();
      if (snapshot == null) {
        _showMessage('No cloud backup was found.');
        return;
      }
      await ideasProvider.replaceIdeas(snapshot.ideas);
      if (!mounted) {
        return;
      }
      backupProvider.dismissRestorePrompt();
      Navigator.of(context).popUntil((route) => route.isFirst);
      _showMessage('Backup restored.');
    } catch (error, stackTrace) {
      printLog('Cloud backup restore failed: $error\n$stackTrace');
      _showMessage(_generalCloudBackupErrorMessage);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
