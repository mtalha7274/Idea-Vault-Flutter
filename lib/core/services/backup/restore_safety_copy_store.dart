import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../models/backup/cloud_backup_restore.dart';
import '../../../models/backup/cloud_backup_snapshot.dart';

class RestoreSafetyCopy {
  const RestoreSafetyCopy({
    required this.id,
    required this.createdAt,
  });

  final String id;
  final DateTime createdAt;
}

class RestoreSafetyCopyStore {
  RestoreSafetyCopyStore({
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
    this.keep = defaultKeep,
  })  : _directory = directory,
        _clock = clock ?? DateTime.now;

  static const int defaultKeep = 3;
  static const String folderName = 'backup_safety_copies';
  static const String _prefix = 'safety_';
  static const String _suffix = '.json';

  final Future<Directory> Function()? _directory;
  final DateTime Function() _clock;
  final int keep;

  Future<Directory> _resolveDirectory() async {
    final override = _directory;
    final base = override != null
        ? await override()
        : Directory(
            '${(await getApplicationSupportDirectory()).path}/$folderName',
          );
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    return base;
  }

  Future<RestoreSafetyCopy> save(LocalVaultContent content) async {
    final directory = await _resolveDirectory();
    var createdAt = _clock().toUtc();
    var id = '$_prefix${createdAt.microsecondsSinceEpoch}';
    while (await File('${directory.path}/$id$_suffix').exists()) {
      createdAt = createdAt.add(const Duration(microseconds: 1));
      id = '$_prefix${createdAt.microsecondsSinceEpoch}';
    }
    final snapshot = CloudBackupSnapshot.fromContent(
      ideas: content.ideas,
      randomAdditions: content.randomAdditions,
      createdAt: createdAt,
      lock: content.lock,
    );
    final file = File('${directory.path}/$id$_suffix');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(snapshot.encode(), flush: true);
    await temp.rename(file.path);
    await _prune(directory);
    return RestoreSafetyCopy(id: id, createdAt: createdAt);
  }

  Future<int> rewriteAll(
    Future<LocalVaultContent> Function(LocalVaultContent content) transform,
  ) async {
    final directory = await _resolveDirectory();
    var rewritten = 0;
    for (final copy in await list()) {
      final file = File('${directory.path}/${copy.id}$_suffix');
      try {
        final snapshot =
            CloudBackupSnapshot.decodeAndValidate(await file.readAsString());
        if (!snapshot.hasPlaintextLockedIdeas) {
          continue;
        }
        final next = await transform(
          LocalVaultContent(
            ideas: snapshot.ideas,
            randomAdditions: snapshot.randomAdditions,
            lock: snapshot.lockBlock,
          ),
        );
        final updated = CloudBackupSnapshot.fromContent(
          ideas: next.ideas,
          randomAdditions: next.randomAdditions,
          createdAt: snapshot.createdAt,
          lock: next.lock,
        );
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(updated.encode(), flush: true);
        await temp.rename(file.path);
        rewritten += 1;
      } catch (_) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    return rewritten;
  }

  Future<List<RestoreSafetyCopy>> list() async {
    final directory = await _resolveDirectory();
    final copies = <RestoreSafetyCopy>[];
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_prefix) || !name.endsWith(_suffix)) {
        continue;
      }
      final id = name.substring(0, name.length - _suffix.length);
      final micros = int.tryParse(id.substring(_prefix.length));
      if (micros == null) {
        continue;
      }
      copies.add(
        RestoreSafetyCopy(
          id: id,
          createdAt: DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
        ),
      );
    }
    copies.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copies;
  }

  Future<LocalVaultContent?> read(String id) async {
    final directory = await _resolveDirectory();
    final file = File('${directory.path}/$id$_suffix');
    if (!await file.exists()) {
      return null;
    }
    final snapshot =
        CloudBackupSnapshot.decodeAndValidate(await file.readAsString());
    return LocalVaultContent(
      ideas: snapshot.ideas,
      randomAdditions: snapshot.randomAdditions,
      lock: snapshot.lockBlock,
    );
  }

  Future<void> _prune(Directory directory) async {
    final copies = await list();
    for (final copy in copies.skip(keep)) {
      final file = File('${directory.path}/${copy.id}$_suffix');
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }
}
