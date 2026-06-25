import 'package:flutter/foundation.dart';

import '../../../core/services/backup/cloud_backup_scheduler.dart';
import '../../../core/services/backup/cloud_backup_service.dart';
import '../../../core/services/backup/cloud_usage_metadata_sync_service.dart';
import '../../../data/repositories/local/cloud_backup_settings.dart';
import '../../../models/backup/cloud_backup_snapshot.dart';
import '../../../models/backup/cloud_backup_state.dart';
import '../../../models/idea.dart';
import '../../../models/random_addition.dart';

class CloudBackupProvider with ChangeNotifier {
  CloudBackupProvider(
    this._settingsRepo,
    this._backupService,
    this._scheduler, {
    CloudUsageMetadataSyncService? usageMetadataSync,
  })  : _usageMetadataSync = usageMetadataSync,
        _state = _settingsRepo.getState();

  final CloudBackupSettingsRepo _settingsRepo;
  final CloudBackupService _backupService;
  final CloudBackupScheduler _scheduler;
  final CloudUsageMetadataSyncService? _usageMetadataSync;

  CloudBackupState _state;
  CloudBackupState get state => _state;

  Future<void> enableCloudBackup() async {
    await _runBusy(() async {
      final account =
          await _backupService.connect(forceAccountPicker: !_state.enabled);
      if (account == null) {
        return;
      }
      _state = _state.copyWith(
        enabled: true,
        autoBackupEnabled: true,
        email: account.email,
      );
      await _settingsRepo.saveState(_state);
      await _usageMetadataSync?.syncFromCloud(silentAuth: false);
      await _usageMetadataSync?.syncToCloud(silentAuth: true);
      await _scheduler.scheduleDailyBackup();
    });
  }

  Future<void> disableCloudBackup() async {
    await _runBusy(() async {
      await _backupService.disconnect();
      await _scheduler.cancelDailyBackup();
      _state = const CloudBackupState.initial();
      await _settingsRepo.clear();
    });
  }

  Future<void> disableCloudBackupForUsageLimit() async {
    await _runBusy(() async {
      try {
        await _backupService.disconnect();
      } catch (_) {}
      await _scheduler.cancelDailyBackup();
      _state = const CloudBackupState.initial();
      await _settingsRepo.clear();
    });
  }

  Future<void> changeAccount() async {
    await _runBusy(() async {
      final account = await _backupService.connect(forceAccountPicker: true);
      if (account == null) {
        return;
      }
      _state = _state.copyWith(email: account.email, enabled: true);
      await _settingsRepo.saveState(_state);
      await _usageMetadataSync?.syncFromCloud(silentAuth: false);
      await _usageMetadataSync?.syncToCloud(silentAuth: true);
    });
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    _state = _state.copyWith(autoBackupEnabled: enabled);
    notifyListeners();
    await _settingsRepo.saveState(_state);
    if (enabled) {
      await _scheduler.scheduleDailyBackup();
    } else {
      await _scheduler.cancelDailyBackup();
    }
  }

  Future<void> backUpNow(
    List<Idea> ideas, {
    List<RandomAddition> randomAdditions = const [],
  }) async {
    await _runBusy(() async {
      final sizeBytes = await _backupService.backUpIdeas(
        ideas,
        randomAdditions: randomAdditions,
      );
      _state = _state.copyWith(
        lastBackupAt: DateTime.now(),
        lastBackupSizeBytes: sizeBytes,
      );
      await _settingsRepo.saveState(_state);
      await _usageMetadataSync?.syncToCloud();
    });
  }

  Future<void> initializeAutoBackup() async {
    if (!_state.enabled || !_state.autoBackupEnabled) {
      return;
    }
    await _scheduler.scheduleDailyBackup();
  }

  Future<void> runAutoBackupIfDue(
    List<Idea> ideas, {
    List<RandomAddition> randomAdditions = const [],
  }) async {
    if (!_state.enabled || !_state.autoBackupEnabled || _state.isBusy) {
      return;
    }
    if (_state.lastBackupAt != null &&
        DateTime.now().difference(_state.lastBackupAt!) <
            CloudBackupScheduler.backupInterval) {
      return;
    }
    await backUpNow(ideas, randomAdditions: randomAdditions);
  }

  Future<CloudBackupSnapshot?> fetchRestoreSnapshot() async {
    return _backupService.restoreSnapshot();
  }

  Future<void> syncUsageMetadataFromCloud({bool silentAuth = true}) async {
    await _usageMetadataSync?.syncFromCloud(silentAuth: silentAuth);
  }

  Future<void> checkForFreshInstallBackup({required bool hasLocalIdeas}) async {
    if (hasLocalIdeas || _state.restorePromptAvailable) {
      return;
    }

    try {
      final exists = await _backupService.backupExists();
      if (exists) {
        _state = _state.copyWith(restorePromptAvailable: true);
        notifyListeners();
      }
    } catch (_) {
      // The prompt is opportunistic; a failed cloud check should not block app
      // launch or local idea access.
    }
  }

  void dismissRestorePrompt() {
    if (!_state.restorePromptAvailable) {
      return;
    }
    _state = _state.copyWith(restorePromptAvailable: false);
    notifyListeners();
  }

  Future<void> _runBusy(Future<void> Function() body) async {
    _state = _state.copyWith(isBusy: true);
    notifyListeners();
    try {
      await body();
    } finally {
      _state = _state.copyWith(isBusy: false);
      notifyListeners();
    }
  }
}
