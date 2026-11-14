import 'dart:convert';
import 'dart:math';

import '../../../models/backup/backup_device_identity.dart';
import '../../managers/local/local_storage.dart';

class BackupDeviceIdentityRepo {
  BackupDeviceIdentityRepo(this._localStorage, {Random? random})
      : _random = random ?? Random.secure();

  static const String storageKey = 'backup_device_identity_v1';

  final LocalStorageManager _localStorage;
  final Random _random;

  BackupDeviceIdentity? read() {
    final raw = _localStorage.getString(key: storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      final id = json['id'];
      if (id is! String || id.isEmpty) {
        return null;
      }
      final name = json['name'];
      return BackupDeviceIdentity(
        id: id,
        name: name is String ? name : '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<BackupDeviceIdentity> ensure({required String deviceName}) async {
    final existing = read();
    final trimmedName = deviceName.trim();
    if (existing != null) {
      if (trimmedName.isNotEmpty && existing.name != trimmedName) {
        final updated = BackupDeviceIdentity(id: existing.id, name: trimmedName);
        await _write(updated);
        return updated;
      }
      return existing;
    }
    final created = BackupDeviceIdentity(id: _newId(), name: trimmedName);
    await _write(created);
    return created;
  }

  Future<void> _write(BackupDeviceIdentity identity) {
    return _localStorage.setString(
      key: storageKey,
      value: jsonEncode({'id': identity.id, 'name': identity.name}),
    );
  }

  String _newId() {
    final buffer = StringBuffer();
    for (var index = 0; index < 16; index++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
