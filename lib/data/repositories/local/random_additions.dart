import 'package:sqflite/sqflite.dart';

import '../../../models/random_addition.dart';
import '../../managers/local/ideas_database.dart';

class RandomAdditionsRepo {
  const RandomAdditionsRepo(this._databaseManager);

  final IdeasDatabaseManager _databaseManager;

  Future<List<RandomAddition>> getAdditions() async {
    final db = await _databaseManager.database;
    final rows = await db.query(
      IdeasDatabaseManager.randomAdditionsTable,
      orderBy: 'created_at ASC',
    );

    return rows.map((row) {
      return RandomAddition(
        id: row['id'] as String,
        content: row['content'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList(growable: false);
  }

  Future<void> upsertAddition(RandomAddition addition) async {
    final db = await _databaseManager.database;
    await db.insert(
      IdeasDatabaseManager.randomAdditionsTable,
      {
        'id': addition.id,
        'content': addition.content,
        'created_at': addition.createdAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAddition(String additionId) async {
    final db = await _databaseManager.database;
    await db.delete(
      IdeasDatabaseManager.randomAdditionsTable,
      where: 'id = ?',
      whereArgs: [additionId],
    );
  }

  Future<void> saveAdditions(List<RandomAddition> additions) async {
    final db = await _databaseManager.database;
    await db.transaction((txn) async {
      await txn.delete(IdeasDatabaseManager.randomAdditionsTable);
      final batch = txn.batch();
      for (final addition in additions) {
        batch.insert(
          IdeasDatabaseManager.randomAdditionsTable,
          {
            'id': addition.id,
            'content': addition.content,
            'created_at': addition.createdAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<void> writeAdditionRow(
    DatabaseExecutor executor,
    RandomAddition addition,
  ) async {
    await executor.insert(
      IdeasDatabaseManager.randomAdditionsTable,
      {
        'id': addition.id,
        'content': addition.content,
        'created_at': addition.createdAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteAllAdditionRows(DatabaseExecutor executor) async {
    await executor.delete(IdeasDatabaseManager.randomAdditionsTable);
  }
}
