import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NoteLockAttemptStatus {
  const NoteLockAttemptStatus({
    required this.failedAttempts,
    required this.remainingWait,
  });

  static const NoteLockAttemptStatus clear = NoteLockAttemptStatus(
    failedAttempts: 0,
    remainingWait: Duration.zero,
  );

  final int failedAttempts;
  final Duration remainingWait;

  bool get isLockedOut => remainingWait > Duration.zero;

  int get freeAttemptsLeft {
    final left = NoteLockAttemptLimiter.freeAttempts - failedAttempts;
    return left < 0 ? 0 : left;
  }
}

class NoteLockAttemptLimiter {
  NoteLockAttemptLimiter({
    FlutterSecureStorage? secureStorage,
    Future<String?> Function(String key)? readValue,
    Future<void> Function(String key, String value)? writeValue,
    Future<void> Function(String key)? deleteValue,
    DateTime Function()? clock,
  })  : _readValue = readValue ??
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
        _clock = clock ?? DateTime.now;

  static const int freeAttempts = 5;
  static const List<Duration> waitSchedule = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  static const String _failedAttemptsKey = 'note_lock_failed_attempts';
  static const String _waitStartedAtKey = 'note_lock_wait_started_at';
  static const String _waitDurationKey = 'note_lock_wait_duration_ms';

  final Future<String?> Function(String key) _readValue;
  final Future<void> Function(String key, String value) _writeValue;
  final Future<void> Function(String key) _deleteValue;
  final DateTime Function() _clock;

  static Duration waitAfterFailures(int failedAttempts) {
    if (failedAttempts < freeAttempts) {
      return Duration.zero;
    }
    final index = failedAttempts - freeAttempts;
    return waitSchedule[
        index < waitSchedule.length ? index : waitSchedule.length - 1];
  }

  Future<NoteLockAttemptStatus> status() async {
    final failedAttempts = await _readInt(_failedAttemptsKey) ?? 0;
    final startedAtMs = await _readInt(_waitStartedAtKey);
    final waitMs = await _readInt(_waitDurationKey);
    if (startedAtMs == null || waitMs == null || waitMs <= 0) {
      return NoteLockAttemptStatus(
        failedAttempts: failedAttempts,
        remainingWait: Duration.zero,
      );
    }

    final nowMs = _clock().millisecondsSinceEpoch;
    if (nowMs < startedAtMs) {
      await _writeValue(_waitStartedAtKey, '$nowMs');
      return NoteLockAttemptStatus(
        failedAttempts: failedAttempts,
        remainingWait: Duration(milliseconds: waitMs),
      );
    }

    final remainingMs = startedAtMs + waitMs - nowMs;
    return NoteLockAttemptStatus(
      failedAttempts: failedAttempts,
      remainingWait:
          remainingMs > 0 ? Duration(milliseconds: remainingMs) : Duration.zero,
    );
  }

  Future<NoteLockAttemptStatus> registerFailure() async {
    final failedAttempts = (await _readInt(_failedAttemptsKey) ?? 0) + 1;
    await _writeValue(_failedAttemptsKey, '$failedAttempts');
    final wait = waitAfterFailures(failedAttempts);
    if (wait > Duration.zero) {
      await _writeValue(
        _waitStartedAtKey,
        '${_clock().millisecondsSinceEpoch}',
      );
      await _writeValue(_waitDurationKey, '${wait.inMilliseconds}');
    } else {
      await _deleteIfPresent(_waitStartedAtKey);
      await _deleteIfPresent(_waitDurationKey);
    }
    return NoteLockAttemptStatus(
      failedAttempts: failedAttempts,
      remainingWait: wait,
    );
  }

  Future<void> reset() async {
    await _deleteIfPresent(_failedAttemptsKey);
    await _deleteIfPresent(_waitStartedAtKey);
    await _deleteIfPresent(_waitDurationKey);
  }

  Future<void> _deleteIfPresent(String key) async {
    if (await _readValue(key) != null) {
      await _deleteValue(key);
    }
  }

  Future<int?> _readInt(String key) async {
    final value = await _readValue(key);
    return value == null ? null : int.tryParse(value);
  }
}
