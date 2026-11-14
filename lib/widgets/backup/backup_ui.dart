import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../core/services/backup/cloud_backup_error_classifier.dart';
import '../../models/backup/cloud_backup_entry.dart';
import '../../models/backup/cloud_backup_error.dart';
import '../../models/backup/cloud_backup_restore.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';
import '../translated_text.dart';

String backupErrorMessageKey(CloudBackupErrorType? type) {
  switch (type) {
    case CloudBackupErrorType.offline:
      return ViewConstants.backupErrorOffline;
    case CloudBackupErrorType.timeout:
      return ViewConstants.backupErrorTimeout;
    case CloudBackupErrorType.signInRequired:
      return ViewConstants.backupErrorSignInRequired;
    case CloudBackupErrorType.signInCancelled:
      return ViewConstants.backupErrorSignInCancelled;
    case CloudBackupErrorType.iCloudUnavailable:
      return ViewConstants.backupErrorICloudUnavailable;
    case CloudBackupErrorType.noBackupFound:
      return ViewConstants.backupRestoreNoBackupFound;
    case CloudBackupErrorType.emptyBackup:
      return ViewConstants.backupErrorEmptyBackup;
    case CloudBackupErrorType.invalidBackup:
      return ViewConstants.backupErrorInvalidBackup;
    case CloudBackupErrorType.newerVersion:
      return ViewConstants.backupErrorNewerVersion;
    case CloudBackupErrorType.integrityFailed:
      return ViewConstants.backupErrorIntegrity;
    case CloudBackupErrorType.unknown:
    case null:
      return ViewConstants.backupErrorUnknown;
  }
}

String backupErrorMessageKeyFor(Object error) {
  return backupErrorMessageKey(CloudBackupErrorClassifier.classify(error));
}

String formatBackupBytes(int bytes) {
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
  return ViewConstants.backupRestoreFormatBytesMb.tr(namedArgs: {'mb': mbStr});
}

String formatBackupDate(BuildContext context, DateTime? time) {
  if (time == null) {
    return ViewConstants.backupRestoreLastBackupNever.tr();
  }
  return DateFormat.yMMMd(Localizations.localeOf(context).toString())
      .add_jm()
      .format(time.toLocal());
}

String backupDeviceLabel(
  CloudBackupEntry entry, {
  String? deviceName,
  String? thisDeviceShortId,
}) {
  if (entry.isLegacy) {
    return ViewConstants.backupLegacyLabel.tr();
  }
  if (thisDeviceShortId != null && entry.deviceShortId == thisDeviceShortId) {
    return ViewConstants.backupThisDevice.tr();
  }
  final name = deviceName ?? entry.deviceName;
  if (name != null && name.trim().isNotEmpty) {
    return name;
  }
  return ViewConstants.backupUnknownDevice.tr();
}

void showBackupSnackBar(
  ScaffoldMessengerState messenger,
  String messageKey, {
  Map<String, String>? namedArgs,
}) {
  messenger.showSnackBar(
    SnackBar(content: TranslatedText(messageKey, namedArgs: namedArgs)),
  );
}

Future<bool> showBackupConfirmDialog(
  BuildContext context, {
  required String titleKey,
  required String bodyKey,
  required String confirmKey,
  Key? confirmButtonKey,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final errorColor = Theme.of(dialogContext).colorScheme.error;
      return AlertDialog(
        title: TranslatedText(titleKey),
        content: TranslatedText(bodyKey),
        actions: [
          TextButton(
            key: const Key('backup-confirm-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: TranslatedText(ViewConstants.cancel),
          ),
          FilledButton(
            key: confirmButtonKey ?? const Key('backup-confirm-accept'),
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: errorColor)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: TranslatedText(confirmKey),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

class BackupSheetAction<T> {
  const BackupSheetAction({
    required this.value,
    required this.labelKey,
    required this.key,
    this.hintKey,
    this.primary = false,
  });

  final T value;
  final String labelKey;
  final String? hintKey;
  final Key key;
  final bool primary;
}

Future<T?> showBackupActionSheet<T>(
  BuildContext context, {
  required String titleKey,
  required String summary,
  required String bodyKey,
  required List<BackupSheetAction<T>> actions,
}) {
  final theme = context.read<ThemeProvider>().baseTheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.surface,
    builder: (sheetContext) {
      final sheetTheme = sheetContext.watch<ThemeProvider>().baseTheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            key: const Key('backup-action-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TranslatedText(
                titleKey,
                style: ideaVaultHeadline(sheetContext, size: 22),
              ),
              const Gap(6),
              Text(
                summary,
                style: ideaVaultBody(
                  sheetContext,
                  size: 14,
                  weight: FontWeight.w700,
                  color: sheetTheme.primary,
                ),
              ),
              const Gap(10),
              TranslatedText(
                bodyKey,
                style: ideaVaultBody(
                  sheetContext,
                  size: 14,
                  color: sheetTheme.textMuted,
                  height: 1.4,
                ),
              ),
              const Gap(18),
              for (final action in actions) ...[
                _BackupSheetButton<T>(action: action),
                const Gap(10),
              ],
              TextButton(
                key: const Key('backup-sheet-cancel'),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: TranslatedText(ViewConstants.cancel),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _BackupSheetButton<T> extends StatelessWidget {
  const _BackupSheetButton({required this.action});

  final BackupSheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final foreground = action.primary ? theme.onPrimary : theme.primaryText;
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslatedText(
            action.labelKey,
            style: ideaVaultLabel(
              context,
              size: 15,
              weight: FontWeight.w800,
              color: foreground,
            ),
          ),
          if (action.hintKey != null) ...[
            const Gap(2),
            TranslatedText(
              action.hintKey!,
              style: ideaVaultBody(
                context,
                size: 12,
                color: foreground.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    if (action.primary) {
      return FilledButton(
        key: action.key,
        style: FilledButton.styleFrom(
          backgroundColor: theme.primary,
          alignment: Alignment.centerLeft,
          shape: shape,
        ),
        onPressed: () => Navigator.of(context).pop(action.value),
        child: child,
      );
    }
    return OutlinedButton(
      key: action.key,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        side: BorderSide(color: theme.outline.withValues(alpha: 0.55)),
        shape: shape,
      ),
      onPressed: () => Navigator.of(context).pop(action.value),
      child: child,
    );
  }
}

String backupSummaryText(
  BuildContext context, {
  required int? ideaCount,
  required int? noteCount,
  required DateTime? createdAt,
  required String device,
}) {
  return ViewConstants.backupFoundSummary.tr(
    namedArgs: {
      'ideas': ideaCount?.toString() ?? '?',
      'notes': noteCount?.toString() ?? '?',
      'date': createdAt == null
          ? ViewConstants.backupRestoreLastBackupNever.tr()
          : DateFormat.yMMMd(Localizations.localeOf(context).toString())
              .format(createdAt.toLocal()),
      'device': device,
    },
  );
}

Future<CloudBackupEnableChoice?> showEnablePromptSheet(
  BuildContext context,
  CloudBackupEnablePrompt prompt, {
  String? thisDeviceShortId,
}) {
  final summary = backupSummaryText(
    context,
    ideaCount: prompt.ideaCount,
    noteCount: prompt.randomAdditionCount,
    createdAt: prompt.createdAt,
    device: backupDeviceLabel(
      prompt.entry,
      deviceName: prompt.deviceName,
      thisDeviceShortId: thisDeviceShortId,
    ),
  );
  final readable = prompt.snapshot != null;
  if (prompt.kind == CloudBackupEnablePromptKind.restoreOrStartFresh) {
    return showBackupActionSheet<CloudBackupEnableChoice>(
      context,
      titleKey: ViewConstants.backupFoundTitle,
      summary: summary,
      bodyKey: readable
          ? ViewConstants.backupFoundBodyEmptyDevice
          : ViewConstants.backupFoundUnreadable,
      actions: [
        if (readable)
          const BackupSheetAction(
            value: CloudBackupEnableChoice.restore,
            labelKey: ViewConstants.backupChoiceRestore,
            key: Key('backup-choice-restore'),
            primary: true,
          ),
        const BackupSheetAction(
          value: CloudBackupEnableChoice.startFresh,
          labelKey: ViewConstants.backupChoiceStartFresh,
          key: Key('backup-choice-start-fresh'),
        ),
      ],
    );
  }
  return showBackupActionSheet<CloudBackupEnableChoice>(
    context,
    titleKey: ViewConstants.backupFoundTitle,
    summary: summary,
    bodyKey: readable
        ? ViewConstants.backupFoundBodyOtherDevice
        : ViewConstants.backupFoundUnreadable,
    actions: [
      if (readable) ...const [
        BackupSheetAction(
          value: CloudBackupEnableChoice.merge,
          labelKey: ViewConstants.backupChoiceMerge,
          hintKey: ViewConstants.backupChoiceMergeHint,
          key: Key('backup-choice-merge'),
          primary: true,
        ),
        BackupSheetAction(
          value: CloudBackupEnableChoice.replace,
          labelKey: ViewConstants.backupChoiceReplaceDevice,
          hintKey: ViewConstants.backupChoiceReplaceHint,
          key: Key('backup-choice-replace'),
        ),
      ],
      const BackupSheetAction(
        value: CloudBackupEnableChoice.keepLocal,
        labelKey: ViewConstants.backupChoiceKeepDevice,
        hintKey: ViewConstants.backupChoiceKeepHint,
        key: Key('backup-choice-keep'),
      ),
    ],
  );
}

Future<CloudBackupRestoreMode?> showRestoreConfirmSheet(
  BuildContext context,
  CloudBackupRestorePreview preview, {
  required bool hasLocalData,
  String? thisDeviceShortId,
}) {
  final summary = backupSummaryText(
    context,
    ideaCount: preview.snapshot.ideaCount,
    noteCount: preview.snapshot.randomAdditionCount,
    createdAt: preview.snapshot.createdAt.millisecondsSinceEpoch == 0
        ? preview.entry.createdAt ?? preview.entry.modifiedAt
        : preview.snapshot.createdAt,
    device: backupDeviceLabel(
      preview.entry,
      deviceName: preview.snapshot.deviceName,
      thisDeviceShortId: thisDeviceShortId,
    ),
  );
  if (!hasLocalData) {
    return showBackupActionSheet<CloudBackupRestoreMode>(
      context,
      titleKey: ViewConstants.backupRestoreConfirmTitle,
      summary: summary,
      bodyKey: ViewConstants.backupRestoreConfirmBodyEmpty,
      actions: const [
        BackupSheetAction(
          value: CloudBackupRestoreMode.replace,
          labelKey: ViewConstants.backupChoiceRestore,
          key: Key('backup-choice-restore'),
          primary: true,
        ),
      ],
    );
  }
  return showBackupActionSheet<CloudBackupRestoreMode>(
    context,
    titleKey: ViewConstants.backupRestoreConfirmTitle,
    summary: summary,
    bodyKey: ViewConstants.backupRestoreConfirmBodyHasData,
    actions: const [
      BackupSheetAction(
        value: CloudBackupRestoreMode.merge,
        labelKey: ViewConstants.backupChoiceMerge,
        hintKey: ViewConstants.backupChoiceMergeHint,
        key: Key('backup-choice-merge'),
        primary: true,
      ),
      BackupSheetAction(
        value: CloudBackupRestoreMode.replace,
        labelKey: ViewConstants.backupChoiceReplace,
        hintKey: ViewConstants.backupChoiceReplaceHint,
        key: Key('backup-choice-replace'),
      ),
    ],
  );
}

Future<CloudBackupEntry?> showBackupPickerSheet(
  BuildContext context,
  List<CloudBackupEntry> entries, {
  String? thisDeviceShortId,
}) {
  final theme = context.read<ThemeProvider>().baseTheme;
  return showModalBottomSheet<CloudBackupEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.surface,
    builder: (sheetContext) {
      return _BackupPicker(
        entries: entries,
        thisDeviceShortId: thisDeviceShortId,
      );
    },
  );
}

class _BackupPicker extends StatefulWidget {
  const _BackupPicker({
    required this.entries,
    required this.thisDeviceShortId,
  });

  final List<CloudBackupEntry> entries;
  final String? thisDeviceShortId;

  @override
  State<_BackupPicker> createState() => _BackupPickerState();
}

class _BackupPickerState extends State<_BackupPicker> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            key: const Key('backup-picker-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TranslatedText(
                ViewConstants.backupPickerTitle,
                style: ideaVaultHeadline(context, size: 22),
              ),
              const Gap(12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.entries.length,
                  itemBuilder: (itemContext, index) {
                    final entry = widget.entries[index];
                    final selected = index == _selected;
                    final details = [
                      if (entry.hasKnownCounts)
                        ViewConstants.backupPickerCounts.tr(
                          namedArgs: {
                            'ideas': '${entry.ideaCount}',
                            'notes': '${entry.randomAdditionCount}',
                          },
                        )
                      else
                        ViewConstants.backupPickerUnknownCounts.tr(),
                      if (entry.sizeBytes != null)
                        formatBackupBytes(entry.sizeBytes!),
                    ].join(' · ');
                    return ListTile(
                      key: Key('backup-picker-item-$index'),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => setState(() => _selected = index),
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected ? theme.primary : theme.textMuted,
                      ),
                      title: Text(
                        formatBackupDate(
                          context,
                          entry.modifiedAt ?? entry.createdAt,
                        ),
                        style: ideaVaultBody(
                          context,
                          size: 15,
                          weight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${backupDeviceLabel(entry, thisDeviceShortId: widget.thisDeviceShortId)}\n$details',
                        style: ideaVaultBody(
                          context,
                          size: 13,
                          color: theme.textMuted,
                        ),
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
              ),
              const Gap(12),
              FilledButton(
                key: const Key('backup-picker-continue'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: theme.onPrimary,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: widget.entries.isEmpty
                    ? null
                    : () => Navigator.of(context)
                        .pop(widget.entries[_selected]),
                child: TranslatedText(
                  ViewConstants.backupPickerContinue,
                  style: ideaVaultLabel(
                    context,
                    size: 15,
                    weight: FontWeight.w800,
                    color: theme.onPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: TranslatedText(ViewConstants.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
