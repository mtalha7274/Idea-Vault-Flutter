import 'dart:convert';
import 'dart:io';

import '../../../models/backup/cloud_backup_account.dart';
import '../../../models/backup/cloud_backup_snapshot.dart';
import '../../../models/idea.dart';
import '../../../models/random_addition.dart';
import 'cloud_backup_store.dart';
import 'google_drive_backup_store.dart';
import 'icloud_backup_store.dart';

class CloudBackupService {
  CloudBackupService({
    CloudBackupStore? androidStore,
    CloudBackupStore? iosStore,
  })  : _androidStore = androidStore ?? GoogleDriveBackupStore(),
        _iosStore = iosStore ?? const ICloudBackupStore();

  final CloudBackupStore _androidStore;
  final CloudBackupStore _iosStore;

  CloudBackupStore get _store => Platform.isIOS ? _iosStore : _androidStore;

  Future<CloudBackupAccount?> connect({bool forceAccountPicker = false}) {
    return _store.connect(forceAccountPicker: forceAccountPicker);
  }

  Future<void> disconnect() {
    return _store.disconnect();
  }

  Future<bool> backupExists() {
    return _store.backupExists();
  }

  Future<int> backUpIdeas(
    List<Idea> ideas, {
    List<RandomAddition> randomAdditions = const [],
  }) async {
    final snapshot = CloudBackupSnapshot.fromContent(
      ideas: ideas,
      randomAdditions: randomAdditions,
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(snapshot);
    return _store.writeBackup(encoded);
  }

  Future<CloudBackupSnapshot?> restoreSnapshot() async {
    final file = await _store.readBackup();
    if (file == null) {
      return null;
    }
    final decoded = jsonDecode(file.contents) as Map<String, dynamic>;
    return CloudBackupSnapshot.fromJson(decoded);
  }
}
