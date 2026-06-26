import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../data/repositories/local/cloud_backup_settings.dart';
import '../../../data/repositories/local/ideas.dart';
import '../../../data/repositories/local/random_additions.dart';
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

Future<void> _loadBackgroundEnv() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
}

bool _isBackupDue(DateTime? lastBackupAt) {
  if (lastBackupAt == null) {
    return true;
  }
  return DateTime.now().difference(lastBackupAt) >=
      CloudBackupScheduler.backupInterval;
}

@pragma('vm:entry-point')
void cloudBackupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (!CloudBackupScheduler.isCloudBackupTask(task)) {
      return true;
    }

    try {
      WidgetsFlutterBinding.ensureInitialized();
      await _loadBackgroundEnv();

      final localStorage =
          SharedPreferenceManager(await SharedPreferences.getInstance());
      final settingsRepo = CloudBackupSettingsRepo(localStorage);
      final state = settingsRepo.getState();
      if (!state.enabled || !state.autoBackupEnabled) {
        return true;
      }
      if (!_isBackupDue(state.lastBackupAt)) {
        return true;
      }

      final databaseManager = IdeasDatabaseManager();
      final ideasRepo = IdeasRepo(databaseManager);
      final randomAdditionsRepo = RandomAdditionsRepo(databaseManager);
      final ideas = await ideasRepo.getIdeas();
      final randomAdditions = await randomAdditionsRepo.getAdditions();
      final sizeBytes = await CloudBackupService().backUpIdeas(
        ideas,
        randomAdditions: randomAdditions,
        silentAuth: true,
      );
      await settingsRepo.saveState(
        state.copyWith(
          lastBackupAt: DateTime.now(),
          lastBackupSizeBytes: sizeBytes,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  });
}
