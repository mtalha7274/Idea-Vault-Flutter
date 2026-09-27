import 'package:flutter/foundation.dart';

import '../../../core/services/backup/cloud_backup_scheduler.dart';
import '../../../core/services/backup/cloud_backup_service.dart';
import '../../../core/services/backup/initial_cloud_auth_coordinator.dart';
import '../../../data/repositories/local/cloud_backup_settings.dart';
import '../../../models/backup/cloud_backup_snapshot.dart';
import '../../../models/backup/cloud_backup_state.dart';
import '../../../models/idea.dart';
import '../../../models/random_addition.dart';

class CloudBackupProvider with ChangeNotifier {
  CloudBackupProvider(
    this._settingsRepo,
    this._backupService,
    this._scheduler,
    this._initialCloudAuthCoordinator,
  ) : _state = _settingsRepo.getState();

  final CloudBackupSettingsRepo _settingsRepo;
  final CloudBackupService _backupService;
  final CloudBackupScheduler _scheduler;
  final InitialCloudAuthCoordinator _initialCloudAuthCoordinator;

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

  Future<void> changeAccount() async {
    await _runBusy(() async {
      final account = await _backupService.connect(forceAccountPicker: true);
      if (account == null) {
        return;
      }
      _state = _state.copyWith(email: account.email, enabled: true);
      await _settingsRepo.saveState(_state);
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
    bool silentAuth = false,
  }) async {
    await _runBusy(() async {
      final sizeBytes = await _backupService.backUpIdeas(
        ideas,
        randomAdditions: randomAdditions,
        silentAuth: silentAuth,
      );
      _state = _state.copyWith(
        lastBackupAt: DateTime.now(),
        lastBackupSizeBytes: sizeBytes,
      );
      await _settingsRepo.saveState(_state);
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
    // Auto backup runs on cold start and on resume, without the user asking for
    // it, so it must never be allowed to put an account picker or a consent
    // screen on screen. If authorization has lapsed the backup is simply
    // skipped until the user triggers one from the backup screen.
    await backUpNow(
      ideas,
      randomAdditions: randomAdditions,
      silentAuth: true,
    );
  }

  Future<CloudBackupSnapshot?> fetchRestoreSnapshot() async {
    return _backupService.restoreSnapshot();
  }

  Future<void> checkForFreshInstallBackup({required bool hasLocalIdeas}) async {
    if (hasLocalIdeas ||
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
        await _settingsRepo.saveState(_state);
        notifyListeners();
      } catch (_) {
        _state = _state.copyWith(freshInstallRestoreCheckCompleted: true);
        await _settingsRepo.saveState(_state);
      }
    });
  }

  Future<void> dismissRestorePrompt() async {
    if (!_state.restorePromptAvailable) {
      return;
    }
    _state = _state.copyWith(restorePromptAvailable: false);
    await _settingsRepo.saveState(_state);
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
