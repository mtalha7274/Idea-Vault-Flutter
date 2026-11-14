import '../../../models/backup/cloud_backup_restore.dart';
import '../../../models/idea.dart';
import '../../../models/vault/vault_lock_block.dart';
import '../vault/note_vault_service.dart';
import '../vault/vault_crypto.dart';
import 'cloud_backup_merge.dart';

class BackupVaultPreparation {
  const BackupVaultPreparation({
    required this.backup,
    required this.notImported,
    this.adoptLock,
    this.key,
    this.keyId,
  });

  final LocalVaultContent backup;
  final int notImported;
  final VaultLockBlock? adoptLock;
  final List<int>? key;
  final String? keyId;

  bool get adoptsBackupVault => adoptLock != null;
}

class BackupVaultReconciler {
  const BackupVaultReconciler(this._vault);

  final NoteVaultService? _vault;

  Future<BackupVaultPreparation> prepare({
    required LocalVaultContent local,
    required LocalVaultContent backup,
    required CloudBackupRestoreMode mode,
    BackupVaultKeyPrompt? askBackupKey,
  }) async {
    final encrypted = backup.ideas.where((idea) => idea.isEncrypted).toList();
    if (encrypted.isEmpty) {
      if (mode != CloudBackupRestoreMode.merge || !local.hasEncryptedIdeas) {
        return BackupVaultPreparation(backup: backup, notImported: 0);
      }
      final key = await _vault?.loadKey();
      if (key != null) {
        return BackupVaultPreparation(
          backup: backup,
          notImported: 0,
          key: key,
          keyId: await _vault?.currentKeyId(),
        );
      }
      var dropped = 0;
      final filtered = _withoutUnsafeConflicts(
        backup,
        local,
        (count) => dropped = count,
      );
      return BackupVaultPreparation(backup: filtered, notImported: dropped);
    }
    final backupLock = backup.lock;
    if (backupLock == null) {
      return _dropEncrypted(backup, encrypted.length);
    }
    final vault = _vault;
    final localLock =
        vault == null ? local.lock : await vault.lockBlock() ?? local.lock;

    if (localLock == null) {
      var dropped = 0;
      final filtered = mode == CloudBackupRestoreMode.merge
          ? _withoutUnsafeConflicts(backup, local, (count) => dropped = count)
          : backup;
      return BackupVaultPreparation(
        backup: filtered,
        notImported: dropped,
        adoptLock: backupLock,
      );
    }

    final localKey = vault == null ? null : await vault.loadKey();
    if (localLock.keyId == backupLock.keyId) {
      if (localKey == null) {
        var dropped = 0;
        final filtered = mode == CloudBackupRestoreMode.merge
            ? _withoutUnsafeConflicts(backup, local, (count) => dropped = count)
            : backup;
        return BackupVaultPreparation(backup: filtered, notImported: dropped);
      }
      final matched = mode == CloudBackupRestoreMode.merge
          ? await _alignIdentical(
              backup,
              local,
              localKey,
              localLock.keyId,
            )
          : backup;
      return BackupVaultPreparation(
        backup: matched,
        notImported: 0,
        key: localKey,
        keyId: localLock.keyId,
      );
    }

    if (localKey == null || vault == null) {
      return _dropEncrypted(backup, encrypted.length);
    }
    final backupKey =
        askBackupKey == null ? null : await askBackupKey(backupLock);
    if (backupKey == null) {
      return _dropEncrypted(backup, encrypted.length);
    }

    var failed = 0;
    final ideas = <Idea>[];
    for (final idea in backup.ideas) {
      if (!idea.isEncrypted) {
        ideas.add(idea);
        continue;
      }
      try {
        ideas.add(
          await vault.reencryptIdea(
            idea,
            fromKey: backupKey,
            fromKeyId: backupLock.keyId,
            toKey: localKey,
            toKeyId: localLock.keyId,
          ),
        );
      } on VaultCryptoException {
        failed += 1;
      }
    }
    final rebound = LocalVaultContent(
      ideas: ideas,
      randomAdditions: backup.randomAdditions,
      lock: localLock,
    );
    final matched = mode == CloudBackupRestoreMode.merge
        ? await _alignIdentical(rebound, local, localKey, localLock.keyId)
        : rebound;
    return BackupVaultPreparation(
      backup: matched,
      notImported: failed,
      key: localKey,
      keyId: localLock.keyId,
    );
  }

  Future<CloudBackupMergePlan> rebindCopies(
    CloudBackupMergePlan plan,
    BackupVaultPreparation preparation,
  ) async {
    final vault = _vault;
    if (plan.copiedFrom.isEmpty) {
      return plan;
    }
    final key = preparation.key ?? await vault?.loadKey();
    final keyId = preparation.keyId ?? await vault?.currentKeyId();
    final ideas = <Idea>[];
    final droppedSources = <String>{};
    var dropped = 0;
    for (final idea in plan.ideasToWrite) {
      final sourceId = plan.copiedFrom[idea.id];
      if (sourceId == null || !idea.isEncrypted) {
        ideas.add(idea);
        continue;
      }
      if (vault == null || key == null || keyId == null) {
        dropped += 1;
        droppedSources.add(sourceId);
        continue;
      }
      try {
        final sourceIdea = Idea(
          id: sourceId,
          title: idea.title,
          createdAt: idea.createdAt,
          updatedAt: idea.updatedAt,
          lastOpenedSectionId: idea.lastOpenedSectionId,
          isLocked: true,
          encryptedPayload: idea.encryptedPayload,
          titleHidden: idea.titleHidden,
          sections: const [],
        );
        ideas.add(
          await vault.reencryptIdea(
            sourceIdea,
            fromKey: key,
            fromKeyId: keyId,
            toKey: key,
            toKeyId: keyId,
            newId: idea.id,
          ),
        );
      } on VaultCryptoException {
        dropped += 1;
        droppedSources.add(sourceId);
      }
    }
    final result = plan.result;
    return CloudBackupMergePlan(
      ideasToWrite:
          ideas.where((idea) => !droppedSources.contains(idea.id)).toList(),
      randomAdditionsToWrite: plan.randomAdditionsToWrite,
      copiedFrom: plan.copiedFrom,
      result: CloudBackupMergeResult(
        added: result.added,
        copies: result.copies - dropped,
        skippedIdentical: result.skippedIdentical,
      ),
    );
  }

  BackupVaultPreparation _dropEncrypted(LocalVaultContent backup, int count) {
    return BackupVaultPreparation(
      backup: LocalVaultContent(
        ideas: backup.ideas.where((idea) => !idea.isEncrypted).toList(),
        randomAdditions: backup.randomAdditions,
        lock: backup.lock,
      ),
      notImported: count,
    );
  }

  bool _isUnsafeConflict(Idea backupIdea, Idea? localIdea) {
    if (localIdea == null) {
      return false;
    }
    if (!backupIdea.isEncrypted && !localIdea.isEncrypted) {
      return false;
    }
    return !CloudBackupMerge.ideasMatch(localIdea, backupIdea);
  }

  LocalVaultContent _withoutUnsafeConflicts(
    LocalVaultContent backup,
    LocalVaultContent local,
    void Function(int count) onDropped,
  ) {
    final localById = {for (final idea in local.ideas) idea.id: idea};
    final kept = <Idea>[];
    var dropped = 0;
    for (final idea in backup.ideas) {
      if (_isUnsafeConflict(idea, localById[idea.id])) {
        dropped += 1;
      } else {
        kept.add(idea);
      }
    }
    onDropped(dropped);
    return LocalVaultContent(
      ideas: kept,
      randomAdditions: backup.randomAdditions,
      lock: backup.lock,
    );
  }

  Future<LocalVaultContent> _alignIdentical(
    LocalVaultContent backup,
    LocalVaultContent local,
    List<int> key,
    String keyId,
  ) async {
    final vault = _vault;
    if (vault == null) {
      return backup;
    }
    final localById = {for (final idea in local.ideas) idea.id: idea};
    final ideas = <Idea>[];
    for (final idea in backup.ideas) {
      final localIdea = localById[idea.id];
      if (localIdea == null ||
          !idea.isEncrypted ||
          !localIdea.isEncrypted ||
          localIdea.isLocked != idea.isLocked) {
        ideas.add(idea);
        continue;
      }
      try {
        final a = await vault.decryptIdea(idea, key: key, keyId: keyId);
        final b = await vault.decryptIdea(localIdea, key: key, keyId: keyId);
        final same = a.title == b.title &&
            a.sections.length == b.sections.length &&
            [
              for (var index = 0; index < a.sections.length; index++)
                a.sections[index] == b.sections[index],
            ].every((value) => value);
        ideas.add(same ? localIdea : idea);
      } on VaultCryptoException {
        ideas.add(idea);
      }
    }
    return LocalVaultContent(
      ideas: ideas,
      randomAdditions: backup.randomAdditions,
      lock: backup.lock,
    );
  }
}
