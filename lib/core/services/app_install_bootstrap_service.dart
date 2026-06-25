import '../../data/repositories/local/app_install_state.dart';
import 'note_lock_auth_service.dart';
import 'note_lock_biometric_service.dart';

class AppInstallBootstrapService {
  const AppInstallBootstrapService(
    this._installStateRepo,
    this._noteLockAuthService,
    this._noteLockBiometricService, {
    Future<bool> Function()? hasLocalAppData,
  }) : _hasLocalAppData = hasLocalAppData;

  final AppInstallStateRepo _installStateRepo;
  final NoteLockAuthService _noteLockAuthService;
  final NoteLockBiometricService _noteLockBiometricService;
  final Future<bool> Function()? _hasLocalAppData;

  Future<void> runFreshInstallTasks() async {
    if (_installStateRepo.hasInstallMarker) {
      return;
    }
    if (await (_hasLocalAppData?.call() ?? Future<bool>.value(false))) {
      await _installStateRepo.markInstalled();
      return;
    }
    await _noteLockAuthService.clearPin();
    await _noteLockBiometricService.clearBiometricUnlock();
    await _installStateRepo.markInstalled();
  }
}
