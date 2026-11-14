import '../../../models/backup/cloud_backup_account.dart';

class CloudBackupFile {
  const CloudBackupFile({
    required this.contents,
    required this.sizeBytes,
  });

  final String contents;
  final int sizeBytes;
}

class CloudBackupFileInfo {
  const CloudBackupFileInfo({
    required this.id,
    required this.name,
    this.modifiedAt,
    this.sizeBytes,
  });

  final String id;
  final String name;
  final DateTime? modifiedAt;
  final int? sizeBytes;
}

class CloudBackupWriteResult {
  const CloudBackupWriteResult({
    required this.sizeBytes,
    this.pending = false,
  });

  final int sizeBytes;
  final bool pending;
}

enum CloudBackupUploadState { complete, pending, missing }

abstract class CloudBackupStore {
  Future<CloudBackupAccount?> connect({required bool forceAccountPicker});

  Future<void> signOut();

  Future<List<CloudBackupFileInfo>> listFiles({bool silentAuth = false});

  Future<CloudBackupFile> readFile(
    CloudBackupFileInfo file, {
    bool silentAuth = false,
  });

  Future<CloudBackupWriteResult> writeFile(
    String name,
    String contents, {
    bool silentAuth = false,
  });

  Future<void> deleteFile(CloudBackupFileInfo file, {bool silentAuth = false});

  Future<CloudBackupUploadState> uploadState(
    String name, {
    bool silentAuth = true,
  });
}
