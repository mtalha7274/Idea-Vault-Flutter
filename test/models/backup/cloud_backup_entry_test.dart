import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/models/backup/cloud_backup_entry.dart';

void main() {
  group('CloudBackupEntry', () {
    test('builds and parses a snapshot file name', () {
      final name = CloudBackupEntry.buildFileName(
        formatVersion: 3,
        createdAt: DateTime.utc(2026, 11, 13, 10, 15, 30),
        deviceShortId: 'ab12cd34',
        ideaCount: 12,
        randomAdditionCount: 3,
        deviceName: 'Pixel 8',
      );

      expect(name, startsWith('idea_vault_backup_v3_20261113T101530Z_ab12cd34_i12_n3'));
      expect(name, endsWith('.json'));

      final entry = CloudBackupEntry.fromFile(
        fileId: 'file-1',
        fileName: name,
        modifiedAt: DateTime.utc(2026, 11, 13, 10, 16),
        sizeBytes: 2048,
      )!;

      expect(entry.isLegacy, isFalse);
      expect(entry.formatVersion, 3);
      expect(entry.createdAt, DateTime.utc(2026, 11, 13, 10, 15, 30));
      expect(entry.deviceShortId, 'ab12cd34');
      expect(entry.ideaCount, 12);
      expect(entry.randomAdditionCount, 3);
      expect(entry.deviceName, 'Pixel 8');
      expect(entry.isEmpty, isFalse);
    });

    test('recognises the legacy single backup file', () {
      final entry = CloudBackupEntry.fromFile(
        fileId: 'legacy',
        fileName: CloudBackupEntry.legacyFileName,
      )!;

      expect(entry.isLegacy, isTrue);
      expect(entry.isEmpty, isFalse);
      expect(entry.hasKnownCounts, isFalse);
    });

    test('ignores unrelated files', () {
      expect(
        CloudBackupEntry.fromFile(fileId: 'x', fileName: 'notes.json'),
        isNull,
      );
    });

    test('marks snapshots with no ideas and no notes as empty', () {
      final entry = CloudBackupEntry.fromFile(
        fileId: 'e',
        fileName: CloudBackupEntry.buildFileName(
          formatVersion: 3,
          createdAt: DateTime.utc(2026, 1, 1),
          deviceShortId: 'aaaa0000',
          ideaCount: 0,
          randomAdditionCount: 0,
        ),
      )!;

      expect(entry.isEmpty, isTrue);
      expect(entry.deviceName, isNull);
    });

    test('orders by cloud modified time, not by the device clock', () {
      final wrongClock = CloudBackupEntry.fromFile(
        fileId: 'a',
        fileName: CloudBackupEntry.buildFileName(
          formatVersion: 3,
          createdAt: DateTime.utc(2030, 1, 1),
          deviceShortId: 'aaaa0000',
          ideaCount: 1,
          randomAdditionCount: 0,
        ),
        modifiedAt: DateTime.utc(2026, 1, 1),
      )!;
      final newer = CloudBackupEntry.fromFile(
        fileId: 'b',
        fileName: CloudBackupEntry.buildFileName(
          formatVersion: 3,
          createdAt: DateTime.utc(2026, 2, 1),
          deviceShortId: 'bbbb0000',
          ideaCount: 1,
          randomAdditionCount: 0,
        ),
        modifiedAt: DateTime.utc(2026, 2, 1),
      )!;

      final sorted = CloudBackupEntry.sortNewestFirst([wrongClock, newer]);

      expect(sorted.first.fileId, 'b');
    });
  });
}
