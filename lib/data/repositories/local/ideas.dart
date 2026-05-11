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
      return Idea(
        id: ideaId,
        title: row['title'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        sections: sectionsByIdeaId[ideaId] ?? const [],
      );
    }).toList();
  }

  Future<void> upsertIdea(Idea idea) async {
    final db = await _databaseManager.database;
    await db.transaction((txn) async {
      await txn.insert(
        IdeasDatabaseManager.ideasTable,
        {
          'id': idea.id,
          'title': idea.title,
          'created_at': idea.createdAt.toIso8601String(),
          'updated_at': idea.updatedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        IdeasDatabaseManager.sectionsTable,
        where: 'idea_id = ?',
        whereArgs: [idea.id],
      );

      final batch = txn.batch();
      for (final (index, section) in idea.sections.indexed) {
        batch.insert(
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
      await batch.commit(noResult: true);
    });
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
      await txn.delete(IdeasDatabaseManager.sectionsTable);
      await txn.delete(IdeasDatabaseManager.ideasTable);
      for (final idea in ideas) {
        await txn.insert(
          IdeasDatabaseManager.ideasTable,
          {
            'id': idea.id,
            'title': idea.title,
            'created_at': idea.createdAt.toIso8601String(),
            'updated_at': idea.updatedAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        for (final (index, section) in idea.sections.indexed) {
          await txn.insert(
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
    });
  }
}
