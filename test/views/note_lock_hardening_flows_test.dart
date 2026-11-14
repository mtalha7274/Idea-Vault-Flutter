import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/core/services/note_lock_session_guard.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/export_for_ai_screen.dart';
import 'package:idea_vault/views/random_additions_screen.dart';
import 'package:idea_vault/views/settings.dart';
import 'package:provider/provider.dart';

import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/in_memory_random_additions_repo.dart';
import '../helpers/memory_local_storage.dart';

void main() {
  dotenv.loadFromString(envString: 'DEBUG=false');
  GoogleFonts.config.allowRuntimeFetching = false;

  late Map<String, String> secureStorage;
  late NoteLockAuthService authService;
  late MemoryLocalStorageManager storage;
  late IdeasProvider ideasProvider;
  late RandomAdditionsProvider additionsProvider;
  late ThemeProvider themeProvider;
  late int biometricPrompts;

  Future<void> registerServices({
    required bool withPin,
    required bool biometricsAvailable,
  }) async {
    if (withPin) {
      await authService.createPin('2468');
    }
    final biometricService = NoteLockBiometricService(
      readValue: (key) async => secureStorage[key],
      writeValue: (key, value) async {
        secureStorage[key] = value;
      },
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
    sl.registerSingleton<NoteLockAuthService>(authService);
    sl.registerSingleton<NoteLockBiometricService>(biometricService);
  }

  setUp(() async {
    biometricPrompts = 0;
    secureStorage = {};
    authService = NoteLockAuthService(
      random: Random(1),
      readValue: (key) async => secureStorage[key],
      writeValue: (key, value) async {
        secureStorage[key] = value;
      },
      deleteValue: (key) async {
        secureStorage.remove(key);
      },
    );
    storage = MemoryLocalStorageManager();
    ideasProvider = IdeasProvider(
      InMemoryIdeasRepo(),
      IdeaEditorStateRepo(storage),
    );
    additionsProvider = RandomAdditionsProvider(InMemoryRandomAdditionsRepo());
    themeProvider = ThemeProvider(ThemeRepo(storage));
    await ideasProvider.ensureLoaded();
    await additionsProvider.ensureLoaded();
    NoteLockSecureWindow.resetForTesting();
    if (sl.isRegistered<NoteLockAuthService>()) {
      await sl.unregister<NoteLockAuthService>();
    }
    if (sl.isRegistered<NoteLockBiometricService>()) {
      await sl.unregister<NoteLockBiometricService>();
    }
  });

  tearDown(() async {
    if (sl.isRegistered<NoteLockAuthService>()) {
      await sl.unregister<NoteLockAuthService>();
    }
    if (sl.isRegistered<NoteLockBiometricService>()) {
      await sl.unregister<NoteLockBiometricService>();
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<IdeasProvider>.value(value: ideasProvider),
          ChangeNotifierProvider<RandomAdditionsProvider>.value(
            value: additionsProvider,
          ),
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
          home: home,
        ),
      ),
    );
    await settle(tester);
  }

  group('filing a random note into a locked idea', () {
    testWidgets('hides sections until the PIN is entered', (tester) async {
      await registerServices(withPin: true, biometricsAvailable: false);
      late Idea locked;
      late String additionId;
      await tester.runAsync(() async {
        locked = (await ideasProvider.saveIdea(
          title: 'Locked plans',
          sections: const [
            IdeaSection(id: 'secret-section', name: 'Hidden', content: 'Old'),
          ],
        ))!;
        await ideasProvider.setIdeaLocked(ideaId: locked.id, isLocked: true);
        additionId = (await additionsProvider.addAddition('Loose thought'))!.id;
      });
      await pumpApp(tester, const RandomAdditionsScreen());

      await tester.tap(find.byKey(Key('random-addition-bubble-$additionId')));
      await settle(tester);

      final ideaTile = find.byKey(Key('random-addition-idea-${locked.id}'));
      expect(ideaTile, findsOneWidget);
      expect(
        find.descendant(
          of: ideaTile,
          matching: find.byIcon(Icons.lock_outline_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.text(ViewConstants.noteLockPickerLockedSubtitle),
        findsOneWidget,
      );

      await tester.tap(ideaTile);
      await settle(tester);

      expect(find.byKey(const Key('note-lock-pin-screen')), findsOneWidget);
      expect(find.text('Hidden'), findsNothing);

      await tester.enterText(find.byType(TextField).last, '2468');
      await settle(tester);

      expect(find.byKey(const Key('note-lock-pin-screen')), findsNothing);
      await tester
          .tap(find.byKey(const Key('random-addition-section-secret-section')));
      await settle(tester);

      expect(additionsProvider.additions, isEmpty);
      expect(
        ideasProvider.findById(locked.id)!.sections.single.content,
        'Old\n\nLoose thought',
      );
      expect(authService.isIdeaUnlocked(locked.id), isFalse);
    });

    testWidgets('cancelling the PIN keeps the note in the inbox',
        (tester) async {
      await registerServices(withPin: true, biometricsAvailable: false);
      late Idea locked;
      late String additionId;
      await tester.runAsync(() async {
        locked = (await ideasProvider.saveIdea(
          title: 'Locked plans',
          sections: const [
            IdeaSection(id: 'secret-section', name: 'Hidden', content: 'Old'),
          ],
        ))!;
        await ideasProvider.setIdeaLocked(ideaId: locked.id, isLocked: true);
        additionId = (await additionsProvider.addAddition('Keep me'))!.id;
      });
      await pumpApp(tester, const RandomAdditionsScreen());

      await tester.tap(find.byKey(Key('random-addition-bubble-$additionId')));
      await settle(tester);
      await tester.tap(find.byKey(Key('random-addition-idea-${locked.id}')));
      await settle(tester);

      Navigator.of(
        tester.element(find.byKey(const Key('note-lock-pin-screen'))),
      ).pop(false);
      await settle(tester);

      expect(find.text('Hidden'), findsNothing);
      expect(additionsProvider.additions, hasLength(1));
    });
  });

  group('export screen for a locked note', () {
    Widget host({required bool isLocked}) {
      return Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open-export'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExportForAIScreen(
                    ideaTitle: 'Secret',
                    sections: const [
                      IdeaSection(id: 's', name: 'Hidden', content: 'Body'),
                    ],
                    mode: ExportMode.pdfExport,
                    isLocked: isLocked,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
    }

    const toBackground = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    const toForeground = [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ];

    void sendLifecycle(WidgetTester tester, List<AppLifecycleState> states) {
      for (final state in states) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    setUp(NoteLockSessionGuard.resetForTesting);

    testWidgets('holds the secure window and re-locks on pause',
        (tester) async {
      await registerServices(withPin: true, biometricsAvailable: false);
      authService.markIdeaUnlocked('idea-x');
      await pumpApp(tester, host(isLocked: true));
      await tester.tap(find.byKey(const Key('open-export')));
      await settle(tester);

      expect(find.text('Hidden'), findsOneWidget);
      expect(NoteLockSecureWindow.isSecure, isTrue);

      sendLifecycle(tester, toBackground);
      await settle(tester);
      sendLifecycle(tester, toForeground);
      await settle(tester);

      expect(authService.isIdeaUnlocked('idea-x'), isFalse);
      expect(find.text('Hidden'), findsNothing);
      expect(find.byKey(const Key('open-export')), findsOneWidget);
      expect(NoteLockSecureWindow.isSecure, isFalse);
    });

    testWidgets('stays open while the print dialog is in front',
        (tester) async {
      await registerServices(withPin: true, biometricsAvailable: false);
      authService.markIdeaUnlocked('idea-x');
      await pumpApp(tester, host(isLocked: true));
      await tester.tap(find.byKey(const Key('open-export')));
      await settle(tester);

      await NoteLockSessionGuard.runWithoutRelock(() async {
        sendLifecycle(tester, toBackground);
        sendLifecycle(tester, toForeground);
      });
      await settle(tester);

      expect(authService.isIdeaUnlocked('idea-x'), isTrue);
      expect(find.text('Hidden'), findsOneWidget);
      expect(NoteLockSecureWindow.isSecure, isTrue);
    });

    testWidgets('an open note export does not use the secure window',
        (tester) async {
      await registerServices(withPin: true, biometricsAvailable: false);
      await pumpApp(tester, host(isLocked: false));
      await tester.tap(find.byKey(const Key('open-export')));
      await settle(tester);

      expect(NoteLockSecureWindow.isSecure, isFalse);
      sendLifecycle(tester, toBackground);
      await settle(tester);
      sendLifecycle(tester, toForeground);
      await settle(tester);
      expect(find.text('Hidden'), findsOneWidget);
    });
  });

  group('settings biometric toggle', () {
    testWidgets('is hidden without a PIN', (tester) async {
      await registerServices(withPin: false, biometricsAvailable: true);
      await pumpApp(tester, const Settings());

      expect(find.byKey(const Key('settings-biometric-toggle')), findsNothing);
    });

    testWidgets('is hidden when biometrics are unavailable', (tester) async {
      await registerServices(withPin: true, biometricsAvailable: false);
      await pumpApp(tester, const Settings());

      expect(find.byKey(const Key('settings-biometric-toggle')), findsNothing);
    });

    testWidgets('turning it on needs the PIN, turning it off does not',
        (tester) async {
      await registerServices(withPin: true, biometricsAvailable: true);
      await pumpApp(tester, const Settings());

      final toggle = find.byKey(const Key('settings-biometric-toggle'));
      expect(toggle, findsOneWidget);
      expect(tester.widget<Switch>(toggle).value, isFalse);

      await tester.tap(toggle);
      await settle(tester);

      expect(find.byKey(const Key('note-lock-pin-screen')), findsOneWidget);
      expect(biometricPrompts, 0);

      await tester.enterText(find.byType(TextField), '2468');
      await settle(tester);

      expect(biometricPrompts, 1);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(secureStorage['note_lock_biometric_enabled'], 'true');

      await tester.tap(toggle);
      await settle(tester);

      expect(find.byKey(const Key('note-lock-pin-screen')), findsNothing);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(secureStorage['note_lock_biometric_enabled'], 'false');
    });
  });
}
