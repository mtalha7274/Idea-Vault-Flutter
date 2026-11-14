import 'dart:convert';

import 'package:idea_vault/core/services/backup/cloud_backup_store.dart';
import 'package:idea_vault/models/backup/cloud_backup_account.dart';
import 'package:idea_vault/models/backup/cloud_backup_entry.dart';
import 'package:idea_vault/models/backup/cloud_backup_error.dart';

class FakeCloudFile {
  FakeCloudFile({
    required this.contents,
    required this.modifiedAt,
    this.sizeOverride,
  });

  String contents;
  DateTime modifiedAt;
  int? sizeOverride;

  int get sizeBytes => sizeOverride ?? utf8.encode(contents).length;
}

class FakeCloudBackupStore implements CloudBackupStore {
  FakeCloudBackupStore({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, FakeCloudFile> files = {};
  int connectCount = 0;
  int signOutCount = 0;
  int listCount = 0;
  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;
  bool? lastWriteSilentAuth;
  final List<bool> listSilentAuthCalls = [];
  Object? connectError;
  bool connectReturnsNull = false;
  Object? listError;
  Object? readError;
  Object? writeError;
  Object? deleteError;
  bool writePending = false;
  CloudBackupUploadState uploadStateResult = CloudBackupUploadState.complete;
  String accountEmail = 'writer@example.com';
  bool requireAuthWhenSilent = false;
  Future<void>? listGate;
  int _tick = 0;

  void putFile(
    String name,
    String contents, {
    DateTime? modifiedAt,
    int? sizeOverride,
  }) {
    files[name] = FakeCloudFile(
      contents: contents,
      modifiedAt: modifiedAt ?? _nextTime(),
      sizeOverride: sizeOverride,
    );
  }

  DateTime _nextTime() {
    _tick += 1;
    return _clock().toUtc().add(Duration(milliseconds: _tick));
  }

  List<String> get fileNames => files.keys.toList();

  @override
  Future<CloudBackupAccount?> connect(
      {required bool forceAccountPicker}) async {
    connectCount += 1;
    final error = connectError;
    if (error != null) {
      throw error;
    }
    if (connectReturnsNull) {
      return null;
    }
    return CloudBackupAccount(email: accountEmail, provider: 'fake');
  }

  @override
  Future<void> signOut() async {
    signOutCount += 1;
  }

  void _checkSilentAuth(bool silentAuth) {
    if (silentAuth && requireAuthWhenSilent) {
      throw const CloudBackupException(CloudBackupErrorType.signInRequired);
    }
  }

  @override
  Future<List<CloudBackupFileInfo>> listFiles({bool silentAuth = false}) async {
    listCount += 1;
    listSilentAuthCalls.add(silentAuth);
    final gate = listGate;
    if (gate != null) {
      await gate;
    }
    final error = listError;
    if (error != null) {
      throw error;
    }
    _checkSilentAuth(silentAuth);
    return [
      for (final entry in files.entries)
        if (CloudBackupEntry.isBackupFileName(entry.key))
          CloudBackupFileInfo(
            id: 'id-${entry.key}',
            name: entry.key,
            modifiedAt: entry.value.modifiedAt,
            sizeBytes: entry.value.sizeBytes,
          ),
    ];
  }

  @override
  Future<CloudBackupFile> readFile(
    CloudBackupFileInfo file, {
    bool silentAuth = false,
  }) async {
    readCount += 1;
    final error = readError;
    if (error != null) {
      throw error;
    }
    _checkSilentAuth(silentAuth);
    final stored = files[file.name];
    if (stored == null) {
      throw const CloudBackupException(CloudBackupErrorType.noBackupFound);
    }
    return CloudBackupFile(
      contents: stored.contents,
      sizeBytes: stored.sizeBytes,
    );
  }

  @override
  Future<CloudBackupWriteResult> writeFile(
    String name,
    String contents, {
    bool silentAuth = false,
  }) async {
    writeCount += 1;
    lastWriteSilentAuth = silentAuth;
    final error = writeError;
    if (error != null) {
      throw error;
    }
    _checkSilentAuth(silentAuth);
    putFile(name, contents);
    return CloudBackupWriteResult(
      sizeBytes: utf8.encode(contents).length,
      pending: writePending,
    );
  }

  @override
  Future<void> deleteFile(
    CloudBackupFileInfo file, {
    bool silentAuth = false,
  }) async {
    deleteCount += 1;
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    files.remove(file.name);
  }

  @override
  Future<CloudBackupUploadState> uploadState(
    String name, {
    bool silentAuth = true,
  }) async {
    if (!files.containsKey(name)) {
      return CloudBackupUploadState.missing;
    }
    return uploadStateResult;
  }
}
