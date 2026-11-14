import '../../../models/backup/cloud_backup_restore.dart';
import '../../../models/idea.dart';
import '../../../models/random_addition.dart';

typedef MergeCopyTitleBuilder = String Function(String title, bool fromBackup);

class CloudBackupMergePlan {
  const CloudBackupMergePlan({
    required this.ideasToWrite,
    required this.randomAdditionsToWrite,
    required this.result,
    this.copiedFrom = const {},
  });

  final List<Idea> ideasToWrite;
  final List<RandomAddition> randomAdditionsToWrite;
  final CloudBackupMergeResult result;
  final Map<String, String> copiedFrom;
}

class CloudBackupMerge {
  const CloudBackupMerge._();

  static bool ideasMatch(Idea a, Idea b) {
    if (a.title != b.title || a.isLocked != b.isLocked) {
      return false;
    }
    if (a.encryptedPayload != b.encryptedPayload ||
        a.titleHidden != b.titleHidden) {
      return false;
    }
    if (a.sections.length != b.sections.length) {
      return false;
    }
    for (var index = 0; index < a.sections.length; index++) {
      if (a.sections[index] != b.sections[index]) {
        return false;
      }
    }
    return true;
  }

  static bool additionsMatch(RandomAddition a, RandomAddition b) {
    return a.content == b.content && a.createdAt.isAtSameMomentAs(b.createdAt);
  }

  static CloudBackupMergePlan plan({
    required LocalVaultContent local,
    required LocalVaultContent backup,
    required MergeCopyTitleBuilder copyTitle,
    String Function(String prefix)? newId,
  }) {
    final generateId = newId ?? generateIdeaVaultId;
    final localById = {for (final idea in local.ideas) idea.id: idea};
    final ideaIdsInUse = {
      ...local.ideas.map((idea) => idea.id),
      ...backup.ideas.map((idea) => idea.id),
    };
    final sectionOwner = <String, String>{
      for (final idea in local.ideas)
        for (final section in idea.sections) section.id: idea.id,
    };

    final ideasToWrite = <Idea>[];
    final copiedFrom = <String, String>{};
    var added = 0;
    var copies = 0;
    var skipped = 0;

    String freshIdeaId() {
      var id = generateId('idea');
      while (ideaIdsInUse.contains(id)) {
        id = generateId('idea');
      }
      ideaIdsInUse.add(id);
      return id;
    }

    Idea withSafeSections(Idea idea, {required bool forceNewIds}) {
      final remapped = <String, String>{};
      final sections = <IdeaSection>[];
      for (final section in idea.sections) {
        final owner = sectionOwner[section.id];
        final collides = owner != null && owner != idea.id;
        if (forceNewIds || collides) {
          var nextId = generateId('section');
          while (sectionOwner.containsKey(nextId)) {
            nextId = generateId('section');
          }
          remapped[section.id] = nextId;
          sectionOwner[nextId] = idea.id;
          sections.add(section.copyWith(id: nextId));
        } else {
          sectionOwner[section.id] = idea.id;
          sections.add(section);
        }
      }
      final lastOpened = idea.lastOpenedSectionId;
      return Idea(
        id: idea.id,
        title: idea.title,
        createdAt: idea.createdAt,
        updatedAt: idea.updatedAt,
        lastOpenedSectionId:
            lastOpened == null ? null : remapped[lastOpened] ?? lastOpened,
        isLocked: idea.isLocked,
        encryptedPayload: idea.encryptedPayload,
        titleHidden: idea.titleHidden,
        sections: sections,
      );
    }

    Idea asCopy(Idea idea, {required bool fromBackup}) {
      final copy = Idea(
        id: freshIdeaId(),
        title: copyTitle(idea.title, fromBackup),
        createdAt: idea.createdAt,
        updatedAt: idea.updatedAt,
        lastOpenedSectionId: idea.lastOpenedSectionId,
        isLocked: idea.isLocked,
        encryptedPayload: idea.encryptedPayload,
        titleHidden: idea.titleHidden,
        sections: idea.sections,
      );
      copiedFrom[copy.id] = idea.id;
      return withSafeSections(copy, forceNewIds: true);
    }

    for (final backupIdea in backup.ideas) {
      final localIdea = localById[backupIdea.id];
      if (localIdea == null) {
        ideasToWrite.add(withSafeSections(backupIdea, forceNewIds: false));
        added += 1;
        continue;
      }
      if (ideasMatch(localIdea, backupIdea)) {
        skipped += 1;
        continue;
      }
      if (backupIdea.updatedAt.isAfter(localIdea.updatedAt)) {
        for (final section in localIdea.sections) {
          if (sectionOwner[section.id] == localIdea.id) {
            sectionOwner.remove(section.id);
          }
        }
        final localCopy = asCopy(localIdea, fromBackup: false);
        ideasToWrite.add(withSafeSections(backupIdea, forceNewIds: false));
        ideasToWrite.add(localCopy);
      } else {
        ideasToWrite.add(asCopy(backupIdea, fromBackup: true));
      }
      copies += 1;
    }

    final localAdditionsById = {
      for (final addition in local.randomAdditions) addition.id: addition,
    };
    final additionIdsInUse = {
      ...local.randomAdditions.map((addition) => addition.id),
      ...backup.randomAdditions.map((addition) => addition.id),
    };
    final additionsToWrite = <RandomAddition>[];
    for (final backupAddition in backup.randomAdditions) {
      final localAddition = localAdditionsById[backupAddition.id];
      if (localAddition == null) {
        additionsToWrite.add(backupAddition);
        added += 1;
        continue;
      }
      if (additionsMatch(localAddition, backupAddition)) {
        skipped += 1;
        continue;
      }
      var copyId = generateId('random-addition');
      while (additionIdsInUse.contains(copyId)) {
        copyId = generateId('random-addition');
      }
      additionIdsInUse.add(copyId);
      additionsToWrite.add(backupAddition.copyWith(id: copyId));
      copies += 1;
    }

    return CloudBackupMergePlan(
      ideasToWrite: ideasToWrite,
      randomAdditionsToWrite: additionsToWrite,
      result: CloudBackupMergeResult(
        added: added,
        copies: copies,
        skippedIdentical: skipped,
      ),
      copiedFrom: copiedFrom,
    );
  }
}
