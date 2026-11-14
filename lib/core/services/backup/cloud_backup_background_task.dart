import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../data/managers/local/ideas_database.dart';
import '../../../data/managers/local/local_storage.dart';
import '../../../data/managers/local/shared_preference.dart';
import '../../../data/repositories/local/backup_device_identity.dart';
import '../../../data/repositories/local/cloud_backup_settings.dart';
import '../../../data/repositories/local/local_vault.dart';
import '../../../models/backup/cloud_backup_restore.dart';
import 'cloud_backup_coordinator.dart';
import 'cloud_backup_scheduler.dart';
import 'cloud_backup_service.dart';
import 'cloud_backup_upload_lock.dart';

class CloudBackupBackgroundTask {
  const CloudBackupBackgroundTask._();

  static Future<void> initialize() {
    return Workmanager().initialize(
      cloudBackupCallbackDispatcher,
    );
  }

  static CloudBackupCoordinator buildCoordinator({
    required LocalStorageManager storage,
    required CloudBackupService service,
    Future<void> Function()? reloadStorage,
    String appVersion = '',
    DateTime Function()? clock,
  }) {
    return CloudBackupCoordinator(
      settingsRepo: CloudBackupSettingsRepo(storage),
      service: service,
      deviceIdentityRepo: BackupDeviceIdentityRepo(storage),
      lock: CloudBackupUploadLock(
        storage,
        owner: CloudBackupUploadLock.backgroundOwner,
        reloadStorage: reloadStorage,
        clock: clock,
      ),
      appVersion: appVersion,
      reloadStorage: reloadStorage,
      clock: clock,
    );
  }

  static Future<CloudBackupRunResult> run({
    required LocalStorageManager storage,
    required CloudBackupService service,
    required LocalVaultLoader loadContent,
    Future<void> Function()? reloadStorage,
    String appVersion = '',
    DateTime Function()? clock,
  }) {
    final coordinator = buildCoordinator(
      storage: storage,
      service: service,
      reloadStorage: reloadStorage,
      appVersion: appVersion,
      clock: clock,
    );
    return coordinator.runAutoBackupIfDue(loadContent);
  }
}

Future<void> _loadBackgroundEnv() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
}

Future<String> _appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    return '';
  }
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

      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final localVault = LocalVaultRepo(IdeasDatabaseManager());
      await CloudBackupBackgroundTask.run(
        storage: SharedPreferenceManager(preferences),
        service: CloudBackupService(),
        loadContent: localVault.read,
        reloadStorage: preferences.reload,
        appVersion: await _appVersion(),
      );
      return true;
    } catch (_) {
      return false;
    }
  });
}
