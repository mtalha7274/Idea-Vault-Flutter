import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/config/theme/base.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:idea_vault/core/utils/helpers.dart';
import 'package:provider/provider.dart';

import '../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/random_additions_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

enum _BackupRestoreAction { backup, restore }

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  _BackupRestoreAction? _activeBackupAction;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final backupProvider = context.watch<CloudBackupProvider>();
    final backupState = backupProvider.state;
    final isManualActionRunning = _activeBackupAction != null;
    final isBackupBusy = backupState.isBusy || isManualActionRunning;
    final cloudOffOverlayColor = theme.background.withValues(alpha: 0.78);
    final lastBackupFormatted = backupState.lastBackupAt == null
        ? ViewConstants.backupRestoreLastBackupNever.tr()
        : DateFormat.yMMMd(
            Localizations.localeOf(context).toString(),
          ).add_jm().format(backupState.lastBackupAt!);
    final backupSizeLabel = backupState.lastBackupSizeBytes == null
        ? ViewConstants.backupRestoreNoBackupYet.tr()
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
                        onChanged: isBackupBusy
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
                                      backupState.email ??
                                          ViewConstants
                                              .backupRestoreAccountPlaceholderIcloud
                                              .tr(),
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
                                    onPressed:
                                        isBackupBusy ? null : _changeAccount,
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
                                    onChanged: isBackupBusy
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
                              onPressed: isBackupBusy ? null : _backUpNow,
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.primary,
                                foregroundColor: theme.onPrimary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              child: _activeBackupAction ==
                                      _BackupRestoreAction.backup
                                  ? TranslatedText(
                                      ViewConstants.backupRestoreBackingUp,
                                      style: ideaVaultLabel(
                                        context,
                                        size: 15,
                                        weight: FontWeight.w800,
                                        color: theme.onPrimary,
                                      ),
                                    )
                                  : TranslatedText(
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
                              onPressed: isBackupBusy
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
                              child: _activeBackupAction ==
                                      _BackupRestoreAction.restore
                                  ? TranslatedText(
                                      ViewConstants.backupRestoreRestoring,
                                      style: ideaVaultLabel(
                                        context,
                                        size: 15,
                                        weight: FontWeight.w800,
                                        color: theme.primaryText,
                                      ),
                                    )
                                  : TranslatedText(
                                      ViewConstants
                                          .backupRestoreRestoreFromBackup,
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
      _showTranslatedSnackBar(ViewConstants.backupRestoreCloudUpdateFailed);
    }
  }

  Future<void> _changeAccount() async {
    try {
      await context.read<CloudBackupProvider>().changeAccount();
    } catch (error, stackTrace) {
      printLog('Cloud backup account change failed: $error\n$stackTrace');
      _showTranslatedSnackBar(ViewConstants.backupRestoreCloudUpdateFailed);
    }
  }

  Future<void> _setAutoBackupEnabled(bool enabled) async {
    try {
      await context.read<CloudBackupProvider>().setAutoBackupEnabled(enabled);
    } catch (_) {
      _showTranslatedSnackBar(
        ViewConstants.backupRestoreAutoBackupUpdateFailed,
      );
    }
  }

  Future<void> _backUpNow() async {
    _setActiveBackupAction(_BackupRestoreAction.backup);
    try {
      final ideasProvider = context.read<IdeasProvider>();
      final randomAdditionsProvider = context.read<RandomAdditionsProvider>();
      final backupProvider = context.read<CloudBackupProvider>();
      await ideasProvider.ensureLoaded();
      await randomAdditionsProvider.ensureLoaded();
      await backupProvider.backUpNow(
        ideasProvider.ideas,
        randomAdditions: randomAdditionsProvider.additions,
      );
      _showTranslatedSnackBar(ViewConstants.backupRestoreBackupComplete);
    } catch (error, stackTrace) {
      printLog('Manual cloud backup failed: $error\n$stackTrace');
      _showTranslatedSnackBar(ViewConstants.backupRestoreCloudUpdateFailed);
    } finally {
      _setActiveBackupAction(null);
    }
  }

  Future<void> _confirmRestoreFromBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: TranslatedText(ViewConstants.backupRestoreConfirmRestoreTitle),
          content: TranslatedText(
            ViewConstants.backupRestoreConfirmRestoreBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: TranslatedText(ViewConstants.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: TranslatedText(
                ViewConstants.backupRestoreConfirmRestoreButton,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    _setActiveBackupAction(_BackupRestoreAction.restore);
    try {
      final backupProvider = context.read<CloudBackupProvider>();
      final ideasProvider = context.read<IdeasProvider>();
      final randomAdditionsProvider = context.read<RandomAdditionsProvider>();
      final snapshot = await backupProvider.fetchRestoreSnapshot();
      if (snapshot == null) {
        _showTranslatedSnackBar(ViewConstants.backupRestoreNoBackupFound);
        return;
      }
      await ideasProvider.replaceIdeas(snapshot.ideas);
      await randomAdditionsProvider.replaceAdditions(snapshot.randomAdditions);
      if (!mounted) {
        return;
      }
      await backupProvider.dismissRestorePrompt();
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
      _showTranslatedSnackBar(ViewConstants.backupRestoreRestoredMessage);
    } catch (error, stackTrace) {
      printLog('Cloud backup restore failed: $error\n$stackTrace');
      _showTranslatedSnackBar(ViewConstants.backupRestoreCloudUpdateFailed);
    } finally {
      _setActiveBackupAction(null);
    }
  }

  void _setActiveBackupAction(_BackupRestoreAction? action) {
    if (!mounted) {
      return;
    }
    setState(() {
      _activeBackupAction = action;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return ViewConstants.backupRestoreFormatBytesB
          .tr(namedArgs: {'bytes': '$bytes'});
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      final kbStr = kb.toStringAsFixed(kb < 10 ? 1 : 0);
      return ViewConstants.backupRestoreFormatBytesKb
          .tr(namedArgs: {'kb': kbStr});
    }
    final mb = kb / 1024;
    final mbStr = mb.toStringAsFixed(mb < 10 ? 1 : 0);
    return ViewConstants.backupRestoreFormatBytesMb
        .tr(namedArgs: {'mb': mbStr});
  }

  void _showTranslatedSnackBar(String messageKey) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: TranslatedText(messageKey)),
    );
  }
}
