import 'dart:io';

import '../../../models/backup/cloud_backup_account.dart';
import '../../../models/backup/cloud_backup_entry.dart';
import '../../../models/backup/cloud_backup_error.dart';
import '../../../models/backup/cloud_backup_snapshot.dart';
import 'cloud_backup_retention.dart';
import 'cloud_backup_store.dart';
import 'google_drive_backup_store.dart';
import 'icloud_backup_store.dart';

class CloudBackupUploadResult {
  const CloudBackupUploadResult({
    required this.fileName,
    required this.sizeBytes,
    required this.pending,
  });

  final String fileName;
  final int sizeBytes;
  final bool pending;
}

class CloudBackupService {
  CloudBackupService({
    CloudBackupStore? androidStore,
    CloudBackupStore? iosStore,
    bool? useICloud,
  })  : _androidStore = androidStore,
        _iosStore = iosStore,
        _useICloud = useICloud;

  final CloudBackupStore? _androidStore;
  final CloudBackupStore? _iosStore;
  final bool? _useICloud;
  CloudBackupStore? _resolvedAndroidStore;
  CloudBackupStore? _resolvedIosStore;

  bool get usesICloud => _useICloud ?? Platform.isIOS;

  CloudBackupStore get store {
    if (usesICloud) {
      return _resolvedIosStore ??= _iosStore ?? ICloudBackupStore();
    }
    return _resolvedAndroidStore ??= _androidStore ?? GoogleDriveBackupStore();
  }

  Future<CloudBackupAccount?> connect({bool forceAccountPicker = false}) {
    return store.connect(forceAccountPicker: forceAccountPicker);
  }

  Future<void> signOut() {
    return store.signOut();
  }

  Future<void> disconnect() => signOut();

  Future<List<CloudBackupEntry>> listBackups({bool silentAuth = false}) async {
    final files = await store.listFiles(silentAuth: silentAuth);
    final entries = <CloudBackupEntry>[];
    for (final file in files) {
      final entry = CloudBackupEntry.fromFile(
        fileId: file.id,
        fileName: file.name,
        modifiedAt: file.modifiedAt,
        sizeBytes: file.sizeBytes,
      );
      if (entry != null) {
        entries.add(entry);
      }
    }
    return CloudBackupEntry.sortNewestFirst(entries);
  }

  Future<bool> backupExists() async {
    try {
      final entries = await listBackups(silentAuth: true);
      return entries.isNotEmpty;
    } on CloudBackupException catch (error) {
      if (error.type == CloudBackupErrorType.signInRequired) {
        return false;
      }
      rethrow;
    }
  }

  Future<CloudBackupSnapshot> downloadSnapshot(
    CloudBackupEntry entry, {
    bool silentAuth = false,
  }) async {
    final file = await store.readFile(
      CloudBackupFileInfo(
        id: entry.fileId,
        name: entry.fileName,
        modifiedAt: entry.modifiedAt,
        sizeBytes: entry.sizeBytes,
      ),
      silentAuth: silentAuth,
    );
    return CloudBackupSnapshot.decodeAndValidate(file.contents);
  }

  Future<String> downloadRaw(
    CloudBackupEntry entry, {
    bool silentAuth = false,
  }) async {
    final file = await store.readFile(
      CloudBackupFileInfo(
        id: entry.fileId,
        name: entry.fileName,
        modifiedAt: entry.modifiedAt,
        sizeBytes: entry.sizeBytes,
      ),
      silentAuth: silentAuth,
    );
    return file.contents;
  }

  Future<void> deleteEntry(CloudBackupEntry entry, {bool silentAuth = false}) {
    return _delete(entry, silentAuth: silentAuth);
  }

  Future<CloudBackupUploadResult> uploadSnapshot(
    CloudBackupSnapshot snapshot, {
    required String deviceShortId,
    bool silentAuth = false,
  }) async {
    final fileName = CloudBackupEntry.buildFileName(
      formatVersion: snapshot.version,
      createdAt: snapshot.createdAt,
      deviceShortId: deviceShortId,
      ideaCount: snapshot.ideaCount,
      randomAdditionCount: snapshot.randomAdditionCount,
      deviceName: snapshot.deviceName,
    );
    final result = await store.writeFile(
      fileName,
      snapshot.encode(),
      silentAuth: silentAuth,
    );
    return CloudBackupUploadResult(
      fileName: fileName,
      sizeBytes: result.sizeBytes,
      pending: result.pending,
    );
  }

  Future<CloudBackupUploadState> uploadState(String fileName) {
    return store.uploadState(fileName, silentAuth: true);
  }

  Future<int> rotateBackups({
    required String deviceShortId,
    bool silentAuth = true,
  }) async {
    final List<CloudBackupEntry> entries;
    try {
      entries = await listBackups(silentAuth: silentAuth);
    } catch (_) {
      return 0;
    }
    final toDelete = CloudBackupRetention.entriesToDelete(
      entries: entries,
      deviceShortId: deviceShortId,
    );
    var deleted = 0;
    for (final entry in toDelete) {
      try {
        await _delete(entry, silentAuth: silentAuth);
        deleted += 1;
      } catch (_) {}
    }
    return deleted;
  }

  Future<int> deleteAllBackups({bool silentAuth = false}) async {
    final entries = await listBackups(silentAuth: silentAuth);
    var deleted = 0;
    Object? firstError;
    for (final entry in entries) {
      try {
        await _delete(entry, silentAuth: silentAuth);
        deleted += 1;
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) {
      throw firstError;
    }
    return deleted;
  }

  Future<CloudBackupSnapshot?> restoreSnapshot() async {
    final entries = await listBackups();
    if (entries.isEmpty) {
      return null;
    }
    return downloadSnapshot(entries.first);
  }

  Future<void> _delete(CloudBackupEntry entry, {required bool silentAuth}) {
    return store.deleteFile(
      CloudBackupFileInfo(
        id: entry.fileId,
        name: entry.fileName,
        modifiedAt: entry.modifiedAt,
        sizeBytes: entry.sizeBytes,
      ),
      silentAuth: silentAuth,
    );
  }
}
