import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/core/services/note_lock_session_guard.dart';

void main() {
  group('NoteLockBiometricService', () {
    test('tracks biometric unlock preference', () async {
      final storage = <String, String>{};
      final service = NoteLockBiometricService(
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
      );

      expect(await service.isBiometricUnlockEnabled(), isFalse);

      await service.setBiometricUnlockEnabled(true);

      expect(await service.isBiometricUnlockEnabled(), isTrue);
      expect(storage['note_lock_biometric_enabled'], 'true');
    });

    test('clearBiometricUnlock removes stored biometric preference', () async {
      final storage = <String, String>{};
      final service = NoteLockBiometricService(
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        deleteValue: (key) async {
          storage.remove(key);
        },
      );

      await service.setBiometricUnlockEnabled(true);
      expect(await service.isBiometricUnlockEnabled(), isTrue);

      await service.clearBiometricUnlock();

      expect(await service.isBiometricUnlockEnabled(), isFalse);
      expect(storage, isEmpty);
    });

    test('canUseBiometricUnlock requires enabled preference and device support',
        () async {
      final storage = <String, String>{};
      final service = NoteLockBiometricService(
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        isDeviceSupported: () async => true,
        canCheckBiometrics: () async => true,
      );

      expect(await service.canUseBiometricUnlock(), isFalse);

      await service.setBiometricUnlockEnabled(true);

      expect(await service.canUseBiometricUnlock(), isTrue);
    });

    test('enableBiometricUnlock stores preference only after success',
        () async {
      final storage = <String, String>{};
      var authenticateCalls = 0;
      final service = NoteLockBiometricService(
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        authenticate: ({
          required String localizedReason,
          bool biometricOnly = false,
          bool persistAcrossBackgrounding = false,
        }) async {
          authenticateCalls += 1;
          return authenticateCalls == 1;
        },
      );

      final firstResult = await service.enableBiometricUnlock('Confirm');
      final secondResult = await service.enableBiometricUnlock('Confirm');

      expect(firstResult, BiometricAuthResult.success);
      expect(secondResult, BiometricAuthResult.canceled);
      expect(await service.isBiometricUnlockEnabled(), isTrue);
      expect(authenticateCalls, 2);
    });

    test(
        'authenticate returns canceled when challenge fails without side effects',
        () async {
      final service = NoteLockBiometricService(
        readValue: (_) async => null,
        writeValue: (_, __) async {},
        authenticate: ({
          required String localizedReason,
          bool biometricOnly = false,
          bool persistAcrossBackgrounding = false,
        }) async =>
            false,
      );

      expect(
        await service.authenticate('Unlock'),
        BiometricAuthResult.canceled,
      );
    });

    test('asks for biometrics only so the device passcode is not accepted',
        () async {
      bool? requestedBiometricOnly;
      var suppressedDuringPrompt = false;
      final service = NoteLockBiometricService(
        readValue: (_) async => null,
        writeValue: (_, __) async {},
        authenticate: ({
          required String localizedReason,
          bool biometricOnly = false,
          bool persistAcrossBackgrounding = false,
        }) async {
          requestedBiometricOnly = biometricOnly;
          suppressedDuringPrompt = NoteLockSessionGuard.isRelockSuppressed;
          return true;
        },
      );

      expect(await service.authenticate('Unlock'), BiometricAuthResult.success);
      expect(requestedBiometricOnly, isTrue);
      expect(suppressedDuringPrompt, isTrue);
      expect(NoteLockSessionGuard.isRelockSuppressed, isFalse);
    });
  });
}
