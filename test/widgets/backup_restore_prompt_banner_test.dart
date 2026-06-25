import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_scheduler.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/data/repositories/local/cloud_backup_settings.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/backup/cloud_backup_snapshot.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/widgets/backup_restore_prompt_banner.dart';
import 'package:provider/provider.dart';

import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/in_memory_random_additions_repo.dart';
import '../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('BackupRestorePromptBanner', () {
    late MemoryLocalStorageManager storage;
    late IdeasProvider ideasProvider;
    late RandomAdditionsProvider additionsProvider;
    late ThemeProvider themeProvider;
    late _FakeCloudBackupService backupService;
    late CloudBackupProvider backupProvider;

    final restoredIdea = Idea(
      id: 'restored-idea',
      title: 'Restored idea',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      sections: const [],
    );

    setUp(() async {
      storage = MemoryLocalStorageManager();
      ideasProvider = IdeasProvider(
        InMemoryIdeasRepo(),
        IdeaEditorStateRepo(storage),
      );
      additionsProvider = RandomAdditionsProvider(
        InMemoryRandomAdditionsRepo(),
      );
      themeProvider = ThemeProvider(ThemeRepo(storage));
      backupService = _FakeCloudBackupService();
      backupProvider = CloudBackupProvider(
        CloudBackupSettingsRepo(storage),
        backupService,
        _FakeCloudBackupScheduler(),
      );
      await ideasProvider.ensureLoaded();
      await additionsProvider.ensureLoaded();
    });

    Future<void> showPrompt() async {
      backupService.backupExistsResult = true;
      await backupProvider.checkForFreshInstallBackup(hasLocalIdeas: false);
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

    Future<void> settleAsyncAction(WidgetTester tester) async {
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 20; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (!backupProvider.state.restorePromptAvailable ||
              find
                  .text(ViewConstants.backupRestoreNoBackupFound)
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
    }

    testWidgets('is hidden when restore prompt is unavailable', (tester) async {
      await pumpBanner(tester);

      expect(find.text(ViewConstants.backupRestorePromptFound), findsNothing);
    });

    testWidgets('restores backup and dismisses prompt on first tap',
        (tester) async {
      await showPrompt();
      backupService.restoreSnapshotResult = CloudBackupSnapshot.fromIdeas([
        restoredIdea,
      ]);
      await pumpBanner(tester);

      await tester
          .tap(find.text(ViewConstants.backupRestoreConfirmRestoreButton));
      await settleAsyncAction(tester);

      expect(ideasProvider.ideas.single.title, 'Restored idea');
      expect(backupService.restoreSnapshotCount, 1);
    });

    testWidgets(
        'keeps prompt visible and shows feedback when backup is missing',
        (tester) async {
      await showPrompt();
      backupService.restoreSnapshotResult = null;
      await pumpBanner(tester);

      await tester
          .tap(find.text(ViewConstants.backupRestoreConfirmRestoreButton));
      await settleAsyncAction(tester);

      expect(backupProvider.state.restorePromptAvailable, isTrue);
      expect(find.text(ViewConstants.backupRestorePromptFound), findsOneWidget);
      expect(
          find.text(ViewConstants.backupRestoreNoBackupFound), findsOneWidget);
      expect(ideasProvider.ideas, isEmpty);
    });
  });
}

class _FakeCloudBackupService extends CloudBackupService {
  bool backupExistsResult = false;
  CloudBackupSnapshot? restoreSnapshotResult;
  int restoreSnapshotCount = 0;

  @override
  Future<bool> backupExists() async => backupExistsResult;

  @override
  Future<CloudBackupSnapshot?> restoreSnapshot() async {
    restoreSnapshotCount += 1;
    return restoreSnapshotResult;
  }
}

class _FakeCloudBackupScheduler extends CloudBackupScheduler {
  @override
  Future<void> cancelDailyBackup() async {}

  @override
  Future<void> scheduleDailyBackup() async {}
}
