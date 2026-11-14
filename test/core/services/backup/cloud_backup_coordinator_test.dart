import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_background_task.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_coordinator.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_store.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_upload_lock.dart';
import 'package:idea_vault/models/backup/cloud_backup_entry.dart';
import 'package:idea_vault/models/backup/cloud_backup_error.dart';
import 'package:idea_vault/models/backup/cloud_backup_restore.dart';
import 'package:idea_vault/models/backup/cloud_backup_state.dart';

import '../../../helpers/backup_test_harness.dart';

void main() {
  group('CloudBackupCoordinator', () {
    late DateTime now;
    late BackupTestHarness harness;
    late String shortId;

    final content = LocalVaultContent(
      ideas: [backupTestIdea('a')],
      randomAdditions: [backupTestNote('n')],
    );

    CloudBackupCoordinator buildCoordinator({String owner = 'foreground'}) {
      return CloudBackupCoordinator(
        settingsRepo: harness.settingsRepo,
        service: harness.service,
        deviceIdentityRepo: harness.identityRepo,
        lock: CloudBackupUploadLock(
          harness.storage,
          owner: owner,
          clock: () => now,
        ),
        appVersion: '2.0.0+5',
        clock: () => now,
      );
    }

    Future<void> saveSettings({
      bool enabled = true,
      bool auto = true,
      bool resolved = true,
      CloudBackupStatus status = CloudBackupStatus.empty,
    }) {
      return harness.settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: enabled,
          autoBackupEnabled: auto,
          remoteStateResolved: resolved,
          email: 'writer@example.com',
          status: status,
        ),
      );
    }

    setUp(() async {
      now = DateTime.utc(2026, 11, 13, 12);
      harness = BackupTestHarness(clock: () => now);
      shortId = await harness.ensureIdentity();
    });

    test('auto backup refuses to run until the cloud state is resolved',
        () async {
      await saveSettings(resolved: false);

      final result =
          await buildCoordinator().runAutoBackupIfDue(() async => content);

      expect(result.outcome, CloudBackupRunOutcome.skippedUnresolved);
      expect(harness.store.writeCount, 0);
    });

    test('auto backup skips when cloud backup or auto backup is off',
        () async {
      await saveSettings(auto: false);

      final result =
          await buildCoordinator().runAutoBackupIfDue(() async => content);

      expect(result.outcome, CloudBackupRunOutcome.skippedDisabled);
      expect(harness.store.writeCount, 0);
    });

    test('foreground auto backup never uploads an empty vault', () async {
      await saveSettings();

      final result = await buildCoordinator()
          .runAutoBackupIfDue(() async => LocalVaultContent.empty);

      expect(result.outcome, CloudBackupRunOutcome.skippedEmpty);
      expect(harness.store.writeCount, 0);
    });

    test('background auto backup never uploads an empty vault', () async {
      await saveSettings();

      final result = await CloudBackupBackgroundTask.run(
        storage: harness.storage,
        service: harness.service,
        loadContent: () async => LocalVaultContent.empty,
        clock: () => now,
      );

      expect(result.outcome, CloudBackupRunOutcome.skippedEmpty);
      expect(harness.store.writeCount, 0);
    });

    test('a vault with only random notes counts as non-empty', () async {
      await saveSettings();

      final result = await buildCoordinator().runAutoBackupIfDue(
        () async => LocalVaultContent(
          ideas: const [],
          randomAdditions: [backupTestNote('only')],
        ),
      );

      expect(result.outcome, CloudBackupRunOutcome.uploaded);
    });

    test('uploads a new named file per backup without pretty printing',
        () async {
      await saveSettings();

      final result =
          await buildCoordinator().runAutoBackupIfDue(() async => content);

      expect(result.outcome, CloudBackupRunOutcome.uploaded);
      expect(harness.store.lastWriteSilentAuth, isTrue);
      final name = harness.store.fileNames.single;
      final entry = CloudBackupEntry.fromFile(fileId: name, fileName: name)!;
      expect(entry.deviceShortId, shortId);
      expect(entry.ideaCount, 1);
      expect(entry.randomAdditionCount, 1);
      final contents = harness.store.files[name]!.contents;
      expect(contents.contains('\n'), isFalse);
      expect((jsonDecode(contents) as Map)['deviceName'], 'Test Phone');

      final status = harness.settingsRepo.getStatus();
      expect(status.lastBackupAt, now);
      expect(status.lastUploadedFileName, name);
      expect(status.consecutiveFailures, 0);
    });

    test('does not run again before 24 hours have passed', () async {
      await saveSettings();
      final coordinator = buildCoordinator();
      await coordinator.runAutoBackupIfDue(() async => content);

      now = now.add(const Duration(hours: 5));
      final result = await coordinator.runAutoBackupIfDue(
        () async => LocalVaultContent(
          ideas: [backupTestIdea('changed')],
          randomAdditions: const [],
        ),
      );

      expect(result.outcome, CloudBackupRunOutcome.skippedNotDue);
      expect(harness.store.writeCount, 1);
    });

    test('skips the upload when content is unchanged and records a check',
        () async {
      await saveSettings();
      final coordinator = buildCoordinator();
      await coordinator.runAutoBackupIfDue(() async => content);

      now = now.add(const Duration(days: 2));
      final result = await coordinator.runAutoBackupIfDue(() async => content);

      expect(result.outcome, CloudBackupRunOutcome.unchanged);
      expect(harness.store.writeCount, 1);
      expect(harness.store.files, hasLength(1));
      expect(harness.settingsRepo.getStatus().lastBackupAt, now);
    });

    test('uploads again when the last uploaded file is gone from the cloud',
        () async {
      await saveSettings();
      final coordinator = buildCoordinator();
      await coordinator.runAutoBackupIfDue(() async => content);
      harness.store.files.clear();

      now = now.add(const Duration(days: 2));
      final result = await coordinator.runAutoBackupIfDue(() async => content);

      expect(result.outcome, CloudBackupRunOutcome.uploaded);
      expect(harness.store.writeCount, 2);
    });

    test('rotates old snapshots of this device after a successful upload',
        () async {
      await saveSettings();
      final coordinator = buildCoordinator();
      for (var day = 0; day < 9; day++) {
        await coordinator.runAutoBackupIfDue(
          () async => LocalVaultContent(
            ideas: [backupTestIdea('idea-$day')],
            randomAdditions: const [],
          ),
        );
        now = now.add(const Duration(days: 1));
      }

      expect(harness.store.writeCount, 9);
      expect(harness.store.files, hasLength(7));
    });

    test('a failed delete during rotation never fails the backup', () async {
      await saveSettings();
      final coordinator = buildCoordinator();
      for (var day = 0; day < 7; day++) {
        await coordinator.runAutoBackupIfDue(
          () async => LocalVaultContent(
            ideas: [backupTestIdea('idea-$day')],
            randomAdditions: const [],
          ),
        );
        now = now.add(const Duration(days: 1));
      }
      harness.store.deleteError = StateError('delete failed');

      final result = await coordinator.runAutoBackupIfDue(() async => content);

      expect(result.outcome, CloudBackupRunOutcome.uploaded);
      expect(harness.settingsRepo.getStatus().consecutiveFailures, 0);
    });

    test('records sign-in required without prompting when auth lapsed',
        () async {
      await saveSettings();
      harness.store.requireAuthWhenSilent = true;

      final result =
          await buildCoordinator().runAutoBackupIfDue(() async => content);

      expect(result.outcome, CloudBackupRunOutcome.failed);
      expect(result.errorType, CloudBackupErrorType.signInRequired);
      expect(harness.store.connectCount, 0);
      final status = harness.settingsRepo.getStatus();
      expect(status.lastErrorType, CloudBackupErrorType.signInRequired);
      expect(status.consecutiveFailures, 1);
      expect(status.firstFailureAt, now);
      expect(status.lastAttemptAt, now);
    });

    test('skips while another isolate holds a fresh upload lock', () async {
      await saveSettings();
      final other = CloudBackupUploadLock(
        harness.storage,
        owner: CloudBackupUploadLock.backgroundOwner,
        clock: () => now,
      );
      expect(await other.acquire(), isTrue);

      final result =
          await buildCoordinator().runAutoBackupIfDue(() async => content);

      expect(result.outcome, CloudBackupRunOutcome.skippedBusy);
      expect(harness.store.writeCount, 0);
    });

    test('treats an upload lock older than 10 minutes as stale', () async {
      await saveSettings();
      final other = CloudBackupUploadLock(
        harness.storage,
        owner: CloudBackupUploadLock.backgroundOwner,
        clock: () => now.subtract(const Duration(minutes: 11)),
      );
      expect(await other.acquire(), isTrue);

      final result =
          await buildCoordinator().runAutoBackupIfDue(() async => content);

      expect(result.outcome, CloudBackupRunOutcome.uploaded);
    });

    test('background run only writes status, never user settings', () async {
      await saveSettings();
      final before = harness.storage.getString(key: 'cloud_backup_settings_v1');

      await CloudBackupBackgroundTask.run(
        storage: harness.storage,
        service: harness.service,
        loadContent: () async => content,
        clock: () => now,
      );

      expect(harness.store.writeCount, 1);
      expect(
        harness.storage.getString(key: 'cloud_backup_settings_v1'),
        before,
      );
      expect(harness.settingsRepo.getStatus().lastBackupAt, now);
    });

    test('background run reloads storage before reading settings', () async {
      await saveSettings(enabled: false);
      var reloads = 0;

      final result = await CloudBackupBackgroundTask.run(
        storage: harness.storage,
        service: harness.service,
        loadContent: () async => content,
        clock: () => now,
        reloadStorage: () async {
          reloads += 1;
          if (reloads == 1) {
            await saveSettings();
          }
        },
      );

      expect(reloads, greaterThan(0));
      expect(result.outcome, CloudBackupRunOutcome.uploaded);
    });

    test('pending iCloud upload is confirmed on the next run', () async {
      await saveSettings();
      harness.store.writePending = true;
      harness.store.uploadStateResult = CloudBackupUploadState.pending;
      final coordinator = buildCoordinator();

      final first = await coordinator.runAutoBackupIfDue(() async => content);
      expect(first.outcome, CloudBackupRunOutcome.pending);
      expect(harness.settingsRepo.getStatus().hasPendingUpload, isTrue);
      expect(harness.settingsRepo.getStatus().lastBackupAt, isNull);

      now = now.add(const Duration(hours: 1));
      final second = await coordinator.runAutoBackupIfDue(() async => content);
      expect(second.outcome, CloudBackupRunOutcome.skippedNotDue);

      harness.store.uploadStateResult = CloudBackupUploadState.complete;
      await coordinator.confirmPendingUpload();
      final status = harness.settingsRepo.getStatus();
      expect(status.hasPendingUpload, isFalse);
      expect(status.lastBackupAt, isNotNull);
      expect(status.lastUploadedFileName, harness.store.fileNames.single);
    });

    test('manual backup of an empty vault asks first when a backup exists',
        () async {
      await saveSettings();
      putBackupFile(harness.store, ideas: [backupTestIdea('old')]);
      final coordinator = buildCoordinator();

      final first = await coordinator.backUpNow(
        () async => LocalVaultContent.empty,
      );
      expect(first.outcome, CloudBackupRunOutcome.needsEmptyConfirmation);
      expect(harness.store.writeCount, 0);

      final confirmed = await coordinator.backUpNow(
        () async => LocalVaultContent.empty,
        allowEmpty: true,
      );
      expect(confirmed.outcome, CloudBackupRunOutcome.uploaded);
      expect(harness.store.files, hasLength(2));
    });
  });
}
