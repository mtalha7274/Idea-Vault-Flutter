import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_scheduler.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  group('CloudBackupScheduler', () {
    test('isCloudBackupTask accepts Android task name', () {
      expect(
        CloudBackupScheduler.isCloudBackupTask(
          CloudBackupScheduler.taskName,
        ),
        isTrue,
      );
    });

    test('isCloudBackupTask accepts iOS periodic unique name', () {
      expect(
        CloudBackupScheduler.isCloudBackupTask(
          CloudBackupScheduler.uniqueName,
        ),
        isTrue,
      );
    });

    test('isCloudBackupTask accepts iOS background fetch token', () {
      expect(
        CloudBackupScheduler.isCloudBackupTask(Workmanager.iOSBackgroundTask),
        isTrue,
      );
    });

    test('isCloudBackupTask rejects unrelated tasks', () {
      expect(
        CloudBackupScheduler.isCloudBackupTask('some_other_task'),
        isFalse,
      );
    });
  });
}
