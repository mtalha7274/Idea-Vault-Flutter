import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/config/config.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_scheduler.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/core/services/premium/paywall_provider.dart';
import 'package:idea_vault/core/services/premium/subscription_service.dart';
import 'package:idea_vault/data/repositories/local/cloud_backup_settings.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/idea_list_preferences.dart';
import 'package:idea_vault/data/repositories/local/paid_feature_usage.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/data/repositories/remote/idea_organization_repository.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/models/backup/cloud_backup_account.dart';
import 'package:idea_vault/models/backup/cloud_backup_state.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/premium/paywall_offering.dart';
import 'package:idea_vault/models/premium/subscription_state.dart';
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/premium/paywall_view_model.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/homepage.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
    late PaidFeatureUsageRepo paidFeatureUsageRepo;

    setUpAll(() {
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      if (!sl.isRegistered<IdeaOrganizationRepository>()) {
        sl.registerSingleton<IdeaOrganizationRepository>(
          _FakeIdeaOrganizationRepository(),
        );
      }
    });

    setUp(() async {
      storage = MemoryLocalStorageManager();
      sortPreferencesRepo = IdeaListPreferencesRepo(storage);
      if (sl.isRegistered<IdeaListPreferencesRepo>()) {
        await sl.unregister<IdeaListPreferencesRepo>();
      }
      sl.registerSingleton<IdeaListPreferencesRepo>(sortPreferencesRepo);
      paidFeatureUsageRepo = PaidFeatureUsageRepo(storage);
      if (sl.isRegistered<PaidFeatureUsageRepo>()) {
        await sl.unregister<PaidFeatureUsageRepo>();
      }
      sl.registerSingleton<PaidFeatureUsageRepo>(paidFeatureUsageRepo);
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
      PaywallViewModel? paywallViewModel,
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
            if (paywallViewModel != null)
              ChangeNotifierProvider<PaywallViewModel>.value(
                value: paywallViewModel,
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
      _FakeCloudBackupService? backupService,
    }) {
      return CloudBackupProvider(
        CloudBackupSettingsRepo(storage),
        backupService ?? _FakeCloudBackupService(),
        _FakeCloudBackupScheduler(),
      );
    }

    PaywallViewModel buildPaywallViewModel({bool isPro = false}) {
      final subscriptionService = _FakeSubscriptionService(
        state: const SubscriptionState.initial().copyWith(isPro: isPro),
      );
      return PaywallViewModel(
        subscriptionService,
        LocalPaywallProvider(subscriptionService),
        paidFeatureUsageRepo,
        CloudBackupSettingsRepo(storage),
        _FakeCloudBackupService(),
        _FakeCloudBackupScheduler(),
        showPaywall: (_) async => false,
        requestRateAppReview: () async => false,
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

    Finder sectionTab(IdeaSection section) {
      return find.byKey(Key('idea-editor-section-tab-${section.id}'));
    }

    Future<void> openRandomAdditionsFromDrawer(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('ideas-menu-button')));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('random-additions-drawer')));
      await settleUi(tester);
    }

    testWidgets('shows the empty state and fab', (tester) async {
      await pumpIdeasApp(tester);

      expect(find.byKey(const Key('ideas-empty-state')), findsOneWidget);
      expect(find.byKey(const Key('ideas-fab')), findsOneWidget);
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
      await pumpIdeasApp(tester, backupProvider: buildCloudBackupProvider());

      expect(find.text(ViewConstants.backupRestorePromptFound), findsNothing);
      expect(
        find.byKey(const Key('homepage-backup-off-indicator')),
        findsOneWidget,
      );
    });

    testWidgets(
        'shows restore prompt with backup-off indicator when backup exists',
        (tester) async {
      final backupService = _FakeCloudBackupService()
        ..backupExistsResult = true;

      await pumpIdeasApp(
        tester,
        backupProvider: buildCloudBackupProvider(backupService: backupService),
      );

      expect(find.text(ViewConstants.backupRestorePromptFound), findsOneWidget);
      expect(
        find.byKey(const Key('homepage-backup-off-indicator')),
        findsOneWidget,
      );
    });

    testWidgets('hides backup-off indicator when backup is enabled',
        (tester) async {
      await CloudBackupSettingsRepo(storage).saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          email: 'writer@example.com',
        ),
      );

      await pumpIdeasApp(tester, backupProvider: buildCloudBackupProvider());

      expect(
        find.byKey(const Key('homepage-backup-off-indicator')),
        findsNothing,
      );
    });

    testWidgets('shows free usage intro for new non-pro installs',
        (tester) async {
      await pumpIdeasApp(
        tester,
        paywallViewModel: buildPaywallViewModel(),
      );
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('free-usage-screen')), findsOneWidget);
      expect(paidFeatureUsageRepo.hasSeenFreeUsageIntro, isTrue);
      expect(
        paidFeatureUsageRepo.freeUsageGrantLimit,
        Config.paidFeatureFreeUsageLimit,
      );
      expect(paidFeatureUsageRepo.usageCount, 0);
    });

    testWidgets('does not show free usage intro after it has been seen',
        (tester) async {
      await paidFeatureUsageRepo.initializeFreeUsageGrantIfNeeded();
      await paidFeatureUsageRepo.markFreeUsageIntroSeen();

      await pumpIdeasApp(
        tester,
        paywallViewModel: buildPaywallViewModel(),
      );

      expect(find.byKey(const Key('free-usage-screen')), findsNothing);
    });

    testWidgets('does not show free usage intro for pro users', (tester) async {
      final paywallViewModel = buildPaywallViewModel(isPro: true);
      await paywallViewModel.refreshSubscription();

      await pumpIdeasApp(
        tester,
        paywallViewModel: paywallViewModel,
      );

      expect(find.byKey(const Key('free-usage-screen')), findsNothing);
    });

    testWidgets('does not show free usage intro when local ideas exist',
        (tester) async {
      await tester.runAsync(() async {
        await provider.saveIdea(
          title: 'Existing idea',
          sections: provider.createDefaultSections(),
        );
      });

      await pumpIdeasApp(
        tester,
        paywallViewModel: buildPaywallViewModel(),
      );

      expect(find.byKey(const Key('free-usage-screen')), findsNothing);
      expect(paidFeatureUsageRepo.hasFreeUsageIntroMetadata, isFalse);
    });

    testWidgets('does not show free usage intro when additions exist',
        (tester) async {
      await tester.runAsync(() async {
        await randomAdditionsProvider.addAddition('Inbox thought');
      });

      await pumpIdeasApp(
        tester,
        paywallViewModel: buildPaywallViewModel(),
      );

      expect(find.byKey(const Key('free-usage-screen')), findsNothing);
      expect(paidFeatureUsageRepo.hasFreeUsageIntroMetadata, isFalse);
    });

    testWidgets('does not show free usage intro after usage has started',
        (tester) async {
      await paidFeatureUsageRepo.incrementUsage();

      await pumpIdeasApp(
        tester,
        paywallViewModel: buildPaywallViewModel(),
      );

      expect(find.byKey(const Key('free-usage-screen')), findsNothing);
      expect(paidFeatureUsageRepo.hasFreeUsageIntroMetadata, isFalse);
    });

    testWidgets('shows free usage drawer row while under the limit',
        (tester) async {
      await paidFeatureUsageRepo.markFreeUsageIntroSeen();
      await paidFeatureUsageRepo.incrementUsage();

      await pumpIdeasApp(
        tester,
        paywallViewModel: buildPaywallViewModel(),
      );

      await tester.tap(find.byKey(const Key('ideas-menu-button')));
      await settleUi(tester);

      expect(
        find.byKey(const Key('homepage-free-usage-drawer')),
        findsOneWidget,
      );
      expect(find.text('freeUsageDrawerTitle'), findsOneWidget);
      expect(find.text('homepageGetIdeaVaultPro'), findsNothing);

      await tester.tap(find.byKey(const Key('homepage-free-usage-drawer')));
      await settleUi(tester);

      expect(find.byKey(const Key('free-usage-screen')), findsOneWidget);
    });

    testWidgets('shows pro drawer row after free usage is exhausted',
        (tester) async {
      for (var i = 0; i < Config.paidFeatureFreeUsageLimit; i += 1) {
        await paidFeatureUsageRepo.incrementUsage();
      }

      await pumpIdeasApp(
        tester,
        paywallViewModel: buildPaywallViewModel(),
      );

      await tester.tap(find.byKey(const Key('ideas-menu-button')));
      await settleUi(tester);

      expect(
        find.byKey(const Key('homepage-free-usage-drawer')),
        findsNothing,
      );
      expect(find.text('homepageGetIdeaVaultPro'), findsOneWidget);
    });

    testWidgets('opens the editor from the fab', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
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
      expect(provider.ideas, hasLength(1));
      expect(provider.ideas.single.title, 'ideaEditorUntitledIdea');

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);
    });

    testWidgets('autosaves a new idea and returns to the list', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await settleUi(tester);

      Future<void> expectTooltip(IconData icon, String label) async {
        await tester.longPress(find.byIcon(icon));
        await settleUi(tester);
        expect(find.text(label), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await settleUi(tester);
      }

      await expectTooltip(Icons.title, 'Heading');
      await expectTooltip(Icons.format_bold, 'Bold');
      await expectTooltip(Icons.format_italic, 'Italic');
      await expectTooltip(Icons.format_list_bulleted, 'Bullet List');
      await expectTooltip(Icons.code, 'Code Block');
    });

    testWidgets('shows AI warning after 4000 characters', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        List.filled(4001, 'a').join(),
      );
      await tester.tap(find.byKey(const Key('idea-editor-organize')));
      await settleUi(tester);

      expect(
        find.byKey(const Key('idea-editor-soft-limit-warning')),
        findsWidgets,
      );
      final confirmButton = tester.widget<FilledButton>(
        find.byKey(const Key('organize-over-limit-confirm')),
      );
      expect(confirmButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('organize-over-limit-cancel')));
      await settleUi(tester);
      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);
    });

    testWidgets('allows AI organize at 4200 characters', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        List.filled(4200, 'a').join(),
      );
      await tester.tap(find.byKey(const Key('idea-editor-organize')));
      await settleUi(tester);

      expect(
        find.byKey(const Key('idea-editor-soft-limit-warning')),
        findsWidgets,
      );
      final confirmButton = tester.widget<FilledButton>(
        find.byKey(const Key('organize-over-limit-confirm')),
      );
      expect(confirmButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('organize-over-limit-cancel')));
      await settleUi(tester);
      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);
    });

    testWidgets('blocks AI organize over 4200 characters', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        List.filled(4201, 'a').join(),
      );
      await tester.tap(find.byKey(const Key('idea-editor-organize')));
      await settleUi(tester);

      expect(
        find.byKey(const Key('idea-editor-max-limit-warning')),
        findsWidgets,
      );
      final confirmButton = tester.widget<FilledButton>(
        find.byKey(const Key('organize-over-limit-confirm')),
      );
      expect(confirmButton.onPressed, isNull);

      await tester.tap(find.byKey(const Key('organize-over-limit-cancel')));
      await settleUi(tester);
      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settlePersistenceAction(tester);
    });

    testWidgets('restores the open editor with preview mode on relaunch',
        (tester) async {
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
      expect(find.byKey(const Key('idea-markdown-text-field')), findsNothing);
      expect(find.text('ideaEditorTitleEdit'), findsOneWidget);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settleUi(tester);
    });

    testWidgets('restores locked editor through PIN setup on relaunch',
        (tester) async {
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

      expect(find.byKey(const Key('note-lock-pin-screen')), findsOneWidget);
      expect(find.text(ViewConstants.noteLockCreatePinTitle), findsWidgets);
      expect(find.byKey(const Key('idea-editor-lock-toggle')), findsNothing);
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
      await tester.tap(find.byKey(const Key('ideas-fab')));
      await settleUi(tester);

      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'Secret draft',
      );
      await settlePersistenceAction(tester);

      await tester.tap(find.byKey(const Key('idea-editor-lock-toggle')));
      await settlePersistenceAction(tester);

      expect(find.text(ViewConstants.noteLockEditorTitle), findsNothing);
      expect(find.byKey(const Key('idea-markdown-text-field')), findsOneWidget);
      expect(provider.ideas.single.isLocked, isTrue);

      final lockButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-lock-toggle')),
      );
      expect(
        lockButton.style?.foregroundColor?.resolve({}),
        themeProvider.baseTheme.primary,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('idea-editor-lock-toggle')),
          matching: find.byIcon(Icons.lock_outline_rounded),
        ),
        findsOneWidget,
      );

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
      expect(
        find.descendant(of: deleteButton, matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(find.text('Second delete target'));
      await settleUi(tester);
      expect(
        find.descendant(of: deleteButton, matching: find.text('2')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ideas-delete-button')));
      await settleUi(tester);
      expect(find.text('Delete ideas?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ideas-delete-confirm')));
      await settlePersistenceAction(tester);

      expect(provider.ideas, isEmpty);
      expect(find.byKey(const Key('ideas-empty-state')), findsOneWidget);
      expect(find.byKey(const Key('ideas-fab')), findsOneWidget);
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

      expect(
        tester.getTopLeft(find.byKey(Key('idea-card-$newerIdeaId'))).dy,
        lessThan(
            tester.getTopLeft(find.byKey(Key('idea-card-$olderIdeaId'))).dy),
      );

      await tester.tap(find.byKey(const Key('ideas-more-menu')));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('ideas-menu-filter')));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('ideas-sort-most-sections')));
      await settlePersistenceAction(tester);

      expect(
        tester.getTopLeft(find.byKey(Key('idea-card-$olderIdeaId'))).dy,
        lessThan(
            tester.getTopLeft(find.byKey(Key('idea-card-$newerIdeaId'))).dy),
      );

      await pumpIdeasApp(tester);

      expect(
        tester.getTopLeft(find.byKey(Key('idea-card-$olderIdeaId'))).dy,
        lessThan(
            tester.getTopLeft(find.byKey(Key('idea-card-$newerIdeaId'))).dy),
      );
    });

    testWidgets('toggles idea cards between list and remembered grid layout',
        (tester) async {
      late String firstIdeaId;
      late String secondIdeaId;
      await tester.runAsync(() async {
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
        (tester.getTopLeft(firstCard).dx - tester.getTopLeft(secondCard).dx)
            .abs(),
        lessThan(1),
      );
      expect(
        tester.getTopLeft(firstCard).dy,
        greaterThan(tester.getTopLeft(secondCard).dy),
      );

      await tester.tap(find.byKey(const Key('ideas-more-menu')));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('ideas-menu-layout')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(
        tester.getTopLeft(firstCard).dx,
        greaterThan(tester.getTopLeft(secondCard).dx),
      );
      expect(
        (tester.getTopLeft(firstCard).dy - tester.getTopLeft(secondCard).dy)
            .abs(),
        lessThan(1),
      );

      await pumpIdeasApp(tester);

      expect(
        tester.getTopLeft(firstCard).dx,
        greaterThan(tester.getTopLeft(secondCard).dx),
      );
      expect(
        (tester.getTopLeft(firstCard).dy - tester.getTopLeft(secondCard).dy)
            .abs(),
        lessThan(1),
      );

      await tester.tap(find.byKey(const Key('ideas-more-menu')));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('ideas-menu-layout')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(
        (tester.getTopLeft(firstCard).dx - tester.getTopLeft(secondCard).dx)
            .abs(),
        lessThan(1),
      );
      expect(
        tester.getTopLeft(firstCard).dy,
        greaterThan(tester.getTopLeft(secondCard).dy),
      );
    });

    testWidgets('homepage composer saves a note and opens random additions',
        (tester) async {
      await pumpIdeasApp(tester);

      await tester.enterText(
        find.byKey(const Key('homepage-random-addition-field')),
        'Loose capture\nwith two lines',
      );
      await tester.tap(find.byKey(const Key('homepage-random-addition-send')));
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('random-additions-screen')), findsOneWidget);
      expect(randomAdditionsProvider.additions, hasLength(1));
      expect(
        randomAdditionsProvider.additions.single.content,
        'Loose capture\nwith two lines',
      );
      expect(find.text('Loose capture\nwith two lines'), findsOneWidget);
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
        find.byKey(const Key('random-additions-drawer-count')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
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
        find.descendant(of: deleteButton, matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(Key('random-addition-bubble-$secondAdditionId')),
      );
      await settleUi(tester);
      expect(
        find.descendant(of: deleteButton, matching: find.text('2')),
        findsOneWidget,
      );

      await tester.tap(deleteButton);
      await settleUi(tester);
      expect(find.text('Delete additions?'), findsOneWidget);

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
      await tester.tap(find.text('Cancel'));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
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

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await settlePersistenceAction(tester);
      expect(provider.ideas.single.title, 'ideaEditorUntitledIdea');

      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Failure visible',
      );
      await tester.pump();

      failingRepo.failWrites = true;
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('idea-editor-save-failed')), findsOneWidget);
      expect(provider.ideas.single.title, 'ideaEditorUntitledIdea');

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

class _FakeCloudBackupService extends CloudBackupService {
  bool backupExistsResult = false;

  @override
  Future<bool> backupExists() async => backupExistsResult;

  @override
  Future<CloudBackupAccount?> connect({bool forceAccountPicker = false}) async {
    return const CloudBackupAccount(
      email: 'writer@example.com',
      provider: 'test',
    );
  }

  @override
  Future<void> disconnect() async {}
}

class _FakeCloudBackupScheduler extends CloudBackupScheduler {
  @override
  Future<void> cancelDailyBackup() async {}

  @override
  Future<void> scheduleDailyBackup() async {}
}

class _FakeSubscriptionService implements SubscriptionService {
  _FakeSubscriptionService({required this.state});

  SubscriptionState state;

  @override
  void addListener(SubscriptionStateListener listener) {}

  @override
  Future<PaywallOffering?> getOffering() async => null;

  @override
  Future<SubscriptionState> getSubscriptionState() async => state;

  @override
  Future<void> initialize() async {}

  @override
  Future<SubscriptionState> purchasePackage(PaywallPackage package) async {
    state = state.copyWith(isPro: true);
    return state;
  }

  @override
  Future<SubscriptionState> restorePurchases() async {
    state = state.copyWith(isPro: true);
    return state;
  }
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

class _FakeIdeaOrganizationRepository implements IdeaOrganizationRepository {
  @override
  Future<String> organizeIdea(String sectionContent) async {
    return sectionContent;
  }
}
