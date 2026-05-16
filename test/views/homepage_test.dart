import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/idea_list_preferences.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/data/repositories/remote/idea_organization_repository.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/homepage.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/in_memory_random_additions_repo.dart';
import '../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Homepage ideas flow', () {
    late MemoryLocalStorageManager storage;
    late IdeasProvider provider;
    late RandomAdditionsProvider randomAdditionsProvider;
    late ThemeProvider themeProvider;
    late IdeaListPreferencesRepo sortPreferencesRepo;

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

    Future<void> pumpIdeasApp(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<IdeasProvider>.value(value: provider),
            ChangeNotifierProvider<RandomAdditionsProvider>.value(
              value: randomAdditionsProvider,
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

    testWidgets('opens the editor from the fab', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('idea-editor-title')), findsOneWidget);
      expect(find.byKey(const Key('idea-editor-save')), findsNothing);
      expect(find.byKey(const Key('idea-markdown-text-field')), findsOneWidget);
      expect(find.byKey(const Key('idea-editor-mic-fab')), findsOneWidget);
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
      await tester.enterText(
        find.byKey(const Key('idea-editor-section-name')),
        'Notes',
      );
      await tester.tap(find.byKey(const Key('idea-editor-create-section')));
      await settleUi(tester);

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

    testWidgets('preserves tab edits while switching sections', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await settleUi(tester);

      await tester.tap(find.byKey(const Key('idea-editor-add-section')));
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
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('idea-editor-section-tab-requirements')),
      );
      await settleUi(tester);
      await tester.tap(
        find.byKey(const Key('idea-editor-section-tab-idea')),
        warnIfMissed: false,
      );
      await settleUi(tester);

      final editor = tester.widget<TextField>(
        find.byKey(const Key('idea-markdown-text-field')),
      );
      expect(editor.controller?.text, contains('Vision'));

      await tester.tap(find.byKey(const Key('idea-markdown-preview-toggle')));
      await settleUi(tester);
      expect(find.byType(MarkdownBlock), findsOneWidget);

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
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
      expect(find.byKey(const Key('idea-markdown-text-field')), findsNothing);
      expect(find.text('ideaEditorTitleEdit'), findsOneWidget);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
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

      await tester.tap(find.byKey(const Key('ideas-sort-button')));
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

      await tester.tap(find.byKey(const Key('ideas-layout-toggle')));
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

      await tester.tap(find.byKey(const Key('ideas-layout-toggle')));
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
      tester
          .widget<IconButton>(
            find.byKey(Key('random-addition-file-$additionId')),
          )
          .onPressed!
          .call();
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
      tester
          .widget<IconButton>(
            find.byKey(Key('random-addition-file-$additionId')),
          )
          .onPressed!
          .call();
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
      await tester.enterText(
        find.byKey(const Key('idea-editor-section-name')),
        'Notes',
      );
      await tester.tap(find.byKey(const Key('idea-editor-create-section')));
      await settleUi(tester);

      await tester.tap(find.byKey(const Key('idea-editor-section-tab-notes')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-section-name')),
        'Details',
      );
      await tester.tap(find.byKey(const Key('idea-editor-create-section')));
      await settleUi(tester);

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Notes'), findsNothing);

      await tester.tap(
        find.byKey(const Key('idea-editor-section-tab-details')),
      );
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
