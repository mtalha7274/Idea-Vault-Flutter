import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/data/managers/local/ideas_database.dart';
import 'package:idea_vault/data/repositories/local/ideas.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../helpers/test_ideas_database.dart';

void main() {
  group('IdeasRepo', () {
    late IdeasDatabaseManager databaseManager;
    late IdeasRepo repo;

    setUp(() async {
      databaseManager = await createTestIdeasDatabaseManager();
      repo = IdeasRepo(databaseManager);
    });

    tearDown(() async {
      await disposeTestIdeasDatabaseManager(databaseManager);
    });

    test('serializes and deserializes ideas with custom sections', () async {
      final ideas = [
        Idea(
          id: 'idea-1',
          title: 'Neighborhood Lab',
          createdAt: DateTime.utc(2026, 4, 20, 10, 30),
          updatedAt: DateTime.utc(2026, 4, 21, 11, 45),
          lastOpenedSectionId: 'section-2',
          isLocked: true,
          sections: [
            const IdeaSection(
              id: 'section-1',
              name: 'Idea',
              content:
                  '# Shared workshop spaces\n\nA flexible local maker hub.',
            ),
            const IdeaSection(
              id: 'section-2',
              name: 'Research',
              content: '- Pilot with 10 makers.\n- Measure repeat usage.',
            ),
          ],
        ),
      ];

      await repo.saveIdeas(ideas);

      final loadedIdeas = await repo.getIdeas();

      expect(loadedIdeas, hasLength(1));
      expect(loadedIdeas.first, ideas.first);
      expect(
        loadedIdeas.first.sections.last.content,
        ideas.first.sections.last.content,
      );
      expect(loadedIdeas.first.lastOpenedSectionId, 'section-2');
      expect(loadedIdeas.first.isLocked, isTrue);
    });

    test('updates an idea lock state without touching sections', () async {
      final idea = Idea(
        id: 'idea-1',
        title: 'Private Lab',
        createdAt: DateTime.utc(2026, 4, 20, 10, 30),
        updatedAt: DateTime.utc(2026, 4, 21, 11, 45),
        sections: const [
          IdeaSection(
            id: 'section-1',
            name: 'Idea',
            content: 'First',
          ),
        ],
      );

      await repo.upsertIdea(idea);
      await repo.updateIdeaLockState(ideaId: idea.id, isLocked: true);

      final loadedIdeas = await repo.getIdeas();

      expect(loadedIdeas.single.isLocked, isTrue);
      expect(loadedIdeas.single.sections, idea.sections);
    });

    test('updates an idea last opened section without touching sections',
        () async {
      final idea = Idea(
        id: 'idea-1',
        title: 'Neighborhood Lab',
        createdAt: DateTime.utc(2026, 4, 20, 10, 30),
        updatedAt: DateTime.utc(2026, 4, 21, 11, 45),
        sections: const [
          IdeaSection(
            id: 'section-1',
            name: 'Idea',
            content: 'First',
          ),
          IdeaSection(
            id: 'section-2',
            name: 'Research',
            content: 'Second',
          ),
        ],
      );

      await repo.upsertIdea(idea);
      await repo.updateLastOpenedSectionId(
        ideaId: idea.id,
        sectionId: 'section-2',
      );

      final loadedIdeas = await repo.getIdeas();

      expect(loadedIdeas.single.lastOpenedSectionId, 'section-2');
      expect(loadedIdeas.single.sections, idea.sections);
    });

    test('migrates v3 ideas table with unlocked default', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final tempDirectory =
          await Directory.systemTemp.createTemp('idea_vault_migration_test_');
      final dbPath = path.join(tempDirectory.path, 'idea_vault.db');
      final oldDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE ideas (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                last_opened_section_id TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE idea_sections (
                id TEXT PRIMARY KEY,
                idea_id TEXT NOT NULL,
                name TEXT NOT NULL,
                content TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                FOREIGN KEY (idea_id) REFERENCES ideas(id) ON DELETE CASCADE
              )
            ''');
            await db.insert('ideas', {
              'id': 'idea-1',
              'title': 'Migrated',
              'created_at': DateTime.utc(2026, 4, 20).toIso8601String(),
              'updated_at': DateTime.utc(2026, 4, 21).toIso8601String(),
              'last_opened_section_id': null,
            });
          },
        ),
      );
      await oldDb.close();

      final migratedManager = IdeasDatabaseManager(databasePath: dbPath);
      final migratedRepo = IdeasRepo(migratedManager);
      final loadedIdeas = await migratedRepo.getIdeas();

      expect(loadedIdeas.single.isLocked, isFalse);

      await disposeTestIdeasDatabaseManager(migratedManager);
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
  });
}
