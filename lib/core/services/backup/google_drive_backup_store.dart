import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../../models/backup/cloud_backup_account.dart';
import 'cloud_backup_store.dart';
import 'google_drive_http_client.dart';

class GoogleDriveBackupStore implements CloudBackupStore {
  GoogleDriveBackupStore({
    GoogleSignIn? googleSignIn,
    String? serverClientId,
  })  : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
        _serverClientId = serverClientId;

  final String? _serverClientId;

  static const String backupFileName = 'idea_vault_backup.json';
  static const List<String> scopes = [
    drive.DriveApi.driveAppdataScope,
  ];

  final GoogleSignIn _googleSignIn;
  bool _initialized = false;
  GoogleSignInAccount? _account;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final String? webClientId = _resolveServerClientId();
    await _googleSignIn.initialize(serverClientId: webClientId);
    _initialized = true;
  }

  String? _resolveServerClientId() {
    final String? fromCtor = _serverClientId?.trim();
    if (fromCtor != null && fromCtor.isNotEmpty) {
      return fromCtor;
    }
    final String? fromEnv =
        dotenv.env['GOOGLE_SIGN_IN_SERVER_CLIENT_ID']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return null;
  }

  @override
  Future<CloudBackupAccount?> connect(
      {required bool forceAccountPicker}) async {
    await initialize();
    GoogleSignInAccount? account;

    if (!forceAccountPicker) {
      account = await _googleSignIn.attemptLightweightAuthentication();
    }
    account ??= await _googleSignIn.authenticate(scopeHint: scopes);

    await account.authorizationClient.authorizeScopes(scopes);
    _account = account;
    return CloudBackupAccount(email: account.email, provider: 'google_drive');
  }

  @override
  Future<void> disconnect() async {
    await initialize();
    _account = null;
    await _googleSignIn.disconnect();
  }

  @override
  Future<bool> backupExists() async {
    final api = await _driveApi(promptIfNecessary: false);
    if (api == null) {
      return false;
    }
    final file = await _findFile(api, backupFileName);
    return file?.id != null;
  }

  @override
  Future<CloudBackupFile?> readBackup() async {
    return _readFile(backupFileName, promptIfNecessary: true);
  }

  @override
  Future<int> writeBackup(String contents, {bool silentAuth = false}) async {
    return _writeFile(
      backupFileName,
      contents,
      promptIfNecessary: !silentAuth,
    );
  }

  Future<CloudBackupFile?> _readFile(
    String fileName, {
    required bool promptIfNecessary,
  }) async {
    final api = await _driveApi(promptIfNecessary: promptIfNecessary);
    if (api == null) {
      return null;
    }

    final file = await _findFile(api, fileName);
    final fileId = file?.id;
    if (fileId == null) {
      return null;
    }

    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = await media.stream.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    return CloudBackupFile(
      contents: utf8.decode(bytes),
      sizeBytes: bytes.length,
    );
  }

  Future<int> _writeFile(
    String fileName,
    String contents, {
    required bool promptIfNecessary,
  }) async {
    final api = await _driveApi(promptIfNecessary: promptIfNecessary);
    if (api == null) {
      throw StateError('Google Drive is not connected.');
    }

    final bytes = utf8.encode(contents);
    final existingFile = await _findFile(api, fileName);
    final media = drive.Media(Stream.value(bytes), bytes.length);
    final metadata = drive.File()
      ..name = fileName
      ..parents = ['appDataFolder'];

    if (existingFile?.id == null) {
      await api.files.create(metadata, uploadMedia: media);
    } else {
      await api.files.update(
        drive.File()..name = fileName,
        existingFile!.id!,
        uploadMedia: media,
      );
    }

    return bytes.length;
  }

  Future<drive.DriveApi?> _driveApi({required bool promptIfNecessary}) async {
    await initialize();

    // Drive access only needs an *authorization* token, which Play Services
    // hands back from its cache without any UI. Re-authenticating here instead
    // (attemptLightweightAuthentication) routes through Credential Manager,
    // which pops the "Signing you in" bottom sheet on Android every time the
    // app cold starts. Fall back to the account-less authorization client when
    // no account has been resolved in this session, e.g. after a cold start or
    // in the background isolate, where there is no activity to attach UI to.
    final authorizationClient =
        _account?.authorizationClient ?? _googleSignIn.authorizationClient;

    // With promptIfNecessary false this never shows UI: it returns null when
    // the scopes are not already authorized.
    final headers = await authorizationClient.authorizationHeaders(
      scopes,
      promptIfNecessary: promptIfNecessary,
    );
    if (headers == null) {
      return null;
    }

    return drive.DriveApi(GoogleDriveHttpClient(headers));
  }

  Future<drive.File?> _findFile(drive.DriveApi api, String fileName) async {
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$fileName' and trashed = false",
      $fields: 'files(id, name, size, modifiedTime)',
      pageSize: 1,
    );
    final files = result.files;
    if (files == null || files.isEmpty) {
      return null;
    }
    return files.first;
  }
}
