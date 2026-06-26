import '../../../data/repositories/local/paid_feature_usage.dart';
import 'cloud_backup_service.dart';

class CloudUsageMetadataSyncService {
  const CloudUsageMetadataSyncService(
    this._usageRepo,
    this._backupService,
  );

  final PaidFeatureUsageRepo _usageRepo;
  final CloudBackupService _backupService;

  Future<void> syncFromCloud({
    bool silentAuth = true,
    bool overrideLocal = false,
  }) async {
    try {
      final metadata = await _backupService.restoreUsageMetadata(
        silentAuth: silentAuth,
      );
      if (metadata == null) {
        return;
      }
      if (overrideLocal) {
        await _usageRepo.applyCloudUsageMetadataFromRestore(metadata);
      } else {
        await _usageRepo.mergeCloudUsageMetadata(metadata);
      }
    } catch (_) {}
  }

  Future<void> syncToCloud({bool silentAuth = true}) async {
    try {
      await _backupService.backUpUsageMetadata(
        _usageRepo.toCloudUsageMetadata(),
        silentAuth: silentAuth,
      );
    } catch (_) {}
  }
}
