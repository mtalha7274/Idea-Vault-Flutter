import '../idea.dart';
import '../random_addition.dart';
import '../vault/vault_lock_block.dart';
import 'cloud_backup_entry.dart';
import 'cloud_backup_error.dart';
import 'cloud_backup_snapshot.dart';

enum CloudBackupRestoreMode { replace, merge }

class LocalVaultContent {
  const LocalVaultContent({
    required this.ideas,
    required this.randomAdditions,
    this.lock,
  });

  static const LocalVaultContent empty = LocalVaultContent(
    ideas: [],
    randomAdditions: [],
  );

  final List<Idea> ideas;
  final List<RandomAddition> randomAdditions;
  final VaultLockBlock? lock;

  bool get isEmpty => ideas.isEmpty && randomAdditions.isEmpty;
  bool get isNotEmpty => !isEmpty;
  bool get hasEncryptedIdeas => ideas.any((idea) => idea.isEncrypted);

  LocalVaultContent withLock(VaultLockBlock? lock) {
    return LocalVaultContent(
      ideas: ideas,
      randomAdditions: randomAdditions,
      lock: lock,
    );
  }
}

class CloudBackupMergeResult {
  const CloudBackupMergeResult({
    required this.added,
    required this.copies,
    required this.skippedIdentical,
  });

  static const CloudBackupMergeResult none = CloudBackupMergeResult(
    added: 0,
    copies: 0,
    skippedIdentical: 0,
  );

  final int added;
  final int copies;
  final int skippedIdentical;
}

class CloudBackupRestorePreview {
  const CloudBackupRestorePreview({
    required this.entry,
    required this.snapshot,
  });

  final CloudBackupEntry entry;
  final CloudBackupSnapshot snapshot;
}

class CloudBackupRestoreResult {
  const CloudBackupRestoreResult({
    required this.mode,
    required this.ideaCount,
    required this.randomAdditionCount,
    this.merge,
    this.lockedNotImported = 0,
    this.needsVaultUnlock = false,
  });

  final CloudBackupRestoreMode mode;
  final int ideaCount;
  final int randomAdditionCount;
  final CloudBackupMergeResult? merge;
  final int lockedNotImported;
  final bool needsVaultUnlock;
}

typedef BackupVaultKeyPrompt = Future<List<int>?> Function(
  VaultLockBlock block,
);

enum CloudBackupEnablePromptKind { restoreOrStartFresh, mergeReplaceOrKeep }

enum CloudBackupEnableChoice { restore, startFresh, merge, replace, keepLocal }

class CloudBackupEnablePrompt {
  const CloudBackupEnablePrompt({
    required this.kind,
    required this.entry,
    this.snapshot,
    this.snapshotError,
  });

  final CloudBackupEnablePromptKind kind;
  final CloudBackupEntry entry;
  final CloudBackupSnapshot? snapshot;
  final CloudBackupErrorType? snapshotError;

  int? get ideaCount => snapshot?.ideaCount ?? entry.ideaCount;
  int? get randomAdditionCount =>
      snapshot?.randomAdditionCount ?? entry.randomAdditionCount;
  DateTime? get createdAt => snapshot?.createdAt ?? entry.createdAt;
  String? get deviceName => snapshot?.deviceName ?? entry.deviceName;
}

typedef CloudBackupEnableChooser = Future<CloudBackupEnableChoice?> Function(
  CloudBackupEnablePrompt prompt,
);

enum CloudBackupEnableStatus { enabled, cancelled, failed }

enum CloudBackupRunOutcome {
  uploaded,
  pending,
  unchanged,
  skippedDisabled,
  skippedUnresolved,
  skippedNotDue,
  skippedEmpty,
  skippedBusy,
  needsEmptyConfirmation,
  failed,
}

class CloudBackupRunResult {
  const CloudBackupRunResult(
    this.outcome, {
    this.errorType,
    this.sizeBytes,
    this.error,
  });

  final CloudBackupRunOutcome outcome;
  final CloudBackupErrorType? errorType;
  final int? sizeBytes;
  final Object? error;

  bool get didUpload =>
      outcome == CloudBackupRunOutcome.uploaded ||
      outcome == CloudBackupRunOutcome.pending;
}

class CloudBackupEnableResult {
  const CloudBackupEnableResult(
    this.status, {
    this.errorType,
    this.firstBackup,
    this.restore,
  });

  final CloudBackupEnableStatus status;
  final CloudBackupErrorType? errorType;
  final CloudBackupRunResult? firstBackup;
  final CloudBackupRestoreResult? restore;

  bool get changedLocalData => restore != null;
}
