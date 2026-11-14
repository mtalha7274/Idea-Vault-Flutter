import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'note_lock_session_guard.dart';

enum BiometricAuthResult {
  success,
  canceled,
  failed,
}

class NoteLockBiometricService {
  NoteLockBiometricService({
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuthentication,
    Future<String?> Function(String key)? readValue,
    Future<void> Function(String key, String value)? writeValue,
    Future<void> Function(String key)? deleteValue,
    Future<bool> Function({
      required String localizedReason,
      bool biometricOnly,
      bool persistAcrossBackgrounding,
    })? authenticate,
    Future<bool> Function()? isDeviceSupported,
    Future<bool> Function()? canCheckBiometrics,
  })  : _localAuthentication = localAuthentication ?? LocalAuthentication(),
        _readValue = readValue ??
            ((key) => (secureStorage ?? const FlutterSecureStorage()).read(
                  key: key,
                )),
        _writeValue = writeValue ??
            ((key, value) =>
                (secureStorage ?? const FlutterSecureStorage()).write(
                  key: key,
                  value: value,
                )),
        _deleteValue = deleteValue ??
            ((key) => (secureStorage ?? const FlutterSecureStorage()).delete(
                  key: key,
                )),
        _authenticate = authenticate,
        _isDeviceSupported = isDeviceSupported,
        _canCheckBiometrics = canCheckBiometrics;

  static const String _biometricEnabledKey = 'note_lock_biometric_enabled';

  final LocalAuthentication _localAuthentication;
  final Future<String?> Function(String key) _readValue;
  final Future<void> Function(String key, String value) _writeValue;
  final Future<void> Function(String key) _deleteValue;
  final Future<bool> Function({
    required String localizedReason,
    bool biometricOnly,
    bool persistAcrossBackgrounding,
  })? _authenticate;
  final Future<bool> Function()? _isDeviceSupported;
  final Future<bool> Function()? _canCheckBiometrics;

  Future<bool> isBiometricUnlockEnabled() async {
    final value = await _readValue(_biometricEnabledKey);
    return value == 'true';
  }

  Future<void> setBiometricUnlockEnabled(bool enabled) async {
    await _writeValue(_biometricEnabledKey, enabled.toString());
  }

  Future<void> clearBiometricUnlock() async {
    await _deleteValue(_biometricEnabledKey);
  }

  Future<bool> isDeviceSupported() async {
    try {
      final checkDeviceSupported = _isDeviceSupported;
      if (checkDeviceSupported != null) {
        return await checkDeviceSupported();
      }
      return await _localAuthentication.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasEnrolledBiometrics() async {
    try {
      final checkBiometrics = _canCheckBiometrics;
      if (checkBiometrics != null) {
        return await checkBiometrics();
      }
      if (!await _localAuthentication.canCheckBiometrics) {
        return false;
      }
      final available = await _localAuthentication.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> canOfferBiometricEnrollment() async {
    final isSupported = await isDeviceSupported();
    final hasEnrolled = await hasEnrolledBiometrics();
    return isSupported && hasEnrolled;
  }

  Future<bool> canUseBiometricUnlock() async {
    final isEnabled = await isBiometricUnlockEnabled();
    if (!isEnabled) {
      return false;
    }
    return canOfferBiometricEnrollment();
  }

  Future<BiometricAuthResult> authenticate(String localizedReason) async {
    try {
      final didAuthenticate = await NoteLockSessionGuard.runWithoutRelock(
        () => _performAuthenticate(localizedReason),
      );
      if (didAuthenticate) {
        return BiometricAuthResult.success;
      }
      return BiometricAuthResult.canceled;
    } on LocalAuthException catch (error) {
      if (error.code == LocalAuthExceptionCode.userCanceled ||
          error.code == LocalAuthExceptionCode.systemCanceled ||
          error.code == LocalAuthExceptionCode.userRequestedFallback ||
          error.code == LocalAuthExceptionCode.timeout) {
        return BiometricAuthResult.canceled;
      }
      return BiometricAuthResult.failed;
    } on PlatformException catch (error) {
      if (error.code == 'UserCanceled' || error.code == 'SystemCanceled') {
        return BiometricAuthResult.canceled;
      }
      return BiometricAuthResult.failed;
    } catch (_) {
      return BiometricAuthResult.failed;
    }
  }

  Future<BiometricAuthResult> enableBiometricUnlock(
    String localizedReason,
  ) async {
    final result = await authenticate(localizedReason);
    if (result == BiometricAuthResult.success) {
      await setBiometricUnlockEnabled(true);
    }
    return result;
  }

  Future<bool> _performAuthenticate(String localizedReason) async {
    final authenticate = _authenticate;
    if (authenticate != null) {
      return authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    }
    return _localAuthentication.authenticate(
      localizedReason: localizedReason,
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
  }
}
