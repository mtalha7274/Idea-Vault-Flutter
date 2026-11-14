import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/note_lock_attempt_limiter.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';

class _FakeClock {
  _FakeClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) {
    now = now.add(duration);
  }
}

NoteLockAuthService _buildService(
  Map<String, String> storage,
  _FakeClock clock,
) {
  return NoteLockAuthService(
    random: Random(1),
    clock: clock.call,
    readValue: (key) async => storage[key],
    writeValue: (key, value) async {
      storage[key] = value;
    },
    deleteValue: (key) async {
      storage.remove(key);
    },
  );
}

void main() {
  group('NoteLockAttemptLimiter schedule', () {
    test('gives five free tries then 30s, 1m, 5m, 15m and 1h repeating', () {
      final waits = [
        for (var failures = 1; failures <= 12; failures++)
          NoteLockAttemptLimiter.waitAfterFailures(failures),
      ];

      expect(waits.take(4), everyElement(Duration.zero));
      expect(waits.sublist(4, 10), const [
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 5),
        Duration(minutes: 15),
        Duration(hours: 1),
        Duration(hours: 1),
      ]);
      expect(waits.last, const Duration(hours: 1));
    });
  });

  group('NoteLockAuthService attempt limits', () {
    late Map<String, String> storage;
    late _FakeClock clock;
    late NoteLockAuthService service;

    setUp(() async {
      storage = {};
      clock = _FakeClock(DateTime.utc(2026, 11, 13, 9));
      service = _buildService(storage, clock);
      await service.createPin('2468');
    });

    test('locks out after five wrong PINs and rejects the right one', () async {
      for (var attempt = 1; attempt <= 4; attempt++) {
        final result = await service.attemptPin('0000');
        expect(result.check, NoteLockPinCheck.wrongPin);
      }

      final fifth = await service.attemptPin('0000');
      expect(fifth.check, NoteLockPinCheck.lockedOut);
      expect(fifth.status.remainingWait, const Duration(seconds: 30));

      clock.advance(const Duration(seconds: 10));
      final blocked = await service.attemptPin('2468');
      expect(blocked.check, NoteLockPinCheck.lockedOut);
      expect(blocked.status.remainingWait, const Duration(seconds: 20));

      clock.advance(const Duration(seconds: 20));
      final allowed = await service.attemptPin('2468');
      expect(allowed.check, NoteLockPinCheck.success);
      expect((await service.attemptStatus()).failedAttempts, 0);
    });

    test('escalates waits and ten wrong PINs take more than six minutes',
        () async {
      var waited = Duration.zero;
      for (var attempt = 1; attempt <= 10; attempt++) {
        final status = await service.attemptStatus();
        waited += status.remainingWait;
        clock.advance(status.remainingWait);
        await service.attemptPin('0000');
      }

      expect(waited, greaterThan(const Duration(minutes: 6)));
      expect(
        (await service.attemptStatus()).remainingWait,
        const Duration(hours: 1),
      );
    });

    test('keeps the counter across service instances', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        await service.attemptPin('0000');
      }

      final restarted = _buildService(storage, clock);
      final status = await restarted.attemptStatus();
      expect(status.failedAttempts, 5);
      expect(status.isLockedOut, isTrue);
      expect(
        (await restarted.attemptPin('2468')).check,
        NoteLockPinCheck.lockedOut,
      );
    });

    test('restarts the wait when the clock moves backwards', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        await service.attemptPin('0000');
      }
      clock.advance(const Duration(seconds: 25));
      expect(
        (await service.attemptStatus()).remainingWait,
        const Duration(seconds: 5),
      );

      clock.advance(const Duration(days: -1));
      expect(
        (await service.attemptStatus()).remainingWait,
        const Duration(seconds: 30),
      );

      clock.advance(const Duration(seconds: 29));
      expect((await service.attemptStatus()).isLockedOut, isTrue);
      clock.advance(const Duration(seconds: 1));
      expect((await service.attemptStatus()).isLockedOut, isFalse);
    });

    test('verifyPin also counts failures and respects the lockout', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        expect(await service.verifyPin('1111'), isFalse);
      }
      expect(await service.verifyPin('2468'), isFalse);

      clock.advance(const Duration(seconds: 30));
      expect(await service.verifyPin('2468'), isTrue);
    });

    test('creating or clearing the PIN resets the counter', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        await service.attemptPin('0000');
      }
      await service.clearPin();
      expect((await service.attemptStatus()).failedAttempts, 0);
      expect(storage.keys.where((key) => key.contains('attempt')), isEmpty);
    });
  });
}
