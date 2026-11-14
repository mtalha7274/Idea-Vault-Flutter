import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/vault/note_vault_service.dart';
import 'package:idea_vault/core/services/vault/vault_crypto.dart';
import 'package:idea_vault/data/managers/local/ideas_database.dart';
import 'package:idea_vault/data/repositories/local/ideas.dart';
import 'package:idea_vault/data/repositories/local/note_vault_repo.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/vault/vault_lock_block.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../helpers/memory_local_storage.dart';
import '../../../helpers/test_ideas_database.dart';
import '../../../helpers/vault_test_env.dart';

class FailingIdeasRepo extends IdeasRepo {
  FailingIdeasRepo(super.databaseManager, {this.failAt = 1});

  final int failAt;
  int writes = 0;

  @override
  Future<void> writeIdeaInTransaction(DatabaseExecutor executor, Idea idea) {
    if (writes++ == failAt) {
      throw StateError('killed mid-migration');
    }
    return super.writeIdeaInTransaction(executor, idea);
  }
}

const secretText = 'the launch code is swordfish';

Future<String> rawDatabaseDump(IdeasDatabaseManager manager) async {
  final db = await manager.database;
  final buffer = StringBuffer();
  for (final table in [
    IdeasDatabaseManager.ideasTable,
    IdeasDatabaseManager.sectionsTable,
    IdeasDatabaseManager.noteVaultTable,
  ]) {
    for (final row in await db.query(table)) {
      buffer.writeln(jsonEncode(row));
    }
  }
  return buffer.toString();
}

void main() {
  late IdeasDatabaseManager manager;
  late IdeasRepo ideasRepo;
  late NoteVaultRepo vaultRepo;
  late VaultTestKeys keys;
  late MemoryLocalStorageManager preferences;
  late NoteVaultService vault;

  setUp(() async {
    manager = await createTestIdeasDatabaseManager();
    ideasRepo = IdeasRepo(manager);
    vaultRepo = NoteVaultRepo(manager);
    keys = VaultTestKeys();
    preferences = MemoryLocalStorageManager();
    vault = buildTestVault(
      vaultRepo: vaultRepo,
      ideasRepo: ideasRepo,
      keys: keys,
      preferences: preferences,
    );
  });

  tearDown(() async {
    await disposeTestIdeasDatabaseManager(manager);
  });

  group('setup and unwrap', () {
    test('setup stores both wraps in the database and caches the key',
        () async {
      expect(await vault.state(), NoteVaultState.none);

      final code = await vault.setUp(
        pin: '123456',
        pinKind: NoteLockPinKind.digits6,
      );

      expect(code, hasLength(32));
      expect(await vault.state(), NoteVaultState.ready);
      final block = (await vaultRepo.read())!;
      expect(block.pinKind, NoteLockPinKind.digits6);
      expect(block.pinWrap.kdf.algorithm, VaultKdfAlgorithm.argon2id);
      expect(block.recoveryWrap.kdf.algorithm, VaultKdfAlgorithm.hkdfSha256);
      expect(keys.values[NoteVaultService.keyIdStorageKey], block.keyId);
      expect(block.toJson()['encrypted'], isTrue);
      expect(await rawDatabaseDump(manager), isNot(contains('123456')));
    });

    test('a wrong PIN does not unwrap, the right one does', () async {
      await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
      await vault.forgetCachedKey();
      expect(await vault.state(), NoteVaultState.needsUnwrap);

      expect(await vault.unlockWith('654321', VaultWrapKind.pin), isFalse);
      expect(await vault.state(), NoteVaultState.needsUnwrap);
      expect(await vault.unlockWith('123456', VaultWrapKind.pin), isTrue);
      expect(await vault.state(), NoteVaultState.ready);
    });

    test('lost secure storage is treated like a new phone', () async {
      await vault.setUp(
          pin: 'correct horse', pinKind: NoteLockPinKind.passphrase);
      await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));
      keys.values.clear();
      vault.dropKey();

      expect(await vault.state(), NoteVaultState.needsUnwrap);
      final stored = (await ideasRepo.getIdeas()).single;
      expect(
        () => vault.decryptIdea(stored),
        throwsA(isA<VaultCryptoException>()),
      );
      expect(
          await vault.unlockWith('correct horse', VaultWrapKind.pin), isTrue);
      final opened =
          await vault.decryptIdea((await ideasRepo.getIdeas()).single);
      expect(opened.sections.single.content, secretText);
    });

    test('recovery code unlocks and survives a PIN change', () async {
      final code = await vault.setUp(
        pin: '123456',
        pinKind: NoteLockPinKind.digits6,
      );
      await vault.rewrapPin(newPin: '999999', pinKind: NoteLockPinKind.digits6);
      await vault.forgetCachedKey();

      expect(await vault.unlockWith('123456', VaultWrapKind.pin), isFalse);
      expect(
        await vault.unlockWith(
          VaultRecoveryCode.format(code).toLowerCase(),
          VaultWrapKind.recovery,
        ),
        isTrue,
      );
      await vault.rewrapPin(newPin: '424242', pinKind: NoteLockPinKind.digits6);
      await vault.forgetCachedKey();
      expect(await vault.unlockWith('424242', VaultWrapKind.pin), isTrue);
    });

    test('regenerating the recovery code retires the old one', () async {
      final oldCode = await vault.setUp(
        pin: '123456',
        pinKind: NoteLockPinKind.digits6,
      );
      final newCode = await vault.regenerateRecoveryCode();
      await vault.forgetCachedKey();

      expect(newCode, isNot(oldCode));
      expect(await vault.unlockWith(oldCode, VaultWrapKind.recovery), isFalse);
      expect(await vault.unlockWith(newCode, VaultWrapKind.recovery), isTrue);
    });

    test('an existing 4-digit PIN can wrap the vault key', () async {
      await vault.setUp(pin: '2468', pinKind: NoteLockPinKind.digits4);
      await vault.forgetCachedKey();
      final block = (await vaultRepo.read())!;
      expect(block.pinKind, NoteLockPinKind.digits4);
      expect(await vault.unlockWith('2468', VaultWrapKind.pin), isTrue);
    });
  });

  group('locked note content', () {
    setUp(() async {
      await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
    });

    test('database rows hold no readable locked text', () async {
      final encrypted = await vault.encryptIdea(vaultTestIdea('a'));
      await ideasRepo.upsertIdea(encrypted);

      final dump = await rawDatabaseDump(manager);
      expect(dump, isNot(contains(secretText)));
      expect(dump, isNot(contains('Hidden part')));
      expect(dump, contains('Secret plans'));

      final stored = (await ideasRepo.getIdeas()).single;
      expect(stored.isEncrypted, isTrue);
      expect(stored.sections, isEmpty);
      final opened = await vault.decryptIdea(stored);
      expect(opened.sections.single.content, secretText);
      expect(opened.sections.single.name, 'Hidden part');
    });

    test('a blob swapped onto another note is rejected', () async {
      final a = await vault.encryptIdea(vaultTestIdea('a'));
      final b = await vault.encryptIdea(vaultTestIdea('b', content: 'other'));
      final swapped = b.copyWith(encryptedPayload: a.encryptedPayload);
      expect(
        () => vault.decryptIdea(swapped),
        throwsA(
          isA<VaultCryptoException>()
              .having((e) => e.type, 'type', VaultCryptoErrorType.tampered),
        ),
      );
    });

    test('a tampered blob is an error, not garbage', () async {
      final a = await vault.encryptIdea(vaultTestIdea('a'));
      final envelope = EncryptedIdeaEnvelope.decode(a.encryptedPayload!);
      final bytes = [...envelope.cipherText];
      bytes[3] ^= 0xff;
      final tampered = a.copyWith(
        encryptedPayload: EncryptedIdeaEnvelope(
          keyId: envelope.keyId,
          nonce: envelope.nonce,
          cipherText: bytes,
        ).encode(),
      );
      expect(
        () => vault.decryptIdea(tampered),
        throwsA(isA<VaultCryptoException>()),
      );
    });

    test('changing the PIN does not rewrite any note', () async {
      await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));
      final before = (await ideasRepo.getIdeas()).single.encryptedPayload;

      await vault.rewrapPin(
        newPin: 'new passphrase',
        pinKind: NoteLockPinKind.passphrase,
      );

      final after = (await ideasRepo.getIdeas()).single;
      expect(after.encryptedPayload, before);
      expect(
          (await vault.decryptIdea(after)).sections.single.content, secretText);
      expect((await vaultRepo.read())!.pinKind, NoteLockPinKind.passphrase);
    });

    test('hide titles moves the title into the blob and back', () async {
      await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));

      expect(await vault.setHideTitles(true), 1);
      final hidden = (await ideasRepo.getIdeas()).single;
      expect(hidden.title, isEmpty);
      expect(hidden.titleHidden, isTrue);
      expect(await rawDatabaseDump(manager), isNot(contains('Secret plans')));
      expect((await vault.decryptIdea(hidden)).title, 'Secret plans');

      await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('b')));
      expect(
          (await ideasRepo.getIdeas())
              .firstWhere((idea) => idea.id == 'b')
              .titleHidden,
          isTrue);

      expect(await vault.setHideTitles(false), 2);
      final shown = await ideasRepo.getIdeas();
      expect(shown.every((idea) => idea.title == 'Secret plans'), isTrue);
      expect(shown.every((idea) => !idea.titleHidden), isTrue);
    });

    test('delete and reset removes only locked notes and the key', () async {
      await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));
      await ideasRepo.upsertIdea(vaultTestIdea('open', isLocked: false));

      expect(await vault.resetAll(), 1);

      final remaining = await ideasRepo.getIdeas();
      expect(remaining.map((idea) => idea.id), ['open']);
      expect(await vault.state(), NoteVaultState.none);
      expect(keys.values.containsKey(NoteVaultService.keyStorageKey), isFalse);
    });

    test('the key is dropped from memory when no note is open', () async {
      await vault.encryptIdea(vaultTestIdea('a'));
      vault.releaseIfIdle();
      expect(vault.holdsKeyInMemory, isFalse);

      vault.openSession();
      await vault.loadKey();
      vault.releaseIfIdle();
      expect(vault.holdsKeyInMemory, isTrue);
      vault.closeSession();
      expect(vault.holdsKeyInMemory, isFalse);
    });
  });

  group('migration of plaintext locked notes', () {
    test('encrypts every locked note in one go and compacts', () async {
      await ideasRepo.upsertIdea(vaultTestIdea('a'));
      await ideasRepo.upsertIdea(vaultTestIdea('b', content: 'second secret'));
      await ideasRepo.upsertIdea(
        vaultTestIdea('open', isLocked: false, content: 'public text'),
      );
      await vault.setUp(pin: '2468', pinKind: NoteLockPinKind.digits4);

      expect(await vault.encryptPlaintextLockedIdeas(), 2);

      final ideas = await ideasRepo.getIdeas();
      expect(ideas.where((idea) => idea.isEncrypted), hasLength(2));
      expect(
        ideas.firstWhere((idea) => idea.id == 'open').sections.single.content,
        'public text',
      );
      final dump = await rawDatabaseDump(manager);
      expect(dump, isNot(contains(secretText)));
      expect(dump, isNot(contains('second secret')));

      final file = manager.databasePath!;
      await manager.close();
      final bytes = await File(file).readAsBytes();
      final raw = latin1.decode(bytes);
      expect(raw.contains(secretText), isFalse);
      expect(raw.contains('second secret'), isFalse);
      expect(raw.contains('public text'), isTrue);
    });

    test('a crash mid-migration leaves every note as it was', () async {
      await ideasRepo.upsertIdea(vaultTestIdea('a'));
      await ideasRepo.upsertIdea(vaultTestIdea('b', content: 'second secret'));
      final failing = FailingIdeasRepo(manager);
      final failingVault = buildTestVault(
        vaultRepo: vaultRepo,
        ideasRepo: failing,
        keys: keys,
      );
      await failingVault.setUp(pin: '2468', pinKind: NoteLockPinKind.digits4);

      await expectLater(
        failingVault.encryptPlaintextLockedIdeas(),
        throwsA(isA<StateError>()),
      );

      final ideas = await ideasRepo.getIdeas();
      expect(ideas.where((idea) => idea.isEncrypted), isEmpty);
      expect(
        ideas.map((idea) => idea.sections.single.content).toSet(),
        {secretText, 'second secret'},
      );
      expect(await failingVault.state(), NoteVaultState.ready);

      expect(await vault.encryptPlaintextLockedIdeas(), 2);
      expect((await ideasRepo.getIdeas()).every((idea) => idea.isEncrypted),
          isTrue);
    });
  });

  group('database upgrade', () {
    test('a version 4 database gains the encryption columns', () async {
      final file = manager.databasePath!;
      await manager.deleteDatabaseFile();
      await Directory(path.dirname(file)).create(recursive: true);
      final old = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE ideas (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                last_opened_section_id TEXT,
                is_locked INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE idea_sections (
                id TEXT PRIMARY KEY,
                idea_id TEXT NOT NULL,
                name TEXT NOT NULL,
                content TEXT NOT NULL,
                sort_order INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE random_additions (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL
              )
            ''');
          },
        ),
      );
      await old.insert('ideas', {
        'id': 'legacy',
        'title': 'Old locked',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'is_locked': 1,
      });
      await old.insert('idea_sections', {
        'id': 'legacy-section',
        'idea_id': 'legacy',
        'name': 'Idea',
        'content': 'old plain text',
        'sort_order': 0,
      });
      await old.close();

      final upgraded = IdeasRepo(manager);
      final ideas = await upgraded.getIdeas();
      expect(ideas.single.isLocked, isTrue);
      expect(ideas.single.isEncrypted, isFalse);
      expect(ideas.single.sections.single.content, 'old plain text');
      expect(await NoteVaultRepo(manager).read(), isNull);
      final db = await manager.database;
      expect(await db.getVersion(), IdeasDatabaseManager.databaseVersion);
    });
  });
}
