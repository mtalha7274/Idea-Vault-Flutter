import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/view_constants.dart';
import '../../../core/services/backup/backup_vault_reconciler.dart';
import '../../../core/services/backup/cloud_backup_coordinator.dart';
import '../../../core/services/backup/cloud_backup_error_classifier.dart';
import '../../../core/services/backup/cloud_backup_merge.dart';
import '../../../core/services/backup/cloud_backup_scheduler.dart';
import '../../../core/services/backup/cloud_backup_service.dart';
import '../../../core/services/backup/cloud_backup_upload_lock.dart';
import '../../../core/services/backup/initial_cloud_auth_coordinator.dart';
import '../../../core/services/backup/restore_safety_copy_store.dart';
import '../../../core/services/backup/vault_plaintext_cleanup.dart';
import '../../../core/services/vault/note_vault_service.dart';
import '../../../data/repositories/local/backup_device_identity.dart';
import '../../../data/repositories/local/cloud_backup_settings.dart';
import '../../../data/repositories/local/idea_editor_state.dart';
import '../../../data/repositories/local/local_vault.dart';
import '../../../models/backup/backup_device_identity.dart';
import '../../../models/backup/cloud_backup_account.dart';
import '../../../models/backup/cloud_backup_entry.dart';
import '../../../models/backup/cloud_backup_error.dart';
import '../../../models/backup/cloud_backup_restore.dart';
import '../../../models/backup/cloud_backup_snapshot.dart';
import '../../../models/backup/cloud_backup_state.dart';
import '../../../models/idea.dart';
import '../../../models/random_addition.dart';

enum CloudBackupBannerKind { backupFound, haveBackup }

class CloudBackupProvider with ChangeNotifier {
  CloudBackupProvider(
    this._settingsRepo,
    this._backupService,
    this._scheduler,
    this._initialCloudAuthCoordinator, {
    LocalVaultRepo? localVaultRepo,
    RestoreSafetyCopyStore? safetyCopyStore,
    BackupDeviceIdentityRepo? deviceIdentityRepo,
    IdeaEditorStateRepo? editorStateRepo,
    CloudBackupCoordinator? coordinator,
    Future<void> Function()? reloadStorage,
    bool? isIOS,
    DateTime Function()? clock,
    String appVersion = '',
    String deviceName = '',
    MergeCopyTitleBuilder? copyTitle,
    NoteVaultService? vault,
    Future<void> Function()? onVaultAdopted,
  })  : _state = _settingsRepo.getState(),
        _vault = vault,
        _onVaultAdopted = onVaultAdopted,
        _localVaultRepo = localVaultRepo,
        _safetyCopyStore = safetyCopyStore,
        _editorStateRepo = editorStateRepo,
        _isIOS = isIOS,
        _clock = clock ?? DateTime.now,
        _deviceName = deviceName,
        _copyTitle = copyTitle ?? _defaultCopyTitle,
        _deviceIdentityRepo = deviceIdentityRepo ??
            BackupDeviceIdentityRepo(_settingsRepo.storage) {
    _coordinator = coordinator ??
        CloudBackupCoordinator(
          settingsRepo: _settingsRepo,
          service: _backupService,
          deviceIdentityRepo: _deviceIdentityRepo,
          lock: CloudBackupUploadLock(
            _settingsRepo.storage,
            owner: CloudBackupUploadLock.foregroundOwner,
            reloadStorage: reloadStorage,
            clock: _clock,
          ),
          appVersion: appVersion,
          reloadStorage: reloadStorage,
          clock: _clock,
        );
  }

  static const Duration undoRestoreWindow = Duration(days: 7);

  final CloudBackupSettingsRepo _settingsRepo;
  final CloudBackupService _backupService;
  final CloudBackupScheduler _scheduler;
  final InitialCloudAuthCoordinator _initialCloudAuthCoordinator;
  final LocalVaultRepo? _localVaultRepo;
  final RestoreSafetyCopyStore? _safetyCopyStore;
  final BackupDeviceIdentityRepo _deviceIdentityRepo;
  final IdeaEditorStateRepo? _editorStateRepo;
  final bool? _isIOS;
  final DateTime Function() _clock;
  final String _deviceName;
  final MergeCopyTitleBuilder _copyTitle;
  final NoteVaultService? _vault;
  final Future<void> Function()? _onVaultAdopted;
  late final CloudBackupCoordinator _coordinator;
  bool _cleanupRunning = false;

  CloudBackupState _state;
  bool _autoBackupRunning = false;
  List<CloudBackupEntry> _entries = const [];

  CloudBackupState get state => _state;
  bool get isIOS => _isIOS ?? _backupService.usesICloud;
  bool get isWorking => _state.isBusy || _autoBackupRunning;
  DateTime get now => _clock();
  CloudBackupHealth get health => _state.health(now);
  bool get needsAttention => _state.needsAttention(now);
  bool get canUndoRestore => _state.canUndoRestore(now);
  List<CloudBackupEntry> get knownEntries => List.unmodifiable(_entries);
  bool get plaintextCleanupPending => _settingsRepo.plaintextCleanupPending;
  bool get isPlaintextCleanupRunning => _cleanupRunning;
  String? get deviceShortId => _deviceIdentityRepo.read()?.shortId;

  List<CloudBackupEntry> get otherDeviceEntries {
    final mine = deviceShortId;
    final seen = <String>{};
    final result = <CloudBackupEntry>[];
    for (final entry in _entries) {
      final shortId = entry.deviceShortId;
      if (entry.isLegacy || shortId == null || shortId == mine) {
        continue;
      }
      if (seen.add(shortId)) {
        result.add(entry);
      }
    }
    return result;
  }

  static String _defaultCopyTitle(String title, bool fromBackup) {
    final key = fromBackup
        ? ViewConstants.backupMergeCopyFromBackup
        : ViewConstants.backupMergeCopyFromDevice;
    return key.tr(namedArgs: {'title': title});
  }

  CloudBackupBannerKind? restoreBannerKind({required bool hasLocalContent}) {
    if (hasLocalContent) {
      return null;
    }
    if (_state.restorePromptAvailable) {
      return CloudBackupBannerKind.backupFound;
    }
    if (!isIOS && !_state.restoreCardCompleted && !_state.enabled) {
      return CloudBackupBannerKind.haveBackup;
    }
    return null;
  }

  Future<void> refreshFromStorage() async {
    await _coordinator.reloadStorage();
    _reloadState();
    notifyListeners();
  }

  Future<CloudBackupEnableResult> enableCloudBackup({
    CloudBackupEnableChooser? choose,
    LocalVaultContent? local,
    BackupVaultKeyPrompt? askBackupKey,
  }) {
    return _runEnableFlow(
      choose: choose,
      local: local,
      askBackupKey: askBackupKey,
      forceAccountPicker: !_state.enabled,
      revertOnFailure: true,
      resetAutoBackup: true,
    );
  }

  Future<CloudBackupEnableResult> finishSetup({
    CloudBackupEnableChooser? choose,
    LocalVaultContent? local,
    BackupVaultKeyPrompt? askBackupKey,
  }) {
    return _runEnableFlow(
      choose: choose,
      local: local,
      askBackupKey: askBackupKey,
      forceAccountPicker: false,
      revertOnFailure: false,
      resetAutoBackup: false,
    );
  }

  Future<CloudBackupEnableResult> changeAccount({
    CloudBackupEnableChooser? choose,
    LocalVaultContent? local,
    BackupVaultKeyPrompt? askBackupKey,
  }) async {
    if (_state.isBusy) {
      return const CloudBackupEnableResult(CloudBackupEnableStatus.cancelled);
    }
    await _safeCancelSchedule();
    _state = _state.copyWith(
      remoteStateResolved: false,
      status: CloudBackupStatus.empty,
    );
    await _settingsRepo.saveSettings(_state);
    await _settingsRepo.clearStatus();
    notifyListeners();
    return _runEnableFlow(
      choose: choose,
      local: local,
      askBackupKey: askBackupKey,
      forceAccountPicker: true,
      revertOnFailure: true,
      resetAutoBackup: false,
    );
  }

  Future<void> disableCloudBackup() async {
    await _runBusy(() async {
      try {
        await _backupService.signOut();
      } catch (_) {}
      await _safeCancelSchedule();
      _state = const CloudBackupState.initial().copyWith(
        isBusy: true,
        freshInstallRestoreCheckCompleted:
            _state.freshInstallRestoreCheckCompleted,
        restoreCardCompleted: _state.restoreCardCompleted,
        undoRestoreCopyId: _state.undoRestoreCopyId,
        undoRestoreAvailableUntil: _state.undoRestoreAvailableUntil,
      );
      _entries = const [];
      await _settingsRepo.saveSettings(_state);
      await _settingsRepo.clearStatus();
    });
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    _state = _state.copyWith(autoBackupEnabled: enabled);
    notifyListeners();
    await _settingsRepo.saveSettings(_state);
    if (enabled && _state.enabled && _state.remoteStateResolved) {
      await _scheduler.scheduleDailyBackup();
    } else if (!enabled) {
      await _scheduler.cancelDailyBackup();
    }
  }

  Future<CloudBackupRunResult> backUpNow(
    List<Idea> ideas, {
    List<RandomAddition> randomAdditions = const [],
    bool silentAuth = false,
    bool allowEmpty = false,
  }) async {
    if (_state.isBusy) {
      return const CloudBackupRunResult(CloudBackupRunOutcome.skippedBusy);
    }
    var result = const CloudBackupRunResult(CloudBackupRunOutcome.skippedBusy);
    await _runBusy(() async {
      result = await _coordinator.backUpNow(
        () => _withLock(
          LocalVaultContent(
            ideas: ideas,
            randomAdditions: randomAdditions,
          ),
        ),
        allowEmpty: allowEmpty,
        silentAuth: silentAuth,
      );
      _reloadState();
    });
    return result;
  }

  Future<void> initializeAutoBackup() async {
    if (!_state.enabled ||
        !_state.autoBackupEnabled ||
        !_state.remoteStateResolved) {
      return;
    }
    await _scheduler.scheduleDailyBackup();
  }

  Future<CloudBackupRunResult> runAutoBackupIfDue(
    List<Idea> ideas, {
    List<RandomAddition> randomAdditions = const [],
  }) async {
    if (_state.isBusy || _autoBackupRunning) {
      return const CloudBackupRunResult(CloudBackupRunOutcome.skippedBusy);
    }
    _autoBackupRunning = true;
    try {
      final result = await _coordinator.runAutoBackupIfDue(
        () => _withLock(
          LocalVaultContent(
            ideas: ideas,
            randomAdditions: randomAdditions,
          ),
        ),
      );
      _reloadState();
      return result;
    } finally {
      _autoBackupRunning = false;
      notifyListeners();
    }
  }

  Future<void> resolvePendingRemoteState({LocalVaultContent? local}) async {
    if (!_state.enabled || _state.remoteStateResolved || _state.isBusy) {
      return;
    }
    final List<CloudBackupEntry> entries;
    try {
      entries = await _backupService.listBackups(silentAuth: true);
    } catch (_) {
      return;
    }
    _entries = entries;
    final identity = await _identity();
    final content = local ?? await _readLocal();
    if (entries.isEmpty || entries.first.deviceShortId == identity.shortId) {
      _state = _state.copyWith(remoteStateResolved: true);
      await _settingsRepo.saveSettings(_state);
      if (_state.autoBackupEnabled) {
        await _safeSchedule();
      }
    } else if (content.isEmpty && !_state.restorePromptAvailable) {
      _state = _state.copyWith(restorePromptAvailable: true);
      await _settingsRepo.saveSettings(_state);
    }
    notifyListeners();
  }

  Future<void> refreshCloudEntries() async {
    if (!_state.enabled) {
      return;
    }
    try {
      _entries = await _backupService.listBackups(silentAuth: true);
      notifyListeners();
    } catch (_) {}
  }

  Future<CloudBackupSnapshot?> fetchRestoreSnapshot() async {
    return _backupService.restoreSnapshot();
  }

  Future<void> checkForFreshInstallBackup({
    required bool hasLocalContent,
  }) async {
    if (!isIOS ||
        hasLocalContent ||
        _state.freshInstallRestoreCheckCompleted ||
        _initialCloudAuthCoordinator.isCompleted) {
      return;
    }

    await _initialCloudAuthCoordinator.runOncePerInstall(() async {
      try {
        final exists = await _backupService.backupExists();
        _state = _state.copyWith(
          freshInstallRestoreCheckCompleted: true,
          restorePromptAvailable: exists,
        );
        await _settingsRepo.saveSettings(_state);
        notifyListeners();
      } catch (_) {
        _state = _state.copyWith(freshInstallRestoreCheckCompleted: true);
        await _settingsRepo.saveSettings(_state);
      }
    });
  }

  Future<void> dismissRestorePrompt() async {
    if (!_state.restorePromptAvailable && _state.restoreCardCompleted) {
      return;
    }
    _state = _state.copyWith(
      restorePromptAvailable: false,
      restoreCardCompleted: true,
    );
    await _settingsRepo.saveSettings(_state);
    notifyListeners();
  }

  Future<List<CloudBackupEntry>> listRestoreEntries() {
    return _runBusyValue(() async {
      await _connectForRead();
      final entries = await _backupService.listBackups();
      _entries = entries;
      return entries;
    });
  }

  Future<CloudBackupRestorePreview> prepareRestore(CloudBackupEntry entry) {
    return _runBusyValue(() async {
      final snapshot = await _backupService.downloadSnapshot(entry);
      return CloudBackupRestorePreview(entry: entry, snapshot: snapshot);
    });
  }

  Future<CloudBackupRestorePreview?> prepareNewestRestore() {
    return _runBusyValue(() async {
      await _connectForRead();
      final entries = await _backupService.listBackups();
      _entries = entries;
      if (entries.isEmpty) {
        return null;
      }
      final newest = entries.first;
      final snapshot = await _backupService.downloadSnapshot(newest);
      return CloudBackupRestorePreview(entry: newest, snapshot: snapshot);
    });
  }

  Future<CloudBackupRestoreResult> restore(
    CloudBackupSnapshot snapshot,
    CloudBackupRestoreMode mode, {
    LocalVaultContent? local,
    BackupVaultKeyPrompt? askBackupKey,
  }) {
    return _runBusyValue(
      () => _applyRestore(
        snapshot,
        mode,
        local: local,
        askBackupKey: askBackupKey,
      ),
    );
  }

  Future<void> markPlaintextCleanupPending() async {
    await _settingsRepo.setPlaintextCleanupPending(true);
    notifyListeners();
  }

  Future<bool> runPlaintextCleanup(
    List<Idea> ideas, {
    List<RandomAddition> randomAdditions = const [],
  }) async {
    if (!plaintextCleanupPending) {
      return true;
    }
    final stillPlain = ideas.any(
      (idea) => idea.isLocked && !idea.isEncrypted,
    );
    if (stillPlain || !_state.enabled || _cleanupRunning || _state.isBusy) {
      return false;
    }
    _cleanupRunning = true;
    notifyListeners();
    try {
      final backup = await _coordinator.backUpNow(
        () => _withLock(
          LocalVaultContent(ideas: ideas, randomAdditions: randomAdditions),
        ),
        allowEmpty: true,
        silentAuth: true,
      );
      _reloadState();
      if (backup.outcome != CloudBackupRunOutcome.uploaded &&
          backup.outcome != CloudBackupRunOutcome.unchanged &&
          backup.outcome != CloudBackupRunOutcome.pending) {
        return false;
      }
      final status = _settingsRepo.getStatus();
      final keep = {
        if (status.lastUploadedFileName != null) status.lastUploadedFileName!,
        if (status.pendingUploadFileName != null) status.pendingUploadFileName!,
      };
      final result = await VaultPlaintextCleanup.run(
        service: _backupService,
        keepFileNames: keep,
      );
      if (result.isComplete) {
        await _settingsRepo.setPlaintextCleanupPending(false);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _cleanupRunning = false;
      notifyListeners();
    }
  }

  Future<LocalVaultContent> _withLock(LocalVaultContent content) async {
    if (content.lock != null) {
      return content;
    }
    final repo = _localVaultRepo;
    if (repo == null) {
      return content;
    }
    try {
      return content.withLock(await repo.readLock());
    } catch (_) {
      return content;
    }
  }

  Future<void> undoRestore() {
    return _runBusyValue(() async {
      final copyId = _state.undoRestoreCopyId;
      final store = _safetyCopyStore;
      final repo = _requireVaultRepo();
      if (copyId == null || store == null || !canUndoRestore) {
        throw const CloudBackupException(CloudBackupErrorType.noBackupFound);
      }
      final content = await store.read(copyId);
      if (content == null) {
        throw const CloudBackupException(CloudBackupErrorType.noBackupFound);
      }
      final current = await repo.read();
      if (current.isNotEmpty) {
        await store.save(current);
      }
      final replaceLock = content.lock != null || !content.hasEncryptedIdeas;
      await repo.replaceAll(content, replaceLock: replaceLock);
      final restoredKeyId = content.lock?.keyId;
      if (replaceLock &&
          restoredKeyId != null &&
          restoredKeyId != current.lock?.keyId) {
        await _onVaultAdopted?.call();
      }
      await _editorStateRepo?.clearState();
      _state = _state.copyWith(clearUndoRestore: true);
      await _settingsRepo.saveSettings(_state);
    });
  }

  Future<int> deleteCloudBackups() {
    return _runBusyValue(() async {
      await _connectForRead();
      final deleted = await _backupService.deleteAllBackups();
      _entries = const [];
      await _coordinator.reloadStorage();
      final status = _settingsRepo.getStatus();
      await _settingsRepo.saveStatus(
        status.copyWith(clearLastUpload: true, clearPending: true),
      );
      _reloadState();
      return deleted;
    });
  }

  Future<CloudBackupEnableResult> _runEnableFlow({
    required CloudBackupEnableChooser? choose,
    required LocalVaultContent? local,
    BackupVaultKeyPrompt? askBackupKey,
    required bool forceAccountPicker,
    required bool revertOnFailure,
    required bool resetAutoBackup,
  }) async {
    if (_state.isBusy) {
      return const CloudBackupEnableResult(CloudBackupEnableStatus.cancelled);
    }
    _setBusy(true);
    try {
      final CloudBackupAccount? account;
      try {
        account = await _backupService.connect(
          forceAccountPicker: forceAccountPicker,
        );
      } catch (error) {
        return _enableFailed(
          CloudBackupErrorClassifier.classify(error),
          revertOnFailure,
        );
      }
      if (account == null) {
        return _enableFailed(
          CloudBackupErrorType.signInCancelled,
          revertOnFailure,
        );
      }

      final List<CloudBackupEntry> entries;
      try {
        entries = await _backupService.listBackups();
      } catch (error) {
        return _enableFailed(
          CloudBackupErrorClassifier.classify(error),
          revertOnFailure,
        );
      }
      _entries = entries;
      final localContent = await _withLock(local ?? await _readLocal());
      final identity = await _identity();

      if (entries.isEmpty) {
        await _markEnabled(account, resetAutoBackup: resetAutoBackup);
        CloudBackupRunResult? firstBackup;
        if (localContent.isNotEmpty) {
          firstBackup = await _coordinator.backUpNow(() async => localContent);
          _reloadState();
        }
        return CloudBackupEnableResult(
          CloudBackupEnableStatus.enabled,
          firstBackup: firstBackup,
        );
      }

      final newest = entries.first;
      if (localContent.isNotEmpty &&
          !newest.isLegacy &&
          newest.deviceShortId == identity.shortId) {
        await _markEnabled(account, resetAutoBackup: resetAutoBackup);
        return const CloudBackupEnableResult(CloudBackupEnableStatus.enabled);
      }

      CloudBackupSnapshot? snapshot;
      CloudBackupErrorType? snapshotError;
      try {
        snapshot = await _backupService.downloadSnapshot(newest);
      } catch (error) {
        final type = CloudBackupErrorClassifier.classify(error);
        if (!type.isValidationFailure) {
          return _enableFailed(type, revertOnFailure);
        }
        snapshotError = type;
      }

      final prompt = CloudBackupEnablePrompt(
        kind: localContent.isEmpty
            ? CloudBackupEnablePromptKind.restoreOrStartFresh
            : CloudBackupEnablePromptKind.mergeReplaceOrKeep,
        entry: newest,
        snapshot: snapshot,
        snapshotError: snapshotError,
      );
      final choice = choose == null ? null : await choose(prompt);
      switch (choice) {
        case null:
          if (revertOnFailure) {
            await _revertToOff();
          }
          return const CloudBackupEnableResult(
            CloudBackupEnableStatus.cancelled,
          );
        case CloudBackupEnableChoice.startFresh:
        case CloudBackupEnableChoice.keepLocal:
          await _markEnabled(account, resetAutoBackup: resetAutoBackup);
          return const CloudBackupEnableResult(
            CloudBackupEnableStatus.enabled,
          );
        case CloudBackupEnableChoice.restore:
        case CloudBackupEnableChoice.replace:
        case CloudBackupEnableChoice.merge:
          if (snapshot == null) {
            return _enableFailed(
              snapshotError ?? CloudBackupErrorType.invalidBackup,
              revertOnFailure,
            );
          }
          final CloudBackupRestoreResult restored;
          try {
            restored = await _applyRestore(
              snapshot,
              choice == CloudBackupEnableChoice.merge
                  ? CloudBackupRestoreMode.merge
                  : CloudBackupRestoreMode.replace,
              local: localContent,
              askBackupKey: askBackupKey,
            );
          } catch (error) {
            return _enableFailed(
              CloudBackupErrorClassifier.classify(error),
              revertOnFailure,
            );
          }
          await _markEnabled(account, resetAutoBackup: resetAutoBackup);
          return CloudBackupEnableResult(
            CloudBackupEnableStatus.enabled,
            restore: restored,
          );
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<CloudBackupEnableResult> _enableFailed(
    CloudBackupErrorType type,
    bool revertOnFailure,
  ) async {
    if (revertOnFailure) {
      await _revertToOff();
    }
    return CloudBackupEnableResult(
      CloudBackupEnableStatus.failed,
      errorType: type,
    );
  }

  Future<void> _revertToOff() async {
    if (!_state.enabled && !_state.remoteStateResolved) {
      return;
    }
    await _safeCancelSchedule();
    _state = _state.copyWith(enabled: false, remoteStateResolved: false);
    await _settingsRepo.saveSettings(_state);
  }

  Future<void> _markEnabled(
    CloudBackupAccount account, {
    required bool resetAutoBackup,
  }) async {
    _state = _state.copyWith(
      enabled: true,
      autoBackupEnabled: resetAutoBackup ? true : null,
      email: account.email,
      remoteStateResolved: true,
      restorePromptAvailable: false,
      restoreCardCompleted: true,
    );
    await _settingsRepo.saveSettings(_state);
    if (_state.autoBackupEnabled) {
      await _safeSchedule();
    }
  }

  Future<CloudBackupRestoreResult> _applyRestore(
    CloudBackupSnapshot snapshot,
    CloudBackupRestoreMode mode, {
    LocalVaultContent? local,
    BackupVaultKeyPrompt? askBackupKey,
  }) async {
    final repo = _requireVaultRepo();
    if (snapshot.isEmpty) {
      throw const CloudBackupException(CloudBackupErrorType.emptyBackup);
    }
    final current = await _withLock(local ?? await repo.read());
    final reconciler = BackupVaultReconciler(_vault);
    final preparation = await reconciler.prepare(
      local: current,
      backup: LocalVaultContent(
        ideas: snapshot.ideas,
        randomAdditions: snapshot.randomAdditions,
        lock: snapshot.lockBlock,
      ),
      mode: mode,
      askBackupKey: askBackupKey,
    );
    final backupContent = preparation.backup;

    String? safetyCopyId;
    final store = _safetyCopyStore;
    if (current.isNotEmpty && store != null) {
      safetyCopyId = (await store.save(current)).id;
    }

    final adoptLock = preparation.adoptLock;
    final CloudBackupRestoreResult result;
    if (mode == CloudBackupRestoreMode.replace) {
      if (adoptLock != null) {
        await repo.replaceAll(
          backupContent.withLock(adoptLock),
          replaceLock: true,
        );
      } else {
        await repo.replaceAll(backupContent);
      }
      result = CloudBackupRestoreResult(
        mode: mode,
        ideaCount: backupContent.ideas.length,
        randomAdditionCount: snapshot.randomAdditionCount,
        lockedNotImported: preparation.notImported,
        needsVaultUnlock: adoptLock != null,
      );
    } else {
      final rawPlan = CloudBackupMerge.plan(
        local: current,
        backup: backupContent,
        copyTitle: _copyTitle,
      );
      final plan = await reconciler.rebindCopies(rawPlan, preparation);
      final dropped = rawPlan.ideasToWrite.length - plan.ideasToWrite.length;
      await repo.writeMerged(
        ideas: plan.ideasToWrite,
        randomAdditions: plan.randomAdditionsToWrite,
        adoptLock: adoptLock,
      );
      result = CloudBackupRestoreResult(
        mode: mode,
        ideaCount: backupContent.ideas.length,
        randomAdditionCount: snapshot.randomAdditionCount,
        merge: plan.result,
        lockedNotImported: preparation.notImported + dropped,
        needsVaultUnlock: adoptLock != null,
      );
    }
    _vault?.releaseIfIdle();
    if (adoptLock != null) {
      await _onVaultAdopted?.call();
    }

    try {
      await _editorStateRepo?.clearState();
    } catch (_) {}

    _state = _state.copyWith(
      restorePromptAvailable: false,
      restoreCardCompleted: true,
      remoteStateResolved: _state.enabled ? true : null,
      undoRestoreCopyId: safetyCopyId,
      undoRestoreAvailableUntil:
          safetyCopyId == null ? null : now.add(undoRestoreWindow),
      clearUndoRestore: safetyCopyId == null,
    );
    await _settingsRepo.saveSettings(_state);
    notifyListeners();
    return result;
  }

  LocalVaultRepo _requireVaultRepo() {
    final repo = _localVaultRepo;
    if (repo == null) {
      throw StateError('Local vault repository is not configured.');
    }
    return repo;
  }

  Future<LocalVaultContent> _readLocal() async {
    return _requireVaultRepo().read();
  }

  Future<BackupDeviceIdentity> _identity() async {
    return _deviceIdentityRepo.read() ??
        await _deviceIdentityRepo.ensure(deviceName: _deviceName);
  }

  Future<void> _connectForRead() async {
    if (_state.enabled) {
      return;
    }
    final account = await _backupService.connect(forceAccountPicker: false);
    if (account == null) {
      throw const CloudBackupException(CloudBackupErrorType.signInCancelled);
    }
  }

  Future<void> _safeSchedule() async {
    try {
      await _scheduler.scheduleDailyBackup();
    } catch (_) {}
  }

  Future<void> _safeCancelSchedule() async {
    try {
      await _scheduler.cancelDailyBackup();
    } catch (_) {}
  }

  void _reloadState() {
    _state = _settingsRepo.getState().copyWith(isBusy: _state.isBusy);
  }

  void _setBusy(bool busy) {
    _state = _state.copyWith(isBusy: busy);
    notifyListeners();
  }

  Future<void> _runBusy(Future<void> Function() body) async {
    _setBusy(true);
    try {
      await body();
    } finally {
      _setBusy(false);
    }
  }

  Future<T> _runBusyValue<T>(Future<T> Function() body) async {
    _setBusy(true);
    try {
      return await body();
    } finally {
      _setBusy(false);
    }
  }
}
