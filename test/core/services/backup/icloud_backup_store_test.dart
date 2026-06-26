import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage/icloud_storage.dart';
import 'package:idea_vault/core/services/backup/icloud_backup_store.dart';

void main() {
  group('ICloudBackupStore', () {
    late Directory tempDirectory;
    late File backupFile;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('icloud_backup_');
      backupFile = File('${tempDirectory.path}/idea_vault_backup.json');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('waits for download progress to complete before reading backup',
        () async {
      final store = ICloudBackupStore(
        gather: ({required containerId}) async => [
          _icloudFile(sizeInBytes: 12),
        ],
        download: ({
          required containerId,
          required relativePath,
          required destinationFilePath,
          onProgress,
        }) async {
          final controller = StreamController<double>();
          onProgress?.call(controller.stream);
          unawaited(
            Future<void>(() async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await File(destinationFilePath).writeAsString('backup-json');
              controller.add(1);
              await controller.close();
            }),
          );
        },
        tempBackupFile: () async => backupFile,
      );

      final backup = await store.readBackup();

      expect(backup?.contents, 'backup-json');
      expect(backup?.sizeBytes, 11);
    });

    test('does not report empty iCloud metadata as restorable backup',
        () async {
      final store = ICloudBackupStore(
        gather: ({required containerId}) async => [
          _icloudFile(sizeInBytes: 0),
        ],
        tempBackupFile: () async => backupFile,
      );

      expect(await store.backupExists(), isFalse);
    });
  });
}

ICloudFile _icloudFile({required int sizeInBytes}) {
  return ICloudFile.fromMap({
    'relativePath': ICloudBackupStore.backupRelativePath,
    'sizeInBytes': sizeInBytes,
    'creationDate': 0.0,
    'contentChangeDate': 0.0,
    'isDownloading': false,
    'downloadStatus': 'NSMetadataUbiquitousItemDownloadingStatusCurrent',
    'isUploading': false,
    'isUploaded': true,
    'hasUnresolvedConflicts': false,
  });
}
