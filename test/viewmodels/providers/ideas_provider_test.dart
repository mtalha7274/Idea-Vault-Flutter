import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/data/repositories/local/ideas.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';

import '../../helpers/memory_local_storage.dart';

void main() {
  group('IdeasProvider', () {
    late MemoryLocalStorageManager storage;
    late IdeasRepo repo;

    setUp(() {
      storage = MemoryLocalStorageManager();
      repo = IdeasRepo(storage);
    });

    test('loads ideas from local storage on startup', () async {
      final seededIdea = Idea(
        id: 'seeded-idea',
        title: 'Offline-first notes',
        createdAt: DateTime.utc(2026, 4, 18),
        updatedAt: DateTime.utc(2026, 4, 19),
        sections: buildDefaultIdeaSections(),
      );
      await repo.saveIdeas([seededIdea]);

      final provider = IdeasProvider(repo);

      expect(provider.ideas, [seededIdea]);
    });

    test('creates a new idea', () async {
      final provider = IdeasProvider(repo);

      final savedIdea = await provider.saveIdea(
        title: 'New vault item',
        sections: provider.createDefaultSections(),
      );

      expect(savedIdea, isNotNull);
      expect(provider.ideas, hasLength(1));
      expect(provider.ideas.first.title, 'New vault item');
      expect(repo.getIdeas().first.title, 'New vault item');
    });

    test('updates an existing idea', () async {
      final provider = IdeasProvider(repo);
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
      expect(provider.ideas.first.sections, hasLength(4));
      expect(provider.ideas.first.createdAt, initialIdea.createdAt);
      expect(
        provider.ideas.first.updatedAt.isAfter(initialIdea.updatedAt),
        isTrue,
      );
    });

    test('keeps the list sorted by newest updatedAt', () async {
      final provider = IdeasProvider(repo);
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
  });
}
