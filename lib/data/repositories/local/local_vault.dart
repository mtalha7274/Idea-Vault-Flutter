import '../../../models/backup/cloud_backup_restore.dart';
import '../../../models/idea.dart';
import '../../../models/random_addition.dart';
import '../../../models/vault/vault_lock_block.dart';
import '../../managers/local/ideas_database.dart';
import 'ideas.dart';
import 'note_vault_repo.dart';
import 'random_additions.dart';

class LocalVaultRepo {
  LocalVaultRepo(
    this._databaseManager, {
    IdeasRepo? ideasRepo,
    RandomAdditionsRepo? randomAdditionsRepo,
  })  : _ideasRepo = ideasRepo ?? IdeasRepo(_databaseManager),
        _randomAdditionsRepo =
            randomAdditionsRepo ?? RandomAdditionsRepo(_databaseManager);

  final IdeasDatabaseManager _databaseManager;
  final IdeasRepo _ideasRepo;
  final RandomAdditionsRepo _randomAdditionsRepo;

  Future<LocalVaultContent> read() async {
    final ideas = await _ideasRepo.getIdeas();
    final additions = await _randomAdditionsRepo.getAdditions();
    return LocalVaultContent(
      ideas: ideas,
      randomAdditions: additions,
      lock: await readLock(),
    );
  }

  Future<VaultLockBlock?> readLock() async {
    final db = await _databaseManager.database;
    return NoteVaultRepo.readWith(db);
  }

  Future<void> replaceAll(
    LocalVaultContent content, {
    bool replaceLock = false,
  }) async {
    final db = await _databaseManager.database;
    await db.transaction((txn) async {
      await IdeasRepo.deleteAllIdeaRows(txn);
      await RandomAdditionsRepo.deleteAllAdditionRows(txn);
      for (final idea in content.ideas) {
        await IdeasRepo.writeIdeaRows(txn, idea);
      }
      for (final addition in content.randomAdditions) {
        await RandomAdditionsRepo.writeAdditionRow(txn, addition);
      }
      if (replaceLock) {
        final lock = content.lock;
        if (lock == null) {
          await txn.delete(IdeasDatabaseManager.noteVaultTable);
        } else {
          await NoteVaultRepo.writeWith(txn, lock);
        }
      }
    });
    await _databaseManager.compact();
  }

  Future<void> writeMerged({
    required List<Idea> ideas,
    required List<RandomAddition> randomAdditions,
    VaultLockBlock? adoptLock,
  }) async {
    if (ideas.isEmpty && randomAdditions.isEmpty && adoptLock == null) {
      return;
    }
    final db = await _databaseManager.database;
    await db.transaction((txn) async {
      if (adoptLock != null) {
        await NoteVaultRepo.writeWith(txn, adoptLock);
      }
      for (final idea in ideas) {
        await IdeasRepo.writeIdeaRows(txn, idea);
      }
      for (final addition in randomAdditions) {
        await RandomAdditionsRepo.writeAdditionRow(txn, addition);
      }
    });
  }
}
