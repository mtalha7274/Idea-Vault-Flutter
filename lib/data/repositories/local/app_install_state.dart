import '../../managers/local/local_storage.dart';

class AppInstallStateRepo {
  const AppInstallStateRepo(this._localStorage);

  static const String _installMarkerKey = 'app_install_marker_v1';

  final LocalStorageManager _localStorage;

  bool get hasInstallMarker =>
      _localStorage.getString(key: _installMarkerKey) == 'true';

  Future<void> markInstalled() {
    return _localStorage.setString(key: _installMarkerKey, value: 'true');
  }
}
