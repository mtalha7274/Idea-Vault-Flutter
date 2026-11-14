import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/core/services/backup/initial_cloud_auth_coordinator.dart';
import 'package:idea_vault/data/repositories/local/app_install_state.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/data/repositories/local/cloud_backup_settings.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/idea_list_preferences.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/models/backup/cloud_backup_error.dart';
import 'package:idea_vault/models/backup/cloud_backup_state.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/homepage.dart';
import 'package:idea_vault/widgets/selection/selection_check_badge.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../helpers/backup_test_harness.dart';
import '../helpers/fake_cloud_backup_store.dart';
import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/in_memory_random_additions_repo.dart';
import '../helpers/memory_local_storage.dart';

void main() {
  dotenv.loadFromString(envString: 'DEBUG=false');
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Homepage ideas flow', () {
    late MemoryLocalStorageManager storage;
    late IdeasProvider provider;
    late RandomAdditionsProvider randomAdditionsProvider;
    late ThemeProvider themeProvider;
    late IdeaListPreferencesRepo sortPreferencesRepo;

    setUpAll(() {
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
    });

    setUp(() async {
      storage = MemoryLocalStorageManager();
      sortPreferencesRepo = IdeaListPreferencesRepo(storage);
      if (sl.isRegistered<IdeaListPreferencesRepo>()) {
        await sl.unregister<IdeaListPreferencesRepo>();
      }
      sl.registerSingleton<IdeaListPreferencesRepo>(sortPreferencesRepo);
      themeProvider = ThemeProvider(ThemeRepo(storage));
      provider = IdeasProvider(
        InMemoryIdeasRepo(),
        IdeaEditorStateRepo(storage),
      );
      randomAdditionsProvider = RandomAdditionsProvider(
        InMemoryRandomAdditionsRepo(),
      );
      await provider.ensureLoaded();
      await randomAdditionsProvider.ensureLoaded();
    });

    Future<void> settleUi(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
    }

    Future<void> settlePersistenceAction(WidgetTester tester) async {
      await settleUi(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await settleUi(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await settleUi(tester);
    }

    Future<void> pumpIdeasApp(
      WidgetTester tester, {
      CloudBackupProvider? backupProvider,
    }) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<IdeasProvider>.value(value: provider),
            ChangeNotifierProvider<RandomAdditionsProvider>.value(
              value: randomAdditionsProvider,
            ),
            if (backupProvider != null)
              ChangeNotifierProvider<CloudBackupProvider>.value(
                value: backupProvider,
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
            home: Homepage(sortPreferencesRepo: sortPreferencesRepo),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await settleUi(tester);
    }

    CloudBackupProvider buildCloudBackupProvider({
      FakeCloudBackupStore? store,
      bool isIOS = false,
    }) {
      final cloudStore = store ?? FakeCloudBackupStore();
      return CloudBackupProvider(
        CloudBackupSettingsRepo(storage),
        CloudBackupService(
          androidStore: cloudStore,
          iosStore: cloudStore,
          useICloud: isIOS,
        ),
        FakeCloudBackupScheduler(),
        InitialCloudAuthCoordinator(AppInstallStateRepo(storage)),
        isIOS: isIOS,
      );
    }

    Future<NoteLockAuthService> registerNoteLockServices({
      bool withPin = false,
    }) async {
      final pinStorage = <String, String>{};
      final authService = NoteLockAuthService(
        random: Random(1),
        readValue: (key) async => pinStorage[key],
        writeValue: (key, value) async {
          pinStorage[key] = value;
        },
      );
      if (withPin) {
        await authService.createPin('1234');
      }
      final biometricService = NoteLockBiometricService(
        readValue: (key) async => pinStorage[key],
        writeValue: (key, value) async {
          pinStorage[key] = value;
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
      if (sl.isRegistered<NoteLockAuthService>()) {
        await sl.unregister<NoteLockAuthService>();
      }
      if (sl.isRegistered<NoteLockBiometricService>()) {
        await sl.unregister<NoteLockBiometricService>();
      }
      sl.registerSingleton<NoteLockAuthService>(authService);
      sl.registerSingleton<NoteLockBiometricService>(biometricService);
      addTearDown(() async {
        if (sl.isRegistered<NoteLockAuthService>()) {
          await sl.unregister<NoteLockAuthService>();
        }
        if (sl.isRegistered<NoteLockBiometricService>()) {
          await sl.unregister<NoteLockBiometricService>();
        }
      });
      return authService;
    }

    bool appearsBefore(WidgetTester tester, String firstId, String secondId) {
      final first = tester.getTopLeft(find.byKey(Key('idea-card-$firstId')));
      final second = tester.getTopLeft(find.byKey(Key('idea-card-$secondId')));
      if ((first.dy - second.dy).abs() > 1) {
        return first.dy < second.dy;
      }
      return first.dx < second.dx;
    }

    Finder sectionTab(IdeaSection section) {
      return find.byKey(Key('idea-editor-section-tab-${section.id}'));
    }

    Future<void> openRandomAdditionsFromDrawer(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('ideas-menu-button')));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('random-additions-drawer')));
      await settleUi(tester);
    }

    testWidgets('shows the empty state, its create button and the top bar',
        (tester) async {
      await pumpIdeasApp(tester);

      expect(find.byKey(const Key('ideas-empty-state')), findsOneWidget);
      expect(
          find.byKey(const Key('ideas-empty-create-button')), findsOneWidget);
      expect(find.byKey(const Key('ideas-new-idea-button')), findsOneWidget);
      expect(find.byKey(const Key('ideas-search-button')), findsOneWidget);
      expect(find.byKey(const Key('ideas-sort-button')), findsOneWidget);
      expect(find.byKey(const Key('ideas-more-menu')), findsNothing);
      expect(find.byKey(const Key('ideas-fab')), findsNothing);
      expect(find.byKey(const Key('home-quick-note-button')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      final title = tester.widget<Text>(
        find.byKey(const Key('ideas-home-title')),
      );
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(title.style?.fontSize, 22);

      final plusSize =
          tester.getSize(find.byKey(const Key('ideas-new-idea-button')));
      expect(plusSize.width, greaterThanOrEqualTo(48));
      expect(plusSize.height, greaterThanOrEqualTo(48));
      expect(find.byTooltip(ViewConstants.homepageFabNewIdea), findsOneWidget);
    });

    testWidgets('empty state create button opens the editor', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-empty-create-button')));
      await settleUi(tester);

      expect(find.byKey(const Key('idea-editor-title')), findsOneWidget);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);
    });

    testWidgets('double tapping the plus opens only one editor',
        (tester) async {
      await pumpIdeasApp(tester);

      final plus = tester.widget<IconButton>(
        find.byKey(const Key('ideas-new-idea-button')),
      );
      plus.onPressed!.call();
      plus.onPressed!.call();
      await settleUi(tester);

      expect(find.byKey(const Key('idea-editor-title')), findsOneWidget);
      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('idea-editor-title')), findsNothing);
      expect(find.byKey(const Key('ideas-new-idea-button')), findsOneWidget);
    });

    testWidgets('top bar fits a narrow phone with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpIdeasApp(tester);

      expect(tester.takeException(), isNull);
      final plus =
          tester.getRect(find.byKey(const Key('ideas-new-idea-button')));
      final sort = tester.getRect(find.byKey(const Key('ideas-sort-button')));
      final search =
          tester.getRect(find.byKey(const Key('ideas-search-button')));
      expect(plus.right, lessThanOrEqualTo(320));
      expect((plus.center.dy - sort.center.dy).abs(), lessThan(1));
      expect((plus.center.dy - search.center.dy).abs(), lessThan(1));
    });

    testWidgets('hides backup-off indicator without backup provider',
        (tester) async {
      await pumpIdeasApp(tester);

      expect(
        find.byKey(const Key('homepage-backup-off-indicator')),
        findsNothing,
      );
    });

    testWidgets('shows backup-off indicator when backup is disabled',
        (tester) async {
      await pumpIdeasApp(tester, backupProvider: buildCloudBackupProvider());

      expect(
        find.byKey(const Key('homepage-backup-off-indicator')),
        findsOneWidget,
      );
      expect(find.text('homepageBackupOffIndicator'), findsOneWidget);
      expect(find.text('homepageBackupOffAction'), findsOneWidget);
    });

    testWidgets('hides restore prompt when no backup is available',
        (tester) async {
      await pumpIdeasApp(
        tester,
        backupProvider: buildCloudBackupProvider(isIOS: true),
      );

      expect(find.text(ViewConstants.backupRestorePromptFound), findsNothing);
      expect(
        find.byKey(const Key('homepage-backup-off-indicator')),
        findsOneWidget,
      );
    });

    testWidgets(
        'shows restore prompt with backup-off indicator when backup exists',
        (tester) async {
      final store = FakeCloudBackupStore();
      putBackupFile(store, ideas: [backupTestIdea('cloud')]);

      await pumpIdeasApp(
        tester,
        backupProvider: buildCloudBackupProvider(store: store, isIOS: true),
      );

      expect(find.text(ViewConstants.backupRestorePromptFound), findsOneWidget);
      expect(
        find.byKey(const Key('homepage-backup-off-indicator')),
        findsOneWidget,
      );
    });

    testWidgets('shows the neutral restore card on an empty Android vault',
        (tester) async {
      final store = FakeCloudBackupStore();

      await pumpIdeasApp(
        tester,
        backupProvider: buildCloudBackupProvider(store: store),
      );

      expect(find.text(ViewConstants.backupHavePrompt), findsOneWidget);
      expect(find.text(ViewConstants.backupRestorePromptFound), findsNothing);
      expect(store.listCount, 0);
    });

    testWidgets('shows backup needs attention when sign-in is required',
        (tester) async {
      await CloudBackupSettingsRepo(storage).saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          remoteStateResolved: true,
          email: 'writer@example.com',
          lastBackupAt: DateTime.now(),
          status: CloudBackupStatus(
            lastBackupAt: DateTime.now().subtract(const Duration(hours: 2)),
            lastAttemptAt: DateTime.now(),
            lastErrorType: CloudBackupErrorType.signInRequired,
            consecutiveFailures: 1,
            firstFailureAt: DateTime.now(),
          ),
        ),
      );

      await pumpIdeasApp(tester, backupProvider: buildCloudBackupProvider());

      expect(
        find.byKey(const Key('homepage-backup-attention-indicator')),
        findsOneWidget,
      );
      expect(find.text(ViewConstants.backupNeedsAttention), findsOneWidget);
      expect(
        find.byKey(const Key('homepage-backup-off-indicator')),
        findsNothing,
      );
    });

    testWidgets('hides backup-off indicator when backup is enabled',
        (tester) async {
      await CloudBackupSettingsRepo(storage).saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          remoteStateResolved: true,
          email: 'writer@example.com',
          lastBackupAt: DateTime.now(),
        ),
      );

      await pumpIdeasApp(tester, backupProvider: buildCloudBackupProvider());

      expect(
        find.byKey(const Key('homepage-backup-off-indicator')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('homepage-backup-attention-indicator')),
        findsNothing,
      );
    });

    testWidgets('opens the editor from the top bar plus', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('idea-editor-title')), findsOneWidget);
      expect(find.byKey(const Key('idea-editor-save')), findsNothing);
      expect(find.byKey(const Key('idea-markdown-text-field')), findsOneWidget);
      expect(find.byKey(const Key('idea-editor-add-section')), findsOneWidget);

      final titleField = tester.widget<TextField>(
        find.byKey(const Key('idea-editor-title')),
      );
      expect(titleField.autofocus, isTrue);
      expect(titleField.controller?.text, isEmpty);
      expect(provider.ideas, isEmpty);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);
      expect(provider.ideas, isEmpty);
    });

    testWidgets('autosaves a new idea and returns to the list', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Solar Rooftop Co-op',
      );
      await tester.pump();
      final titleField = tester.widget<TextField>(
        find.byKey(const Key('idea-editor-title')),
      );
      expect(titleField.controller?.text, 'Solar Rooftop Co-op');

      await settlePersistenceAction(tester);
      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);

      expect(find.text('Solar Rooftop Co-op'), findsOneWidget);
      expect(find.text('homepageIdeaCardOneSection'), findsOneWidget);
      expect(provider.ideas, hasLength(1));
    });

    testWidgets('autosaves an untitled draft when title is empty',
        (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'A title can come later.',
      );
      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);

      expect(provider.ideas, hasLength(1));
      expect(provider.ideas.single.title, 'ideaEditorUntitledIdea');
    });

    testWidgets('opens an existing idea with populated data', (tester) async {
      await tester.runAsync(() async {
        await provider.saveIdea(
          title: 'Existing Idea',
          sections: provider.createDefaultSections(),
        );
      });

      await pumpIdeasApp(tester);

      await tester.tap(find.text('Existing Idea'));
      await settleUi(tester);

      final titleField = tester.widget<TextField>(
        find.byKey(const Key('idea-editor-title')),
      );

      expect(titleField.controller?.text, 'Existing Idea');
      expect(find.text('Idea'), findsOneWidget);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settleUi(tester);
    });

    testWidgets('adds a custom section and persists it after autosave',
        (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Audio journal prompts',
      );

      await tester.tap(find.byKey(const Key('idea-editor-add-section')));
      await settleUi(tester);
      await tester.tap(find.text('Untitled').last);
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-section-name')),
        'Notes',
      );
      await tester.tap(find.byKey(const Key('idea-editor-create-section')));
      await settlePersistenceAction(tester);

      expect(find.text('Notes'), findsOneWidget);

      await settlePersistenceAction(tester);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);

      await tester.tap(find.text('Audio journal prompts'));
      await settleUi(tester);

      expect(find.text('Notes'), findsOneWidget);
      expect(provider.ideas.first.sections, hasLength(2));

      final reopenedCloseButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      reopenedCloseButton.onPressed!.call();
      await settleUi(tester);
    });

    testWidgets('creates duplicate untitled sections quickly', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);

      await tester.tap(find.byKey(const Key('idea-editor-add-section')));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('idea-editor-add-section')));
      await settlePersistenceAction(tester);

      expect(find.text('Untitled'), findsNWidgets(2));
      expect(
        provider.ideas.single.sections
            .where((section) => section.name == 'Untitled'),
        hasLength(2),
      );

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);
    });

    testWidgets('keeps manual section renames duplicate-protected',
        (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);

      await tester.tap(find.byKey(const Key('idea-editor-add-section')));
      await settleUi(tester);
      await tester.tap(find.text('Untitled').last);
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-section-name')),
        'Idea',
      );
      await tester.tap(find.byKey(const Key('idea-editor-create-section')));
      await settleUi(tester);

      expect(find.text('ideaEditorSnackbarDuplicateSection'), findsOneWidget);
      expect(find.text('Idea'), findsOneWidget);
      expect(find.text('Untitled'), findsOneWidget);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);
    });

    testWidgets('reopens an idea on its last active section', (tester) async {
      late final Idea savedIdea;
      await tester.runAsync(() async {
        savedIdea = (await provider.saveIdea(
          title: 'Remember sections',
          sections: [
            const IdeaSection(
              id: 'section-first',
              name: 'Idea',
              content: 'First content',
            ),
            const IdeaSection(
              id: 'section-second',
              name: 'Notes',
              content: 'Second content',
            ),
          ],
        ))!;
      });

      await pumpIdeasApp(tester);
      await tester.tap(find.text('Remember sections'));
      await settleUi(tester);

      await tester.tap(sectionTab(savedIdea.sections.last));
      await settlePersistenceAction(tester);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);

      await tester.tap(find.text('Remember sections'));
      await settleUi(tester);

      final editor = tester.widget<TextField>(
        find.byKey(const Key('idea-markdown-text-field')),
      );
      expect(editor.controller?.text, 'Second content');

      final reopenedCloseButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      reopenedCloseButton.onPressed!.call();
      await settleUi(tester);
    });

    testWidgets('preserves tab edits while switching sections', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);

      await tester.tap(find.byKey(const Key('idea-editor-add-section')));
      await settleUi(tester);
      await tester.tap(find.text('Untitled').last);
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-section-name')),
        'Requirements',
      );
      await tester.tap(find.byKey(const Key('idea-editor-create-section')));
      await settleUi(tester);

      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'Vision',
      );
      await settlePersistenceAction(tester);

      final ideaSection = provider.ideas.single.sections.firstWhere(
        (section) => section.name == 'Idea',
      );
      final requirementsSection = provider.ideas.single.sections.firstWhere(
        (section) => section.name == 'Requirements',
      );
      await tester.tap(
        sectionTab(ideaSection),
      );
      await settleUi(tester);
      await tester.tap(
        sectionTab(requirementsSection),
      );
      await settleUi(tester);

      final editor = tester.widget<TextField>(
        find.byKey(const Key('idea-markdown-text-field')),
      );
      expect(editor.controller?.text, contains('Vision'));

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('shows tooltips for toolbar actions', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);

      Future<void> expectTooltip(IconData icon, String label) async {
        await tester.longPress(find.byIcon(icon));
        await settleUi(tester);
        expect(find.text(label), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await settleUi(tester);
      }

      await expectTooltip(Icons.title, ViewConstants.editorToolbarHeading);
      await expectTooltip(Icons.format_bold, ViewConstants.editorToolbarBold);
      await expectTooltip(
          Icons.format_italic, ViewConstants.editorToolbarItalic);
      await expectTooltip(
          Icons.format_list_bulleted, ViewConstants.editorToolbarBulletList);
      await expectTooltip(Icons.code, ViewConstants.editorToolbarCodeBlock);
    });

    testWidgets('restores the open editor on relaunch', (tester) async {
      late final String ideaId;
      late final String sectionId;
      await tester.runAsync(() async {
        final savedIdea = await provider.saveIdea(
          title: 'Resume flow',
          sections: provider.createDefaultSections(),
        );
        ideaId = savedIdea!.id;
        sectionId = savedIdea.sections.first.id;

        await provider.saveEditorState(
          ideaId: ideaId,
          activeSectionId: sectionId,
          isPreviewMode: true,
        );
      });

      await pumpIdeasApp(tester);
      await settleUi(tester);

      expect(find.byKey(const Key('idea-editor-title')), findsOneWidget);
      expect(find.byKey(const Key('idea-markdown-text-field')), findsOneWidget);
      expect(find.text('ideaEditorTitleEdit'), findsOneWidget);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settleUi(tester);
    });

    testWidgets('does not reopen a locked note on relaunch', (tester) async {
      await registerNoteLockServices();
      late final String ideaId;
      late final String sectionId;
      await tester.runAsync(() async {
        final savedIdea = await provider.saveIdea(
          title: 'Locked resume',
          sections: provider.createDefaultSections(),
        );
        ideaId = savedIdea!.id;
        sectionId = savedIdea.sections.first.id;

        await provider.setIdeaLocked(ideaId: ideaId, isLocked: true);
        await provider.saveEditorState(
          ideaId: ideaId,
          activeSectionId: sectionId,
          isPreviewMode: false,
        );
      });

      await pumpIdeasApp(tester);
      await settleUi(tester);

      expect(find.byKey(const Key('note-lock-pin-screen')), findsNothing);
      expect(find.byKey(const Key('idea-editor-title')), findsNothing);
      expect(find.byKey(Key('idea-card-$ideaId')), findsOneWidget);
      expect(provider.resumeEditorState, isNull);
      expect(IdeaEditorStateRepo(storage).getState(), isNull);
    });

    testWidgets(
        'opens restored locked note through PIN setup when no PIN exists',
        (tester) async {
      await registerNoteLockServices();
      late final String ideaId;
      await tester.runAsync(() async {
        final savedIdea = await provider.saveIdea(
          title: 'Restored locked note',
          sections: provider.createDefaultSections(),
        );
        ideaId = savedIdea!.id;
        await provider.setIdeaLocked(ideaId: ideaId, isLocked: true);
      });

      await pumpIdeasApp(tester);
      await tester.tap(find.byKey(Key('idea-card-$ideaId')));
      await settleUi(tester);

      expect(find.byKey(const Key('note-lock-pin-screen')), findsOneWidget);
      expect(find.text(ViewConstants.noteLockCreatePinTitle), findsWidgets);
    });

    testWidgets('locks note in editor without showing overlay', (tester) async {
      final authService = await registerNoteLockServices(withPin: true);

      await pumpIdeasApp(tester);
      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);

      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'Secret draft',
      );
      await settlePersistenceAction(tester);

      await tester.tap(find.byKey(const Key('idea-editor-menu')));
      await settleUi(tester);
      expect(
        find.text(ViewConstants.ideaEditorOptionsLockNote),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('idea-editor-option-lock')));
      await settlePersistenceAction(tester);

      expect(find.text(ViewConstants.noteLockEditorTitle), findsNothing);
      expect(find.byKey(const Key('idea-markdown-text-field')), findsOneWidget);
      expect(provider.ideas.single.isLocked, isTrue);
      expect(find.byKey(const Key('idea-editor-lock-toggle')), findsNothing);

      await tester.tap(find.byKey(const Key('idea-editor-menu')));
      await settleUi(tester);
      expect(
        find.text(ViewConstants.ideaEditorOptionsUnlockNote),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(20, 20));
      await settleUi(tester);

      final ideaId = provider.ideas.single.id;
      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);

      expect(authService.isIdeaUnlocked(ideaId), isFalse);

      await tester.tap(find.byKey(Key('idea-card-$ideaId')));
      await settleUi(tester);

      expect(find.byKey(const Key('note-lock-pin-screen')), findsOneWidget);
      expect(find.text(ViewConstants.noteLockEnterPinTitle), findsWidgets);

      Navigator.of(
        tester.element(find.byKey(const Key('note-lock-pin-screen'))),
      ).pop();
      await settleUi(tester);
    });

    testWidgets('supports selecting and deleting ideas from the list',
        (tester) async {
      String? firstIdeaId;
      await tester.runAsync(() async {
        final firstIdea = await provider.saveIdea(
          title: 'First delete target',
          sections: provider.createDefaultSections(),
        );
        firstIdeaId = firstIdea!.id;
        await provider.saveIdea(
          title: 'Second delete target',
          sections: provider.createDefaultSections(),
        );
      });

      await pumpIdeasApp(tester);

      await tester.longPress(find.byKey(Key('idea-card-$firstIdeaId')));
      await settleUi(tester);
      final deleteButton = find.byKey(const Key('ideas-delete-button'));
      expect(deleteButton, findsOneWidget);
      expect(find.byKey(const Key('ideas-selection-count')), findsOneWidget);
      expect(find.byKey(const Key('ideas-new-idea-button')), findsNothing);
      expect(find.byKey(const Key('ideas-search-button')), findsNothing);
      expect(find.byKey(const Key('ideas-sort-button')), findsNothing);
      expect(find.byKey(const Key('home-quick-note-button')), findsNothing);
      expect(
        tester
            .widget<SelectionCheckBadge>(
              find.byKey(Key('idea-card-badge-$firstIdeaId')),
            )
            .isSelected,
        isTrue,
      );

      await tester.tap(find.text('Second delete target'));
      await settleUi(tester);
      final selectedBadges = tester
          .widgetList<SelectionCheckBadge>(find.byType(SelectionCheckBadge))
          .where((badge) => badge.isSelected);
      expect(selectedBadges, hasLength(2));

      await tester.tap(find.byKey(const Key('ideas-delete-button')));
      await settleUi(tester);
      expect(
        find.text(ViewConstants.selectionDeleteIdeasTitleMany),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ideas-delete-confirm')));
      await settlePersistenceAction(tester);

      expect(provider.ideas, isEmpty);
      expect(find.byKey(const Key('ideas-empty-state')), findsOneWidget);
      expect(find.byKey(const Key('ideas-new-idea-button')), findsOneWidget);
      expect(find.byKey(const Key('home-quick-note-button')), findsOneWidget);
    });

    testWidgets('selection shows empty circles, select all and exits on last',
        (tester) async {
      late String firstId;
      late String secondId;
      await tester.runAsync(() async {
        firstId = (await provider.saveIdea(
          title: 'Alpha select',
          sections: provider.createDefaultSections(),
        ))!
            .id;
        secondId = (await provider.saveIdea(
          title: 'Beta select',
          sections: provider.createDefaultSections(),
        ))!
            .id;
      });

      await pumpIdeasApp(tester);
      expect(find.byType(SelectionCheckBadge), findsNothing);

      await tester.longPress(find.byKey(Key('idea-card-$firstId')));
      await settleUi(tester);

      SelectionCheckBadge badgeFor(String id) => tester
          .widget<SelectionCheckBadge>(find.byKey(Key('idea-card-badge-$id')));
      expect(badgeFor(firstId).isSelected, isTrue);
      expect(badgeFor(secondId).isSelected, isFalse);

      await tester.tap(find.byKey(const Key('ideas-select-all-button')));
      await settleUi(tester);
      expect(badgeFor(secondId).isSelected, isTrue);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(const Key('ideas-select-all-button')),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(Key('idea-card-$firstId')));
      await settleUi(tester);
      await tester.tap(find.byKey(Key('idea-card-$secondId')));
      await settleUi(tester);

      expect(find.byKey(const Key('ideas-selection-count')), findsNothing);
      expect(find.byType(SelectionCheckBadge), findsNothing);
      expect(find.byKey(const Key('ideas-new-idea-button')), findsOneWidget);
    });

    testWidgets('selected idea card is announced and not colour only',
        (tester) async {
      final semantics = tester.ensureSemantics();
      late String ideaId;
      await tester.runAsync(() async {
        ideaId = (await provider.saveIdea(
          title: 'Announce me',
          sections: provider.createDefaultSections(),
        ))!
            .id;
      });

      await pumpIdeasApp(tester);
      await tester.longPress(find.byKey(Key('idea-card-$ideaId')));
      await settleUi(tester);

      final cardSemantics = tester.getSemantics(
        find.byKey(Key('idea-card-$ideaId')),
      );
      expect(cardSemantics, containsSemantics(isSelected: true));
      expect(
        find.descendant(
          of: find.byKey(Key('idea-card-badge-$ideaId')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('back exits idea selection before leaving home',
        (tester) async {
      late String ideaId;
      await tester.runAsync(() async {
        ideaId = (await provider.saveIdea(
          title: 'Back target',
          sections: provider.createDefaultSections(),
        ))!
            .id;
      });

      await pumpIdeasApp(tester);
      await tester.longPress(find.byKey(Key('idea-card-$ideaId')));
      await settleUi(tester);
      expect(find.byKey(const Key('ideas-selection-count')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settleUi(tester);

      expect(find.byKey(const Key('ideas-selection-count')), findsNothing);
      expect(find.byKey(Key('idea-card-$ideaId')), findsOneWidget);
      expect(find.byKey(const Key('ideas-new-idea-button')), findsOneWidget);
    });

    testWidgets('selection drops ideas that no longer exist', (tester) async {
      late String ideaId;
      late String keptId;
      await tester.runAsync(() async {
        ideaId = (await provider.saveIdea(
          title: 'Vanishing idea',
          sections: provider.createDefaultSections(),
        ))!
            .id;
        keptId = (await provider.saveIdea(
          title: 'Kept idea',
          sections: provider.createDefaultSections(),
        ))!
            .id;
      });

      await pumpIdeasApp(tester);
      await tester.longPress(find.byKey(Key('idea-card-$ideaId')));
      await settleUi(tester);

      await tester.runAsync(() async {
        await provider.deleteIdeas([ideaId]);
      });
      await settleUi(tester);

      expect(find.byKey(const Key('ideas-selection-count')), findsNothing);
      expect(find.byKey(Key('idea-card-$keptId')), findsOneWidget);
    });

    testWidgets('filters ideas with the search bar in real time',
        (tester) async {
      await tester.runAsync(() async {
        await provider.saveIdea(
          title: 'Neighborhood Lab',
          sections: [
            const IdeaSection(
              id: 'idea-section',
              name: 'Idea',
              content: 'A solar rooftop garden with shared maintenance.',
            ),
          ],
        );
        await provider.saveIdea(
          title: 'Quiet Library Pods',
          sections: [
            const IdeaSection(
              id: 'library-section',
              name: 'Idea',
              content: 'Soundproof study spaces for teams.',
            ),
          ],
        );
      });

      await pumpIdeasApp(tester);

      expect(find.byKey(const Key('ideas-search-field')), findsNothing);

      await tester.tap(find.byKey(const Key('ideas-search-button')));
      await settleUi(tester);

      expect(find.byKey(const Key('search-ideas-screen')), findsOneWidget);
      expect(
          find.byKey(const Key('search-ideas-empty-prompt')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('ideas-search-field')),
        'rooftop',
      );
      await settleUi(tester);

      expect(find.text('Neighborhood Lab'), findsOneWidget);
      expect(find.text('Quiet Library Pods'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('ideas-search-field')),
        'zzzzz',
      );
      await settleUi(tester);

      expect(find.text('homepageNoSearchResults'), findsOneWidget);
    });

    testWidgets('search screen uses the saved grid layout for results',
        (tester) async {
      late String firstIdeaId;
      late String secondIdeaId;
      await tester.runAsync(() async {
        await sortPreferencesRepo.saveLayoutOption(IdeaLayoutOption.grid);
        final firstIdea = await provider.saveIdea(
          title: 'Grid search alpha',
          sections: [
            const IdeaSection(
              id: 'grid-search-alpha',
              name: 'Idea',
              content: 'Alpha content for grid search layout test.',
            ),
          ],
        );
        firstIdeaId = firstIdea!.id;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final secondIdea = await provider.saveIdea(
          title: 'Grid search beta',
          sections: [
            const IdeaSection(
              id: 'grid-search-beta',
              name: 'Idea',
              content: 'Beta content for grid search layout test.',
            ),
          ],
        );
        secondIdeaId = secondIdea!.id;
      });

      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-search-button')));
      await settleUi(tester);

      await tester.enterText(
        find.byKey(const Key('ideas-search-field')),
        'grid search',
      );
      await settleUi(tester);

      final firstCard = find.byKey(Key('idea-card-$firstIdeaId'));
      final secondCard = find.byKey(Key('idea-card-$secondIdeaId'));

      expect(firstCard, findsOneWidget);
      expect(secondCard, findsOneWidget);
      expect(
        tester.getTopLeft(firstCard).dx,
        greaterThan(tester.getTopLeft(secondCard).dx),
      );
      expect(
        (tester.getTopLeft(firstCard).dy - tester.getTopLeft(secondCard).dy)
            .abs(),
        lessThan(1),
      );
    });

    testWidgets('sorts ideas and remembers the selected preference',
        (tester) async {
      late String olderIdeaId;
      late String newerIdeaId;
      await tester.runAsync(() async {
        final olderIdea = await provider.saveIdea(
          title: 'Deep Archive',
          sections: [
            ...provider.createDefaultSections(),
            IdeaSection.empty(name: 'Design'),
          ],
        );
        olderIdeaId = olderIdea!.id;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final newerIdea = await provider.saveIdea(
          title: 'Fresh Spark',
          sections: provider.createDefaultSections(),
        );
        newerIdeaId = newerIdea!.id;
      });

      await pumpIdeasApp(tester);

      expect(appearsBefore(tester, newerIdeaId, olderIdeaId), isTrue);

      await tester.tap(find.byKey(const Key('ideas-sort-button')));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('ideas-sort-most-sections')));
      await settlePersistenceAction(tester);

      expect(appearsBefore(tester, olderIdeaId, newerIdeaId), isTrue);

      await pumpIdeasApp(tester);

      expect(appearsBefore(tester, olderIdeaId, newerIdeaId), isTrue);
    });

    testWidgets('homepage renders grid layout and hides layout menu item',
        (tester) async {
      late String firstIdeaId;
      late String secondIdeaId;
      await tester.runAsync(() async {
        await sortPreferencesRepo.saveLayoutOption(IdeaLayoutOption.list);
        final firstIdea = await provider.saveIdea(
          title: 'First layout card',
          sections: [
            const IdeaSection(
              id: 'first-layout-section',
              name: 'Idea',
              content: 'A compact card should still reveal useful context.',
            ),
          ],
        );
        firstIdeaId = firstIdea!.id;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final secondIdea = await provider.saveIdea(
          title: 'Second layout card',
          sections: [
            const IdeaSection(
              id: 'second-layout-section',
              name: 'Idea',
              content: 'The grid keeps this preview visible too.',
            ),
          ],
        );
        secondIdeaId = secondIdea!.id;
      });

      await pumpIdeasApp(tester);

      final firstCard = find.byKey(Key('idea-card-$firstIdeaId'));
      final secondCard = find.byKey(Key('idea-card-$secondIdeaId'));

      expect(
        tester.getTopLeft(firstCard).dx,
        greaterThan(tester.getTopLeft(secondCard).dx),
      );
      expect(
        (tester.getTopLeft(firstCard).dy - tester.getTopLeft(secondCard).dy)
            .abs(),
        lessThan(1),
      );

      expect(find.byKey(const Key('ideas-more-menu')), findsNothing);
      expect(find.byKey(const Key('ideas-menu-layout')), findsNothing);
      expect(find.byKey(const Key('ideas-sort-button')), findsOneWidget);
      expect(
        sortPreferencesRepo.getLayoutOption(),
        IdeaLayoutOption.grid,
      );
    });

    testWidgets('quick-note button opens random notes with the keyboard up',
        (tester) async {
      await pumpIdeasApp(tester);

      final semantics = tester.ensureSemantics();
      final buttonSemantics = tester.getSemantics(
        find.byKey(const Key('home-quick-note-button')),
      );
      expect(
        buttonSemantics,
        containsSemantics(isButton: true, isTextField: false),
      );
      semantics.dispose();

      await tester.tap(find.byKey(const Key('home-quick-note-button')));
      await settleUi(tester);

      expect(find.byKey(const Key('random-additions-screen')), findsOneWidget);
      final composer = tester.widget<TextField>(
        find.byKey(const Key('random-additions-composer')),
      );
      expect(composer.autofocus, isTrue);
      expect(composer.focusNode?.hasFocus, isTrue);

      await tester.enterText(
        find.byKey(const Key('random-additions-composer')),
        'Loose capture\nwith two lines',
      );
      await tester.tap(find.byKey(const Key('random-additions-send')));
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('random-additions-screen')), findsOneWidget);
      expect(randomAdditionsProvider.additions, hasLength(1));
      expect(
        randomAdditionsProvider.additions.single.content,
        'Loose capture\nwith two lines',
      );
      expect(find.text('Loose capture\nwith two lines'), findsOneWidget);
    });

    testWidgets('drawer entry opens random notes without the keyboard',
        (tester) async {
      await pumpIdeasApp(tester);
      await openRandomAdditionsFromDrawer(tester);

      final composer = tester.widget<TextField>(
        find.byKey(const Key('random-additions-composer')),
      );
      expect(composer.autofocus, isFalse);
    });

    testWidgets('quick-note button shows the unfiled count capped at 99+',
        (tester) async {
      await pumpIdeasApp(tester);
      expect(find.byKey(const Key('home-quick-note-count')), findsNothing);

      await tester.runAsync(() async {
        await randomAdditionsProvider.addAddition('One loose note');
      });
      await settleUi(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-quick-note-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        for (var index = 0; index < 100; index++) {
          await randomAdditionsProvider.addAddition('Note $index');
        }
      });
      await settleUi(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-quick-note-count')),
          matching: find.text(ViewConstants.homeQuickNoteCountOverflow),
        ),
        findsOneWidget,
      );
    });

    testWidgets('drawer random additions entry shows unfiled count badge',
        (tester) async {
      await tester.runAsync(() async {
        await randomAdditionsProvider.addAddition('First loose note');
        await randomAdditionsProvider.addAddition('Second loose note');
      });

      await pumpIdeasApp(tester);
      await tester.tap(find.byKey(const Key('ideas-menu-button')));
      await settleUi(tester);

      expect(find.byKey(const Key('random-additions-drawer')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('random-additions-drawer-count')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('random additions screen sends multiline notes',
        (tester) async {
      await pumpIdeasApp(tester);

      await openRandomAdditionsFromDrawer(tester);
      await tester.enterText(
        find.byKey(const Key('random-additions-composer')),
        'First line\nSecond line',
      );
      await tester.tap(find.byKey(const Key('random-additions-send')));
      await settlePersistenceAction(tester);

      expect(randomAdditionsProvider.additions, hasLength(1));
      expect(
        randomAdditionsProvider.additions.single.content,
        'First line\nSecond line',
      );
      expect(find.text('First line\nSecond line'), findsOneWidget);
    });

    testWidgets('supports selecting and deleting random additions',
        (tester) async {
      late String firstAdditionId;
      late String secondAdditionId;
      await tester.runAsync(() async {
        final firstAddition = await randomAdditionsProvider.addAddition(
          'First loose note',
        );
        final secondAddition = await randomAdditionsProvider.addAddition(
          'Second loose note',
        );
        firstAdditionId = firstAddition!.id;
        secondAdditionId = secondAddition!.id;
      });

      await pumpIdeasApp(tester);
      await openRandomAdditionsFromDrawer(tester);

      await tester.longPress(
        find.byKey(Key('random-addition-bubble-$firstAdditionId')),
      );
      await settleUi(tester);
      final deleteButton =
          find.byKey(const Key('random-additions-delete-button'));
      expect(deleteButton, findsOneWidget);
      expect(
        find.byKey(const Key('random-additions-selection-count')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(Key('random-addition-bubble-$secondAdditionId')),
      );
      await settleUi(tester);
      final selectedChecks = tester
          .widgetList<SelectionCheckBadge>(find.byType(SelectionCheckBadge))
          .where((badge) => badge.isSelected);
      expect(selectedChecks, hasLength(2));

      await tester.tap(deleteButton);
      await settleUi(tester);
      expect(
        find.text(ViewConstants.selectionDeleteNotesTitleMany),
        findsOneWidget,
      );
      expect(
        find.text(ViewConstants.selectionDeleteNotesBodyMany),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('random-additions-delete-confirm')),
      );
      await settlePersistenceAction(tester);

      expect(randomAdditionsProvider.additions, isEmpty);
      expect(find.byKey(const Key('random-additions-empty')), findsOneWidget);
    });

    testWidgets('canceling random additions deletion keeps additions',
        (tester) async {
      late String additionId;
      await tester.runAsync(() async {
        final addition = await randomAdditionsProvider.addAddition(
          'Keep this loose note',
        );
        additionId = addition!.id;
      });

      await pumpIdeasApp(tester);
      await openRandomAdditionsFromDrawer(tester);

      await tester.longPress(
        find.byKey(Key('random-addition-bubble-$additionId')),
      );
      await settleUi(tester);
      await tester.tap(
        find.byKey(const Key('random-additions-delete-button')),
      );
      await settleUi(tester);
      expect(
        find.text(ViewConstants.selectionDeleteNoteTitleOne),
        findsOneWidget,
      );
      await tester.tap(find.text(ViewConstants.cancel));
      await settleUi(tester);

      expect(randomAdditionsProvider.additions, hasLength(1));
      expect(find.text('Keep this loose note'), findsOneWidget);
      expect(
        find.byKey(const Key('random-additions-delete-button')),
        findsOneWidget,
      );
    });

    testWidgets('files a random addition into an idea section', (tester) async {
      late String ideaId;
      late String sectionId;
      await tester.runAsync(() async {
        final savedIdea = await provider.saveIdea(
          title: 'Filed idea',
          sections: [
            const IdeaSection(
              id: 'filing-section',
              name: 'Notes',
              content: 'Existing note',
            ),
          ],
        );
        ideaId = savedIdea!.id;
        sectionId = savedIdea.sections.single.id;
        await randomAdditionsProvider.addAddition(
          'New dictated line\nSecond line',
        );
      });

      await pumpIdeasApp(tester);

      final additionId = randomAdditionsProvider.additions.single.id;
      await openRandomAdditionsFromDrawer(tester);
      await tester.tap(find.byKey(Key('random-addition-bubble-$additionId')));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('random-addition-idea-$ideaId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('random-addition-section-$sectionId')));
      await settlePersistenceAction(tester);

      expect(randomAdditionsProvider.additions, isEmpty);
      expect(
        provider.ideas.single.sections.single.content,
        'Existing note\n\nNew dictated line\nSecond line',
      );
    });

    testWidgets('filing without ideas keeps the random addition in the inbox',
        (tester) async {
      await tester.runAsync(() async {
        await randomAdditionsProvider.addAddition('Keep me unfiled');
      });

      await pumpIdeasApp(tester);

      final additionId = randomAdditionsProvider.additions.single.id;
      await openRandomAdditionsFromDrawer(tester);
      await tester.tap(find.byKey(Key('random-addition-bubble-$additionId')));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('random-additions-no-ideas')),
        findsOneWidget,
      );
      expect(randomAdditionsProvider.additions, hasLength(1));
    });

    testWidgets('renames and deletes sections from the edit sheet',
        (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);

      await tester.tap(find.byKey(const Key('idea-editor-add-section')));
      await settleUi(tester);
      await tester.tap(find.text('Untitled').last);
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-section-name')),
        'Notes',
      );
      await tester.tap(find.byKey(const Key('idea-editor-create-section')));
      await settleUi(tester);

      await tester.tap(find.text('Notes'));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-section-name')),
        'Details',
      );
      await tester.tap(find.byKey(const Key('idea-editor-create-section')));
      await settleUi(tester);

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Notes'), findsNothing);

      await tester.tap(find.text('Details'));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('idea-editor-delete-section')));
      await settleUi(tester);

      expect(find.text('Details'), findsNothing);
      expect(find.text('Idea'), findsOneWidget);
    });

    testWidgets('flushes autosave when closing a dirty draft', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Unsaved concept',
      );

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Unsaved concept'), findsOneWidget);
      expect(provider.ideas.single.title, 'Unsaved concept');
    });

    testWidgets('flushes autosave when the app is paused', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Background save',
      );
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settlePersistenceAction(tester);

      expect(provider.ideas.single.title, 'Background save');
    });

    testWidgets('shows and clears save failed indicator', (tester) async {
      final failingRepo = _FailingIdeasRepo();
      provider = IdeasProvider(
        failingRepo,
        IdeaEditorStateRepo(storage),
      );
      await provider.ensureLoaded();

      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-new-idea-button')));
      await settlePersistenceAction(tester);
      expect(provider.ideas, isEmpty);
      expect(find.byKey(const Key('idea-editor-save-failed')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Failure visible',
      );
      await tester.pump();

      failingRepo.failWrites = true;
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('idea-editor-save-failed')), findsOneWidget);
      expect(provider.ideas, isEmpty);

      failingRepo.failWrites = false;
      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Failure recovered',
      );
      await tester.pump();
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('idea-editor-save-failed')), findsNothing);
      expect(provider.ideas.single.title, 'Failure recovered');
    });
  });
}

class _FailingIdeasRepo extends InMemoryIdeasRepo {
  bool failWrites = false;

  @override
  Future<void> upsertIdea(Idea idea) async {
    if (failWrites) {
      throw StateError('sqlite write failed');
    }
    await super.upsertIdea(idea);
  }
}
