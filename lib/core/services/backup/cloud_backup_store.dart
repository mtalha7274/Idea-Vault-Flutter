import '../../../models/backup/cloud_backup_account.dart';

class CloudBackupFile {
  const CloudBackupFile({
    required this.contents,
    required this.sizeBytes,
  });

  final String contents;
  final int sizeBytes;
}

abstract class CloudBackupStore {
  Future<CloudBackupAccount?> connect({required bool forceAccountPicker});
  Future<void> disconnect();
  Future<CloudBackupFile?> readBackup();
  Future<int> writeBackup(String contents);
  Future<bool> backupExists();
}
