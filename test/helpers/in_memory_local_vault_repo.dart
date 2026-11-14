import 'package:idea_vault/data/managers/local/ideas_database.dart';
import 'package:idea_vault/data/repositories/local/local_vault.dart';
import 'package:idea_vault/models/backup/cloud_backup_restore.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/random_addition.dart';
import 'package:idea_vault/models/vault/vault_lock_block.dart';

import 'in_memory_ideas_repo.dart';
import 'in_memory_random_additions_repo.dart';

class InMemoryLocalVaultRepo extends LocalVaultRepo {
  InMemoryLocalVaultRepo({
    InMemoryIdeasRepo? ideasRepo,
    InMemoryRandomAdditionsRepo? randomAdditionsRepo,
  })  : memoryIdeasRepo = ideasRepo ?? InMemoryIdeasRepo(),
        memoryAdditionsRepo =
            randomAdditionsRepo ?? InMemoryRandomAdditionsRepo(),
        super(IdeasDatabaseManager(databasePath: 'in-memory-vault'));

  final InMemoryIdeasRepo memoryIdeasRepo;
  final InMemoryRandomAdditionsRepo memoryAdditionsRepo;
  bool failWrites = false;
  VaultLockBlock? lock;
  int replaceCount = 0;
  int mergeCount = 0;

  @override
  Future<LocalVaultContent> read() async {
    return LocalVaultContent(
      ideas: await memoryIdeasRepo.getIdeas(),
      randomAdditions: await memoryAdditionsRepo.getAdditions(),
      lock: lock,
    );
  }

  @override
  Future<VaultLockBlock?> readLock() async => lock;

  @override
  Future<void> replaceAll(
    LocalVaultContent content, {
    bool replaceLock = false,
  }) async {
    if (failWrites) {
      throw StateError('write failed');
    }
    replaceCount += 1;
    if (replaceLock) {
      lock = content.lock;
    }
    await memoryIdeasRepo.saveIdeas(content.ideas);
    await memoryAdditionsRepo.saveAdditions(content.randomAdditions);
  }

  @override
  Future<void> writeMerged({
    required List<Idea> ideas,
    required List<RandomAddition> randomAdditions,
    VaultLockBlock? adoptLock,
  }) async {
    if (failWrites) {
      throw StateError('write failed');
    }
    mergeCount += 1;
    if (adoptLock != null) {
      lock = adoptLock;
    }
    for (final idea in ideas) {
      await memoryIdeasRepo.upsertIdea(idea);
    }
    for (final addition in randomAdditions) {
      await memoryAdditionsRepo.upsertAddition(addition);
    }
  }
}
