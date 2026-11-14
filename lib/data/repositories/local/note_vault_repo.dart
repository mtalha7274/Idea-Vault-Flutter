import 'package:sqflite/sqflite.dart';

import '../../../models/vault/vault_lock_block.dart';
import '../../managers/local/ideas_database.dart';

class NoteVaultRepo {
  const NoteVaultRepo(this._databaseManager);

  final IdeasDatabaseManager _databaseManager;

  Future<VaultLockBlock?> read() async {
    final db = await _databaseManager.database;
    return readWith(db);
  }

  Future<void> write(VaultLockBlock block) async {
    final db = await _databaseManager.database;
    await writeWith(db, block);
  }

  Future<void> clear() async {
    final db = await _databaseManager.database;
    await db.delete(IdeasDatabaseManager.noteVaultTable);
  }

  static Future<VaultLockBlock?> readWith(DatabaseExecutor executor) async {
    final rows = await executor.query(
      IdeasDatabaseManager.noteVaultTable,
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return VaultLockBlock.tryDecode(rows.single['lock_block'] as String?);
  }

  static Future<void> writeWith(
    DatabaseExecutor executor,
    VaultLockBlock block,
  ) async {
    await executor.insert(
      IdeasDatabaseManager.noteVaultTable,
      {
        'id': 1,
        'key_id': block.keyId,
        'lock_block': block.encode(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
