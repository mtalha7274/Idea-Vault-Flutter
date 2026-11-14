import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/widgets/backup_restore_prompt_banner.dart';
import 'package:provider/provider.dart';

import '../helpers/backup_test_harness.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('BackupRestorePromptBanner', () {
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
      backupProvider = harness.buildProvider();
      await ideasProvider.ensureLoaded();
      await additionsProvider.ensureLoaded();
    }

    Future<void> pumpBanner(WidgetTester tester) async {
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
            home: const Scaffold(
              body: BackupRestorePromptBanner(),
            ),
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

    Future<void> showIosPrompt() async {
      putBackupFile(
        harness.store,
        ideas: [backupTestIdea('restored', title: 'Restored idea')],
      );
      await backupProvider.checkForFreshInstallBackup(hasLocalContent: false);
    }

    testWidgets('is hidden on iOS when no backup was found', (tester) async {
      await setUpHarness(isIOS: true);
      await pumpBanner(tester);

      expect(find.byKey(BackupRestorePromptBanner.bannerKey), findsNothing);
    });

    testWidgets('restores immediately on first tap when the vault is empty',
        (tester) async {
      await setUpHarness(isIOS: true);
      await showIosPrompt();
      await pumpBanner(tester);
      expect(find.text(ViewConstants.backupRestorePromptFound), findsOneWidget);

      await tester.tap(find.byKey(BackupRestorePromptBanner.restoreKey));
      await settleAsync(tester);

      expect(ideasProvider.ideas.single.title, 'Restored idea');
      expect(find.byKey(const Key('backup-action-sheet')), findsNothing);
      expect(find.byKey(BackupRestorePromptBanner.bannerKey), findsNothing);
    });

    testWidgets('dismiss hides the banner and is remembered', (tester) async {
      await setUpHarness(isIOS: true);
      await showIosPrompt();
      await pumpBanner(tester);

      await tester.tap(find.byKey(BackupRestorePromptBanner.dismissKey));
      await settleAsync(tester);

      expect(find.byKey(BackupRestorePromptBanner.bannerKey), findsNothing);
      expect(
        harness.buildProvider().restoreBannerKind(hasLocalContent: false),
        isNull,
      );
    });

    testWidgets('auto-hides as soon as a random note exists', (tester) async {
      await setUpHarness(isIOS: true);
      await showIosPrompt();
      await pumpBanner(tester);
      expect(find.byKey(BackupRestorePromptBanner.bannerKey), findsOneWidget);

      await tester.runAsync(() => additionsProvider.addAddition('A thought'));
      await settleAsync(tester);

      expect(find.byKey(BackupRestorePromptBanner.bannerKey), findsNothing);
      expect(backupProvider.state.restorePromptAvailable, isFalse);
    });

    testWidgets('keeps the banner and shows the reason when restore fails',
        (tester) async {
      await setUpHarness(isIOS: true);
      await showIosPrompt();
      harness.store.readError = const SocketException('offline');
      await pumpBanner(tester);

      await tester.tap(find.byKey(BackupRestorePromptBanner.restoreKey));
      await settleAsync(tester);

      expect(find.byKey(BackupRestorePromptBanner.bannerKey), findsOneWidget);
      expect(find.text(ViewConstants.backupErrorOffline), findsOneWidget);
      expect(ideasProvider.ideas, isEmpty);
    });

    testWidgets('Android shows a neutral one-time card on an empty vault',
        (tester) async {
      await setUpHarness(isIOS: false);
      await pumpBanner(tester);

      expect(find.text(ViewConstants.backupHavePrompt), findsOneWidget);
      expect(harness.store.listCount, 0);
    });

    testWidgets('Android card starts sign-in and restores the newest backup',
        (tester) async {
      await setUpHarness(isIOS: false);
      putBackupFile(
        harness.store,
        ideas: [backupTestIdea('cloud', title: 'From cloud')],
      );
      await pumpBanner(tester);

      await tester.tap(find.byKey(BackupRestorePromptBanner.restoreKey));
      await settleAsync(tester);

      expect(harness.store.connectCount, 1);
      expect(ideasProvider.ideas.single.title, 'From cloud');
      expect(backupProvider.state.enabled, isFalse);
    });

    testWidgets('Android card hides itself when no backup exists',
        (tester) async {
      await setUpHarness(isIOS: false);
      await pumpBanner(tester);

      await tester.tap(find.byKey(BackupRestorePromptBanner.restoreKey));
      await settleAsync(tester);

      expect(find.byKey(BackupRestorePromptBanner.bannerKey), findsNothing);
      expect(
        find.text(ViewConstants.backupRestoreNoBackupFound),
        findsOneWidget,
      );
    });

    testWidgets('is disabled while a backup or restore is running',
        (tester) async {
      await setUpHarness(isIOS: false);
      await pumpBanner(tester);
      final gate = Completer<void>();
      harness.store.listGate = gate.future;
      final pending = backupProvider.listRestoreEntries();
      await tester.pump();

      final button = tester.widget<TextButton>(
        find.byKey(BackupRestorePromptBanner.restoreKey),
      );
      expect(button.onPressed, isNull);
      gate.complete();
      await pending;
      await tester.pump();
      final enabled = tester.widget<TextButton>(
        find.byKey(BackupRestorePromptBanner.restoreKey),
      );
      expect(enabled.onPressed, isNotNull);
    });
  });
}
