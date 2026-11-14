import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../../models/backup/cloud_backup_account.dart';
import '../../../models/backup/cloud_backup_entry.dart';
import '../../../models/backup/cloud_backup_error.dart';
import 'cloud_backup_store.dart';
import 'google_drive_http_client.dart';

class GoogleDriveBackupStore implements CloudBackupStore {
  GoogleDriveBackupStore({
    GoogleSignIn? googleSignIn,
    String? serverClientId,
  })  : _googleSignIn = googleSignIn,
        _serverClientId = serverClientId;

  final String? _serverClientId;

  static const String backupFileName = CloudBackupEntry.legacyFileName;
  static const String appDataSpace = 'appDataFolder';
  static const int pageSize = 100;
  static const List<String> scopes = [
    drive.DriveApi.driveAppdataScope,
  ];

  final GoogleSignIn? _googleSignIn;
  bool _initialized = false;
  GoogleSignInAccount? _account;

  GoogleSignIn get _signIn => _googleSignIn ?? GoogleSignIn.instance;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final String? webClientId = _resolveServerClientId();
    await _signIn.initialize(serverClientId: webClientId);
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
      account = await _signIn.attemptLightweightAuthentication();
    }
    account ??= await _signIn.authenticate(scopeHint: scopes);

    await account.authorizationClient.authorizeScopes(scopes);
    _account = account;
    return CloudBackupAccount(email: account.email, provider: 'google_drive');
  }

  @override
  Future<void> signOut() async {
    await initialize();
    _account = null;
    await _signIn.signOut();
  }

  @override
  Future<List<CloudBackupFileInfo>> listFiles({bool silentAuth = false}) async {
    final api = await _requireApi(silentAuth: silentAuth);
    final files = <CloudBackupFileInfo>[];
    String? pageToken;
    do {
      final result = await api.files.list(
        spaces: appDataSpace,
        q: "name contains 'idea_vault_backup' and trashed = false",
        orderBy: 'modifiedTime desc',
        $fields: 'nextPageToken, files(id, name, size, modifiedTime)',
        pageSize: pageSize,
        pageToken: pageToken,
      );
      for (final file in result.files ?? const <drive.File>[]) {
        final id = file.id;
        final name = file.name;
        if (id == null ||
            name == null ||
            !CloudBackupEntry.isBackupFileName(name)) {
          continue;
        }
        files.add(
          CloudBackupFileInfo(
            id: id,
            name: name,
            modifiedAt: file.modifiedTime?.toUtc(),
            sizeBytes: int.tryParse(file.size ?? ''),
          ),
        );
      }
      pageToken = result.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
    return files;
  }

  @override
  Future<CloudBackupFile> readFile(
    CloudBackupFileInfo file, {
    bool silentAuth = false,
  }) async {
    final api = await _requireApi(silentAuth: silentAuth);
    final media = await api.files.get(
      file.id,
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

  @override
  Future<CloudBackupWriteResult> writeFile(
    String name,
    String contents, {
    bool silentAuth = false,
  }) async {
    final api = await _requireApi(silentAuth: silentAuth);
    final bytes = utf8.encode(contents);
    final media = drive.Media(Stream.value(bytes), bytes.length);
    final metadata = drive.File()
      ..name = name
      ..parents = [appDataSpace];
    await api.files.create(
      metadata,
      uploadMedia: media,
      $fields: 'id, name, size, modifiedTime',
    );
    return CloudBackupWriteResult(sizeBytes: bytes.length);
  }

  @override
  Future<void> deleteFile(
    CloudBackupFileInfo file, {
    bool silentAuth = false,
  }) async {
    final api = await _requireApi(silentAuth: silentAuth);
    await api.files.delete(file.id);
  }

  @override
  Future<CloudBackupUploadState> uploadState(
    String name, {
    bool silentAuth = true,
  }) async {
    return CloudBackupUploadState.complete;
  }

  Future<drive.DriveApi> _requireApi({required bool silentAuth}) async {
    final api = await _driveApi(promptIfNecessary: !silentAuth);
    if (api == null) {
      throw const CloudBackupException(
        CloudBackupErrorType.signInRequired,
        'Google Drive access is not authorized',
      );
    }
    return api;
  }

  Future<drive.DriveApi?> _driveApi({required bool promptIfNecessary}) async {
    await initialize();

    final authorizationClient =
        _account?.authorizationClient ?? _signIn.authorizationClient;

    final headers = await authorizationClient.authorizationHeaders(
      scopes,
      promptIfNecessary: promptIfNecessary,
    );
    if (headers == null) {
      return null;
    }

    return drive.DriveApi(GoogleDriveHttpClient(headers));
  }
}
