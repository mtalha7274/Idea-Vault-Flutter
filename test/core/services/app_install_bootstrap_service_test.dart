import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/app_install_bootstrap_service.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/data/repositories/local/app_install_state.dart';

import '../../helpers/memory_local_storage.dart';

void main() {
  group('AppInstallBootstrapService', () {
    test('clears note lock credentials on fresh local install only', () async {
      final localStorage = MemoryLocalStorageManager();
      final secureStorage = <String, String>{};
      final authService = NoteLockAuthService(
        random: Random(1),
        readValue: (key) async => secureStorage[key],
        writeValue: (key, value) async {
          secureStorage[key] = value;
        },
        deleteValue: (key) async {
          secureStorage.remove(key);
        },
      );
      final biometricService = NoteLockBiometricService(
        readValue: (key) async => secureStorage[key],
        writeValue: (key, value) async {
          secureStorage[key] = value;
        },
        deleteValue: (key) async {
          secureStorage.remove(key);
        },
      );
      final installStateRepo = AppInstallStateRepo(localStorage);
      final service = AppInstallBootstrapService(
        installStateRepo,
        authService,
        biometricService,
      );

      await authService.createPin('1234');
      await biometricService.setBiometricUnlockEnabled(true);

      await service.runFreshInstallTasks();

      expect(await authService.hasPin(), isFalse);
      expect(await biometricService.isBiometricUnlockEnabled(), isFalse);
      expect(installStateRepo.hasInstallMarker, isTrue);

      await authService.createPin('2468');
      await biometricService.setBiometricUnlockEnabled(true);

      await service.runFreshInstallTasks();

      expect(await authService.verifyPin('2468'), isTrue);
      expect(await biometricService.isBiometricUnlockEnabled(), isTrue);
    });

    test('keeps note lock credentials when local app data exists', () async {
      final localStorage = MemoryLocalStorageManager();
      final secureStorage = <String, String>{};
      final authService = NoteLockAuthService(
        random: Random(1),
        readValue: (key) async => secureStorage[key],
        writeValue: (key, value) async {
          secureStorage[key] = value;
        },
        deleteValue: (key) async {
          secureStorage.remove(key);
        },
      );
      final biometricService = NoteLockBiometricService(
        readValue: (key) async => secureStorage[key],
        writeValue: (key, value) async {
          secureStorage[key] = value;
        },
        deleteValue: (key) async {
          secureStorage.remove(key);
        },
      );
      final installStateRepo = AppInstallStateRepo(localStorage);
      final service = AppInstallBootstrapService(
        installStateRepo,
        authService,
        biometricService,
        hasLocalAppData: () async => true,
      );

      await authService.createPin('1234');
      await biometricService.setBiometricUnlockEnabled(true);

      await service.runFreshInstallTasks();

      expect(await authService.verifyPin('1234'), isTrue);
      expect(await biometricService.isBiometricUnlockEnabled(), isTrue);
      expect(installStateRepo.hasInstallMarker, isTrue);
    });
  });
}
