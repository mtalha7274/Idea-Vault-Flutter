import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:icloud_storage/icloud_storage.dart';
import 'package:icloud_storage/icloud_storage_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

import '../../../models/backup/cloud_backup_account.dart';
import 'cloud_backup_store.dart';

typedef ICloudGather = Future<List<ICloudFile>> Function({
  required String containerId,
});
typedef ICloudDownload = Future<void> Function({
  required String containerId,
  required String relativePath,
  required String destinationFilePath,
  StreamHandler<double>? onProgress,
});
typedef ICloudUpload = Future<void> Function({
  required String containerId,
  required String filePath,
  required String destinationRelativePath,
  StreamHandler<double>? onProgress,
});

class ICloudBackupStore implements CloudBackupStore {
  ICloudBackupStore({
    this.containerId = 'iCloud.com.pocketmicros.ideavault',
    ICloudGather? gather,
    ICloudDownload? download,
    ICloudUpload? upload,
    Future<File> Function()? tempBackupFile,
  })  : _gather = gather ?? ICloudStorage.gather,
        _download = download ?? ICloudStorage.download,
        _upload = upload ??
            (({
              required containerId,
              required filePath,
              required destinationRelativePath,
              onProgress,
            }) =>
                ICloudStorage.upload(
                  containerId: containerId,
                  filePath: filePath,
                  destinationRelativePath: destinationRelativePath,
                  onProgress: onProgress,
                )),
        _tempBackupFileOverride = tempBackupFile;

  static const String backupRelativePath = 'Backups/idea_vault_backup.json';
  static const String usageMetadataRelativePath =
      'Backups/idea_vault_usage_metadata.json';
  static const Duration downloadTimeout = Duration(seconds: 30);

  final String containerId;
  final ICloudGather _gather;
  final ICloudDownload _download;
  final ICloudUpload _upload;
  final Future<File> Function()? _tempBackupFileOverride;

  @override
  Future<CloudBackupAccount?> connect(
      {required bool forceAccountPicker}) async {
    await _gather(containerId: containerId);
    return const CloudBackupAccount(email: 'iCloud', provider: 'icloud');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> backupExists() async {
    return _fileExists(backupRelativePath);
  }

  Future<bool> _fileExists(String relativePath) async {
    final files = await _gather(containerId: containerId);
    return files.any(
      (file) =>
          file.relativePath == relativePath &&
          file.sizeInBytes > 0 &&
          !file.isUploading,
    );
  }

  @override
  Future<CloudBackupFile?> readBackup() async {
    return _readFile(
      backupRelativePath,
      tempFileName: 'idea_vault_backup.json',
    );
  }

  @override
  Future<CloudBackupFile?> readUsageMetadata({bool silentAuth = false}) {
    return _readFile(
      usageMetadataRelativePath,
      tempFileName: 'idea_vault_usage_metadata.json',
    );
  }

  @override
  Future<int> writeBackup(String contents, {bool silentAuth = false}) async {
    return _writeFile(
      backupRelativePath,
      contents,
      tempFileName: 'idea_vault_backup.json',
    );
  }

  @override
  Future<int> writeUsageMetadata(
    String contents, {
    bool silentAuth = false,
  }) {
    return _writeFile(
      usageMetadataRelativePath,
      contents,
      tempFileName: 'idea_vault_usage_metadata.json',
    );
  }

  Future<CloudBackupFile?> _readFile(
    String relativePath, {
    required String tempFileName,
  }) async {
    if (!await _fileExists(relativePath)) {
      return null;
    }

    final tempFile = await _tempFile(tempFileName);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await _downloadFile(relativePath, tempFile);
    final bytes = await tempFile.readAsBytes();
    return CloudBackupFile(
      contents: utf8.decode(bytes),
      sizeBytes: bytes.length,
    );
  }

  Future<int> _writeFile(
    String relativePath,
    String contents, {
    required String tempFileName,
  }) async {
    final tempFile = await _tempFile(tempFileName);
    final bytes = utf8.encode(contents);
    await tempFile.writeAsBytes(bytes, flush: true);
    await _upload(
      containerId: containerId,
      filePath: tempFile.path,
      destinationRelativePath: relativePath,
    );
    return bytes.length;
  }

  Future<File> _tempFile(String name) async {
    final override = _tempBackupFileOverride;
    if (override != null) {
      return override();
    }
    final directory = await getTemporaryDirectory();
    return File('${directory.path}/$name');
  }

  Future<void> _downloadFile(String relativePath, File tempFile) async {
    final downloadCompleter = Completer<void>();
    StreamSubscription<double>? progressSubscription;

    await _download(
      containerId: containerId,
      relativePath: relativePath,
      destinationFilePath: tempFile.path,
      onProgress: (stream) {
        progressSubscription = stream.listen(
          (_) {},
          onDone: () {
            if (!downloadCompleter.isCompleted) {
              downloadCompleter.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!downloadCompleter.isCompleted) {
              downloadCompleter.completeError(error, stackTrace);
            }
          },
          cancelOnError: true,
        );
      },
    );

    if (progressSubscription == null && !downloadCompleter.isCompleted) {
      downloadCompleter.complete();
    }

    try {
      await downloadCompleter.future.timeout(downloadTimeout);
    } finally {
      await progressSubscription?.cancel();
    }
  }
}
