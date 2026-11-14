import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_merge.dart';
import 'package:idea_vault/models/backup/cloud_backup_restore.dart';
import 'package:idea_vault/models/random_addition.dart';

import '../../../helpers/backup_test_harness.dart';

String _copyTitle(String title, bool fromBackup) =>
    fromBackup ? '$title (from backup)' : '$title (from this device)';

void main() {
  group('CloudBackupMerge', () {
    test('adds missing ideas, skips identical ones and keeps both versions',
        () {
      final local = LocalVaultContent(
        ideas: [
          backupTestIdea('same'),
          backupTestIdea(
            'changed-local-newer',
            content: 'local',
            updatedAt: DateTime.utc(2026, 3, 1),
          ),
          backupTestIdea(
            'changed-backup-newer',
            content: 'local',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        randomAdditions: [backupTestNote('note-same')],
      );
      final backup = LocalVaultContent(
        ideas: [
          backupTestIdea('same'),
          backupTestIdea(
            'changed-local-newer',
            content: 'backup',
            updatedAt: DateTime.utc(2026, 2, 1),
          ),
          backupTestIdea(
            'changed-backup-newer',
            content: 'backup',
            updatedAt: DateTime.utc(2026, 4, 1),
          ),
          backupTestIdea('new'),
        ],
        randomAdditions: [
          backupTestNote('note-same'),
          backupTestNote('note-new'),
        ],
      );

      final plan = CloudBackupMerge.plan(
        local: local,
        backup: backup,
        copyTitle: _copyTitle,
      );

      expect(plan.result.added, 2);
      expect(plan.result.copies, 2);
      expect(plan.result.skippedIdentical, 2);

      final written = {for (final idea in plan.ideasToWrite) idea.title: idea};
      expect(written.containsKey('Idea new'), isTrue);
      expect(
        written['Idea changed-local-newer (from backup)']!.sections.single.content,
        'backup',
      );
      expect(
        written['Idea changed-local-newer (from backup)']!.id,
        isNot('changed-local-newer'),
      );
      final replacedInPlace = plan.ideasToWrite
          .firstWhere((idea) => idea.id == 'changed-backup-newer');
      expect(replacedInPlace.sections.single.content, 'backup');
      final localCopy =
          written['Idea changed-backup-newer (from this device)']!;
      expect(localCopy.sections.single.content, 'local');
      expect(localCopy.sections.single.id, isNot('section-changed-backup-newer'));
      expect(localCopy.lastOpenedSectionId, localCopy.sections.single.id);
      expect(plan.ideasToWrite.any((idea) => idea.id == 'same'), isFalse);
      expect(plan.ideasToWrite.any((idea) => idea.id == 'changed-local-newer'),
          isFalse);
      expect(plan.randomAdditionsToWrite.map((note) => note.id), ['note-new']);
    });

    test('keeps a changed random note as a copy instead of overwriting it', () {
      final local = LocalVaultContent(
        ideas: const [],
        randomAdditions: [backupTestNote('n1', content: 'local text')],
      );
      final backup = LocalVaultContent(
        ideas: const [],
        randomAdditions: [backupTestNote('n1', content: 'backup text')],
      );

      final plan = CloudBackupMerge.plan(
        local: local,
        backup: backup,
        copyTitle: _copyTitle,
      );

      expect(plan.result.copies, 1);
      expect(plan.randomAdditionsToWrite.single.id, isNot('n1'));
      expect(plan.randomAdditionsToWrite.single.content, 'backup text');
    });

    test('renames section ids that collide with another local idea', () {
      final local = LocalVaultContent(
        ideas: [backupTestIdea('a', sectionId: 'shared-section')],
        randomAdditions: const <RandomAddition>[],
      );
      final backup = LocalVaultContent(
        ideas: [backupTestIdea('b', sectionId: 'shared-section')],
        randomAdditions: const <RandomAddition>[],
      );

      final plan = CloudBackupMerge.plan(
        local: local,
        backup: backup,
        copyTitle: _copyTitle,
      );

      final added = plan.ideasToWrite.single;
      expect(added.id, 'b');
      expect(added.sections.single.id, isNot('shared-section'));
      expect(added.lastOpenedSectionId, added.sections.single.id);
    });

    test('treats ideas with the same content but new timestamps as identical',
        () {
      final local = LocalVaultContent(
        ideas: [backupTestIdea('x', updatedAt: DateTime.utc(2026, 5, 1))],
        randomAdditions: const [],
      );
      final backup = LocalVaultContent(
        ideas: [backupTestIdea('x', updatedAt: DateTime.utc(2026, 6, 1))],
        randomAdditions: const [],
      );

      final plan = CloudBackupMerge.plan(
        local: local,
        backup: backup,
        copyTitle: _copyTitle,
      );

      expect(plan.ideasToWrite, isEmpty);
      expect(plan.result.skippedIdentical, 1);
      expect(CloudBackupMerge.ideasMatch(local.ideas.single, backup.ideas.single),
          isTrue);
    });
  });
}
