import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/services/app_install_bootstrap_service.dart';
import 'data/managers/local/ideas_database.dart';
import 'data/managers/local/local_storage.dart';
import 'data/managers/local/shared_preference.dart';
import 'data/managers/remote/api_manager.dart';
import 'data/managers/remote/dio_api_manager.dart';
import 'data/repositories/local/idea_editor_state.dart';
import 'data/repositories/local/idea_list_preferences.dart';
import 'data/repositories/local/app_install_state.dart';
import 'data/repositories/local/ideas.dart';
import 'data/repositories/local/paid_feature_usage.dart';
import 'data/repositories/local/random_additions.dart';
import 'data/repositories/local/cloud_backup_settings.dart';
import 'data/repositories/local/language.dart';
import 'data/repositories/local/theme.dart';
import 'core/services/backup/cloud_backup_scheduler.dart';
import 'core/services/backup/cloud_backup_service.dart';
import 'core/services/backup/cloud_usage_metadata_sync_service.dart';
import 'core/services/note_lock_auth_service.dart';
import 'core/services/note_lock_biometric_service.dart';
import 'core/services/premium/bypass_paywall_subscription_service.dart';
import 'core/services/premium/paywall_provider.dart';
import 'core/services/premium/revenuecat_subscription_service.dart';
import 'core/services/premium/subscription_service.dart';
import 'data/repositories/remote/idea_organization_repository.dart';
import 'data/repositories/remote/settings/country.dart';
import 'models/settings.dart';
import 'viewmodels/providers/language_provider.dart';
import 'viewmodels/providers/ideas_provider.dart';
import 'viewmodels/providers/random_additions_provider.dart';
import 'viewmodels/providers/backup/cloud_backup_provider.dart';
import 'viewmodels/providers/info_provider.dart';
import 'viewmodels/providers/premium/paywall_view_model.dart';
import 'viewmodels/providers/theme_provider.dart';

final sl = GetIt.instance;

Future<void> initializeDependencies() async {
  // Initialize
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(sharedPreferences);

  final packageInfo = await PackageInfo.fromPlatform();
  sl.registerSingleton<PackageInfo>(packageInfo);

  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  final DeviceData deviceName = DeviceData(
      Platform.isAndroid
          ? (await deviceInfo.androidInfo).model
          : (await deviceInfo.iosInfo).utsname.machine,
      Platform.isAndroid
          ? (await deviceInfo.androidInfo).version.release
          : (await deviceInfo.iosInfo).systemVersion);
  sl.registerSingleton<DeviceData>(deviceName);

  // Managers
  sl.registerSingleton<LocalStorageManager>(
      SharedPreferenceManager(sl<SharedPreferences>()));
  sl.registerSingleton<IdeasDatabaseManager>(IdeasDatabaseManager());
  sl.registerSingleton<CloudBackupService>(CloudBackupService());
  sl.registerSingleton<CloudBackupScheduler>(const CloudBackupScheduler());
  sl.registerSingleton<NoteLockAuthService>(NoteLockAuthService());
  sl.registerSingleton<NoteLockBiometricService>(NoteLockBiometricService());
  sl.registerSingleton<SubscriptionService>(_buildSubscriptionService());
  sl.registerSingleton<PaywallProvider>(_buildPaywallProvider());

  sl.registerSingleton<ApiManager>(DioApiManager(AppConstants.countryUrl),
      instanceName: AppConstants.countryUrl);

  // Firebase
  sl.registerSingleton<FirebaseFunctions>(FirebaseFunctions.instance);

  // Repositories
  sl.registerSingleton<IdeaEditorStateRepo>(
      IdeaEditorStateRepo(sl<LocalStorageManager>()));
  sl.registerSingleton<AppInstallStateRepo>(
      AppInstallStateRepo(sl<LocalStorageManager>()));
  sl.registerSingleton<CloudBackupSettingsRepo>(
      CloudBackupSettingsRepo(sl<LocalStorageManager>()));
  sl.registerSingleton<PaidFeatureUsageRepo>(
      PaidFeatureUsageRepo(sl<LocalStorageManager>()));
  sl.registerSingleton<CloudUsageMetadataSyncService>(
      CloudUsageMetadataSyncService(
    sl<PaidFeatureUsageRepo>(),
    sl<CloudBackupService>(),
  ));
  sl.registerSingleton<IdeaListPreferencesRepo>(
      IdeaListPreferencesRepo(sl<LocalStorageManager>()));
  sl.registerSingleton<IdeasRepo>(IdeasRepo(sl<IdeasDatabaseManager>()));
  sl.registerSingleton<RandomAdditionsRepo>(
      RandomAdditionsRepo(sl<IdeasDatabaseManager>()));
  sl.registerSingleton<ThemeRepo>(ThemeRepo(sl<LocalStorageManager>()));
  sl.registerSingleton<LanguageRepo>(LanguageRepo(sl<LocalStorageManager>()));
  sl.registerSingleton<CountryRepo>(
      CountryRepo(sl<ApiManager>(instanceName: AppConstants.countryUrl)));
  sl.registerSingleton<IdeaOrganizationRepository>(
      IdeaOrganizationRepository(sl<FirebaseFunctions>()));

  // Providers
  sl.registerFactory<IdeasProvider>(
      () => IdeasProvider(sl<IdeasRepo>(), sl<IdeaEditorStateRepo>()));
  sl.registerFactory<RandomAdditionsProvider>(
      () => RandomAdditionsProvider(sl<RandomAdditionsRepo>()));
  sl.registerFactory<CloudBackupProvider>(() => CloudBackupProvider(
        sl<CloudBackupSettingsRepo>(),
        sl<CloudBackupService>(),
        sl<CloudBackupScheduler>(),
        usageMetadataSync: sl<CloudUsageMetadataSyncService>(),
      ));
  sl.registerFactory<PaywallViewModel>(() => PaywallViewModel(
        sl<SubscriptionService>(),
        sl<PaywallProvider>(),
        sl<PaidFeatureUsageRepo>(),
        sl<CloudBackupSettingsRepo>(),
        sl<CloudBackupService>(),
        sl<CloudBackupScheduler>(),
        usageMetadataSync: sl<CloudUsageMetadataSyncService>(),
      ));
  sl.registerFactory<ThemeProvider>(() => ThemeProvider(sl<ThemeRepo>()));
  sl.registerFactory<LanguageProvider>(
      () => LanguageProvider(sl<LanguageRepo>()));
  sl.registerFactory<InfoProvider>(
      () => InfoProvider(sl<CountryRepo>(), sl<LocalStorageManager>()));
  sl.registerSingleton<AppInstallBootstrapService>(AppInstallBootstrapService(
    sl<AppInstallStateRepo>(),
    sl<NoteLockAuthService>(),
    sl<NoteLockBiometricService>(),
    hasLocalAppData: () async {
      final ideas = await sl<IdeasRepo>().getIdeas();
      if (ideas.isNotEmpty) {
        return true;
      }
      final additions = await sl<RandomAdditionsRepo>().getAdditions();
      if (additions.isNotEmpty) {
        return true;
      }
      final usageRepo = sl<PaidFeatureUsageRepo>();
      if (usageRepo.usageCount != 0 || usageRepo.hasFreeUsageIntroMetadata) {
        return true;
      }
      final backupState = sl<CloudBackupSettingsRepo>().getState();
      return backupState.enabled ||
          backupState.email != null ||
          backupState.lastBackupAt != null;
    },
  ));
}

SubscriptionService _buildSubscriptionService() {
  final provider = dotenv.env['SUBSCRIPTION_PROVIDER']?.trim().toLowerCase();
  final SubscriptionService inner;
  switch (provider) {
    case 'revenuecat':
    case null:
    case '':
      inner = RevenueCatSubscriptionService();
      break;
    default:
      inner = RevenueCatSubscriptionService();
  }
  return BypassPaywallSubscriptionService(inner);
}

PaywallProvider _buildPaywallProvider() {
  final provider = dotenv.env['PAYWALL_PROVIDER']?.trim().toLowerCase();
  switch (provider) {
    case 'local':
    case null:
    case '':
      return LocalPaywallProvider(sl<SubscriptionService>());
    default:
      return LocalPaywallProvider(sl<SubscriptionService>());
  }
}
