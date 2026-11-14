import 'cloud_backup_error.dart';

enum CloudBackupHealth {
  off,
  needsSetup,
  healthy,
  stale,
  never,
  pending,
  failing,
}

class CloudBackupStatus {
  const CloudBackupStatus({
    this.lastAttemptAt,
    this.lastBackupAt,
    this.lastBackupSizeBytes,
    this.lastErrorType,
    this.consecutiveFailures = 0,
    this.firstFailureAt,
    this.lastUploadedHash,
    this.lastUploadedFileName,
    this.pendingUploadFileName,
    this.pendingUploadAt,
    this.pendingUploadSizeBytes,
    this.pendingUploadHash,
  });

  static const CloudBackupStatus empty = CloudBackupStatus();

  factory CloudBackupStatus.fromJson(Map<String, dynamic> json) {
    return CloudBackupStatus(
      lastAttemptAt: _date(json['lastAttemptAt']),
      lastBackupAt: _date(json['lastBackupAt']),
      lastBackupSizeBytes: json['lastBackupSizeBytes'] as int?,
      lastErrorType:
          CloudBackupErrorType.fromName(json['lastErrorType'] as String?),
      consecutiveFailures: json['consecutiveFailures'] as int? ?? 0,
      firstFailureAt: _date(json['firstFailureAt']),
      lastUploadedHash: json['lastUploadedHash'] as String?,
      lastUploadedFileName: json['lastUploadedFileName'] as String?,
      pendingUploadFileName: json['pendingUploadFileName'] as String?,
      pendingUploadAt: _date(json['pendingUploadAt']),
      pendingUploadSizeBytes: json['pendingUploadSizeBytes'] as int?,
      pendingUploadHash: json['pendingUploadHash'] as String?,
    );
  }

  final DateTime? lastAttemptAt;
  final DateTime? lastBackupAt;
  final int? lastBackupSizeBytes;
  final CloudBackupErrorType? lastErrorType;
  final int consecutiveFailures;
  final DateTime? firstFailureAt;
  final String? lastUploadedHash;
  final String? lastUploadedFileName;
  final String? pendingUploadFileName;
  final DateTime? pendingUploadAt;
  final int? pendingUploadSizeBytes;
  final String? pendingUploadHash;

  bool get hasPendingUpload => pendingUploadFileName != null;

  CloudBackupStatus copyWith({
    DateTime? lastAttemptAt,
    DateTime? lastBackupAt,
    bool clearLastBackupAt = false,
    int? lastBackupSizeBytes,
    bool clearLastBackupSizeBytes = false,
    CloudBackupErrorType? lastErrorType,
    bool clearLastError = false,
    int? consecutiveFailures,
    DateTime? firstFailureAt,
    bool clearFirstFailureAt = false,
    String? lastUploadedHash,
    String? lastUploadedFileName,
    bool clearLastUpload = false,
    String? pendingUploadFileName,
    DateTime? pendingUploadAt,
    int? pendingUploadSizeBytes,
    String? pendingUploadHash,
    bool clearPending = false,
  }) {
    return CloudBackupStatus(
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastBackupAt:
          clearLastBackupAt ? null : lastBackupAt ?? this.lastBackupAt,
      lastBackupSizeBytes: clearLastBackupSizeBytes
          ? null
          : lastBackupSizeBytes ?? this.lastBackupSizeBytes,
      lastErrorType: clearLastError ? null : lastErrorType ?? this.lastErrorType,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      firstFailureAt:
          clearFirstFailureAt ? null : firstFailureAt ?? this.firstFailureAt,
      lastUploadedHash:
          clearLastUpload ? null : lastUploadedHash ?? this.lastUploadedHash,
      lastUploadedFileName: clearLastUpload
          ? null
          : lastUploadedFileName ?? this.lastUploadedFileName,
      pendingUploadFileName: clearPending
          ? null
          : pendingUploadFileName ?? this.pendingUploadFileName,
      pendingUploadAt:
          clearPending ? null : pendingUploadAt ?? this.pendingUploadAt,
      pendingUploadSizeBytes: clearPending
          ? null
          : pendingUploadSizeBytes ?? this.pendingUploadSizeBytes,
      pendingUploadHash:
          clearPending ? null : pendingUploadHash ?? this.pendingUploadHash,
    );
  }

  CloudBackupStatus recordSuccess({
    required DateTime at,
    int? sizeBytes,
    String? uploadedHash,
    String? uploadedFileName,
  }) {
    return CloudBackupStatus(
      lastAttemptAt: at,
      lastBackupAt: at,
      lastBackupSizeBytes: sizeBytes ?? lastBackupSizeBytes,
      consecutiveFailures: 0,
      lastUploadedHash: uploadedHash ?? lastUploadedHash,
      lastUploadedFileName: uploadedFileName ?? lastUploadedFileName,
    );
  }

  CloudBackupStatus recordFailure({
    required DateTime at,
    required CloudBackupErrorType type,
  }) {
    return copyWith(
      lastAttemptAt: at,
      lastErrorType: type,
      consecutiveFailures: consecutiveFailures + 1,
      firstFailureAt: firstFailureAt ?? at,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      'lastBackupAt': lastBackupAt?.toIso8601String(),
      'lastBackupSizeBytes': lastBackupSizeBytes,
      'lastErrorType': lastErrorType?.name,
      'consecutiveFailures': consecutiveFailures,
      'firstFailureAt': firstFailureAt?.toIso8601String(),
      'lastUploadedHash': lastUploadedHash,
      'lastUploadedFileName': lastUploadedFileName,
      'pendingUploadFileName': pendingUploadFileName,
      'pendingUploadAt': pendingUploadAt?.toIso8601String(),
      'pendingUploadSizeBytes': pendingUploadSizeBytes,
      'pendingUploadHash': pendingUploadHash,
    };
  }

  static DateTime? _date(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

class CloudBackupState {
  CloudBackupState({
    required this.enabled,
    required this.autoBackupEnabled,
    required this.email,
    required this.isBusy,
    required this.restorePromptAvailable,
    required this.freshInstallRestoreCheckCompleted,
    DateTime? lastBackupAt,
    int? lastBackupSizeBytes,
    CloudBackupStatus? status,
    this.remoteStateResolved = false,
    this.restoreCardCompleted = false,
    this.undoRestoreCopyId,
    this.undoRestoreAvailableUntil,
  }) : status = status ??
            CloudBackupStatus(
              lastBackupAt: lastBackupAt,
              lastBackupSizeBytes: lastBackupSizeBytes,
            );

  const CloudBackupState.initial()
      : enabled = false,
        autoBackupEnabled = true,
        email = null,
        isBusy = false,
        restorePromptAvailable = false,
        freshInstallRestoreCheckCompleted = false,
        remoteStateResolved = false,
        restoreCardCompleted = false,
        undoRestoreCopyId = null,
        undoRestoreAvailableUntil = null,
        status = CloudBackupStatus.empty;

  static const Duration healthyWindow = Duration(hours: 48);
  static const Duration attentionAfterFailures = Duration(days: 3);

  final bool enabled;
  final bool autoBackupEnabled;
  final String? email;
  final bool isBusy;
  final bool restorePromptAvailable;
  final bool freshInstallRestoreCheckCompleted;
  final bool remoteStateResolved;
  final bool restoreCardCompleted;
  final String? undoRestoreCopyId;
  final DateTime? undoRestoreAvailableUntil;
  final CloudBackupStatus status;

  CloudBackupStatus get backupStatus => status;

  DateTime? get lastBackupAt => backupStatus.lastBackupAt;
  int? get lastBackupSizeBytes => backupStatus.lastBackupSizeBytes;
  CloudBackupErrorType? get lastErrorType => backupStatus.lastErrorType;

  bool canUndoRestore(DateTime now) {
    final until = undoRestoreAvailableUntil;
    return undoRestoreCopyId != null && until != null && now.isBefore(until);
  }

  CloudBackupHealth health(DateTime now) {
    if (!enabled) {
      return CloudBackupHealth.off;
    }
    if (!remoteStateResolved) {
      return CloudBackupHealth.needsSetup;
    }
    final current = backupStatus;
    final lastSuccess = current.lastBackupAt;
    final lastAttempt = current.lastAttemptAt;
    final failingNow = current.consecutiveFailures > 0 &&
        current.lastErrorType != null &&
        (lastSuccess == null ||
            lastAttempt == null ||
            lastAttempt.isAfter(lastSuccess));
    if (failingNow) {
      return CloudBackupHealth.failing;
    }
    if (current.hasPendingUpload) {
      return CloudBackupHealth.pending;
    }
    if (lastSuccess == null) {
      return CloudBackupHealth.never;
    }
    if (now.difference(lastSuccess) < healthyWindow) {
      return CloudBackupHealth.healthy;
    }
    return CloudBackupHealth.stale;
  }

  bool needsAttention(DateTime now) {
    if (!enabled) {
      return false;
    }
    if (!remoteStateResolved) {
      return true;
    }
    final current = backupStatus;
    if (current.consecutiveFailures == 0 || current.lastErrorType == null) {
      return false;
    }
    if (current.lastErrorType == CloudBackupErrorType.signInRequired) {
      return true;
    }
    final firstFailure = current.firstFailureAt;
    return firstFailure != null &&
        now.difference(firstFailure) >= attentionAfterFailures;
  }

  CloudBackupState copyWith({
    bool? enabled,
    bool? autoBackupEnabled,
    String? email,
    bool clearEmail = false,
    DateTime? lastBackupAt,
    bool clearLastBackupAt = false,
    int? lastBackupSizeBytes,
    bool clearLastBackupSizeBytes = false,
    bool? isBusy,
    bool? restorePromptAvailable,
    bool? freshInstallRestoreCheckCompleted,
    bool? remoteStateResolved,
    bool? restoreCardCompleted,
    String? undoRestoreCopyId,
    DateTime? undoRestoreAvailableUntil,
    bool clearUndoRestore = false,
    CloudBackupStatus? status,
  }) {
    var nextStatus = status ?? backupStatus;
    if (lastBackupAt != null ||
        clearLastBackupAt ||
        lastBackupSizeBytes != null ||
        clearLastBackupSizeBytes) {
      nextStatus = nextStatus.copyWith(
        lastBackupAt: lastBackupAt,
        clearLastBackupAt: clearLastBackupAt,
        lastBackupSizeBytes: lastBackupSizeBytes,
        clearLastBackupSizeBytes: clearLastBackupSizeBytes,
      );
    }
    return CloudBackupState(
      enabled: enabled ?? this.enabled,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      email: clearEmail ? null : email ?? this.email,
      isBusy: isBusy ?? this.isBusy,
      restorePromptAvailable:
          restorePromptAvailable ?? this.restorePromptAvailable,
      freshInstallRestoreCheckCompleted: freshInstallRestoreCheckCompleted ??
          this.freshInstallRestoreCheckCompleted,
      remoteStateResolved: remoteStateResolved ?? this.remoteStateResolved,
      restoreCardCompleted: restoreCardCompleted ?? this.restoreCardCompleted,
      undoRestoreCopyId: clearUndoRestore
          ? null
          : undoRestoreCopyId ?? this.undoRestoreCopyId,
      undoRestoreAvailableUntil: clearUndoRestore
          ? null
          : undoRestoreAvailableUntil ?? this.undoRestoreAvailableUntil,
      status: nextStatus,
    );
  }
}
