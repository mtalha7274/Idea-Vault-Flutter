import 'dart:convert';

import '../../managers/local/local_storage.dart';
import '../../../models/backup/cloud_backup_state.dart';

class CloudBackupSettingsRepo {
  const CloudBackupSettingsRepo(this._localStorage);

  static const String _key = 'cloud_backup_settings_v1';
  static const String _statusKey = 'cloud_backup_status_v1';
  static const String plaintextCleanupPendingKey =
      'vault_plaintext_cleanup_pending_v1';

  final LocalStorageManager _localStorage;

  LocalStorageManager get storage => _localStorage;

  Map<String, dynamic>? _readSettingsJson() {
    final raw = _localStorage.getString(key: _key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  CloudBackupStatus getStatus() {
    final raw = _localStorage.getString(key: _statusKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          return CloudBackupStatus.fromJson(json);
        }
      } catch (_) {}
    }
    final legacy = _readSettingsJson();
    if (legacy == null) {
      return CloudBackupStatus.empty;
    }
    try {
      return CloudBackupStatus(
        lastBackupAt:
            DateTime.tryParse(legacy['lastBackupAt'] as String? ?? ''),
        lastBackupSizeBytes: legacy['lastBackupSizeBytes'] as int?,
      );
    } catch (_) {
      return CloudBackupStatus.empty;
    }
  }

  CloudBackupState getState() {
    final json = _readSettingsJson();
    final status = getStatus();
    if (json == null) {
      return const CloudBackupState.initial().copyWith(status: status);
    }

    try {
      final enabled = json['enabled'] as bool? ?? false;
      final storedResolved = json['remoteStateResolved'] as bool?;
      return CloudBackupState(
        enabled: enabled,
        autoBackupEnabled: json['autoBackupEnabled'] as bool? ?? true,
        email: json['email'] as String?,
        isBusy: false,
        restorePromptAvailable:
            json['restorePromptAvailable'] as bool? ?? false,
        freshInstallRestoreCheckCompleted:
            json['freshInstallRestoreCheckCompleted'] as bool? ?? false,
        remoteStateResolved:
            storedResolved ?? (enabled && status.lastBackupAt != null),
        restoreCardCompleted: json['restoreCardCompleted'] as bool? ?? false,
        undoRestoreCopyId: json['undoRestoreCopyId'] as String?,
        undoRestoreAvailableUntil: DateTime.tryParse(
            json['undoRestoreAvailableUntil'] as String? ?? ''),
        status: status,
      );
    } catch (_) {
      return const CloudBackupState.initial().copyWith(status: status);
    }
  }

  Future<void> saveState(CloudBackupState state) async {
    await saveSettings(state);
    await saveStatus(state.backupStatus);
  }

  Future<void> saveSettings(CloudBackupState state) {
    return _localStorage.setString(
      key: _key,
      value: jsonEncode({
        'enabled': state.enabled,
        'autoBackupEnabled': state.autoBackupEnabled,
        'email': state.email,
        'remoteStateResolved': state.remoteStateResolved,
        'restorePromptAvailable': state.restorePromptAvailable,
        'freshInstallRestoreCheckCompleted':
            state.freshInstallRestoreCheckCompleted,
        'restoreCardCompleted': state.restoreCardCompleted,
        'undoRestoreCopyId': state.undoRestoreCopyId,
        'undoRestoreAvailableUntil':
            state.undoRestoreAvailableUntil?.toIso8601String(),
      }),
    );
  }

  Future<void> saveStatus(CloudBackupStatus status) {
    return _localStorage.setString(
      key: _statusKey,
      value: jsonEncode(status.toJson()),
    );
  }

  bool get plaintextCleanupPending =>
      _localStorage.getString(key: plaintextCleanupPendingKey) == 'true';

  Future<void> setPlaintextCleanupPending(bool pending) async {
    if (pending) {
      await _localStorage.setString(
        key: plaintextCleanupPendingKey,
        value: 'true',
      );
    } else {
      await _localStorage.delete(key: plaintextCleanupPendingKey);
    }
  }

  Future<void> clearStatus() {
    return saveStatus(CloudBackupStatus.empty);
  }

  Future<void> clear() async {
    await _localStorage.delete(key: _key);
    await _localStorage.delete(key: _statusKey);
  }
}
