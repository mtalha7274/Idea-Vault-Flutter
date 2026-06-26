import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_scheduler.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/core/services/backup/cloud_usage_metadata_sync_service.dart';
import 'package:idea_vault/core/services/backup/initial_cloud_auth_coordinator.dart';
import 'package:idea_vault/data/repositories/local/app_install_state.dart';
import 'package:idea_vault/data/repositories/local/cloud_backup_settings.dart';
import 'package:idea_vault/data/repositories/local/paid_feature_usage.dart';
import 'package:idea_vault/models/backup/cloud_backup_snapshot.dart';
import 'package:idea_vault/models/backup/cloud_backup_state.dart';
import 'package:idea_vault/models/backup/cloud_usage_metadata.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/random_addition.dart';
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';

import '../../helpers/memory_local_storage.dart';

void main() {
  group('CloudBackupProvider auto backup', () {
    late MemoryLocalStorageManager storage;
    late CloudBackupSettingsRepo settingsRepo;
    late AppInstallStateRepo installStateRepo;
    late InitialCloudAuthCoordinator coordinator;
    late _FakeCloudBackupService backupService;
    late _FakeCloudBackupScheduler scheduler;
    late CloudBackupProvider provider;

    CloudBackupProvider buildProvider({
      CloudUsageMetadataSyncService? usageMetadataSync,
    }) {
      return CloudBackupProvider(
        settingsRepo,
        backupService,
        scheduler,
        coordinator,
        usageMetadataSync: usageMetadataSync,
      );
    }

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
      installStateRepo = AppInstallStateRepo(storage);
      coordinator = InitialCloudAuthCoordinator(installStateRepo);
      backupService = _FakeCloudBackupService();
      scheduler = _FakeCloudBackupScheduler();
      provider = buildProvider();
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
      provider = buildProvider();

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
      provider = buildProvider();

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
      provider = buildProvider();

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
      provider = buildProvider();

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
      provider = buildProvider();

      await provider.runAutoBackupIfDue(sampleIdeas);

      expect(backupService.backUpCount, 1);
    });

    test('checkForFreshInstallBackup shows prompt when backup exists',
        () async {
      backupService.backupExistsResult = true;

      await provider.checkForFreshInstallBackup(hasLocalIdeas: false);

      expect(provider.state.restorePromptAvailable, isTrue);
      expect(provider.state.freshInstallRestoreCheckCompleted, isTrue);
      expect(backupService.backupExistsCount, 1);
    });

    test('checkForFreshInstallBackup skips when local ideas exist', () async {
      backupService.backupExistsResult = true;

      await provider.checkForFreshInstallBackup(hasLocalIdeas: true);

      expect(provider.state.restorePromptAvailable, isFalse);
      expect(provider.state.freshInstallRestoreCheckCompleted, isFalse);
      expect(backupService.backupExistsCount, 0);
    });

    test('checkForFreshInstallBackup runs cloud check only once per install',
        () async {
      backupService.backupExistsResult = true;

      await provider.checkForFreshInstallBackup(hasLocalIdeas: false);
      expect(backupService.backupExistsCount, 1);

      provider = buildProvider();
      await provider.checkForFreshInstallBackup(hasLocalIdeas: false);

      expect(backupService.backupExistsCount, 1);
      expect(provider.state.restorePromptAvailable, isTrue);
      expect(provider.state.freshInstallRestoreCheckCompleted, isTrue);
    });

    test('checkForFreshInstallBackup marks check completed when backup missing',
        () async {
      backupService.backupExistsResult = false;

      await provider.checkForFreshInstallBackup(hasLocalIdeas: false);

      expect(provider.state.restorePromptAvailable, isFalse);
      expect(provider.state.freshInstallRestoreCheckCompleted, isTrue);
      expect(backupService.backupExistsCount, 1);
    });

    test('checkForFreshInstallBackup marks check completed when cloud fails',
        () async {
      backupService.shouldThrowOnBackupExists = true;

      await provider.checkForFreshInstallBackup(hasLocalIdeas: false);

      expect(provider.state.restorePromptAvailable, isFalse);
      expect(provider.state.freshInstallRestoreCheckCompleted, isTrue);
      expect(backupService.backupExistsCount, 1);
    });

    test('dismissRestorePrompt clears fresh install prompt', () async {
      backupService.backupExistsResult = true;
      await provider.checkForFreshInstallBackup(hasLocalIdeas: false);

      await provider.dismissRestorePrompt();

      expect(provider.state.restorePromptAvailable, isFalse);
      expect(provider.state.freshInstallRestoreCheckCompleted, isTrue);
    });

    test('dismissRestorePrompt persists dismissal across provider reload',
        () async {
      backupService.backupExistsResult = true;
      await provider.checkForFreshInstallBackup(hasLocalIdeas: false);
      await provider.dismissRestorePrompt();

      provider = buildProvider();

      expect(provider.state.restorePromptAvailable, isFalse);
      expect(provider.state.freshInstallRestoreCheckCompleted, isTrue);
      expect(backupService.backupExistsCount, 1);
    });

    test('checkForFreshInstallBackup syncs usage metadata during initial auth',
        () async {
      backupService.restoreUsageMetadataResult = CloudUsageMetadata(
        version: CloudUsageMetadata.currentVersion,
        updatedAt: DateTime.utc(2026, 6, 25),
        usageCount: 2,
        freeUsageGrantLimit: 5,
        introSeen: true,
        halfLimitReviewRequested: false,
      );
      final usageRepo = PaidFeatureUsageRepo(storage);
      provider = buildProvider(
        usageMetadataSync: CloudUsageMetadataSyncService(
          usageRepo,
          backupService,
        ),
      );

      await provider.checkForFreshInstallBackup(hasLocalIdeas: false);

      expect(backupService.restoreUsageMetadataCount, 1);
      expect(usageRepo.usageCount, 2);
      expect(installStateRepo.hasInitialCloudAuthCheckCompleted, isTrue);
    });

    test('syncUsageMetadataFromCloud overrides local usage on restore', () async {
      backupService.restoreUsageMetadataResult = CloudUsageMetadata(
        version: CloudUsageMetadata.currentVersion,
        updatedAt: DateTime.utc(2026, 6, 25),
        usageCount: 1,
        freeUsageGrantLimit: 12,
        introSeen: false,
        halfLimitReviewRequested: false,
      );
      final usageRepo = PaidFeatureUsageRepo(storage);
      await usageRepo.incrementUsage();
      await usageRepo.incrementUsage();
      await usageRepo.incrementUsage();
      await usageRepo.markFreeUsageIntroSeen();
      provider = buildProvider(
        usageMetadataSync: CloudUsageMetadataSyncService(
          usageRepo,
          backupService,
        ),
      );

      await provider.syncUsageMetadataFromCloud(overrideLocal: true);

      expect(backupService.restoreUsageMetadataCount, 1);
      expect(usageRepo.usageCount, 1);
      expect(usageRepo.freeUsageGrantLimit, 12);
      expect(usageRepo.hasSeenFreeUsageIntro, isFalse);
    });

    test('fetchRestoreSnapshot delegates to backup service', () async {
      final snapshot = CloudBackupSnapshot.fromIdeas(sampleIdeas);
      backupService.restoreSnapshotResult = snapshot;

      final result = await provider.fetchRestoreSnapshot();

      expect(result, same(snapshot));
      expect(backupService.restoreSnapshotCount, 1);
    });
  });
}

class _FakeCloudBackupService extends CloudBackupService {
  int backUpCount = 0;
  int backupExistsCount = 0;
  int restoreSnapshotCount = 0;
  int restoreUsageMetadataCount = 0;
  bool backupExistsResult = false;
  bool shouldThrowOnBackupExists = false;
  CloudBackupSnapshot? restoreSnapshotResult;
  CloudUsageMetadata? restoreUsageMetadataResult;

  @override
  Future<int> backUpIdeas(
    List<Idea> ideas, {
    List<RandomAddition> randomAdditions = const [],
    bool silentAuth = false,
  }) async {
    backUpCount += 1;
    return 128;
  }

  @override
  Future<bool> backupExists() async {
    backupExistsCount += 1;
    if (shouldThrowOnBackupExists) {
      throw StateError('Cloud backup check failed');
    }
    return backupExistsResult;
  }

  @override
  Future<CloudBackupSnapshot?> restoreSnapshot() async {
    restoreSnapshotCount += 1;
    return restoreSnapshotResult;
  }

  @override
  Future<CloudUsageMetadata?> restoreUsageMetadata({
    bool silentAuth = false,
  }) async {
    restoreUsageMetadataCount += 1;
    return restoreUsageMetadataResult;
  }
}

class _FakeCloudBackupScheduler extends CloudBackupScheduler {
  int scheduleCount = 0;

  @override
  Future<void> scheduleDailyBackup() async {
    scheduleCount += 1;
  }
}
