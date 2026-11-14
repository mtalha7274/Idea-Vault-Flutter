import '../../../data/repositories/local/backup_device_identity.dart';
import '../../../data/repositories/local/cloud_backup_settings.dart';
import '../../../models/backup/cloud_backup_error.dart';
import '../../../models/backup/cloud_backup_restore.dart';
import '../../../models/backup/cloud_backup_snapshot.dart';
import '../../../models/backup/cloud_backup_state.dart';
import 'cloud_backup_error_classifier.dart';
import 'cloud_backup_scheduler.dart';
import 'cloud_backup_service.dart';
import 'cloud_backup_store.dart';
import 'cloud_backup_upload_lock.dart';

typedef LocalVaultLoader = Future<LocalVaultContent> Function();

class CloudBackupCoordinator {
  CloudBackupCoordinator({
    required CloudBackupSettingsRepo settingsRepo,
    required CloudBackupService service,
    required BackupDeviceIdentityRepo deviceIdentityRepo,
    required CloudBackupUploadLock lock,
    String appVersion = '',
    Future<void> Function()? reloadStorage,
    DateTime Function()? clock,
  })  : _settingsRepo = settingsRepo,
        _service = service,
        _deviceIdentityRepo = deviceIdentityRepo,
        _lock = lock,
        _appVersion = appVersion,
        _reloadStorage = reloadStorage,
        _clock = clock ?? DateTime.now;

  static const Duration backupInterval = CloudBackupScheduler.backupInterval;
  static const Duration failureRetryDelay = Duration(minutes: 15);

  final CloudBackupSettingsRepo _settingsRepo;
  final CloudBackupService _service;
  final BackupDeviceIdentityRepo _deviceIdentityRepo;
  final CloudBackupUploadLock _lock;
  final String _appVersion;
  final Future<void> Function()? _reloadStorage;
  final DateTime Function() _clock;

  Future<void> reloadStorage() async {
    final reload = _reloadStorage;
    if (reload == null) {
      return;
    }
    try {
      await reload();
    } catch (_) {}
  }

  bool isDue(CloudBackupStatus status, DateTime now) {
    final pendingAt = status.pendingUploadAt;
    if (status.hasPendingUpload &&
        pendingAt != null &&
        now.difference(pendingAt) < backupInterval) {
      return false;
    }
    final lastAttempt = status.lastAttemptAt;
    if (status.consecutiveFailures > 0 &&
        lastAttempt != null &&
        now.difference(lastAttempt).abs() < failureRetryDelay) {
      return false;
    }
    final lastBackup = status.lastBackupAt;
    if (lastBackup == null) {
      return true;
    }
    return now.difference(lastBackup) >= backupInterval ||
        now.isBefore(lastBackup.subtract(const Duration(hours: 1)));
  }

  Future<CloudBackupRunResult> runAutoBackupIfDue(
    LocalVaultLoader loadContent,
  ) async {
    await reloadStorage();
    final state = _settingsRepo.getState();
    if (!state.enabled || !state.autoBackupEnabled) {
      return const CloudBackupRunResult(CloudBackupRunOutcome.skippedDisabled);
    }
    if (!state.remoteStateResolved) {
      return const CloudBackupRunResult(
        CloudBackupRunOutcome.skippedUnresolved,
      );
    }
    await confirmPendingUpload();
    final status = _settingsRepo.getStatus();
    if (!isDue(status, _clock())) {
      return const CloudBackupRunResult(CloudBackupRunOutcome.skippedNotDue);
    }
    final content = await loadContent();
    if (content.isEmpty) {
      return const CloudBackupRunResult(CloudBackupRunOutcome.skippedEmpty);
    }
    return _performBackup(content, silentAuth: true);
  }

  Future<CloudBackupRunResult> backUpNow(
    LocalVaultLoader loadContent, {
    bool allowEmpty = false,
    bool silentAuth = false,
  }) async {
    await reloadStorage();
    final content = await loadContent();
    if (content.isEmpty && !allowEmpty) {
      try {
        final entries = await _service.listBackups(silentAuth: silentAuth);
        if (entries.any((entry) => entry.isLegacy || !entry.isEmpty)) {
          return const CloudBackupRunResult(
            CloudBackupRunOutcome.needsEmptyConfirmation,
          );
        }
      } catch (error) {
        final type = CloudBackupErrorClassifier.classify(error);
        await _recordFailure(type);
        return CloudBackupRunResult(
          CloudBackupRunOutcome.failed,
          errorType: type,
          error: error,
        );
      }
    }
    return _performBackup(content, silentAuth: silentAuth);
  }

  Future<CloudBackupUploadState?> confirmPendingUpload() async {
    final status = _settingsRepo.getStatus();
    final pendingName = status.pendingUploadFileName;
    if (pendingName == null) {
      return null;
    }
    final CloudBackupUploadState uploadState;
    try {
      uploadState = await _service.uploadState(pendingName);
    } catch (_) {
      return null;
    }
    if (uploadState == CloudBackupUploadState.pending) {
      return uploadState;
    }
    await _updateStatus((current) {
      if (current.pendingUploadFileName != pendingName) {
        return current;
      }
      if (uploadState == CloudBackupUploadState.complete) {
        return current
            .recordSuccess(
              at: current.pendingUploadAt ?? _clock(),
              sizeBytes: current.pendingUploadSizeBytes,
              uploadedHash: current.pendingUploadHash,
              uploadedFileName: pendingName,
            )
            .copyWith(lastAttemptAt: current.lastAttemptAt);
      }
      return current.copyWith(clearPending: true);
    });
    if (uploadState == CloudBackupUploadState.complete) {
      final identity = _deviceIdentityRepo.read();
      if (identity != null) {
        await _service.rotateBackups(deviceShortId: identity.shortId);
      }
    }
    return uploadState;
  }

  Future<CloudBackupRunResult> _performBackup(
    LocalVaultContent content, {
    required bool silentAuth,
  }) async {
    final identity = _deviceIdentityRepo.read();
    if (identity == null) {
      return const CloudBackupRunResult(
        CloudBackupRunOutcome.failed,
        errorType: CloudBackupErrorType.unknown,
      );
    }
    if (!await _lock.acquire()) {
      return const CloudBackupRunResult(CloudBackupRunOutcome.skippedBusy);
    }
    try {
      final now = _clock();
      final snapshot = CloudBackupSnapshot.fromContent(
        ideas: content.ideas,
        randomAdditions: content.randomAdditions,
        deviceId: identity.id,
        deviceName: identity.name,
        appVersion: _appVersion,
        createdAt: now,
        lock: content.lock,
      );
      final fingerprint = snapshot.uploadFingerprint;
      final status = _settingsRepo.getStatus();
      final lastName = status.lastUploadedFileName;
      if (lastName != null && status.lastUploadedHash == fingerprint) {
        final entries = await _service.listBackups(silentAuth: silentAuth);
        if (entries.any((entry) => entry.fileName == lastName)) {
          await _updateStatus(
            (current) =>
                current.recordSuccess(at: now).copyWith(clearPending: true),
          );
          return const CloudBackupRunResult(CloudBackupRunOutcome.unchanged);
        }
      }

      final upload = await _service.uploadSnapshot(
        snapshot,
        deviceShortId: identity.shortId,
        silentAuth: silentAuth,
      );
      if (upload.pending) {
        await _updateStatus(
          (current) => current.copyWith(
            lastAttemptAt: now,
            consecutiveFailures: 0,
            clearLastError: true,
            clearFirstFailureAt: true,
            pendingUploadFileName: upload.fileName,
            pendingUploadAt: now,
            pendingUploadSizeBytes: upload.sizeBytes,
            pendingUploadHash: fingerprint,
          ),
        );
        return CloudBackupRunResult(
          CloudBackupRunOutcome.pending,
          sizeBytes: upload.sizeBytes,
        );
      }
      await _updateStatus(
        (current) => current.recordSuccess(
          at: now,
          sizeBytes: upload.sizeBytes,
          uploadedHash: fingerprint,
          uploadedFileName: upload.fileName,
        ),
      );
      await _service.rotateBackups(
        deviceShortId: identity.shortId,
        silentAuth: true,
      );
      return CloudBackupRunResult(
        CloudBackupRunOutcome.uploaded,
        sizeBytes: upload.sizeBytes,
      );
    } catch (error) {
      final type = CloudBackupErrorClassifier.classify(error);
      await _recordFailure(type);
      return CloudBackupRunResult(
        CloudBackupRunOutcome.failed,
        errorType: type,
        error: error,
      );
    } finally {
      await _lock.release();
    }
  }

  Future<void> _recordFailure(CloudBackupErrorType type) {
    return _updateStatus(
      (current) => current.recordFailure(at: _clock(), type: type),
    );
  }

  Future<void> _updateStatus(
    CloudBackupStatus Function(CloudBackupStatus current) update,
  ) async {
    await reloadStorage();
    final current = _settingsRepo.getStatus();
    await _settingsRepo.saveStatus(update(current));
  }
}
