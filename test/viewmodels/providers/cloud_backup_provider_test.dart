import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/restore_safety_copy_store.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/models/backup/cloud_backup_entry.dart';
import 'package:idea_vault/models/backup/cloud_backup_error.dart';
import 'package:idea_vault/models/backup/cloud_backup_restore.dart';
import 'package:idea_vault/models/backup/cloud_backup_snapshot.dart';
import 'package:idea_vault/models/backup/cloud_backup_state.dart';
import 'package:idea_vault/models/idea_editor_state.dart';
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';

import '../../helpers/backup_test_harness.dart';

Matcher throwsBackupError(CloudBackupErrorType type) {
  return throwsA(
    isA<CloudBackupException>().having((error) => error.type, 'type', type),
  );
}

void main() {
  late DateTime now;
  late Directory safetyDirectory;
  late BackupTestHarness harness;
  late CloudBackupProvider provider;

  const otherDeviceId = 'ffffffff00000000ffffffff00000000';

  Future<void> seedLocal({int ideas = 1, int notes = 0}) async {
    await harness.vault.replaceAll(
      LocalVaultContent(
        ideas: [for (var i = 0; i < ideas; i++) backupTestIdea('local-$i')],
        randomAdditions: [
          for (var i = 0; i < notes; i++) backupTestNote('local-note-$i'),
        ],
      ),
    );
    harness.vault.replaceCount = 0;
  }

  setUp(() async {
    now = DateTime.utc(2026, 11, 13, 12);
    safetyDirectory = await Directory.systemTemp.createTemp('safety_copies_');
    harness = BackupTestHarness(
      clock: () => now,
      safetyDirectory: safetyDirectory,
    );
    provider = harness.buildProvider();
  });

  tearDown(() async {
    if (await safetyDirectory.exists()) {
      await safetyDirectory.delete(recursive: true);
    }
  });

  group('enable flow', () {
    test('no backup and empty device enables without uploading', () async {
      final result = await provider.enableCloudBackup();

      expect(result.status, CloudBackupEnableStatus.enabled);
      expect(provider.state.enabled, isTrue);
      expect(provider.state.remoteStateResolved, isTrue);
      expect(harness.store.writeCount, 0);
      expect(harness.scheduler.scheduleCount, 1);
    });

    test('no backup and local data runs the first backup immediately',
        () async {
      await seedLocal(ideas: 2);

      final result = await provider.enableCloudBackup();

      expect(result.status, CloudBackupEnableStatus.enabled);
      expect(result.firstBackup?.outcome, CloudBackupRunOutcome.uploaded);
      expect(harness.store.writeCount, 1);
      expect(provider.state.lastBackupAt, now);
    });

    test('backup exists and device is empty offers restore or start fresh',
        () async {
      putBackupFile(
        harness.store,
        ideas: [backupTestIdea('cloud-1'), backupTestIdea('cloud-2')],
        notes: [backupTestNote('cloud-note')],
      );
      CloudBackupEnablePrompt? seen;

      final result = await provider.enableCloudBackup(
        choose: (prompt) async {
          seen = prompt;
          return CloudBackupEnableChoice.restore;
        },
      );

      expect(seen?.kind, CloudBackupEnablePromptKind.restoreOrStartFresh);
      expect(seen?.ideaCount, 2);
      expect(seen?.randomAdditionCount, 1);
      expect(seen?.deviceName, 'Pixel 8');
      expect(result.status, CloudBackupEnableStatus.enabled);
      expect(result.restore?.mode, CloudBackupRestoreMode.replace);
      final local = await harness.vault.read();
      expect(local.ideas.map((idea) => idea.id),
          unorderedEquals(['cloud-1', 'cloud-2']));
      expect(provider.state.remoteStateResolved, isTrue);
      expect(harness.store.writeCount, 0);
    });

    test('start fresh resolves and deletes nothing in the cloud', () async {
      final name = putBackupFile(
        harness.store,
        ideas: [backupTestIdea('cloud-1')],
      );

      final result = await provider.enableCloudBackup(
        choose: (_) async => CloudBackupEnableChoice.startFresh,
      );

      expect(result.status, CloudBackupEnableStatus.enabled);
      expect(provider.state.remoteStateResolved, isTrue);
      expect(harness.store.fileNames, [name]);
      expect(harness.store.deleteCount, 0);
      expect(harness.store.writeCount, 0);
      expect((await harness.vault.read()).isEmpty, isTrue);
    });

    test('backup made by this device with local data enables silently',
        () async {
      final shortId = await harness.ensureIdentity();
      final identity = harness.identityRepo.read()!;
      putBackupFile(
        harness.store,
        ideas: [backupTestIdea('mine')],
        deviceId: identity.id,
      );
      expect(identity.shortId, shortId);
      await seedLocal();
      var prompted = false;

      final result = await provider.enableCloudBackup(
        choose: (_) async {
          prompted = true;
          return null;
        },
      );

      expect(prompted, isFalse);
      expect(result.status, CloudBackupEnableStatus.enabled);
      expect(provider.state.remoteStateResolved, isTrue);
    });

    test('backup from another device with local data offers merge', () async {
      putBackupFile(
        harness.store,
        ideas: [backupTestIdea('cloud-1')],
        deviceId: otherDeviceId,
      );
      await seedLocal();
      CloudBackupEnablePrompt? seen;

      final result = await provider.enableCloudBackup(
        choose: (prompt) async {
          seen = prompt;
          return CloudBackupEnableChoice.merge;
        },
      );

      expect(seen?.kind, CloudBackupEnablePromptKind.mergeReplaceOrKeep);
      expect(result.status, CloudBackupEnableStatus.enabled);
      expect(result.restore?.merge?.added, 1);
      final local = await harness.vault.read();
      expect(local.ideas.map((idea) => idea.id),
          unorderedEquals(['local-0', 'cloud-1']));
      expect(provider.state.remoteStateResolved, isTrue);
    });

    test('backup from another device can replace this device', () async {
      putBackupFile(
        harness.store,
        ideas: [backupTestIdea('cloud-1')],
        deviceId: otherDeviceId,
      );
      await seedLocal(ideas: 2);

      final result = await provider.enableCloudBackup(
        choose: (_) async => CloudBackupEnableChoice.replace,
      );

      expect(result.status, CloudBackupEnableStatus.enabled);
      final local = await harness.vault.read();
      expect(local.ideas.single.id, 'cloud-1');
      expect(provider.canUndoRestore, isTrue);
    });

    test('backup from another device can keep this device data', () async {
      final name = putBackupFile(
        harness.store,
        ideas: [backupTestIdea('cloud-1')],
        deviceId: otherDeviceId,
      );
      await seedLocal(ideas: 2);

      final result = await provider.enableCloudBackup(
        choose: (_) async => CloudBackupEnableChoice.keepLocal,
      );

      expect(result.status, CloudBackupEnableStatus.enabled);
      expect((await harness.vault.read()).ideas, hasLength(2));
      expect(harness.store.fileNames, [name]);
      expect(provider.state.remoteStateResolved, isTrue);
    });

    test('closing the sheet cancels: switch off and nothing resolved',
        () async {
      final name = putBackupFile(
        harness.store,
        ideas: [backupTestIdea('cloud-1')],
      );

      final result = await provider.enableCloudBackup(
        choose: (_) async => null,
      );

      expect(result.status, CloudBackupEnableStatus.cancelled);
      expect(provider.state.enabled, isFalse);
      expect(provider.state.remoteStateResolved, isFalse);

      now = now.add(const Duration(days: 1));
      final auto = await provider.runAutoBackupIfDue(const []);
      expect(auto.outcome, CloudBackupRunOutcome.skippedDisabled);
      expect(harness.store.fileNames, [name]);
      expect(harness.store.writeCount, 0);
    });

    test('offline check failure keeps backup off with a specific error',
        () async {
      harness.store.listError = const SocketException('offline');

      final result = await provider.enableCloudBackup();

      expect(result.status, CloudBackupEnableStatus.failed);
      expect(result.errorType, CloudBackupErrorType.offline);
      expect(provider.state.enabled, isFalse);
      expect(provider.state.remoteStateResolved, isFalse);
    });

    test('cancelled sign-in keeps backup off', () async {
      harness.store.connectReturnsNull = true;

      final result = await provider.enableCloudBackup();

      expect(result.status, CloudBackupEnableStatus.failed);
      expect(result.errorType, CloudBackupErrorType.signInCancelled);
      expect(provider.state.enabled, isFalse);
    });

    test('iCloud unavailable keeps backup off', () async {
      harness.store.connectError = PlatformException(code: 'E_CTR');

      final result = await provider.enableCloudBackup();

      expect(result.errorType, CloudBackupErrorType.iCloudUnavailable);
      expect(provider.state.enabled, isFalse);
    });
  });

  group('upgrade and resolution', () {
    test('existing users count as resolved only with a last backup time',
        () async {
      harness.storage.setString(
        key: 'cloud_backup_settings_v1',
        value: jsonEncode({
          'enabled': true,
          'autoBackupEnabled': true,
          'email': 'old@example.com',
          'lastBackupAt': '2026-11-01T00:00:00.000Z',
          'lastBackupSizeBytes': 900,
        }),
      );
      final upgraded = harness.buildProvider();
      expect(upgraded.state.remoteStateResolved, isTrue);
      expect(upgraded.state.lastBackupSizeBytes, 900);

      harness.storage.setString(
        key: 'cloud_backup_settings_v1',
        value: jsonEncode({'enabled': true, 'autoBackupEnabled': true}),
      );
      final neverBackedUp = harness.buildProvider();
      expect(neverBackedUp.state.remoteStateResolved, isFalse);
      expect(neverBackedUp.needsAttention, isTrue);
    });

    test('unresolved users resolve silently when the cloud has no backup',
        () async {
      await harness.settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(enabled: true),
      );
      provider = harness.buildProvider();

      await provider.resolvePendingRemoteState(
        local: LocalVaultContent.empty,
      );

      expect(provider.state.remoteStateResolved, isTrue);
    });

    test('unresolved users with an empty vault get the restore banner',
        () async {
      putBackupFile(harness.store, ideas: [backupTestIdea('cloud')]);
      await harness.settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(enabled: true),
      );
      provider = harness.buildProvider();

      await provider.resolvePendingRemoteState(
        local: LocalVaultContent.empty,
      );

      expect(provider.state.remoteStateResolved, isFalse);
      expect(
        provider.restoreBannerKind(hasLocalContent: false),
        CloudBackupBannerKind.backupFound,
      );
    });
  });

  group('restore', () {
    test('restore works with cloud backup off and does not enable it',
        () async {
      putBackupFile(harness.store, ideas: [backupTestIdea('cloud')]);

      final entries = await provider.listRestoreEntries();
      final preview = await provider.prepareRestore(entries.single);
      await provider.restore(preview.snapshot, CloudBackupRestoreMode.replace);

      expect(harness.store.connectCount, 1);
      expect(provider.state.enabled, isFalse);
      expect(provider.state.autoBackupEnabled, isTrue);
      expect(harness.scheduler.scheduleCount, 0);
      expect((await harness.vault.read()).ideas.single.id, 'cloud');
    });

    Future<void> expectRejected(String contents, CloudBackupErrorType type) async {
      await seedLocal(ideas: 2);
      final name = CloudBackupEntry.buildFileName(
        formatVersion: 3,
        createdAt: DateTime.utc(2026, 11, 1),
        deviceShortId: 'ffffffff',
        ideaCount: 1,
        randomAdditionCount: 0,
      );
      harness.store.putFile(name, contents);
      final entries = await provider.listRestoreEntries();

      await expectLater(provider.prepareRestore(entries.single),
          throwsBackupError(type));

      final local = await harness.vault.read();
      expect(local.ideas.map((idea) => idea.id),
          unorderedEquals(['local-0', 'local-1']));
      expect(harness.vault.replaceCount, 0);
      expect(harness.vault.mergeCount, 0);
    }

    test('bad JSON leaves local data untouched', () async {
      await expectRejected('{"version": 3, "ideas": [', CloudBackupErrorType.invalidBackup);
    });

    test('newer format version leaves local data untouched', () async {
      final json = CloudBackupSnapshot.fromContent(
        ideas: [backupTestIdea('x')],
        randomAdditions: const [],
      ).toJson();
      json['version'] = 99;
      await expectRejected(jsonEncode(json), CloudBackupErrorType.newerVersion);
    });

    test('unparseable entry leaves local data untouched', () async {
      await expectRejected(
        jsonEncode({
          'version': 2,
          'ideas': [
            {'id': 'x', 'title': 'Broken', 'createdAt': 12},
          ],
        }),
        CloudBackupErrorType.invalidBackup,
      );
    });

    test('hash mismatch leaves local data untouched', () async {
      final json = CloudBackupSnapshot.fromContent(
        ideas: [backupTestIdea('x')],
        randomAdditions: const [],
      ).toJson();
      json['contentHash'] = 'sha256:0000';
      await expectRejected(
        jsonEncode(json),
        CloudBackupErrorType.integrityFailed,
      );
    });

    test('an empty backup is refused and nothing is replaced', () async {
      await seedLocal(ideas: 2);
      final snapshot = CloudBackupSnapshot.fromContent(
        ideas: const [],
        randomAdditions: const [],
      );

      await expectLater(
        provider.restore(snapshot, CloudBackupRestoreMode.replace),
        throwsBackupError(CloudBackupErrorType.emptyBackup),
      );
      expect((await harness.vault.read()).ideas, hasLength(2));
    });

    test('merge returns a result summary', () async {
      await harness.vault.replaceAll(
        LocalVaultContent(
          ideas: [
            backupTestIdea('same'),
            backupTestIdea('edited',
                content: 'local', updatedAt: DateTime.utc(2026, 5, 1)),
          ],
          randomAdditions: const [],
        ),
      );
      final snapshot = CloudBackupSnapshot.fromContent(
        ideas: [
          backupTestIdea('same'),
          backupTestIdea('edited',
              content: 'cloud', updatedAt: DateTime.utc(2026, 4, 1)),
          backupTestIdea('new'),
        ],
        randomAdditions: [backupTestNote('note')],
      );

      final result =
          await provider.restore(snapshot, CloudBackupRestoreMode.merge);

      expect(result.merge?.added, 2);
      expect(result.merge?.copies, 1);
      expect(result.merge?.skippedIdentical, 1);
      final local = await harness.vault.read();
      expect(local.ideas, hasLength(4));
      expect(
        local.ideas.any((idea) => idea.title == 'Idea edited (from backup)'),
        isTrue,
      );
      expect(
        local.ideas.firstWhere((idea) => idea.id == 'edited').sections.single
            .content,
        'local',
      );
    });

    test('restore clears the editor resume state', () async {
      final editorRepo = IdeaEditorStateRepo(harness.storage);
      await editorRepo.saveState(
        const IdeaEditorState(
          ideaId: 'local-0',
          activeSectionId: 'section-local-0',
          isPreviewMode: false,
        ),
      );
      final snapshot = CloudBackupSnapshot.fromContent(
        ideas: [backupTestIdea('cloud')],
        randomAdditions: const [],
      );

      await provider.restore(snapshot, CloudBackupRestoreMode.replace);

      expect(editorRepo.getState(), isNull);
    });

    test('undo restore brings back the safety copy within 7 days', () async {
      await seedLocal(ideas: 2, notes: 1);
      final snapshot = CloudBackupSnapshot.fromContent(
        ideas: [backupTestIdea('cloud')],
        randomAdditions: const [],
      );
      await provider.restore(snapshot, CloudBackupRestoreMode.replace);
      expect((await harness.vault.read()).ideas.single.id, 'cloud');
      expect(provider.canUndoRestore, isTrue);

      now = now.add(const Duration(days: 6));
      await provider.undoRestore();

      final local = await harness.vault.read();
      expect(local.ideas.map((idea) => idea.id),
          unorderedEquals(['local-0', 'local-1']));
      expect(local.randomAdditions.single.id, 'local-note-0');
      expect(provider.canUndoRestore, isFalse);
    });

    test('undo restore is no longer offered after 7 days', () async {
      await seedLocal();
      await provider.restore(
        CloudBackupSnapshot.fromContent(
          ideas: [backupTestIdea('cloud')],
          randomAdditions: const [],
        ),
        CloudBackupRestoreMode.replace,
      );

      now = now.add(const Duration(days: 8));

      expect(provider.canUndoRestore, isFalse);
      await expectLater(
        provider.undoRestore(),
        throwsBackupError(CloudBackupErrorType.noBackupFound),
      );
    });

    test('keeps only the last 3 safety copies', () async {
      final store = RestoreSafetyCopyStore(
        directory: () async => safetyDirectory,
        clock: () => now,
      );
      for (var index = 0; index < 5; index++) {
        now = now.add(const Duration(minutes: 1));
        await store.save(
          LocalVaultContent(
            ideas: [backupTestIdea('copy-$index')],
            randomAdditions: const [],
          ),
        );
      }

      final copies = await store.list();
      expect(copies, hasLength(3));
      final newest = await store.read(copies.first.id);
      expect(newest?.ideas.single.id, 'copy-4');
    });
  });

  group('settings and status', () {
    test('turning backup off signs out and keeps cloud backups and device id',
        () async {
      final name = putBackupFile(harness.store, ideas: [backupTestIdea('c')]);
      await provider.enableCloudBackup(
        choose: (_) async => CloudBackupEnableChoice.startFresh,
      );
      final deviceId = harness.identityRepo.read()?.id;

      await provider.disableCloudBackup();

      expect(provider.state.enabled, isFalse);
      expect(provider.state.remoteStateResolved, isFalse);
      expect(harness.store.signOutCount, 1);
      expect(harness.store.fileNames, [name]);
      expect(harness.identityRepo.read()?.id, deviceId);
      expect(harness.scheduler.cancelCount, greaterThan(0));
    });

    test('delete cloud backups removes every backup file', () async {
      putBackupFile(harness.store, ideas: [backupTestIdea('a')]);
      harness.store.putFile(CloudBackupEntry.legacyFileName, '{}');

      final deleted = await provider.deleteCloudBackups();

      expect(deleted, 2);
      expect(harness.store.files, isEmpty);
    });

    test('change account clears last backup and resolution, then re-checks',
        () async {
      await seedLocal();
      await provider.enableCloudBackup();
      expect(provider.state.lastBackupAt, isNotNull);
      harness.store.files.clear();
      harness.store.accountEmail = 'second@example.com';
      now = now.add(const Duration(minutes: 5));

      final result = await provider.changeAccount();

      expect(result.status, CloudBackupEnableStatus.enabled);
      expect(provider.state.email, 'second@example.com');
      expect(provider.state.remoteStateResolved, isTrue);
      expect(provider.state.lastBackupAt, now);
    });

    test('health is green under 48 hours, amber after, red on failure',
        () async {
      await harness.settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          remoteStateResolved: true,
          lastBackupAt: now.subtract(const Duration(hours: 47)),
        ),
      );
      provider = harness.buildProvider();
      expect(provider.health, CloudBackupHealth.healthy);

      now = now.add(const Duration(hours: 2));
      expect(provider.health, CloudBackupHealth.stale);
      expect(provider.needsAttention, isFalse);

      await harness.settingsRepo.saveStatus(
        harness.settingsRepo.getStatus().recordFailure(
              at: now,
              type: CloudBackupErrorType.signInRequired,
            ),
      );
      provider = harness.buildProvider();
      expect(provider.health, CloudBackupHealth.failing);
      expect(provider.needsAttention, isTrue);
    });

    test('needs attention after 3 days of failures', () async {
      await harness.settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          remoteStateResolved: true,
          status: CloudBackupStatus.empty.recordFailure(
            at: now.subtract(const Duration(days: 1)),
            type: CloudBackupErrorType.offline,
          ),
        ),
      );
      provider = harness.buildProvider();
      expect(provider.needsAttention, isFalse);

      now = now.add(const Duration(days: 3));
      expect(provider.needsAttention, isTrue);
    });

    test('fresh install silent check only runs on iOS', () async {
      putBackupFile(harness.store, ideas: [backupTestIdea('cloud')]);

      await provider.checkForFreshInstallBackup(hasLocalContent: false);
      expect(harness.store.listCount, 0);
      expect(
        provider.restoreBannerKind(hasLocalContent: false),
        CloudBackupBannerKind.haveBackup,
      );

      final iosHarness = BackupTestHarness(clock: () => now, isIOS: true);
      putBackupFile(iosHarness.store, ideas: [backupTestIdea('cloud')]);
      final iosProvider = iosHarness.buildProvider();
      await iosProvider.checkForFreshInstallBackup(hasLocalContent: false);
      expect(
        iosProvider.restoreBannerKind(hasLocalContent: false),
        CloudBackupBannerKind.backupFound,
      );
      expect(iosProvider.restoreBannerKind(hasLocalContent: true), isNull);

      await iosProvider.checkForFreshInstallBackup(hasLocalContent: false);
      expect(iosHarness.store.listCount, 1);
    });

    test('dismissing the restore prompt is remembered', () async {
      await provider.dismissRestorePrompt();

      final reloaded = harness.buildProvider();

      expect(reloaded.restoreBannerKind(hasLocalContent: false), isNull);
    });

    test('initializeAutoBackup schedules only when enabled and resolved',
        () async {
      await harness.settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(enabled: true),
      );
      provider = harness.buildProvider();
      await provider.initializeAutoBackup();
      expect(harness.scheduler.scheduleCount, 0);

      await harness.settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          remoteStateResolved: true,
        ),
      );
      provider = harness.buildProvider();
      await provider.initializeAutoBackup();
      expect(harness.scheduler.scheduleCount, 1);
    });
  });
}
