import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_scheduler.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/data/repositories/local/cloud_backup_settings.dart';
import 'package:idea_vault/models/backup/cloud_backup_state.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/random_addition.dart';
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';

import '../../helpers/memory_local_storage.dart';

void main() {
  group('CloudBackupProvider auto backup', () {
    late MemoryLocalStorageManager storage;
    late CloudBackupSettingsRepo settingsRepo;
    late _FakeCloudBackupService backupService;
    late _FakeCloudBackupScheduler scheduler;
    late CloudBackupProvider provider;

    final sampleIdeas = [
      Idea(
        id: 'idea-1',
        title: 'Test',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        sections: [],
      ),
    ];

    setUp(() {
      storage = MemoryLocalStorageManager();
      settingsRepo = CloudBackupSettingsRepo(storage);
      backupService = _FakeCloudBackupService();
      scheduler = _FakeCloudBackupScheduler();
      provider = CloudBackupProvider(
        settingsRepo,
        backupService,
        scheduler,
      );
    });

    test('initializeAutoBackup schedules when enabled with auto backup on',
        () async {
      await settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          autoBackupEnabled: true,
          email: 'user@example.com',
        ),
      );
      provider = CloudBackupProvider(
        settingsRepo,
        backupService,
        scheduler,
      );

      await provider.initializeAutoBackup();

      expect(scheduler.scheduleCount, 1);
    });

    test('initializeAutoBackup skips when cloud backup disabled', () async {
      await provider.initializeAutoBackup();

      expect(scheduler.scheduleCount, 0);
    });

    test('initializeAutoBackup skips when auto backup disabled', () async {
      await settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          autoBackupEnabled: false,
          email: 'user@example.com',
        ),
      );
      provider = CloudBackupProvider(
        settingsRepo,
        backupService,
        scheduler,
      );

      await provider.initializeAutoBackup();

      expect(scheduler.scheduleCount, 0);
    });

    test('runAutoBackupIfDue runs when last backup is null', () async {
      await settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          autoBackupEnabled: true,
          email: 'user@example.com',
        ),
      );
      provider = CloudBackupProvider(
        settingsRepo,
        backupService,
        scheduler,
      );

      await provider.runAutoBackupIfDue(sampleIdeas);

      expect(backupService.backUpCount, 1);
      expect(provider.state.lastBackupAt, isNotNull);
    });

    test('runAutoBackupIfDue skips when backup is recent', () async {
      await settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          autoBackupEnabled: true,
          email: 'user@example.com',
          lastBackupAt: DateTime.now(),
        ),
      );
      provider = CloudBackupProvider(
        settingsRepo,
        backupService,
        scheduler,
      );

      await provider.runAutoBackupIfDue(sampleIdeas);

      expect(backupService.backUpCount, 0);
    });

    test('runAutoBackupIfDue runs when backup is stale', () async {
      await settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          autoBackupEnabled: true,
          email: 'user@example.com',
          lastBackupAt: DateTime.now().subtract(
            CloudBackupScheduler.backupInterval + const Duration(hours: 1),
          ),
        ),
      );
      provider = CloudBackupProvider(
        settingsRepo,
        backupService,
        scheduler,
      );

      await provider.runAutoBackupIfDue(sampleIdeas);

      expect(backupService.backUpCount, 1);
    });
  });
}

class _FakeCloudBackupService extends CloudBackupService {
  int backUpCount = 0;

  @override
  Future<int> backUpIdeas(
    List<Idea> ideas, {
    List<RandomAddition> randomAdditions = const [],
    bool silentAuth = false,
  }) async {
    backUpCount += 1;
    return 128;
  }
}

class _FakeCloudBackupScheduler extends CloudBackupScheduler {
  int scheduleCount = 0;

  @override
  Future<void> scheduleDailyBackup() async {
    scheduleCount += 1;
  }
}
