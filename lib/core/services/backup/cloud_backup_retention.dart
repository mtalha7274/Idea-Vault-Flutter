import '../../../models/backup/cloud_backup_entry.dart';

class CloudBackupRetention {
  const CloudBackupRetention._();

  static const int defaultKeep = 7;
  static const int largeKeep = 3;
  static const int largeSnapshotBytes = 5 * 1024 * 1024;

  static List<CloudBackupEntry> entriesToDelete({
    required List<CloudBackupEntry> entries,
    required String deviceShortId,
  }) {
    final own = CloudBackupEntry.sortNewestFirst(
      entries.where(
        (entry) => !entry.isLegacy && entry.deviceShortId == deviceShortId,
      ),
    );
    if (own.isEmpty) {
      return const [];
    }
    final newestSize = own.first.sizeBytes ?? 0;
    final keepCount =
        newestSize > largeSnapshotBytes ? largeKeep : defaultKeep;
    final keep = <CloudBackupEntry>{...own.take(keepCount)};
    for (final entry in own) {
      if (!entry.isEmpty) {
        keep.add(entry);
        break;
      }
    }
    return own.where((entry) => !keep.contains(entry)).toList();
  }
}
