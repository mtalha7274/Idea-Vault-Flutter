import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/backup/cloud_backup_state.dart';
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/backup_restore_screen.dart';
import 'package:provider/provider.dart';

import '../helpers/backup_test_harness.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('BackupRestoreScreen', () {
    late BackupTestHarness harness;
    late IdeasProvider ideasProvider;
    late RandomAdditionsProvider additionsProvider;
    late ThemeProvider themeProvider;
    late CloudBackupProvider backupProvider;

    Future<void> setUpHarness({required bool isIOS}) async {
      harness = BackupTestHarness(isIOS: isIOS);
      ideasProvider = IdeasProvider(
        harness.vault.memoryIdeasRepo,
        IdeaEditorStateRepo(harness.storage),
      );
      additionsProvider = RandomAdditionsProvider(
        harness.vault.memoryAdditionsRepo,
      );
      themeProvider = ThemeProvider(ThemeRepo(harness.storage));
      await ideasProvider.ensureLoaded();
      await additionsProvider.ensureLoaded();
    }

    Future<void> pumpScreen(WidgetTester tester) async {
      backupProvider = harness.buildProvider();
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<IdeasProvider>.value(value: ideasProvider),
            ChangeNotifierProvider<RandomAdditionsProvider>.value(
              value: additionsProvider,
            ),
            ChangeNotifierProvider<CloudBackupProvider>.value(
              value: backupProvider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: themeProvider.baseTheme.themeData,
            home: const BackupRestoreScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> settleAsync(WidgetTester tester) async {
      for (var attempt = 0; attempt < 5; attempt++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('restore is available while cloud backup is off',
        (tester) async {
      await setUpHarness(isIOS: false);
      putBackupFile(harness.store, ideas: [backupTestIdea('cloud')]);
      await pumpScreen(tester);

      final restoreButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('backup-restore-button')),
      );
      expect(restoreButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('backup-restore-button')));
      await settleAsync(tester);

      expect(find.byKey(const Key('backup-picker-sheet')), findsOneWidget);
      expect(backupProvider.state.enabled, isFalse);
    });

    testWidgets('iOS account row shows iCloud without a change button',
        (tester) async {
      await setUpHarness(isIOS: true);
      await harness.settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          remoteStateResolved: true,
        ),
      );
      await pumpScreen(tester);

      expect(find.text(ViewConstants.backupIcloudAccountTitle), findsOneWidget);
      expect(find.byKey(const Key('backup-change-account')), findsNothing);
      expect(find.text(ViewConstants.backupRestoreGoogleAccount), findsNothing);
    });

    testWidgets('turning backup off asks first and keeps cloud backups',
        (tester) async {
      await setUpHarness(isIOS: false);
      final name = putBackupFile(harness.store, ideas: [backupTestIdea('c')]);
      await harness.settingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          remoteStateResolved: true,
          email: 'writer@example.com',
        ),
      );
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('backup-cloud-toggle')));
      await tester.pumpAndSettle();
      expect(find.text(ViewConstants.backupTurnOffBody), findsOneWidget);

      await tester.tap(find.byKey(const Key('backup-confirm-accept')));
      await settleAsync(tester);

      expect(backupProvider.state.enabled, isFalse);
      expect(harness.store.fileNames, [name]);
      expect(harness.store.signOutCount, 1);
    });

    testWidgets('delete cloud backups needs two confirmations',
        (tester) async {
      await setUpHarness(isIOS: false);
      putBackupFile(harness.store, ideas: [backupTestIdea('c')]);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('backup-delete-cloud')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('backup-confirm-accept')));
      await tester.pumpAndSettle();
      expect(harness.store.files, isNotEmpty);
      expect(
        find.text(ViewConstants.backupDeleteCloudConfirmBody),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('backup-delete-cloud-final')));
      await settleAsync(tester);

      expect(harness.store.files, isEmpty);
    });

    testWidgets('enabling with an existing backup shows the choice sheet',
        (tester) async {
      await setUpHarness(isIOS: false);
      putBackupFile(harness.store, ideas: [backupTestIdea('cloud')]);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('backup-cloud-toggle')));
      await settleAsync(tester);

      expect(find.byKey(const Key('backup-choice-restore')), findsOneWidget);
      expect(find.byKey(const Key('backup-choice-start-fresh')), findsOneWidget);

      await tester.tap(find.byKey(const Key('backup-sheet-cancel')));
      await settleAsync(tester);

      expect(backupProvider.state.enabled, isFalse);
      expect(harness.store.writeCount, 0);
    });
  });
}
