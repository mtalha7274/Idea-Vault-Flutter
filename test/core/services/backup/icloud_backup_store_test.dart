import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage/icloud_storage.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_store.dart';
import 'package:idea_vault/core/services/backup/icloud_backup_store.dart';
import 'package:idea_vault/models/backup/cloud_backup_entry.dart';

void main() {
  group('ICloudBackupStore', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('icloud_backup_');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final snapshotName = CloudBackupEntry.buildFileName(
      formatVersion: 3,
      createdAt: DateTime.utc(2026, 11, 1),
      deviceShortId: 'abcd1234',
      ideaCount: 2,
      randomAdditionCount: 1,
    );

    test('waits for download progress to complete before reading backup',
        () async {
      final store = ICloudBackupStore(
        gather: ({required containerId}) async => [
          _icloudFile(
            relativePath: ICloudBackupStore.backupRelativePath,
            sizeInBytes: 12,
          ),
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
        tempDirectory: () async => tempDirectory,
      );

      final files = await store.listFiles();
      final backup = await store.readFile(files.single);

      expect(backup.contents, 'backup-json');
      expect(backup.sizeBytes, 11);
    });

    test('lists legacy and snapshot files but ignores uploading and empty ones',
        () async {
      final store = ICloudBackupStore(
        gather: ({required containerId}) async => [
          _icloudFile(
            relativePath: ICloudBackupStore.backupRelativePath,
            sizeInBytes: 0,
          ),
          _icloudFile(
            relativePath: ICloudBackupStore.relativePathFor(snapshotName),
            sizeInBytes: 40,
          ),
          _icloudFile(
            relativePath: ICloudBackupStore.relativePathFor(
              snapshotName.replaceFirst('i2', 'i3'),
            ),
            sizeInBytes: 40,
            isUploading: true,
          ),
          _icloudFile(relativePath: 'Backups/other.json', sizeInBytes: 40),
        ],
        tempDirectory: () async => tempDirectory,
      );

      final files = await store.listFiles();

      expect(files.map((file) => file.name), [snapshotName]);
    });

    test('waits for the upload progress stream before reporting success',
        () async {
      var progressClosed = false;
      final store = ICloudBackupStore(
        gather: ({required containerId}) async => const [],
        upload: ({
          required containerId,
          required filePath,
          required destinationRelativePath,
          onProgress,
        }) async {
          final controller = StreamController<double>();
          onProgress?.call(controller.stream);
          unawaited(
            Future<void>(() async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              controller.add(100);
              progressClosed = true;
              await controller.close();
            }),
          );
        },
        tempDirectory: () async => tempDirectory,
      );

      final result = await store.writeFile(snapshotName, '{}');

      expect(progressClosed, isTrue);
      expect(result.pending, isFalse);
      expect(result.sizeBytes, 2);
    });

    test('reports a pending upload when the progress stream times out',
        () async {
      final controller = StreamController<double>();
      addTearDown(controller.close);
      final store = ICloudBackupStore(
        gather: ({required containerId}) async => const [],
        upload: ({
          required containerId,
          required filePath,
          required destinationRelativePath,
          onProgress,
        }) async {
          onProgress?.call(controller.stream);
        },
        tempDirectory: () async => tempDirectory,
        uploadTimeout: const Duration(milliseconds: 30),
      );

      final result = await store.writeFile(snapshotName, '{}');

      expect(result.pending, isTrue);
    });

    test('upload state reflects iCloud metadata', () async {
      var uploaded = false;
      final store = ICloudBackupStore(
        gather: ({required containerId}) async => [
          _icloudFile(
            relativePath: ICloudBackupStore.relativePathFor(snapshotName),
            sizeInBytes: 40,
            isUploading: !uploaded,
            isUploaded: uploaded,
          ),
        ],
        tempDirectory: () async => tempDirectory,
      );

      expect(
        await store.uploadState(snapshotName),
        CloudBackupUploadState.pending,
      );
      uploaded = true;
      expect(
        await store.uploadState(snapshotName),
        CloudBackupUploadState.complete,
      );
      expect(
        await store.uploadState('missing.json'),
        CloudBackupUploadState.missing,
      );
    });
  });
}

ICloudFile _icloudFile({
  required String relativePath,
  required int sizeInBytes,
  bool isUploading = false,
  bool isUploaded = true,
}) {
  return ICloudFile.fromMap({
    'relativePath': relativePath,
    'sizeInBytes': sizeInBytes,
    'creationDate': 0.0,
    'contentChangeDate': 0.0,
    'isDownloading': false,
    'downloadStatus': 'NSMetadataUbiquitousItemDownloadingStatusCurrent',
    'isUploading': isUploading,
    'isUploaded': isUploaded,
    'hasUnresolvedConflicts': false,
  });
}
