import 'dart:convert';

import 'cloud_backup_service.dart';

class VaultPlaintextCleanupResult {
  const VaultPlaintextCleanupResult({
    required this.checked,
    required this.deleted,
    required this.failures,
  });

  final int checked;
  final int deleted;
  final int failures;

  bool get isComplete => failures == 0;
}

class VaultPlaintextCleanup {
  const VaultPlaintextCleanup._();

  static bool containsPlaintextLockedNotes(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return false;
    }
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    final ideas = decoded['ideas'];
    if (ideas is! List<dynamic>) {
      return false;
    }
    for (final idea in ideas) {
      if (idea is! Map<String, dynamic>) {
        continue;
      }
      if (idea['isLocked'] == true && idea['encryptedPayload'] == null) {
        return true;
      }
    }
    return false;
  }

  static Future<VaultPlaintextCleanupResult> run({
    required CloudBackupService service,
    Set<String> keepFileNames = const {},
    bool silentAuth = true,
  }) async {
    final entries = await service.listBackups(silentAuth: silentAuth);
    var checked = 0;
    var deleted = 0;
    var failures = 0;
    for (final entry in entries) {
      if (keepFileNames.contains(entry.fileName)) {
        continue;
      }
      checked += 1;
      final String raw;
      try {
        raw = await service.downloadRaw(entry, silentAuth: silentAuth);
      } catch (_) {
        failures += 1;
        continue;
      }
      if (!containsPlaintextLockedNotes(raw)) {
        continue;
      }
      try {
        await service.deleteEntry(entry, silentAuth: silentAuth);
        deleted += 1;
      } catch (_) {
        failures += 1;
      }
    }
    return VaultPlaintextCleanupResult(
      checked: checked,
      deleted: deleted,
      failures: failures,
    );
  }
}
