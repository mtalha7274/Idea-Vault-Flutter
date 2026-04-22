import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/data/repositories/local/ideas.dart';
import 'package:idea_vault/models/idea.dart';

import '../../../helpers/memory_local_storage.dart';

void main() {
  group('IdeasRepo', () {
    test('serializes and deserializes ideas with custom sections', () async {
      final storage = MemoryLocalStorageManager();
      final repo = IdeasRepo(storage);
      final ideas = [
        Idea(
          id: 'idea-1',
          title: 'Neighborhood Lab',
          createdAt: DateTime.utc(2026, 4, 20, 10, 30),
          updatedAt: DateTime.utc(2026, 4, 21, 11, 45),
          sections: [
            IdeaSection(
              id: 'section-1',
              name: 'Idea',
              content:
                  '# Shared workshop spaces\n\nA flexible local maker hub.',
            ),
            IdeaSection(
              id: 'section-2',
              name: 'Research',
              content: '- Pilot with 10 makers.\n- Measure repeat usage.',
            ),
          ],
        ),
      ];

      await repo.saveIdeas(ideas);

      final loadedIdeas = repo.getIdeas();

      expect(loadedIdeas, hasLength(1));
      expect(loadedIdeas.first, ideas.first);
      expect(loadedIdeas.first.sections.last.content,
          ideas.first.sections.last.content);
    });
  });
}
