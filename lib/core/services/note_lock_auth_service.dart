import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class NoteLockAuthService {
  NoteLockAuthService({
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuthentication,
    Random? random,
    Future<String?> Function(String key)? readValue,
    Future<void> Function(String key, String value)? writeValue,
  })  : _localAuthentication = localAuthentication ?? LocalAuthentication(),
        _random = random ?? Random.secure(),
        _readValue = readValue ??
            ((key) => (secureStorage ?? const FlutterSecureStorage()).read(
                  key: key,
                )),
        _writeValue = writeValue ??
            ((key, value) =>
                (secureStorage ?? const FlutterSecureStorage()).write(
                  key: key,
                  value: value,
                ));

  static const String _pinHashKey = 'note_lock_pin_hash';
  static const String _pinSaltKey = 'note_lock_pin_salt';

  final LocalAuthentication _localAuthentication;
  final Random _random;
  final Set<String> _unlockedIdeaIds = {};
  final Future<String?> Function(String key) _readValue;
  final Future<void> Function(String key, String value) _writeValue;

  Future<bool> hasPin() async {
    final storedHash = await _readValue(_pinHashKey);
    final storedSalt = await _readValue(_pinSaltKey);
    return storedHash != null && storedSalt != null;
  }

  Future<void> createPin(String pin) async {
    final salt = _createSalt();
    final hash = _hashPin(pin, salt);
    await _writeValue(_pinSaltKey, salt);
    await _writeValue(_pinHashKey, hash);
  }

  Future<bool> verifyPin(String pin) async {
    final storedHash = await _readValue(_pinHashKey);
    final storedSalt = await _readValue(_pinSaltKey);
    if (storedHash == null || storedSalt == null) {
      return false;
    }
    return _hashPin(pin, storedSalt) == storedHash;
  }

  Future<bool> canUseBiometrics() async {
    final hasStoredPin = await hasPin();
    if (!hasStoredPin) {
      return false;
    }
    try {
      final isSupported = await _localAuthentication.isDeviceSupported();
      final canCheck = await _localAuthentication.canCheckBiometrics;
      return isSupported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics(String localizedReason) async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  bool isIdeaUnlocked(String ideaId) {
    return _unlockedIdeaIds.contains(ideaId);
  }

  void markIdeaUnlocked(String ideaId) {
    _unlockedIdeaIds.add(ideaId);
  }

  void markIdeaLocked(String ideaId) {
    _unlockedIdeaIds.remove(ideaId);
  }

  void clearSessionUnlocks() {
    _unlockedIdeaIds.clear();
  }

  String _createSalt() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }
}
