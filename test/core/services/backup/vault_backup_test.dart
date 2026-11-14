import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/core/services/backup/initial_cloud_auth_coordinator.dart';
import 'package:idea_vault/core/services/backup/vault_plaintext_cleanup.dart';
import 'package:idea_vault/core/services/vault/note_vault_service.dart';
import 'package:idea_vault/core/services/vault/vault_crypto.dart';
import 'package:idea_vault/data/managers/local/ideas_database.dart';
import 'package:idea_vault/data/repositories/local/app_install_state.dart';
import 'package:idea_vault/data/repositories/local/backup_device_identity.dart';
import 'package:idea_vault/data/repositories/local/cloud_backup_settings.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/ideas.dart';
import 'package:idea_vault/data/repositories/local/local_vault.dart';
import 'package:idea_vault/data/repositories/local/note_vault_repo.dart';
import 'package:idea_vault/models/backup/cloud_backup_entry.dart';
import 'package:idea_vault/models/backup/cloud_backup_error.dart';
import 'package:idea_vault/models/backup/cloud_backup_restore.dart';
import 'package:idea_vault/models/backup/cloud_backup_snapshot.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/vault/vault_lock_block.dart';
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';

import '../../../helpers/backup_test_harness.dart';
import '../../../helpers/fake_cloud_backup_store.dart';
import '../../../helpers/memory_local_storage.dart';
import '../../../helpers/test_ideas_database.dart';
import '../../../helpers/vault_test_env.dart';

const secretText = 'the launch code is swordfish';

class TestDevice {
  TestDevice._(
    this.manager,
    this.store, {
    required this.seed,
    required this.deviceName,
  })  : storage = MemoryLocalStorageManager(),
        keys = VaultTestKeys() {
    ideasRepo = IdeasRepo(manager);
    vaultRepo = NoteVaultRepo(manager);
    localVault = LocalVaultRepo(manager, ideasRepo: ideasRepo);
    vault = buildTestVault(
      vaultRepo: vaultRepo,
      ideasRepo: ideasRepo,
      keys: keys,
      seed: seed,
    );
    settingsRepo = CloudBackupSettingsRepo(storage);
    identityRepo = BackupDeviceIdentityRepo(storage);
    service = CloudBackupService(
      androidStore: store,
      iosStore: store,
      useICloud: false,
    );
    provider = CloudBackupProvider(
      settingsRepo,
      service,
      FakeCloudBackupScheduler(),
      InitialCloudAuthCoordinator(AppInstallStateRepo(storage)),
      localVaultRepo: localVault,
      deviceIdentityRepo: identityRepo,
      editorStateRepo: IdeaEditorStateRepo(storage),
      isIOS: false,
      deviceName: deviceName,
      vault: vault,
      onVaultAdopted: () async {
        adoptedCount += 1;
        await vault.forgetCachedKey();
      },
      copyTitle: (title, fromBackup) =>
          fromBackup ? '$title (from backup)' : '$title (from this device)',
    );
  }

  static Future<TestDevice> create(
    FakeCloudBackupStore store, {
    required int seed,
    String deviceName = 'Phone',
  }) async {
    final manager = await createTestIdeasDatabaseManager();
    final device = TestDevice._(
      manager,
      store,
      seed: seed,
      deviceName: deviceName,
    );
    await device.identityRepo.ensure(deviceName: deviceName);
    return device;
  }

  final IdeasDatabaseManager manager;
  final FakeCloudBackupStore store;
  final int seed;
  final MemoryLocalStorageManager storage;
  final VaultTestKeys keys;
  late final IdeasRepo ideasRepo;
  late final NoteVaultRepo vaultRepo;
  late final LocalVaultRepo localVault;
  late final NoteVaultService vault;
  late final CloudBackupSettingsRepo settingsRepo;
  late final BackupDeviceIdentityRepo identityRepo;
  late final CloudBackupService service;
  late final CloudBackupProvider provider;
  final String deviceName;
  int adoptedCount = 0;

  Future<void> addLocked(String id, {String content = secretText}) async {
    await ideasRepo.upsertIdea(
      await vault.encryptIdea(vaultTestIdea(id, content: content)),
    );
  }

  Future<void> dispose() => disposeTestIdeasDatabaseManager(manager);
}

Future<CloudBackupSnapshot> newestSnapshot(FakeCloudBackupStore store) async {
  final service = CloudBackupService(androidStore: store, useICloud: false);
  final entries = await service.listBackups();
  return service.downloadSnapshot(entries.first);
}

void main() {
  late FakeCloudBackupStore store;
  late TestDevice phoneA;

  setUp(() async {
    store = FakeCloudBackupStore();
    phoneA = await TestDevice.create(store, seed: 1, deviceName: 'Pixel A');
    await phoneA.vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
    await phoneA.addLocked('locked-a');
    await phoneA.ideasRepo.upsertIdea(
      Idea(
        id: 'open-a',
        title: 'Open note',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        sections: const [
          IdeaSection(
              id: 'section-open-a', name: 'Public', content: 'open text'),
        ],
      ),
    );
  });

  tearDown(() async {
    await phoneA.dispose();
  });

  test('the uploaded backup holds ciphertext and the lock block only',
      () async {
    final result = await phoneA.provider.enableCloudBackup();
    expect(result.firstBackup?.didUpload, isTrue);

    final raw = store.files.values.single.contents;
    expect(raw, isNot(contains(secretText)));
    expect(raw, isNot(contains('Hidden part')));
    expect(raw, contains('open text'));
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final lock = json['lock'] as Map<String, dynamic>;
    expect(lock['encrypted'], isTrue);
    expect(lock['keyId'], (await phoneA.vault.lockBlock())!.keyId);
    expect(VaultPlaintextCleanup.containsPlaintextLockedNotes(raw), isFalse);

    final snapshot = await newestSnapshot(store);
    expect(snapshot.hasEncryptedIdeas, isTrue);
    expect(snapshot.lockBlock, isNotNull);
  });

  test('a background-style backup needs no key', () async {
    await phoneA.provider.enableCloudBackup();
    await phoneA.vault.forgetCachedKey();
    final content = await phoneA.localVault.read();
    expect(content.lock, isNotNull);
    final snapshot = CloudBackupSnapshot.fromContent(
      ideas: content.ideas,
      randomAdditions: content.randomAdditions,
      lock: content.lock,
    );
    expect(snapshot.encode(), isNot(contains(secretText)));
    expect(
      CloudBackupSnapshot.decodeAndValidate(snapshot.encode()).ideaCount,
      2,
    );
  });

  test('validation rejects encrypted notes without a key block', () {
    final idea = vaultTestIdea('x').copyWith(
      encryptedPayload: EncryptedIdeaEnvelope(
        keyId: 'abc',
        nonce: List<int>.filled(12, 1),
        cipherText: List<int>.filled(32, 2),
      ).encode(),
      sections: const [],
    );
    final snapshot = CloudBackupSnapshot.fromContent(
      ideas: [idea],
      randomAdditions: const [],
    );
    expect(
      () => CloudBackupSnapshot.decodeAndValidate(snapshot.encode()),
      throwsA(
        isA<CloudBackupException>().having(
          (e) => e.type,
          'type',
          CloudBackupErrorType.invalidBackup,
        ),
      ),
    );
  });

  group('restore on a clean install', () {
    late TestDevice phoneB;

    setUp(() async {
      await phoneA.provider.enableCloudBackup();
      phoneB = await TestDevice.create(store, seed: 99, deviceName: 'Pixel B');
    });

    tearDown(() async {
      await phoneB.dispose();
    });

    test('locked notes stay ciphertext until the original PIN is entered',
        () async {
      final preview = await phoneB.provider.prepareNewestRestore();
      final result = await phoneB.provider.restore(
        preview!.snapshot,
        CloudBackupRestoreMode.replace,
      );

      expect(result.needsVaultUnlock, isTrue);
      expect(result.lockedNotImported, 0);
      expect(phoneB.adoptedCount, 1);
      expect(await phoneB.vault.state(), NoteVaultState.needsUnwrap);
      final locked = (await phoneB.ideasRepo.getIdeas())
          .firstWhere((idea) => idea.id == 'locked-a');
      expect(locked.isEncrypted, isTrue);
      expect(
        () => phoneB.vault.decryptIdea(locked),
        throwsA(isA<VaultCryptoException>()),
      );

      expect(
          await phoneB.vault.unlockWith('000000', VaultWrapKind.pin), isFalse);
      expect(
          await phoneB.vault.unlockWith('123456', VaultWrapKind.pin), isTrue);
      final opened = await phoneB.vault.decryptIdea(locked);
      expect(opened.sections.single.content, secretText);
    });

    test('a vault key that protects local notes is never overwritten',
        () async {
      await phoneB.vault.setUp(
        pin: '111111',
        pinKind: NoteLockPinKind.digits6,
      );
      await phoneB.addLocked('locked-b', content: 'phone b secret');
      final keyIdBefore = (await phoneB.vault.lockBlock())!.keyId;

      final preview = await phoneB.provider.prepareNewestRestore();
      var prompts = 0;
      final result = await phoneB.provider.restore(
        preview!.snapshot,
        CloudBackupRestoreMode.merge,
        askBackupKey: (block) async {
          prompts += 1;
          return phoneB.vault.unwrapKey(block, '123456', VaultWrapKind.pin);
        },
      );

      expect(prompts, 1);
      expect(result.lockedNotImported, 0);
      expect(result.needsVaultUnlock, isFalse);
      expect((await phoneB.vault.lockBlock())!.keyId, keyIdBefore);
      final ideas = await phoneB.ideasRepo.getIdeas();
      final imported = ideas.firstWhere((idea) => idea.id == 'locked-a');
      final own = ideas.firstWhere((idea) => idea.id == 'locked-b');
      expect(
        (await phoneB.vault.decryptIdea(imported)).sections.single.content,
        secretText,
      );
      expect(
        (await phoneB.vault.decryptIdea(own)).sections.single.content,
        'phone b secret',
      );
      expect(
        EncryptedIdeaEnvelope.keyIdOf(imported.encryptedPayload!),
        keyIdBefore,
      );
    });

    test('skipping the backup PIN lists locked notes as not imported',
        () async {
      await phoneB.vault.setUp(
        pin: '111111',
        pinKind: NoteLockPinKind.digits6,
      );
      final preview = await phoneB.provider.prepareNewestRestore();
      final result = await phoneB.provider.restore(
        preview!.snapshot,
        CloudBackupRestoreMode.merge,
        askBackupKey: (_) async => null,
      );

      expect(result.lockedNotImported, 1);
      final ideas = await phoneB.ideasRepo.getIdeas();
      expect(ideas.map((idea) => idea.id), ['open-a']);
    });

    test('a wrong backup PIN does not block the rest of the restore', () async {
      await phoneB.vault.setUp(
        pin: '111111',
        pinKind: NoteLockPinKind.digits6,
      );
      final preview = await phoneB.provider.prepareNewestRestore();
      final result = await phoneB.provider.restore(
        preview!.snapshot,
        CloudBackupRestoreMode.replace,
        askBackupKey: (block) async {
          try {
            return await phoneB.vault.unwrapKey(
              block,
              '999999',
              VaultWrapKind.pin,
            );
          } on VaultCryptoException {
            return null;
          }
        },
      );
      expect(result.lockedNotImported, 1);
      expect(
        (await phoneB.ideasRepo.getIdeas()).map((idea) => idea.id),
        ['open-a'],
      );
    });

    test('the recovery code opens a backup made under another PIN', () async {
      final code = await phoneB.vault.setUp(
        pin: '111111',
        pinKind: NoteLockPinKind.digits6,
      );
      expect(code, isNotEmpty);
      final aBlock = (await phoneA.vault.lockBlock())!;
      await phoneA.vault.rewrapPin(
        newPin: '777777',
        pinKind: NoteLockPinKind.digits6,
      );
      expect(
        () => phoneB.vault.unwrapKey(aBlock, '777777', VaultWrapKind.pin),
        throwsA(isA<VaultCryptoException>()),
      );
      expect(
        await phoneB.vault.unwrapKey(aBlock, '123456', VaultWrapKind.pin),
        hasLength(32),
      );
    });
  });

  test('merging the same vault copies a conflicting note under a new id',
      () async {
    await phoneA.provider.enableCloudBackup();
    final snapshot = await newestSnapshot(store);
    final local = (await phoneA.ideasRepo.getIdeas())
        .firstWhere((idea) => idea.id == 'locked-a');
    final edited = await phoneA.vault.encryptIdea(
      vaultTestIdea(
        'locked-a',
        content: 'edited later',
        updatedAt: DateTime.utc(2027, 1, 1),
      ),
    );
    await phoneA.ideasRepo.upsertIdea(edited);

    final result = await phoneA.provider.restore(
      snapshot,
      CloudBackupRestoreMode.merge,
    );

    expect(result.merge!.copies, 1);
    expect(local.isEncrypted, isTrue);
    final ideas = await phoneA.ideasRepo.getIdeas();
    final lockedIdeas = ideas.where((idea) => idea.isLocked).toList();
    expect(lockedIdeas, hasLength(2));
    final contents = <String>{};
    for (final idea in lockedIdeas) {
      final opened = await phoneA.vault.decryptIdea(idea);
      contents.add(opened.sections.single.content);
    }
    expect(contents, {secretText, 'edited later'});
  });

  test('an older plain backup never overwrites a locked note it cannot copy',
      () async {
    final plainBackup = CloudBackupSnapshot.fromContent(
      ideas: [
        vaultTestIdea(
          'locked-a',
          content: 'old plain version',
          updatedAt: DateTime.utc(2027, 1, 1),
        ),
      ],
      randomAdditions: const [],
    );
    await phoneA.vault.forgetCachedKey();

    final result = await phoneA.provider.restore(
      plainBackup,
      CloudBackupRestoreMode.merge,
    );

    expect(result.lockedNotImported, 1);
    final local = (await phoneA.ideasRepo.getIdeas())
        .firstWhere((idea) => idea.id == 'locked-a');
    expect(local.isEncrypted, isTrue);
    expect(await phoneA.vault.unlockWith('123456', VaultWrapKind.pin), isTrue);
    expect(
      (await phoneA.vault.decryptIdea(local)).sections.single.content,
      secretText,
    );
  });

  test('with the key, a newer plain backup keeps the local note as a copy',
      () async {
    final plainBackup = CloudBackupSnapshot.fromContent(
      ideas: [
        vaultTestIdea(
          'locked-a',
          content: 'newer plain version',
          updatedAt: DateTime.utc(2027, 1, 1),
        ),
      ],
      randomAdditions: const [],
    );

    final result = await phoneA.provider.restore(
      plainBackup,
      CloudBackupRestoreMode.merge,
    );

    expect(result.merge!.copies, 1);
    final locked =
        (await phoneA.ideasRepo.getIdeas()).where((idea) => idea.isLocked);
    final contents = <String>{};
    for (final idea in locked) {
      final opened = await phoneA.vault.decryptIdea(idea);
      contents.add(opened.sections.single.content);
    }
    expect(contents, {secretText, 'newer plain version'});
  });

  test('merging an identical encrypted note is skipped', () async {
    await phoneA.provider.enableCloudBackup();
    final snapshot = await newestSnapshot(store);
    final local = (await phoneA.ideasRepo.getIdeas())
        .firstWhere((idea) => idea.id == 'locked-a');
    final reEncrypted = await phoneA.vault.encryptIdea(
      await phoneA.vault.decryptIdea(local),
    );
    await phoneA.ideasRepo.upsertIdea(reEncrypted);

    final result = await phoneA.provider.restore(
      snapshot,
      CloudBackupRestoreMode.merge,
    );
    expect(result.merge!.copies, 0);
    expect(result.merge!.skippedIdentical, 2);
  });

  test('old pre-encryption backups restore and lock again on next unlock',
      () async {
    final phoneC = await TestDevice.create(store, seed: 5);
    addTearDown(phoneC.dispose);
    await phoneC.vault.setUp(pin: '121212', pinKind: NoteLockPinKind.digits6);
    final legacy = CloudBackupSnapshot.fromContent(
      ideas: [vaultTestIdea('old-locked', content: 'old secret')],
      randomAdditions: const [],
    );
    final restored = await phoneC.provider.restore(
      CloudBackupSnapshot.decodeAndValidate(legacy.encode()),
      CloudBackupRestoreMode.replace,
    );
    expect(restored.ideaCount, 1);
    final plain = (await phoneC.ideasRepo.getIdeas()).single;
    expect(plain.isEncrypted, isFalse);
    expect(plain.sections.single.content, 'old secret');

    expect(await phoneC.vault.encryptPlaintextLockedIdeas(), 1);
    final encrypted = (await phoneC.ideasRepo.getIdeas()).single;
    expect(encrypted.isEncrypted, isTrue);
  });

  group('plaintext backup clean-up', () {
    late String legacyName;
    late String oldSnapshotName;
    late String cleanName;

    setUp(() async {
      final plainLocked = vaultTestIdea('locked-a');
      legacyName = CloudBackupEntry.legacyFileName;
      store.putFile(
        legacyName,
        jsonEncode({
          'exportedAt': '2025-01-01T00:00:00.000Z',
          'ideas': [plainLocked.toJson()],
        }),
      );
      final identity = phoneA.identityRepo.read()!;
      oldSnapshotName = putBackupFile(
        store,
        ideas: [plainLocked],
        deviceId: identity.id,
        createdAt: DateTime.utc(2026, 10, 1),
      );
      cleanName = putBackupFile(
        store,
        ideas: [vaultTestIdea('open', isLocked: false, content: 'public')],
        createdAt: DateTime.utc(2026, 10, 2),
      );
      await phoneA.settingsRepo.saveSettings(
        phoneA.provider.state.copyWith(
          enabled: true,
          remoteStateResolved: true,
        ),
      );
      await phoneA.provider.refreshFromStorage();
    });

    test('backs up first, then deletes only plaintext locked backups',
        () async {
      await phoneA.provider.markPlaintextCleanupPending();
      final ideas = await phoneA.ideasRepo.getIdeas();

      final done = await phoneA.provider.runPlaintextCleanup(ideas);

      expect(done, isTrue);
      expect(phoneA.provider.plaintextCleanupPending, isFalse);
      expect(store.files.containsKey(legacyName), isFalse);
      expect(store.files.containsKey(oldSnapshotName), isFalse);
      expect(store.files.containsKey(cleanName), isTrue);
      final remaining = store.files.values.map((file) => file.contents);
      expect(remaining.any((raw) => raw.contains(secretText)), isFalse);
      expect(
        remaining.where(
          (raw) => (jsonDecode(raw) as Map<String, dynamic>)['lock'] != null,
        ),
        hasLength(1),
      );
    });

    test('a failed delete keeps the flag so the clean-up retries', () async {
      await phoneA.provider.markPlaintextCleanupPending();
      final ideas = await phoneA.ideasRepo.getIdeas();
      store.deleteError = StateError('offline');

      expect(await phoneA.provider.runPlaintextCleanup(ideas), isFalse);
      expect(phoneA.provider.plaintextCleanupPending, isTrue);
      expect(store.files.containsKey(legacyName), isTrue);

      store.deleteError = null;
      expect(await phoneA.provider.runPlaintextCleanup(ideas), isTrue);
      expect(phoneA.provider.plaintextCleanupPending, isFalse);
      expect(store.files.containsKey(legacyName), isFalse);
      expect(store.files.containsKey(oldSnapshotName), isFalse);
    });

    test('a failed backup leaves the old files alone', () async {
      await phoneA.provider.markPlaintextCleanupPending();
      final ideas = await phoneA.ideasRepo.getIdeas();
      store.writeError = StateError('quota');

      expect(await phoneA.provider.runPlaintextCleanup(ideas), isFalse);
      expect(phoneA.provider.plaintextCleanupPending, isTrue);
      expect(store.files.containsKey(legacyName), isTrue);
      expect(store.files.containsKey(oldSnapshotName), isTrue);
    });

    test('the pending flag survives a restart', () async {
      await phoneA.provider.markPlaintextCleanupPending();
      final restarted = CloudBackupSettingsRepo(phoneA.storage);
      expect(restarted.plaintextCleanupPending, isTrue);
    });
  });
}
