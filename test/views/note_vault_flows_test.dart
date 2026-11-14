import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/core/services/note_lock_session_guard.dart';
import 'package:idea_vault/core/services/vault/note_vault_service.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/vault/vault_lock_block.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/idea_editor.dart';
import 'package:idea_vault/views/vault_recovery_code_screen.dart';
import 'package:idea_vault/widgets/note_lock_auth_dialog.dart';
import 'package:provider/provider.dart';

import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/memory_local_storage.dart';
import '../helpers/vault_test_env.dart';

const secretText = 'the launch code is swordfish';

void main() {
  dotenv.loadFromString(envString: 'DEBUG=false');
  GoogleFonts.config.allowRuntimeFetching = false;

  late VaultTestKeys keys;
  late InMemoryIdeasRepo ideasRepo;
  late InMemoryNoteVaultRepo vaultRepo;
  late NoteVaultService vault;
  late NoteLockAuthService authService;
  late NoteLockBiometricService biometricService;
  late IdeasProvider ideasProvider;
  late ThemeProvider themeProvider;
  late MemoryLocalStorageManager storage;
  late int biometricPrompts;
  late bool biometricsAvailable;

  Future<void> unregister() async {
    for (final unregisterType in [
      () async {
        if (sl.isRegistered<NoteLockAuthService>()) {
          await sl.unregister<NoteLockAuthService>();
        }
      },
      () async {
        if (sl.isRegistered<NoteLockBiometricService>()) {
          await sl.unregister<NoteLockBiometricService>();
        }
      },
      () async {
        if (sl.isRegistered<NoteVaultService>()) {
          await sl.unregister<NoteVaultService>();
        }
      },
    ]) {
      await unregisterType();
    }
  }

  setUp(() async {
    await unregister();
    NoteLockSecureWindow.resetForTesting();
    NoteLockSessionGuard.resetForTesting();
    keys = VaultTestKeys();
    ideasRepo = InMemoryIdeasRepo();
    vaultRepo = InMemoryNoteVaultRepo();
    storage = MemoryLocalStorageManager();
    vault = buildTestVault(
      vaultRepo: vaultRepo,
      ideasRepo: ideasRepo,
      keys: keys,
      preferences: storage,
    );
    authService = buildTestAuth(keys);
    biometricPrompts = 0;
    biometricsAvailable = false;
    biometricService = NoteLockBiometricService(
      readValue: keys.read,
      writeValue: keys.write,
      deleteValue: keys.delete,
      isDeviceSupported: () async => biometricsAvailable,
      canCheckBiometrics: () async => biometricsAvailable,
      authenticate: ({
        required String localizedReason,
        bool biometricOnly = false,
        bool persistAcrossBackgrounding = false,
      }) async {
        biometricPrompts += 1;
        return true;
      },
    );
    ideasProvider = IdeasProvider(
      ideasRepo,
      IdeaEditorStateRepo(storage),
      vault: vault,
    );
    themeProvider = ThemeProvider(ThemeRepo(storage));
    sl.registerSingleton<NoteLockAuthService>(authService);
    sl.registerSingleton<NoteLockBiometricService>(biometricService);
    sl.registerSingleton<NoteVaultService>(vault);
  });

  tearDown(unregister);

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 4; round++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpHost(WidgetTester tester, String ideaId) async {
    await tester.runAsync(ideasProvider.reloadFromStorage);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<IdeasProvider>.value(value: ideasProvider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          theme: themeProvider.baseTheme.themeData,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => authenticateAndOpenNote(
                  context,
                  authService,
                  biometricService,
                  ideaId: ideaId,
                  nextRoute: () => IdeaEditorScreen(ideaId: ideaId),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> enterDigits(WidgetTester tester, String digits) async {
    await tester.enterText(find.byType(TextField).last, digits);
    await settle(tester);
  }

  testWidgets('a reinstall with a restored vault only asks for the old PIN',
      (tester) async {
    await tester.runAsync(() async {
      await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
      await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));
      await vault.forgetCachedKey();
      await authService.clearPin();
    });
    await pumpHost(tester, 'a');

    await tester.tap(find.text('Open'));
    await settle(tester);

    expect(find.text(ViewConstants.vaultUnwrapTitle), findsWidgets);
    expect(find.text(ViewConstants.noteLockCreatePinTitle), findsNothing);
    expect(find.byKey(const Key('note-lock-toggle-passphrase')), findsNothing);

    await enterDigits(tester, '000000');
    expect(find.byKey(const Key('note-lock-pin-screen')), findsOneWidget);
    expect(find.text(ViewConstants.noteLockCreatePinTitle), findsNothing);

    await enterDigits(tester, '123456');

    expect(find.byKey(const Key('note-lock-pin-screen')), findsNothing);
    expect(find.text(secretText), findsOneWidget);
    expect(await tester.runAsync(authService.hasPin), isTrue);
    expect(await tester.runAsync(vault.state), NoteVaultState.ready);
    expect(
      ideasProvider.ideas.single.sections,
      isEmpty,
    );
  });

  testWidgets('an existing 4-digit PIN migrates on its next use',
      (tester) async {
    biometricsAvailable = true;
    await tester.runAsync(() async {
      await authService.createPin('2468');
      await biometricService.setBiometricUnlockEnabled(true);
      await ideasRepo.upsertIdea(vaultTestIdea('a'));
      await ideasRepo.upsertIdea(vaultTestIdea('b', content: 'second'));
    });
    await pumpHost(tester, 'a');

    await tester.tap(find.text('Open'));
    await settle(tester);

    expect(find.text(ViewConstants.vaultMigrationBody), findsOneWidget);
    expect(biometricPrompts, 0);

    await enterDigits(tester, '2468');

    expect(find.text(ViewConstants.vaultUpgradeTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('vault-upgrade-skip')));
    await settle(tester);

    expect(find.byKey(const Key('vault-recovery-code-screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('vault-recovery-code-saved')));
    await settle(tester);

    expect(find.text(secretText), findsOneWidget);
    final stored = await tester.runAsync(ideasRepo.getIdeas);
    expect(stored!.every((idea) => idea.isEncrypted), isTrue);
    expect(
      ideasProvider.ideas.every((idea) => idea.sections.isEmpty),
      isTrue,
    );
    final unlocked = await tester.runAsync(() async {
      await vault.forgetCachedKey();
      return vault.unlockWith('2468', VaultWrapKind.pin);
    });
    expect(unlocked, isTrue);
  });

  testWidgets('editing a locked note re-encrypts on autosave', (tester) async {
    await tester.runAsync(() async {
      await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
      await authService.createPin('123456', kind: NoteLockPinKind.digits6);
      await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));
    });
    await pumpHost(tester, 'a');
    await tester.tap(find.text('Open'));
    await settle(tester);
    await enterDigits(tester, '123456');
    expect(find.text(secretText), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('idea-editor-title')),
      'Renamed secret',
    );
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);

    final stored = (await tester.runAsync(ideasRepo.getIdeas))!.single;
    expect(stored.isEncrypted, isTrue);
    expect(stored.title, 'Renamed secret');
    expect(stored.toJson().toString(), isNot(contains(secretText)));
    final opened = await tester.runAsync(() => vault.decryptIdea(stored));
    expect(opened!.sections.single.content, secretText);
  });

  testWidgets('backgrounding saves, drops the content and asks again',
      (tester) async {
    await tester.runAsync(() async {
      await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
      await authService.createPin('123456', kind: NoteLockPinKind.digits6);
      await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));
    });
    await pumpHost(tester, 'a');
    await tester.tap(find.text('Open'));
    await settle(tester);
    await enterDigits(tester, '123456');
    expect(find.text(secretText), findsOneWidget);
    expect(vault.holdsKeyInMemory, isTrue);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);

    expect(find.text(secretText), findsNothing);
    expect(find.text(ViewConstants.noteLockEditorAction), findsOneWidget);
    expect(vault.holdsKeyInMemory, isFalse);
  });

  testWidgets('forgot PIN can delete all locked notes after two confirmations',
      (tester) async {
    await tester.runAsync(() async {
      await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
      await authService.createPin('123456', kind: NoteLockPinKind.digits6);
      await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));
      await ideasRepo.upsertIdea(vaultTestIdea('open', isLocked: false));
    });
    await pumpHost(tester, 'a');
    await tester.tap(find.text('Open'));
    await settle(tester);

    await tester.tap(find.byKey(const Key('note-lock-forgot-pin')));
    await settle(tester);
    expect(find.byKey(const Key('vault-forgot-recovery')), findsOneWidget);
    await tester.tap(find.byKey(const Key('vault-forgot-reset')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-reset-confirm')));
    await settle(tester);
    expect(find.text(ViewConstants.vaultResetFinalTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('vault-reset-final')));
    await settle(tester);

    expect(find.byKey(const Key('note-lock-pin-screen')), findsNothing);
    final remaining = await tester.runAsync(ideasRepo.getIdeas);
    expect(remaining!.map((idea) => idea.id), ['open']);
    expect(await tester.runAsync(authService.hasPin), isFalse);
    expect(await tester.runAsync(vault.state), NoteVaultState.none);
  });

  testWidgets('forgot PIN with the recovery code sets a new PIN',
      (tester) async {
    late String code;
    await tester.runAsync(() async {
      code = await vault.setUp(
        pin: '123456',
        pinKind: NoteLockPinKind.digits6,
      );
      await vault.forgetCachedKey();
      await ideasRepo.upsertIdea(await vault.encryptIdea(
        vaultTestIdea('a'),
        key: await vault.unwrapKey(
          (await vault.lockBlock())!,
          '123456',
          VaultWrapKind.pin,
        ),
        keyId: (await vault.lockBlock())!.keyId,
      ));
    });
    await pumpHost(tester, 'a');
    await tester.tap(find.text('Open'));
    await settle(tester);

    await tester.tap(find.byKey(const Key('note-lock-alternative-action')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('vault-recovery-entry-field')),
      code,
    );
    await tester.tap(find.byKey(const Key('vault-recovery-entry-submit')));
    await settle(tester);

    expect(find.text(ViewConstants.vaultNewPinTitle), findsWidgets);
    await enterDigits(tester, '424242');
    await enterDigits(tester, '424242');

    expect(find.text(secretText), findsOneWidget);
    final reopened = await tester.runAsync(() async {
      await vault.forgetCachedKey();
      return vault.unlockWith('424242', VaultWrapKind.pin);
    });
    expect(reopened, isTrue);
    expect(
        await tester.runAsync(() => authService.verifyPin('424242')), isTrue);
  });

  testWidgets('recovery code entry is rate limited', (tester) async {
    await tester.runAsync(() async {
      await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: themeProvider.baseTheme.themeData,
          home: VaultRecoveryCodeEntryScreen(
            authService: authService,
            verify: (code) => vault.unlockWith(code, VaultWrapKind.recovery),
          ),
        ),
      ),
    );
    await settle(tester);

    for (var attempt = 0; attempt < 5; attempt++) {
      await tester.enterText(
        find.byKey(const Key('vault-recovery-entry-field')),
        'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH',
      );
      await tester.tap(find.byKey(const Key('vault-recovery-entry-submit')));
      await settle(tester);
    }

    expect(find.byKey(const Key('vault-recovery-lockout')), findsOneWidget);
    final status = await tester.runAsync(authService.attemptStatus);
    expect(status!.isLockedOut, isTrue);
    final result = await tester.runAsync(
      () => authService.attemptWith(() async => true),
    );
    expect(result!.check, NoteLockPinCheck.lockedOut);
  });

  testWidgets('first lock sets up a 6-digit PIN and shows the recovery code',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<IdeasProvider>.value(value: ideasProvider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: themeProvider.baseTheme.themeData,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => ensureNoteLockReady(
                  context,
                  authService,
                  biometricService,
                ),
                child: const Text('Lock'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Lock'));
    await settle(tester);

    final dots = find.descendant(
      of: find.byKey(const Key('note-lock-pin-dots')),
      matching: find.byType(AnimatedContainer),
    );
    expect(dots, findsNWidgets(6));
    await enterDigits(tester, '135790');
    await enterDigits(tester, '135790');

    expect(find.byKey(const Key('vault-recovery-code-screen')), findsOneWidget);
    final shown = tester
        .widget<SelectableText>(
          find.byKey(const Key('vault-recovery-code-text')),
        )
        .data!;
    expect(shown.split('-'), hasLength(8));
    await tester.tap(find.byKey(const Key('vault-recovery-code-saved')));
    await settle(tester);

    expect(await tester.runAsync(vault.state), NoteVaultState.ready);
    final block = await tester.runAsync(vault.lockBlock);
    expect(block!.pinKind, NoteLockPinKind.digits6);
    final recovered = await tester.runAsync(() async {
      await vault.forgetCachedKey();
      return vault.unlockWith(shown, VaultWrapKind.recovery);
    });
    expect(recovered, isTrue);
  });

  testWidgets('a passphrase can be chosen instead of digits', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<IdeasProvider>.value(value: ideasProvider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: themeProvider.baseTheme.themeData,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => ensureNoteLockReady(
                  context,
                  authService,
                  biometricService,
                ),
                child: const Text('Lock'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Lock'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('note-lock-toggle-passphrase')));
    await settle(tester);

    final field = find.byKey(const Key('note-lock-passphrase-field'));
    await tester.enterText(field, 'short');
    await tester.tap(find.byKey(const Key('note-lock-passphrase-submit')));
    await settle(tester);
    expect(find.text(ViewConstants.vaultPassphraseTooShort), findsOneWidget);

    await tester.enterText(field, 'correct horse battery');
    await tester.tap(find.byKey(const Key('note-lock-passphrase-submit')));
    await settle(tester);
    await tester.enterText(field, 'correct horse battery');
    await tester.tap(find.byKey(const Key('note-lock-passphrase-submit')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-recovery-code-saved')));
    await settle(tester);

    expect(
        await tester.runAsync(authService.pinKind), NoteLockPinKind.passphrase);
    final unlocked = await tester.runAsync(() async {
      await vault.forgetCachedKey();
      return vault.unlockWith('correct horse battery', VaultWrapKind.pin);
    });
    expect(unlocked, isTrue);
  });

  test('hidden titles keep cards and search from showing the title', () async {
    await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
    await vault.setHideTitles(true);
    await ideasRepo.upsertIdea(vaultTestIdea('a', isLocked: false));
    await ideasProvider.reloadFromStorage();

    await ideasProvider.setIdeaLocked(ideaId: 'a', isLocked: true);

    final stored = ideasProvider.findById('a')!;
    expect(stored.titleHidden, isTrue);
    expect(stored.title, isEmpty);
    expect(stored.sections, isEmpty);
    final opened = await ideasProvider.openLockedIdea('a');
    expect(opened!.title, 'Secret plans');
    expect(ideasProvider.findById('a')!.title, isEmpty);
  });

  test('removing the lock decrypts back to normal sections', () async {
    await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
    await ideasRepo.upsertIdea(vaultTestIdea('a', isLocked: false));
    await ideasProvider.reloadFromStorage();
    await ideasProvider.setIdeaLocked(ideaId: 'a', isLocked: true);
    expect(ideasProvider.findById('a')!.isEncrypted, isTrue);
    expect(ideasRepo.compactCount, 1);

    await ideasProvider.setIdeaLocked(ideaId: 'a', isLocked: false);

    final idea = ideasProvider.findById('a')!;
    expect(idea.isEncrypted, isFalse);
    expect(idea.isLocked, isFalse);
    expect(idea.sections.single.content, secretText);
  });

  test('filing into a locked note decrypts, appends and re-encrypts', () async {
    await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
    await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));
    await ideasProvider.reloadFromStorage();

    final saved = await ideasProvider.appendContentToSection(
      ideaId: 'a',
      sectionId: 'section-a',
      content: 'extra thought',
    );

    expect(saved!.isEncrypted, isTrue);
    final opened = await ideasProvider.openLockedIdea('a');
    expect(opened!.sections.single.content, '$secretText\n\nextra thought');
    expect(ideasProvider.findById('a')!.sections, isEmpty);
  });

  test('locking another note needs no PIN once the vault exists', () async {
    await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
    vault.dropKey();
    await ideasRepo.upsertIdea(vaultTestIdea('b', isLocked: false));
    await ideasProvider.reloadFromStorage();

    await ideasProvider.setIdeaLocked(ideaId: 'b', isLocked: true);

    expect(ideasProvider.findById('b')!.isEncrypted, isTrue);
    expect(vault.holdsKeyInMemory, isFalse);
  });

  test('a saved locked idea never keeps plaintext in the provider', () async {
    await vault.setUp(pin: '123456', pinKind: NoteLockPinKind.digits6);
    await ideasRepo.upsertIdea(await vault.encryptIdea(vaultTestIdea('a')));
    await ideasProvider.reloadFromStorage();

    await ideasProvider.saveIdea(
      ideaId: 'a',
      title: 'Secret plans',
      sections: const [
        IdeaSection(id: 'section-a', name: 'Hidden part', content: 'new text'),
      ],
    );

    final inMemory = ideasProvider.ideas.single;
    expect(inMemory.sections, isEmpty);
    expect(inMemory.toJson().toString(), isNot(contains('new text')));
  });
}
