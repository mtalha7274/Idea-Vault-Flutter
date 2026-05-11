import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../data/repositories/local/cloud_backup_settings.dart';
import '../../../data/repositories/local/ideas.dart';
import '../../../data/managers/local/ideas_database.dart';
import '../../../data/managers/local/shared_preference.dart';
import 'cloud_backup_scheduler.dart';
import 'cloud_backup_service.dart';

class CloudBackupBackgroundTask {
  const CloudBackupBackgroundTask._();

  static Future<void> initialize() {
    return Workmanager().initialize(
      cloudBackupCallbackDispatcher,
    );
  }
}

@pragma('vm:entry-point')
void cloudBackupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != CloudBackupScheduler.taskName &&
        task != Workmanager.iOSBackgroundTask) {
      return true;
    }

    WidgetsFlutterBinding.ensureInitialized();
    final localStorage =
        SharedPreferenceManager(await SharedPreferences.getInstance());
    final settingsRepo = CloudBackupSettingsRepo(localStorage);
    final state = settingsRepo.getState();
    if (!state.enabled || !state.autoBackupEnabled) {
      return true;
    }

    final ideasRepo = IdeasRepo(IdeasDatabaseManager());
    final ideas = await ideasRepo.getIdeas();
    final sizeBytes = await CloudBackupService().backUpIdeas(ideas);
    await settingsRepo.saveState(
      state.copyWith(
        lastBackupAt: DateTime.now(),
        lastBackupSizeBytes: sizeBytes,
      ),
    );
    return true;
  });
}
