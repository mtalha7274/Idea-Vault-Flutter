import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/initial_cloud_auth_coordinator.dart';
import 'package:idea_vault/data/repositories/local/app_install_state.dart';

import '../../helpers/memory_local_storage.dart';

void main() {
  group('InitialCloudAuthCoordinator', () {
    late AppInstallStateRepo installStateRepo;
    late InitialCloudAuthCoordinator coordinator;

    setUp(() {
      installStateRepo = AppInstallStateRepo(MemoryLocalStorageManager());
      coordinator = InitialCloudAuthCoordinator(installStateRepo);
    });

    test('runs action once and marks install auth check completed', () async {
      var actionCount = 0;

      await coordinator.runOncePerInstall(() async {
        actionCount += 1;
      });

      expect(actionCount, 1);
      expect(installStateRepo.hasInitialCloudAuthCheckCompleted, isTrue);
    });

    test('dedupes concurrent runOncePerInstall calls', () async {
      var actionCount = 0;

      await Future.wait([
        coordinator.runOncePerInstall(() async {
          actionCount += 1;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }),
        coordinator.runOncePerInstall(() async {
          actionCount += 1;
        }),
      ]);

      expect(actionCount, 1);
      expect(installStateRepo.hasInitialCloudAuthCheckCompleted, isTrue);
    });

    test('skips action after install auth check is completed', () async {
      var actionCount = 0;
      await installStateRepo.markInitialCloudAuthCheckCompleted();

      await coordinator.runOncePerInstall(() async {
        actionCount += 1;
      });

      expect(actionCount, 0);
    });

    test('marks completed when action throws', () async {
      await expectLater(
        coordinator.runOncePerInstall(() async {
          throw StateError('auth failed');
        }),
        throwsStateError,
      );

      expect(installStateRepo.hasInitialCloudAuthCheckCompleted, isTrue);
    });
  });
}
