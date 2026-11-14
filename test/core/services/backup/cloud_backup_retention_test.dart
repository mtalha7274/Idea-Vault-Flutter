import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_retention.dart';
import 'package:idea_vault/models/backup/cloud_backup_entry.dart';

CloudBackupEntry _entry(
  String device,
  int day, {
  int ideas = 1,
  int notes = 0,
  int size = 1000,
}) {
  final created = DateTime.utc(2026, 1, day);
  return CloudBackupEntry.fromFile(
    fileId: '$device-$day',
    fileName: CloudBackupEntry.buildFileName(
      formatVersion: 3,
      createdAt: created,
      deviceShortId: device,
      ideaCount: ideas,
      randomAdditionCount: notes,
    ),
    modifiedAt: created,
    sizeBytes: size,
  )!;
}

void main() {
  group('CloudBackupRetention', () {
    test('keeps the 7 newest snapshots for this device', () {
      final entries = [for (var day = 1; day <= 10; day++) _entry('aaaa0000', day)];

      final toDelete = CloudBackupRetention.entriesToDelete(
        entries: entries,
        deviceShortId: 'aaaa0000',
      );

      expect(toDelete.map((entry) => entry.fileId),
          unorderedEquals(['aaaa0000-1', 'aaaa0000-2', 'aaaa0000-3']));
    });

    test('never rotates another device or the legacy file', () {
      final entries = [
        for (var day = 1; day <= 10; day++) _entry('bbbb0000', day),
        CloudBackupEntry.fromFile(
          fileId: 'legacy',
          fileName: CloudBackupEntry.legacyFileName,
        )!,
        _entry('aaaa0000', 11),
      ];

      final toDelete = CloudBackupRetention.entriesToDelete(
        entries: entries,
        deviceShortId: 'aaaa0000',
      );

      expect(toDelete, isEmpty);
    });

    test('always keeps the newest non-empty snapshot', () {
      final entries = [
        _entry('aaaa0000', 1, ideas: 5),
        for (var day = 2; day <= 9; day++)
          _entry('aaaa0000', day, ideas: 0, notes: 0),
      ];

      final toDelete = CloudBackupRetention.entriesToDelete(
        entries: entries,
        deviceShortId: 'aaaa0000',
      );

      expect(toDelete.map((entry) => entry.fileId), ['aaaa0000-2']);
    });

    test('keeps only 3 when snapshots are larger than 5 MB', () {
      final entries = [
        for (var day = 1; day <= 6; day++)
          _entry('aaaa0000', day, size: 6 * 1024 * 1024),
      ];

      final toDelete = CloudBackupRetention.entriesToDelete(
        entries: entries,
        deviceShortId: 'aaaa0000',
      );

      expect(toDelete.map((entry) => entry.fileId),
          unorderedEquals(['aaaa0000-1', 'aaaa0000-2', 'aaaa0000-3']));
    });
  });
}
