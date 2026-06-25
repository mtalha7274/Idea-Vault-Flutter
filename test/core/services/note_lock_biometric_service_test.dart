import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';

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

    test('enableBiometricUnlock stores preference only after success', () async {
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

    test('authenticate returns canceled when challenge fails without side effects',
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
  });
}
