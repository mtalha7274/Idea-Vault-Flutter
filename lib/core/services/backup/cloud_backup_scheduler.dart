import 'package:workmanager/workmanager.dart';

class CloudBackupScheduler {
  static const String taskName = 'idea_vault_auto_cloud_backup';
  static const String uniqueName = 'idea_vault_auto_cloud_backup_periodic';

  const CloudBackupScheduler();

  Future<void> scheduleDailyBackup() {
    return Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: const Duration(hours: 24),
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
