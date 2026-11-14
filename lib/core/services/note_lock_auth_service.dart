import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/vault/vault_lock_block.dart';
import 'note_lock_attempt_limiter.dart';

enum NoteLockPinCheck {
  success,
  wrongPin,
  lockedOut,
}

class NoteLockPinAttemptResult {
  const NoteLockPinAttemptResult({
    required this.check,
    required this.status,
  });

  final NoteLockPinCheck check;
  final NoteLockAttemptStatus status;

  bool get isSuccess => check == NoteLockPinCheck.success;
}

class NoteLockAuthService {
  NoteLockAuthService({
    FlutterSecureStorage? secureStorage,
    Random? random,
    Future<String?> Function(String key)? readValue,
    Future<void> Function(String key, String value)? writeValue,
    Future<void> Function(String key)? deleteValue,
    NoteLockAttemptLimiter? attemptLimiter,
    DateTime Function()? clock,
  })  : _random = random ?? Random.secure(),
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
                )) {
    _attemptLimiter = attemptLimiter ??
        NoteLockAttemptLimiter(
          readValue: _readValue,
          writeValue: _writeValue,
          deleteValue: _deleteValue,
          clock: clock,
        );
  }

  static const String _pinHashKey = 'note_lock_pin_hash';
  static const String _pinSaltKey = 'note_lock_pin_salt';
  static const String _pinKindKey = 'note_lock_pin_kind';

  final Random _random;
  final Set<String> _unlockedIdeaIds = {};
  final Future<String?> Function(String key) _readValue;
  final Future<void> Function(String key, String value) _writeValue;
  final Future<void> Function(String key) _deleteValue;
  late final NoteLockAttemptLimiter _attemptLimiter;

  NoteLockAttemptLimiter get attemptLimiter => _attemptLimiter;

  Future<bool> hasPin() async {
    final storedHash = await _readValue(_pinHashKey);
    final storedSalt = await _readValue(_pinSaltKey);
    return storedHash != null && storedSalt != null;
  }

  Future<void> createPin(
    String pin, {
    NoteLockPinKind kind = NoteLockPinKind.digits4,
  }) async {
    final salt = _createSalt();
    final hash = _hashPin(pin, salt);
    await _writeValue(_pinSaltKey, salt);
    await _writeValue(_pinHashKey, hash);
    await _writeValue(_pinKindKey, kind.name);
    await _attemptLimiter.reset();
  }

  Future<NoteLockPinKind> pinKind() async {
    return NoteLockPinKind.fromName(await _readValue(_pinKindKey));
  }

  Future<void> clearPin() async {
    await _deleteValue(_pinSaltKey);
    await _deleteValue(_pinHashKey);
    if (await _readValue(_pinKindKey) != null) {
      await _deleteValue(_pinKindKey);
    }
    await _attemptLimiter.reset();
    clearSessionUnlocks();
  }

  Future<NoteLockAttemptStatus> attemptStatus() => _attemptLimiter.status();

  Future<bool> _matchesStoredPin(String pin) async {
    final storedHash = await _readValue(_pinHashKey);
    final storedSalt = await _readValue(_pinSaltKey);
    if (storedHash == null || storedSalt == null) {
      return false;
    }
    return _hashPin(pin, storedSalt) == storedHash;
  }

  Future<NoteLockPinAttemptResult> attemptPin(String pin) async {
    if (!await hasPin()) {
      final status = await _attemptLimiter.status();
      return NoteLockPinAttemptResult(
        check: status.isLockedOut
            ? NoteLockPinCheck.lockedOut
            : NoteLockPinCheck.wrongPin,
        status: status,
      );
    }
    return attemptWith(() => _matchesStoredPin(pin));
  }

  Future<NoteLockPinAttemptResult> attemptWith(
    Future<bool> Function() check,
  ) async {
    final currentStatus = await _attemptLimiter.status();
    if (currentStatus.isLockedOut) {
      return NoteLockPinAttemptResult(
        check: NoteLockPinCheck.lockedOut,
        status: currentStatus,
      );
    }

    if (await check()) {
      await _attemptLimiter.reset();
      return const NoteLockPinAttemptResult(
        check: NoteLockPinCheck.success,
        status: NoteLockAttemptStatus.clear,
      );
    }

    final failedStatus = await _attemptLimiter.registerFailure();
    return NoteLockPinAttemptResult(
      check: failedStatus.isLockedOut
          ? NoteLockPinCheck.lockedOut
          : NoteLockPinCheck.wrongPin,
      status: failedStatus,
    );
  }

  Future<bool> verifyPin(String pin) async {
    final result = await attemptPin(pin);
    return result.isSuccess;
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
