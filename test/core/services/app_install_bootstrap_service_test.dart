import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/app_install_bootstrap_service.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/core/services/vault/note_vault_service.dart';
import 'package:idea_vault/data/repositories/local/app_install_state.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/vault/vault_lock_block.dart';

import '../../helpers/in_memory_ideas_repo.dart';
import '../../helpers/memory_local_storage.dart';
import '../../helpers/vault_test_env.dart';

Idea _cleanupIdea({
  required String id,
  String title = 'Untitled Idea',
  List<IdeaSection>? sections,
  bool isLocked = false,
}) {
  return Idea(
    id: id,
    title: title,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    isLocked: isLocked,
    sections:
        sections ?? [IdeaSection(id: '$id-section', name: 'Idea', content: '')],
  );
}

NoteLockAuthService _memoryAuthService(Map<String, String> secureStorage) {
  return NoteLockAuthService(
    random: Random(1),
    readValue: (key) async => secureStorage[key],
    writeValue: (key, value) async {
      secureStorage[key] = value;
    },
    deleteValue: (key) async {
      secureStorage.remove(key);
    },
  );
}

NoteLockBiometricService _memoryBiometricService(
  Map<String, String> secureStorage,
) {
  return NoteLockBiometricService(
    readValue: (key) async => secureStorage[key],
    writeValue: (key, value) async {
      secureStorage[key] = value;
    },
    deleteValue: (key) async {
      secureStorage.remove(key);
    },
  );
}

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

    test('a fresh install also clears stale vault key material', () async {
      final secureStorage = <String, String>{};
      final keys = VaultTestKeys();
      final vault = buildTestVault(
        vaultRepo: InMemoryNoteVaultRepo(),
        ideasRepo: InMemoryIdeasRepo(),
        keys: keys,
      );
      await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
      expect(keys.values, isNotEmpty);
      final service = AppInstallBootstrapService(
        AppInstallStateRepo(MemoryLocalStorageManager()),
        _memoryAuthService(secureStorage),
        _memoryBiometricService(secureStorage),
        clearVaultKeyMaterial: vault.forgetCachedKey,
      );

      await service.runFreshInstallTasks();

      expect(keys.values, isEmpty);
      expect(vault.holdsKeyInMemory, isFalse);
      expect(await vault.state(), NoteVaultState.needsUnwrap);
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

    group('empty untitled idea cleanup', () {
      late MemoryLocalStorageManager localStorage;
      late InMemoryIdeasRepo ideasRepo;
      late AppInstallBootstrapService service;

      setUp(() async {
        localStorage = MemoryLocalStorageManager();
        ideasRepo = InMemoryIdeasRepo();
        final installStateRepo = AppInstallStateRepo(localStorage);
        await installStateRepo.markInstalled();
        final secureStorage = <String, String>{};
        service = AppInstallBootstrapService(
          installStateRepo,
          _memoryAuthService(secureStorage),
          _memoryBiometricService(secureStorage),
          ideasRepo: () => ideasRepo,
          localStorage: () => localStorage,
          localizedUntitledTitle: () => 'Idée sans titre',
        );
      });

      Future<List<String>> remainingIds() async {
        final ideas = await ideasRepo.getIdeas();
        return ideas.map((idea) => idea.id).toList();
      }

      test('deletes only blank untitled ideas, even when installed', () async {
        await ideasRepo.saveIdeas([
          _cleanupIdea(id: 'junk-english'),
          _cleanupIdea(id: 'junk-localized', title: 'Idée sans titre'),
          _cleanupIdea(
            id: 'junk-whitespace',
            sections: const [
              IdeaSection(id: 'ws', name: 'Idea', content: '  \n\t '),
            ],
          ),
          _cleanupIdea(id: 'custom-title', title: 'Untitled Idea 2'),
          _cleanupIdea(id: 'lowercase-title', title: 'untitled idea'),
          _cleanupIdea(
            id: 'has-content',
            sections: const [
              IdeaSection(id: 'c', name: 'Idea', content: 'x'),
            ],
          ),
          _cleanupIdea(
            id: 'renamed-section',
            sections: const [
              IdeaSection(id: 'r', name: 'Notes', content: ''),
            ],
          ),
          _cleanupIdea(
            id: 'two-sections',
            sections: const [
              IdeaSection(id: 'a', name: 'Idea', content: ''),
              IdeaSection(id: 'b', name: 'Untitled', content: ''),
            ],
          ),
          _cleanupIdea(id: 'no-sections', sections: const []),
          _cleanupIdea(id: 'locked', isLocked: true),
        ]);

        await service.runFreshInstallTasks();

        expect(
          await remainingIds(),
          unorderedEquals([
            'custom-title',
            'lowercase-title',
            'has-content',
            'renamed-section',
            'two-sections',
            'no-sections',
            'locked',
          ]),
        );
        expect(
          localStorage.getString(
            key: AppInstallBootstrapService.emptyIdeaCleanupFlagKey,
          ),
          'true',
        );
      });

      test('runs only once', () async {
        await service.runFreshInstallTasks();
        await ideasRepo.saveIdeas([_cleanupIdea(id: 'later-junk')]);

        await service.runFreshInstallTasks();

        expect(await remainingIds(), ['later-junk']);
      });

      test('matching helper rejects each failing criterion', () {
        expect(isLeftoverEmptyUntitledIdea(_cleanupIdea(id: 'a')), isTrue);
        expect(
          isLeftoverEmptyUntitledIdea(_cleanupIdea(id: 'b', title: 'Plan')),
          isFalse,
        );
        expect(
          isLeftoverEmptyUntitledIdea(_cleanupIdea(id: 'c', isLocked: true)),
          isFalse,
        );
        expect(
          isLeftoverEmptyUntitledIdea(
            _cleanupIdea(
              id: 'd',
              sections: const [
                IdeaSection(id: 'd1', name: 'Idea', content: 'text'),
              ],
            ),
          ),
          isFalse,
        );
      });
    });
  });
}
