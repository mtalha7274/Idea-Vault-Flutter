import 'package:workmanager/workmanager.dart';

class CloudBackupScheduler {
  static const String taskName = 'idea_vault_auto_cloud_backup';
  static const String uniqueName = 'idea_vault_auto_cloud_backup_periodic';
  static const Duration backupInterval = Duration(hours: 24);
  static const Duration initialDelay = Duration(hours: 1);

  const CloudBackupScheduler();

  static bool isCloudBackupTask(String task) {
    return task == taskName ||
        task == uniqueName ||
        task == Workmanager.iOSBackgroundTask;
  }

  Future<void> scheduleDailyBackup() {
    return Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: backupInterval,
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  Future<void> cancelDailyBackup() {
    return Workmanager().cancelByUniqueName(uniqueName);
  }
}
