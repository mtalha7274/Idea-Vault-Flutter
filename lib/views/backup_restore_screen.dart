import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/config/theme/base.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:idea_vault/core/utils/helpers.dart';
import 'package:provider/provider.dart';

import '../models/backup/cloud_backup_error.dart';
import '../models/backup/cloud_backup_restore.dart';
import '../models/backup/cloud_backup_state.dart';
import '../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/random_additions_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/backup/backup_restore_flow.dart';
import '../widgets/backup/backup_ui.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<CloudBackupProvider>().refreshCloudEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final backupProvider = context.watch<CloudBackupProvider>();
    final backupState = backupProvider.state;
    final isManualActionRunning = _activeBackupAction != null;
    final isBackupBusy = backupState.isBusy || isManualActionRunning;
    final cloudOffOverlayColor = theme.background.withValues(alpha: 0.78);
    final health = backupProvider.health;
    final lastBackupFormatted =
        formatBackupDate(context, backupState.lastBackupAt);
    final backupSizeLabel = backupState.lastBackupSizeBytes == null
        ? ViewConstants.backupRestoreNoBackupYet.tr()
        : formatBackupBytes(backupState.lastBackupSizeBytes!);
    final errorColor = Theme.of(context).colorScheme.error;

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
                              _accountSection(
                                context,
                                theme,
                                backupProvider,
                                isBackupBusy,
                              ),
                              Gap(20.h),
                              _autoBackupRow(
                                context,
                                theme,
                                backupState,
                                isBackupBusy,
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
                                trailing:
                                    _healthIcon(theme, health, errorColor),
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
                              ..._statusDetails(
                                context,
                                theme,
                                backupProvider,
                                health,
                                errorColor,
                                isBackupBusy,
                              ),
                              ..._otherDevices(context, theme, backupProvider),
                              ..._plaintextCleanup(
                                context,
                                theme,
                                backupProvider,
                                errorColor,
                              ),
                            ],
                          ),
                          Gap(22.h),
                          SizedBox(
                            height: 56.h,
                            child: FilledButton(
                              key: const Key('backup-back-up-now'),
                              onPressed: isBackupBusy ? null : _backUpNow,
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.primary,
                                foregroundColor: theme.onPrimary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              child: TranslatedText(
                                _activeBackupAction ==
                                        _BackupRestoreAction.backup
                                    ? ViewConstants.backupRestoreBackingUp
                                    : ViewConstants.backupRestoreBackUpNow,
                                style: ideaVaultLabel(
                                  context,
                                  size: 15,
                                  weight: FontWeight.w800,
                                  color: theme.onPrimary,
                                ),
                              ),
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
                      key: const Key('backup-restore-button'),
                      onPressed: isBackupBusy ? null : _restoreFromBackup,
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
                        _activeBackupAction == _BackupRestoreAction.restore
                            ? ViewConstants.backupRestoreRestoring
                            : ViewConstants.backupRestoreRestoreFromBackup,
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
                  if (backupProvider.canUndoRestore) ...[
                    Gap(16.h),
                    OutlinedButton.icon(
                      key: const Key('backup-undo-restore'),
                      onPressed: isBackupBusy ? null : _undoRestore,
                      icon: const Icon(Icons.undo_rounded),
                      label: TranslatedText(ViewConstants.backupUndoRestore),
                    ),
                    Gap(6.h),
                    TranslatedText(
                      ViewConstants.backupUndoRestoreHint,
                      textAlign: TextAlign.center,
                      style: ideaVaultBody(
                        context,
                        size: 12,
                        color: theme.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                  Gap(28.h),
                  TextButton(
                    key: const Key('backup-delete-cloud'),
                    onPressed: isBackupBusy ? null : _deleteCloudBackups,
                    style: TextButton.styleFrom(foregroundColor: errorColor),
                    child: TranslatedText(
                      ViewConstants.backupDeleteCloud,
                      style: ideaVaultLabel(
                        context,
                        size: 14,
                        weight: FontWeight.w700,
                        color: isBackupBusy ? theme.textMuted : errorColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountSection(
    BuildContext context,
    BaseTheme theme,
    CloudBackupProvider backupProvider,
    bool isBackupBusy,
  ) {
    final isIOS = backupProvider.isIOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TranslatedText(
          isIOS
              ? ViewConstants.backupIcloudAccountTitle
              : ViewConstants.backupRestoreGoogleAccount,
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
              child: isIOS
                  ? TranslatedText(
                      ViewConstants.backupIcloudAccountValue,
                      style: ideaVaultBody(
                        context,
                        size: 15,
                        weight: FontWeight.w600,
                      ),
                    )
                  : Text(
                      backupProvider.state.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ideaVaultBody(
                        context,
                        size: 16,
                        weight: FontWeight.w600,
                      ),
                    ),
            ),
            if (!isIOS) ...[
              Gap(12.w),
              TextButton(
                key: const Key('backup-change-account'),
                onPressed: isBackupBusy ? null : _changeAccount,
                style: TextButton.styleFrom(
                  foregroundColor: theme.primary,
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.w,
                    vertical: 6.h,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
          ],
        ),
      ],
    );
  }

  Widget _autoBackupRow(
    BuildContext context,
    BaseTheme theme,
    CloudBackupState backupState,
    bool isBackupBusy,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                ViewConstants.backupRestoreAutoBackupDescription,
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
          onChanged: isBackupBusy ? null : _setAutoBackupEnabled,
          activeTrackColor: theme.primary,
          thumbColor: theme.settings.switchThumb,
        ),
      ],
    );
  }

  Widget? _healthIcon(
    BaseTheme theme,
    CloudBackupHealth health,
    Color errorColor,
  ) {
    switch (health) {
      case CloudBackupHealth.healthy:
        return Icon(
          Icons.check_circle_rounded,
          key: const Key('backup-health-healthy'),
          size: 22.d,
          color: theme.primary,
        );
      case CloudBackupHealth.stale:
        return Icon(
          Icons.schedule_rounded,
          key: const Key('backup-health-stale'),
          size: 22.d,
          color: theme.warning,
        );
      case CloudBackupHealth.failing:
        return Icon(
          Icons.error_rounded,
          key: const Key('backup-health-failing'),
          size: 22.d,
          color: errorColor,
        );
      case CloudBackupHealth.pending:
        return Icon(
          Icons.cloud_upload_outlined,
          key: const Key('backup-health-pending'),
          size: 22.d,
          color: theme.textMuted,
        );
      case CloudBackupHealth.needsSetup:
        return Icon(
          Icons.sync_problem_rounded,
          key: const Key('backup-health-needs-setup'),
          size: 22.d,
          color: theme.warning,
        );
      case CloudBackupHealth.never:
      case CloudBackupHealth.off:
        return null;
    }
  }

  List<Widget> _statusDetails(
    BuildContext context,
    BaseTheme theme,
    CloudBackupProvider backupProvider,
    CloudBackupHealth health,
    Color errorColor,
    bool isBackupBusy,
  ) {
    final state = backupProvider.state;
    String? messageKey;
    Map<String, String>? namedArgs;
    Color color = theme.textMuted;
    String? actionKey;
    VoidCallback? action;
    switch (health) {
      case CloudBackupHealth.stale:
        final lastBackup = state.lastBackupAt;
        final days = lastBackup == null
            ? 0
            : backupProvider.now.difference(lastBackup).inDays;
        messageKey = ViewConstants.backupStatusStale;
        namedArgs = {'days': '$days'};
        color = theme.warning;
        break;
      case CloudBackupHealth.failing:
        final type = state.lastErrorType;
        messageKey = backupErrorMessageKey(type);
        color = errorColor;
        actionKey = type == CloudBackupErrorType.signInRequired
            ? ViewConstants.backupActionSignInAgain
            : ViewConstants.backupActionTryAgain;
        action = _backUpNow;
        break;
      case CloudBackupHealth.pending:
        messageKey = ViewConstants.backupStatusPending;
        break;
      case CloudBackupHealth.needsSetup:
        messageKey = ViewConstants.backupStatusNeedsSetup;
        color = theme.warning;
        actionKey = ViewConstants.backupStatusFinishSetup;
        action = _finishSetup;
        break;
      case CloudBackupHealth.never:
        messageKey = ViewConstants.backupStatusNever;
        break;
      case CloudBackupHealth.healthy:
      case CloudBackupHealth.off:
        break;
    }
    if (messageKey == null) {
      return const [];
    }
    return [
      Gap(16.h),
      Row(
        key: Key('backup-status-${health.name}'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TranslatedText(
              messageKey,
              namedArgs: namedArgs,
              style: ideaVaultBody(
                context,
                size: 14,
                weight: FontWeight.w600,
                color: color,
                height: 1.4,
              ),
            ),
          ),
          if (actionKey != null) ...[
            Gap(8.w),
            TextButton(
              key: const Key('backup-status-action'),
              onPressed: isBackupBusy ? null : action,
              child: TranslatedText(actionKey),
            ),
          ],
        ],
      ),
    ];
  }

  List<Widget> _otherDevices(
    BuildContext context,
    BaseTheme theme,
    CloudBackupProvider backupProvider,
  ) {
    final entries = backupProvider.otherDeviceEntries;
    if (entries.isEmpty) {
      return const [];
    }
    return [
      Gap(12.h),
      for (final entry in entries)
        TranslatedText(
          ViewConstants.backupAlsoBackedUpFrom,
          namedArgs: {'device': backupDeviceLabel(entry)},
          style: ideaVaultBody(
            context,
            size: 13,
            color: theme.textMuted,
          ),
        ),
    ];
  }

  List<Widget> _plaintextCleanup(
    BuildContext context,
    BaseTheme theme,
    CloudBackupProvider backupProvider,
    Color errorColor,
  ) {
    if (!backupProvider.plaintextCleanupPending) {
      return const [];
    }
    final running = backupProvider.isPlaintextCleanupRunning;
    return [
      Gap(14.h),
      Container(
        key: const Key('backup-plaintext-cleanup'),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: errorColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TranslatedText(
              ViewConstants.vaultCleanupPendingTitle,
              style: ideaVaultBody(
                context,
                size: 14,
                weight: FontWeight.w700,
                color: errorColor,
              ),
            ),
            Gap(4.h),
            TranslatedText(
              ViewConstants.vaultCleanupPendingBody,
              style: ideaVaultBody(
                context,
                size: 13,
                color: theme.textMuted,
                height: 1.4,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('backup-plaintext-cleanup-retry'),
                onPressed: running ? null : _retryPlaintextCleanup,
                child: running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TranslatedText(ViewConstants.vaultCleanupRetry),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _retryPlaintextCleanup() async {
    final backupProvider = context.read<CloudBackupProvider>();
    final ideas = context.read<IdeasProvider>().ideas;
    final additions = context.read<RandomAdditionsProvider>().additions;
    final done = await backupProvider.runPlaintextCleanup(
      ideas,
      randomAdditions: additions,
    );
    _showTranslatedSnackBar(
      done ? ViewConstants.vaultCleanupDone : ViewConstants.vaultCleanupFailed,
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
          key: const Key('backup-cloud-toggle'),
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

  Future<CloudBackupEnableChoice?> _chooseEnableOption(
    CloudBackupEnablePrompt prompt,
  ) async {
    if (!mounted) {
      return null;
    }
    return showEnablePromptSheet(
      context,
      prompt,
      thisDeviceShortId: context.read<CloudBackupProvider>().deviceShortId,
    );
  }

  Future<void> _handleEnableResult(CloudBackupEnableResult result) async {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    switch (result.status) {
      case CloudBackupEnableStatus.cancelled:
        return;
      case CloudBackupEnableStatus.failed:
        showBackupSnackBar(messenger, backupErrorMessageKey(result.errorType));
        return;
      case CloudBackupEnableStatus.enabled:
        break;
    }
    final restored = result.restore;
    if (restored != null) {
      await BackupRestoreFlow.refreshVault(context);
      BackupRestoreFlow.showRestoreResult(messenger, restored);
      return;
    }
    final firstBackup = result.firstBackup;
    if (firstBackup != null) {
      _showRunResult(messenger, firstBackup);
    }
  }

  Future<void> _setCloudBackupEnabled(bool enabled) async {
    final backupProvider = context.read<CloudBackupProvider>();
    if (!enabled) {
      final confirmed = await showBackupConfirmDialog(
        context,
        titleKey: ViewConstants.backupTurnOffTitle,
        bodyKey: ViewConstants.backupTurnOffBody,
        confirmKey: ViewConstants.backupTurnOffButton,
      );
      if (!confirmed || !mounted) {
        return;
      }
      try {
        await backupProvider.disableCloudBackup();
      } catch (error, stackTrace) {
        printLog('Cloud backup disable failed: $error\n$stackTrace');
        _showTranslatedSnackBar(backupErrorMessageKeyFor(error));
      }
      return;
    }
    _setActiveBackupAction(_BackupRestoreAction.backup);
    try {
      final result = await backupProvider.enableCloudBackup(
        choose: _chooseEnableOption,
        askBackupKey: BackupRestoreFlow.vaultKeyPrompt(context),
      );
      await _handleEnableResult(result);
    } catch (error, stackTrace) {
      printLog('Cloud backup enable failed: $error\n$stackTrace');
      _showTranslatedSnackBar(backupErrorMessageKeyFor(error));
    } finally {
      _setActiveBackupAction(null);
    }
  }

  Future<void> _finishSetup() async {
    try {
      final result = await context.read<CloudBackupProvider>().finishSetup(
            choose: _chooseEnableOption,
            askBackupKey: BackupRestoreFlow.vaultKeyPrompt(context),
          );
      await _handleEnableResult(result);
    } catch (error, stackTrace) {
      printLog('Cloud backup setup failed: $error\n$stackTrace');
      _showTranslatedSnackBar(backupErrorMessageKeyFor(error));
    }
  }

  Future<void> _changeAccount() async {
    try {
      final result = await context.read<CloudBackupProvider>().changeAccount(
            choose: _chooseEnableOption,
            askBackupKey: BackupRestoreFlow.vaultKeyPrompt(context),
          );
      await _handleEnableResult(result);
    } catch (error, stackTrace) {
      printLog('Cloud backup account change failed: $error\n$stackTrace');
      _showTranslatedSnackBar(backupErrorMessageKeyFor(error));
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

  void _showRunResult(
    ScaffoldMessengerState messenger,
    CloudBackupRunResult result,
  ) {
    switch (result.outcome) {
      case CloudBackupRunOutcome.uploaded:
        showBackupSnackBar(
            messenger, ViewConstants.backupRestoreBackupComplete);
        return;
      case CloudBackupRunOutcome.pending:
        showBackupSnackBar(messenger, ViewConstants.backupUploadPending);
        return;
      case CloudBackupRunOutcome.unchanged:
        showBackupSnackBar(messenger, ViewConstants.backupUpToDate);
        return;
      case CloudBackupRunOutcome.skippedBusy:
        showBackupSnackBar(messenger, ViewConstants.backupBusyMessage);
        return;
      case CloudBackupRunOutcome.failed:
        showBackupSnackBar(messenger, backupErrorMessageKey(result.errorType));
        return;
      case CloudBackupRunOutcome.needsEmptyConfirmation:
      case CloudBackupRunOutcome.skippedDisabled:
      case CloudBackupRunOutcome.skippedUnresolved:
      case CloudBackupRunOutcome.skippedNotDue:
      case CloudBackupRunOutcome.skippedEmpty:
        return;
    }
  }

  Future<void> _backUpNow() async {
    _setActiveBackupAction(_BackupRestoreAction.backup);
    try {
      final ideasProvider = context.read<IdeasProvider>();
      final randomAdditionsProvider = context.read<RandomAdditionsProvider>();
      final backupProvider = context.read<CloudBackupProvider>();
      final messenger = ScaffoldMessenger.of(context);
      await ideasProvider.ensureLoaded();
      await randomAdditionsProvider.ensureLoaded();
      var result = await backupProvider.backUpNow(
        ideasProvider.ideas,
        randomAdditions: randomAdditionsProvider.additions,
      );
      if (result.outcome == CloudBackupRunOutcome.needsEmptyConfirmation) {
        if (!mounted) {
          return;
        }
        final confirmed = await showBackupConfirmDialog(
          context,
          titleKey: ViewConstants.backupEmptyConfirmTitle,
          bodyKey: ViewConstants.backupEmptyConfirmBody,
          confirmKey: ViewConstants.backupEmptyConfirmButton,
        );
        if (!confirmed) {
          return;
        }
        result = await backupProvider.backUpNow(
          ideasProvider.ideas,
          randomAdditions: randomAdditionsProvider.additions,
          allowEmpty: true,
        );
      }
      _showRunResult(messenger, result);
    } catch (error, stackTrace) {
      printLog('Manual cloud backup failed: $error\n$stackTrace');
      _showTranslatedSnackBar(backupErrorMessageKeyFor(error));
    } finally {
      _setActiveBackupAction(null);
    }
  }

  Future<void> _restoreFromBackup() async {
    _setActiveBackupAction(_BackupRestoreAction.restore);
    try {
      final restored = await BackupRestoreFlow.restoreWithPicker(context);
      if (restored && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } finally {
      _setActiveBackupAction(null);
    }
  }

  Future<void> _undoRestore() async {
    final confirmed = await showBackupConfirmDialog(
      context,
      titleKey: ViewConstants.backupUndoRestoreConfirmTitle,
      bodyKey: ViewConstants.backupUndoRestoreConfirmBody,
      confirmKey: ViewConstants.backupUndoRestore,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CloudBackupProvider>().undoRestore();
      if (!mounted) {
        return;
      }
      await BackupRestoreFlow.refreshVault(context);
      showBackupSnackBar(messenger, ViewConstants.backupUndoRestoreDone);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error, stackTrace) {
      printLog('Undo restore failed: $error\n$stackTrace');
      showBackupSnackBar(messenger, backupErrorMessageKeyFor(error));
    }
  }

  Future<void> _deleteCloudBackups() async {
    final first = await showBackupConfirmDialog(
      context,
      titleKey: ViewConstants.backupDeleteCloudTitle,
      bodyKey: ViewConstants.backupDeleteCloudBody,
      confirmKey: ViewConstants.backupDeleteCloudButton,
      destructive: true,
    );
    if (!first || !mounted) {
      return;
    }
    final second = await showBackupConfirmDialog(
      context,
      titleKey: ViewConstants.backupDeleteCloudConfirmTitle,
      bodyKey: ViewConstants.backupDeleteCloudConfirmBody,
      confirmKey: ViewConstants.backupDeleteCloudButton,
      confirmButtonKey: const Key('backup-delete-cloud-final'),
      destructive: true,
    );
    if (!second || !mounted) {
      return;
    }
    try {
      await context.read<CloudBackupProvider>().deleteCloudBackups();
      _showTranslatedSnackBar(ViewConstants.backupDeleteCloudDone);
    } catch (error, stackTrace) {
      printLog('Delete cloud backups failed: $error\n$stackTrace');
      _showTranslatedSnackBar(backupErrorMessageKeyFor(error));
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

  void _showTranslatedSnackBar(String messageKey) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: TranslatedText(messageKey)),
    );
  }
}
