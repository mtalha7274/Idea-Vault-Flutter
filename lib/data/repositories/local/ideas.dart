import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../models/idea.dart';
import '../../managers/local/ideas_database.dart';

class IdeasRepo {
  const IdeasRepo(this._databaseManager);

  final IdeasDatabaseManager _databaseManager;

  Future<List<Idea>> getIdeas() async {
    final db = await _databaseManager.database;
    final ideaRows = await db.query(
      IdeasDatabaseManager.ideasTable,
      orderBy: 'updated_at DESC',
    );

    if (ideaRows.isEmpty) {
      return const [];
    }

    final sectionRows = await db.query(
      IdeasDatabaseManager.sectionsTable,
      orderBy: 'idea_id ASC, sort_order ASC',
    );
    final sectionsByIdeaId = <String, List<IdeaSection>>{};

    for (final row in sectionRows) {
      final section = IdeaSection(
        id: row['id'] as String,
        name: row['name'] as String,
        content: row['content'] as String,
      );
      final ideaId = row['idea_id'] as String;
      sectionsByIdeaId.putIfAbsent(ideaId, () => []).add(section);
    }

    return ideaRows.map((row) {
      final ideaId = row['id'] as String;
      final payload = row['encrypted_payload'] as String?;
      return Idea(
        id: ideaId,
        title: row['title'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        lastOpenedSectionId: row['last_opened_section_id'] as String?,
        isLocked: row['is_locked'] == 1,
        encryptedPayload: payload,
        titleHidden: row['title_hidden'] == 1,
        sections:
            payload != null ? const [] : sectionsByIdeaId[ideaId] ?? const [],
      );
    }).toList();
  }

  Future<void> upsertIdea(Idea idea) async {
    final db = await _databaseManager.database;
    await db.transaction((txn) => writeIdeaRows(txn, idea));
  }

  Future<void> updateLastOpenedSectionId({
    required String ideaId,
    required String sectionId,
  }) async {
    final db = await _databaseManager.database;
    await db.update(
      IdeasDatabaseManager.ideasTable,
      {'last_opened_section_id': sectionId},
      where: 'id = ?',
      whereArgs: [ideaId],
    );
  }

  Future<void> updateIdeaLockState({
    required String ideaId,
    required bool isLocked,
  }) async {
    final db = await _databaseManager.database;
    await db.update(
      IdeasDatabaseManager.ideasTable,
      {'is_locked': isLocked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [ideaId],
    );
  }

  Future<void> deleteIdeas(Iterable<String> ideaIds) async {
    final ids = ideaIds.toSet().toList();
    if (ids.isEmpty) {
      return;
    }

    final db = await _databaseManager.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.delete(
      IdeasDatabaseManager.ideasTable,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<void> saveIdeas(List<Idea> ideas) async {
    final db = await _databaseManager.database;
    await db.transaction((txn) async {
      await deleteAllIdeaRows(txn);
      for (final idea in ideas) {
        await writeIdeaRows(txn, idea);
      }
    });
  }

  Future<void> writeIdeasAtomically(List<Idea> ideas) async {
    if (ideas.isEmpty) {
      return;
    }
    final db = await _databaseManager.database;
    await db.transaction((txn) async {
      for (final idea in ideas) {
        await writeIdeaInTransaction(txn, idea);
      }
    });
  }

  @protected
  Future<void> writeIdeaInTransaction(DatabaseExecutor executor, Idea idea) {
    return writeIdeaRows(executor, idea);
  }

  Future<bool> hasEncryptedIdeas() async {
    final db = await _databaseManager.database;
    final rows = await db.query(
      IdeasDatabaseManager.ideasTable,
      columns: ['id'],
      where: 'encrypted_payload IS NOT NULL',
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> sectionIdsNotOwnedBy(String ideaId) async {
    final db = await _databaseManager.database;
    final rows = await db.query(
      IdeasDatabaseManager.sectionsTable,
      columns: ['id'],
      where: 'idea_id != ?',
      whereArgs: [ideaId],
    );
    return {for (final row in rows) row['id'] as String};
  }

  Future<void> compact() => _databaseManager.compact();

  static Map<String, Object?> ideaRow(Idea idea) {
    return {
      'id': idea.id,
      'title': idea.title,
      'created_at': idea.createdAt.toIso8601String(),
      'updated_at': idea.updatedAt.toIso8601String(),
      'last_opened_section_id': idea.lastOpenedSectionId,
      'is_locked': idea.isLocked ? 1 : 0,
      'encrypted_payload': idea.encryptedPayload,
      'title_hidden': idea.titleHidden ? 1 : 0,
    };
  }

  static Future<void> writeIdeaRows(
    DatabaseExecutor executor,
    Idea idea,
  ) async {
    await executor.insert(
      IdeasDatabaseManager.ideasTable,
      ideaRow(idea),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await executor.delete(
      IdeasDatabaseManager.sectionsTable,
      where: 'idea_id = ?',
      whereArgs: [idea.id],
    );
    if (idea.isEncrypted) {
      return;
    }
    for (final (index, section) in idea.sections.indexed) {
      await executor.insert(
        IdeasDatabaseManager.sectionsTable,
        {
          'id': section.id,
          'idea_id': idea.id,
          'name': section.name,
          'content': section.content,
          'sort_order': index,
        },
      );
    }
  }

  static Future<void> deleteAllIdeaRows(DatabaseExecutor executor) async {
    await executor.delete(IdeasDatabaseManager.sectionsTable);
    await executor.delete(IdeasDatabaseManager.ideasTable);
  }
}
