import 'dart:math';

import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/vault/note_vault_service.dart';
import 'package:idea_vault/core/services/vault/vault_crypto.dart';
import 'package:idea_vault/data/managers/local/ideas_database.dart';
import 'package:idea_vault/data/repositories/local/ideas.dart';
import 'package:idea_vault/data/repositories/local/note_vault_repo.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/vault/vault_lock_block.dart';

import 'memory_local_storage.dart';

VaultKdfParams fastPinParams(List<int> salt) {
  return VaultKdfParams(
    algorithm: VaultKdfAlgorithm.argon2id,
    salt: salt,
    memoryKiB: 64,
    iterations: 1,
    parallelism: 1,
  );
}

DefaultVaultKdf fastTestKdf({Random? random}) {
  return DefaultVaultKdf(
    random: random,
    useIsolate: false,
    pinParams: fastPinParams,
  );
}

class InMemoryNoteVaultRepo extends NoteVaultRepo {
  InMemoryNoteVaultRepo()
      : super(IdeasDatabaseManager(databasePath: 'in-memory-note-vault'));

  VaultLockBlock? block;

  @override
  Future<VaultLockBlock?> read() async => block;

  @override
  Future<void> write(VaultLockBlock block) async {
    this.block = block;
  }

  @override
  Future<void> clear() async {
    block = null;
  }
}

class VaultTestKeys {
  VaultTestKeys() : values = <String, String>{};

  final Map<String, String> values;

  Future<String?> read(String key) async => values[key];

  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  Future<void> delete(String key) async {
    values.remove(key);
  }
}

NoteVaultService buildTestVault({
  required NoteVaultRepo vaultRepo,
  required IdeasRepo ideasRepo,
  required VaultTestKeys keys,
  MemoryLocalStorageManager? preferences,
  int seed = 7,
  int isolateThresholdBytes = VaultCipher.defaultIsolateThresholdBytes,
}) {
  final random = Random(seed);
  return NoteVaultService(
    vaultRepo: vaultRepo,
    ideasRepo: ideasRepo,
    random: random,
    kdf: fastTestKdf(random: random),
    cipher: VaultCipher(
      random: random,
      isolateThresholdBytes: isolateThresholdBytes,
    ),
    readValue: keys.read,
    writeValue: keys.write,
    deleteValue: keys.delete,
    preferences: () => preferences,
  );
}

NoteLockAuthService buildTestAuth(VaultTestKeys keys,
    {DateTime Function()? clock}) {
  return NoteLockAuthService(
    random: Random(3),
    readValue: keys.read,
    writeValue: keys.write,
    deleteValue: keys.delete,
    clock: clock,
  );
}

Idea vaultTestIdea(
  String id, {
  String title = 'Secret plans',
  String content = 'the launch code is swordfish',
  bool isLocked = true,
  DateTime? updatedAt,
}) {
  return Idea(
    id: id,
    title: title,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
    isLocked: isLocked,
    lastOpenedSectionId: 'section-$id',
    sections: [
      IdeaSection(id: 'section-$id', name: 'Hidden part', content: content),
    ],
  );
}
