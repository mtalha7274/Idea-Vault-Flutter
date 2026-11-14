import 'dart:convert';
import 'dart:math';

import '../../../data/managers/local/local_storage.dart';

class CloudBackupUploadLock {
  CloudBackupUploadLock(
    this._storage, {
    required this.owner,
    Future<void> Function()? reloadStorage,
    DateTime Function()? clock,
    Random? random,
    this.staleAfter = defaultStaleAfter,
  })  : _reloadStorage = reloadStorage,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random();

  static const String storageKey = 'cloud_backup_upload_lock_v1';
  static const Duration defaultStaleAfter = Duration(minutes: 10);
  static const String foregroundOwner = 'foreground';
  static const String backgroundOwner = 'background';

  final LocalStorageManager _storage;
  final String owner;
  final Duration staleAfter;
  final Future<void> Function()? _reloadStorage;
  final DateTime Function() _clock;
  final Random _random;
  String? _heldToken;

  bool get isHeld => _heldToken != null;

  Future<bool> acquire() async {
    if (_heldToken != null) {
      return false;
    }
    await _reload();
    final current = _read();
    final now = _clock();
    if (current != null && now.difference(current.at).abs() < staleAfter) {
      return false;
    }
    final token =
        '$owner-${now.microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
    await _storage.setString(
      key: storageKey,
      value: jsonEncode({
        'token': token,
        'owner': owner,
        'at': now.toUtc().toIso8601String(),
      }),
    );
    await _reload();
    if (_read()?.token != token) {
      return false;
    }
    _heldToken = token;
    return true;
  }

  Future<void> release() async {
    final token = _heldToken;
    _heldToken = null;
    if (token == null) {
      return;
    }
    await _reload();
    if (_read()?.token == token) {
      await _storage.delete(key: storageKey);
    }
  }

  Future<void> _reload() async {
    final reload = _reloadStorage;
    if (reload == null) {
      return;
    }
    try {
      await reload();
    } catch (_) {}
  }

  _LockRecord? _read() {
    final raw = _storage.getString(key: storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      final token = json['token'];
      final at = DateTime.tryParse(json['at'] as String? ?? '');
      if (token is! String || at == null) {
        return null;
      }
      return _LockRecord(token: token, at: at);
    } catch (_) {
      return null;
    }
  }
}

class _LockRecord {
  const _LockRecord({required this.token, required this.at});

  final String token;
  final DateTime at;
}
