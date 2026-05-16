import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/models/backup/cloud_backup_snapshot.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/random_addition.dart';

void main() {
  group('CloudBackupSnapshot', () {
    test('serializes random additions in current backup format', () {
      final idea = Idea(
        id: 'idea-1',
        title: 'Backup idea',
        createdAt: DateTime.utc(2026, 5, 16),
        updatedAt: DateTime.utc(2026, 5, 16),
        lastOpenedSectionId: 'section-1',
        sections: const [
          IdeaSection(
            id: 'section-1',
            name: 'Idea',
            content: '',
          ),
        ],
      );
      final addition = RandomAddition(
        id: 'random-1',
        content: 'Loose note',
        createdAt: DateTime.utc(2026, 5, 16, 12),
      );

      final snapshot = CloudBackupSnapshot.fromContent(
        ideas: [idea],
        randomAdditions: [addition],
      );
      final restored = CloudBackupSnapshot.fromJson(snapshot.toJson());

      expect(restored.version, CloudBackupSnapshot.currentVersion);
      expect(restored.ideas.single.title, 'Backup idea');
      expect(restored.ideas.single.lastOpenedSectionId, 'section-1');
      expect(restored.randomAdditions.single, addition);
    });

    test('parses old backups without random additions', () {
      final snapshot = CloudBackupSnapshot.fromJson({
        'version': 1,
        'exportedAt': '2026-05-16T00:00:00.000Z',
        'ideas': const [],
      });

      expect(snapshot.version, 1);
      expect(snapshot.ideas, isEmpty);
      expect(snapshot.randomAdditions, isEmpty);
    });
  });
}
