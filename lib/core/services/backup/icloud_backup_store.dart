import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:icloud_storage/icloud_storage.dart';
import 'package:icloud_storage/icloud_storage_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

import '../../../models/backup/cloud_backup_account.dart';
import '../../../models/backup/cloud_backup_entry.dart';
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
typedef ICloudDelete = Future<void> Function({
  required String containerId,
  required String relativePath,
});

class ICloudBackupStore implements CloudBackupStore {
  ICloudBackupStore({
    this.containerId = 'iCloud.com.pocketmicros.ideavault',
    ICloudGather? gather,
    ICloudDownload? download,
    ICloudUpload? upload,
    ICloudDelete? delete,
    Future<File> Function()? tempBackupFile,
    Future<Directory> Function()? tempDirectory,
    this.downloadTimeout = defaultDownloadTimeout,
    this.uploadTimeout = defaultUploadTimeout,
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
        _delete = delete ?? ICloudStorage.delete,
        _tempBackupFileOverride = tempBackupFile,
        _tempDirectoryOverride = tempDirectory;

  static const String backupFolder = 'Backups';
  static const String backupRelativePath =
      '$backupFolder/${CloudBackupEntry.legacyFileName}';
  static const String uploadTempFileName = 'idea_vault_backup_upload.json';
  static const Duration defaultDownloadTimeout = Duration(seconds: 120);
  static const Duration defaultUploadTimeout = Duration(seconds: 60);

  final String containerId;
  final Duration downloadTimeout;
  final Duration uploadTimeout;
  final ICloudGather _gather;
  final ICloudDownload _download;
  final ICloudUpload _upload;
  final ICloudDelete _delete;
  final Future<File> Function()? _tempBackupFileOverride;
  final Future<Directory> Function()? _tempDirectoryOverride;

  static String relativePathFor(String name) => '$backupFolder/$name';

  static String? _nameFromRelativePath(String relativePath) {
    const prefix = '$backupFolder/';
    if (!relativePath.startsWith(prefix)) {
      return null;
    }
    final name = relativePath.substring(prefix.length);
    if (name.contains('/') || !CloudBackupEntry.isBackupFileName(name)) {
      return null;
    }
    return name;
  }

  @override
  Future<CloudBackupAccount?> connect(
      {required bool forceAccountPicker}) async {
    await _gather(containerId: containerId);
    return const CloudBackupAccount(email: 'iCloud', provider: 'icloud');
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<List<CloudBackupFileInfo>> listFiles({bool silentAuth = false}) async {
    final files = await _gather(containerId: containerId);
    final result = <CloudBackupFileInfo>[];
    for (final file in files) {
      final name = _nameFromRelativePath(file.relativePath);
      if (name == null || file.isUploading || file.sizeInBytes <= 0) {
        continue;
      }
      result.add(
        CloudBackupFileInfo(
          id: file.relativePath,
          name: name,
          modifiedAt: file.contentChangeDate.toUtc(),
          sizeBytes: file.sizeInBytes,
        ),
      );
    }
    return result;
  }

  @override
  Future<CloudBackupFile> readFile(
    CloudBackupFileInfo file, {
    bool silentAuth = false,
  }) async {
    final tempFile = await _tempFile(file.name);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    try {
      await _downloadFile(file.id, tempFile);
      final bytes = await tempFile.readAsBytes();
      return CloudBackupFile(
        contents: utf8.decode(bytes),
        sizeBytes: bytes.length,
      );
    } finally {
      if (_tempBackupFileOverride == null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  Future<CloudBackupWriteResult> writeFile(
    String name,
    String contents, {
    bool silentAuth = false,
  }) async {
    final tempFile = await _tempFile(uploadTempFileName);
    final bytes = utf8.encode(contents);
    await tempFile.writeAsBytes(bytes, flush: true);
    final completer = Completer<void>();
    StreamSubscription<double>? subscription;
    await _upload(
      containerId: containerId,
      filePath: tempFile.path,
      destinationRelativePath: relativePathFor(name),
      onProgress: (stream) {
        subscription = stream.listen(
          (_) {},
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
          cancelOnError: true,
        );
      },
    );

    if (subscription == null) {
      return CloudBackupWriteResult(sizeBytes: bytes.length, pending: true);
    }

    try {
      await completer.future.timeout(uploadTimeout);
      return CloudBackupWriteResult(sizeBytes: bytes.length);
    } on TimeoutException {
      return CloudBackupWriteResult(sizeBytes: bytes.length, pending: true);
    } finally {
      await subscription?.cancel();
    }
  }

  @override
  Future<void> deleteFile(
    CloudBackupFileInfo file, {
    bool silentAuth = false,
  }) {
    return _delete(containerId: containerId, relativePath: file.id);
  }

  @override
  Future<CloudBackupUploadState> uploadState(
    String name, {
    bool silentAuth = true,
  }) async {
    final files = await _gather(containerId: containerId);
    final relativePath = relativePathFor(name);
    for (final file in files) {
      if (file.relativePath != relativePath) {
        continue;
      }
      if (file.isUploaded && !file.isUploading) {
        return CloudBackupUploadState.complete;
      }
      return CloudBackupUploadState.pending;
    }
    return CloudBackupUploadState.missing;
  }

  Future<File> _tempFile(String name) async {
    final override = _tempBackupFileOverride;
    if (override != null) {
      return override();
    }
    final directoryOverride = _tempDirectoryOverride;
    final directory = directoryOverride != null
        ? await directoryOverride()
        : await getTemporaryDirectory();
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
