import '../../../data/repositories/local/app_install_state.dart';

class InitialCloudAuthCoordinator {
  InitialCloudAuthCoordinator(this._installStateRepo);

  final AppInstallStateRepo _installStateRepo;
  Future<void>? _inFlight;

  bool get isCompleted => _installStateRepo.hasInitialCloudAuthCheckCompleted;

  Future<void> runOncePerInstall(Future<void> Function() action) async {
    if (_installStateRepo.hasInitialCloudAuthCheckCompleted) {
      return;
    }

    final inFlight = _inFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final task = _execute(action);
    _inFlight = task;
    await task;
  }

  Future<void> _execute(Future<void> Function() action) async {
    try {
      await action();
    } finally {
      if (!_installStateRepo.hasInitialCloudAuthCheckCompleted) {
        await _installStateRepo.markInitialCloudAuthCheckCompleted();
      }
      _inFlight = null;
    }
  }
}
