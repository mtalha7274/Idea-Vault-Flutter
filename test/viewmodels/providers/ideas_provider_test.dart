import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/data/managers/local/ideas_database.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/ideas.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';

import '../../helpers/memory_local_storage.dart';
import '../../helpers/test_ideas_database.dart';

void main() {
  group('IdeasProvider', () {
    late MemoryLocalStorageManager storage;
    late IdeasDatabaseManager databaseManager;
    late IdeasRepo repo;
    late IdeaEditorStateRepo editorStateRepo;

    setUp(() async {
      storage = MemoryLocalStorageManager();
      databaseManager = await createTestIdeasDatabaseManager();
      repo = IdeasRepo(databaseManager);
      editorStateRepo = IdeaEditorStateRepo(storage);
    });

    tearDown(() async {
      await disposeTestIdeasDatabaseManager(databaseManager);
    });

    test('loads ideas from sqlite on startup', () async {
      final seededIdea = Idea(
        id: 'seeded-idea',
        title: 'Offline-first notes',
        createdAt: DateTime.utc(2026, 4, 18),
        updatedAt: DateTime.utc(2026, 4, 19),
        sections: buildDefaultIdeaSections(),
      );
      await repo.saveIdeas([seededIdea]);

      final provider = IdeasProvider(repo, editorStateRepo);
      await provider.ensureLoaded();

      expect(provider.ideas, [seededIdea]);
    });

    test('creates a new idea', () async {
      final provider = IdeasProvider(repo, editorStateRepo);
      await provider.ensureLoaded();

      final savedIdea = await provider.saveIdea(
        title: 'New vault item',
        sections: provider.createDefaultSections(),
      );

      expect(savedIdea, isNotNull);
      expect(provider.ideas, hasLength(1));
      expect(provider.ideas.first.title, 'New vault item');
      expect((await repo.getIdeas()).first.title, 'New vault item');
    });

    test('updates an existing idea', () async {
      final provider = IdeasProvider(repo, editorStateRepo);
      await provider.ensureLoaded();

      final initialIdea = await provider.saveIdea(
        title: 'Draft title',
        sections: provider.createDefaultSections(),
      );

      expect(initialIdea, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 2));

      final updatedIdea = await provider.saveIdea(
        ideaId: initialIdea!.id,
        title: 'Refined title',
        sections: [
          ...initialIdea.sections,
          IdeaSection.empty(name: 'Launch'),
        ],
      );

      expect(updatedIdea, isNotNull);
      expect(provider.ideas, hasLength(1));
      expect(provider.ideas.first.title, 'Refined title');
      expect(provider.ideas.first.sections, hasLength(2));
      expect(provider.ideas.first.createdAt, initialIdea.createdAt);
      expect(
        provider.ideas.first.updatedAt.isAfter(initialIdea.updatedAt),
        isTrue,
      );
    });

    test('appends content to a section with a blank line separator', () async {
      final provider = IdeasProvider(repo, editorStateRepo);
      await provider.ensureLoaded();

      final savedIdea = await provider.saveIdea(
        title: 'Append target',
        sections: [
          const IdeaSection(
            id: 'section-1',
            name: 'Idea',
            content: 'Existing content\n\n',
          ),
        ],
      );

      await provider.appendContentToSection(
        ideaId: savedIdea!.id,
        sectionId: 'section-1',
        content: '  First dictated line\nSecond dictated line  ',
      );

      expect(
        provider.ideas.single.sections.single.content,
        'Existing content\n\nFirst dictated line\nSecond dictated line',
      );
    });

    test('keeps the list sorted by newest updatedAt', () async {
      final provider = IdeasProvider(repo, editorStateRepo);
      await provider.ensureLoaded();

      final firstIdea = await provider.saveIdea(
        title: 'First',
        sections: provider.createDefaultSections(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final secondIdea = await provider.saveIdea(
        title: 'Second',
        sections: provider.createDefaultSections(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));

      await provider.saveIdea(
        ideaId: firstIdea!.id,
        title: 'First updated',
        sections: firstIdea.sections,
      );

      expect(provider.ideas.first.id, firstIdea.id);
      expect(provider.ideas[1].id, secondIdea!.id);
    });

    test('persists resume state for an open editor', () async {
      final provider = IdeasProvider(repo, editorStateRepo);
      await provider.ensureLoaded();

      final savedIdea = await provider.saveIdea(
        title: 'Resume me',
        sections: provider.createDefaultSections(),
      );

      await provider.saveEditorState(
        ideaId: savedIdea!.id,
        activeSectionId: savedIdea.sections.first.id,
        isPreviewMode: true,
      );

      final restoredProvider = IdeasProvider(repo, editorStateRepo);
      await restoredProvider.ensureLoaded();

      expect(restoredProvider.resumeEditorState, isNotNull);
      expect(restoredProvider.resumeEditorState!.ideaId, savedIdea.id);
      expect(
        restoredProvider.resumeEditorState!.activeSectionId,
        savedIdea.sections.first.id,
      );
      expect(restoredProvider.resumeEditorState!.isPreviewMode, isTrue);
    });
  });
}
