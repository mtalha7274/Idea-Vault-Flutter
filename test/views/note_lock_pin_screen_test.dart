import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/note_lock_pin_screen.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('NoteLockPinScreen', () {
    late Map<String, String> storage;
    late NoteLockAuthService authService;
    late NoteLockBiometricService biometricService;
    late ThemeProvider themeProvider;

    setUp(() {
      storage = <String, String>{};
      authService = NoteLockAuthService(
        random: Random(1),
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
      );
      biometricService = NoteLockBiometricService(
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        isDeviceSupported: () async => true,
        canCheckBiometrics: () async => true,
        authenticate: ({
          required String localizedReason,
          bool biometricOnly = false,
          bool persistAcrossBackgrounding = false,
        }) async =>
            false,
      );
      themeProvider = ThemeProvider(ThemeRepo(MemoryLocalStorageManager()));
    });

    Future<void> pumpPinScreen(
      WidgetTester tester,
      NoteLockPinMode mode, {
      NoteLockBiometricService? overrideBiometricService,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: themeProvider.baseTheme.themeData,
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => NoteLockPinScreen(
                              mode: mode,
                              authService: authService,
                              biometricService:
                                  overrideBiometricService ?? biometricService,
                            ),
                          ),
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('sets up a 4 digit PIN with confirmation', (tester) async {
      await pumpPinScreen(tester, NoteLockPinMode.setup);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pumpAndSettle();

      expect(find.text(ViewConstants.noteLockConfirmPinTitle), findsWidgets);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pumpAndSettle();

      expect(find.text(ViewConstants.noteLockEnableBiometricTitle),
          findsOneWidget);
      await tester.tap(find.text(ViewConstants.noteLockEnableBiometricSkip));
      await tester.pumpAndSettle();

      expect(await authService.verifyPin('1234'), isTrue);
      expect(find.byKey(const Key('note-lock-pin-screen')), findsNothing);
    });

    testWidgets('unlocks automatically after 4 correct digits', (tester) async {
      await authService.createPin('2468');
      await pumpPinScreen(tester, NoteLockPinMode.unlock);

      await tester.enterText(find.byType(TextField), '1357');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-lock-pin-screen')), findsOneWidget);

      await tester.enterText(find.byType(TextField), '2468');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-lock-pin-screen')), findsNothing);
    });

    testWidgets('shows enable biometric button when enrollment is available',
        (tester) async {
      await authService.createPin('2468');
      await pumpPinScreen(tester, NoteLockPinMode.unlock);

      expect(
        find.text(ViewConstants.noteLockEnableBiometricUnlockAction),
        findsOneWidget,
      );
    });

    testWidgets('does not auto-focus keyboard when biometric auth is canceled',
        (tester) async {
      await authService.createPin('2468');
      await biometricService.setBiometricUnlockEnabled(true);

      await pumpPinScreen(tester, NoteLockPinMode.unlock);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-lock-pin-screen')), findsOneWidget);

      final focusNode =
          tester.widget<TextField>(find.byType(TextField)).focusNode;
      expect(focusNode?.hasFocus, isFalse);

      await tester.tap(find.byKey(const Key('note-lock-pin-dots')));
      await tester.pump();

      expect(focusNode?.hasFocus, isTrue);
    });

    testWidgets('fills all PIN dots before navigating on biometric success',
        (tester) async {
      await authService.createPin('2468');
      await biometricService.setBiometricUnlockEnabled(true);

      final successBiometricService = NoteLockBiometricService(
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        isDeviceSupported: () async => true,
        canCheckBiometrics: () async => true,
        authenticate: ({
          required String localizedReason,
          bool biometricOnly = false,
          bool persistAcrossBackgrounding = false,
        }) async =>
            true,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: themeProvider.baseTheme.themeData,
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => NoteLockPinScreen(
                              mode: NoteLockPinMode.unlock,
                              authService: authService,
                              biometricService: successBiometricService,
                            ),
                          ),
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('note-lock-pin-dots')), findsOneWidget);

      final dotFinder = find.descendant(
        of: find.byKey(const Key('note-lock-pin-dots')),
        matching: find.byType(AnimatedContainer),
      );
      expect(dotFinder, findsNWidgets(4));

      for (var index = 0; index < 4; index++) {
        final dot = tester.widget<AnimatedContainer>(dotFinder.at(index));
        final decoration = dot.decoration! as BoxDecoration;
        expect(decoration.color, isNot(Colors.transparent));
      }

      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-lock-pin-screen')), findsNothing);
    });
  });
}
