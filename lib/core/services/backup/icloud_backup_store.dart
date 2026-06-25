import 'dart:convert';
import 'dart:io';

import 'package:icloud_storage/icloud_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../../models/backup/cloud_backup_account.dart';
import 'cloud_backup_store.dart';

class ICloudBackupStore implements CloudBackupStore {
  const ICloudBackupStore({
    this.containerId = 'iCloud.com.pocketmicros.ideavault',
  });

  static const String backupRelativePath = 'Backups/idea_vault_backup.json';

  final String containerId;

  @override
  Future<CloudBackupAccount?> connect(
      {required bool forceAccountPicker}) async {
    await ICloudStorage.gather(containerId: containerId);
    return const CloudBackupAccount(email: 'iCloud', provider: 'icloud');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> backupExists() async {
    final files = await ICloudStorage.gather(containerId: containerId);
    return files.any((file) => file.relativePath == backupRelativePath);
  }

  @override
  Future<CloudBackupFile?> readBackup() async {
    if (!await backupExists()) {
      return null;
    }

    final tempFile = await _tempBackupFile();
    await ICloudStorage.download(
      containerId: containerId,
      relativePath: backupRelativePath,
      destinationFilePath: tempFile.path,
    );
    final bytes = await tempFile.readAsBytes();
    return CloudBackupFile(
      contents: utf8.decode(bytes),
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<int> writeBackup(String contents, {bool silentAuth = false}) async {
    final tempFile = await _tempBackupFile();
    final bytes = utf8.encode(contents);
    await tempFile.writeAsBytes(bytes, flush: true);
    await ICloudStorage.upload(
      containerId: containerId,
      filePath: tempFile.path,
      destinationRelativePath: backupRelativePath,
    );
    return bytes.length;
  }

  Future<File> _tempBackupFile() async {
    final directory = await getTemporaryDirectory();
    return File('${directory.path}/idea_vault_backup.json');
  }
}
