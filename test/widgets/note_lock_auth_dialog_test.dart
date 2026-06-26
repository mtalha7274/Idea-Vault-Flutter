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
import 'package:idea_vault/widgets/note_lock_auth_dialog.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('authenticateAndOpenNote', () {
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

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: themeProvider.baseTheme.themeData,
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      await authenticateAndOpenNote(
                        context,
                        authService,
                        biometricService,
                        ideaId: 'idea-1',
                        nextRoute: () => const Scaffold(
                          body: Text('Opened locked note'),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    testWidgets('sets up PIN and opens locked note immediately',
        (tester) async {
      await pumpHost(tester);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text(ViewConstants.noteLockCreatePinTitle), findsWidgets);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.pumpAndSettle();
      await tester.tap(find.text(ViewConstants.noteLockEnableBiometricSkip));
      await tester.pumpAndSettle();

      expect(find.text('Opened locked note'), findsOneWidget);
      expect(authService.isIdeaUnlocked('idea-1'), isTrue);

      Navigator.of(tester.element(find.text('Opened locked note'))).pop();
      await tester.pumpAndSettle();

      expect(authService.isIdeaUnlocked('idea-1'), isFalse);
    });
  });
}
