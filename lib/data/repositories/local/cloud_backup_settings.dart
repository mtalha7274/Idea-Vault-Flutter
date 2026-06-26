import 'dart:convert';

import '../../managers/local/local_storage.dart';
import '../../../models/backup/cloud_backup_state.dart';

class CloudBackupSettingsRepo {
  const CloudBackupSettingsRepo(this._localStorage);

  static const String _key = 'cloud_backup_settings_v1';

  final LocalStorageManager _localStorage;

  CloudBackupState getState() {
    final raw = _localStorage.getString(key: _key);
    if (raw == null || raw.isEmpty) {
      return const CloudBackupState.initial();
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CloudBackupState(
        enabled: json['enabled'] as bool? ?? false,
        autoBackupEnabled: json['autoBackupEnabled'] as bool? ?? true,
        email: json['email'] as String?,
        lastBackupAt: DateTime.tryParse(json['lastBackupAt'] as String? ?? ''),
        lastBackupSizeBytes: json['lastBackupSizeBytes'] as int?,
        isBusy: false,
        restorePromptAvailable:
            json['restorePromptAvailable'] as bool? ?? false,
        freshInstallRestoreCheckCompleted:
            json['freshInstallRestoreCheckCompleted'] as bool? ?? false,
      );
    } catch (_) {
      return const CloudBackupState.initial();
    }
  }

  Future<void> saveState(CloudBackupState state) {
    return _localStorage.setString(
      key: _key,
      value: jsonEncode({
        'enabled': state.enabled,
        'autoBackupEnabled': state.autoBackupEnabled,
        'email': state.email,
        'lastBackupAt': state.lastBackupAt?.toIso8601String(),
        'lastBackupSizeBytes': state.lastBackupSizeBytes,
        'restorePromptAvailable': state.restorePromptAvailable,
        'freshInstallRestoreCheckCompleted':
            state.freshInstallRestoreCheckCompleted,
      }),
    );
  }

  Future<void> clear() {
    return _localStorage.delete(key: _key);
  }
}
