import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/idea_list_preferences.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/homepage.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Homepage ideas flow', () {
    late MemoryLocalStorageManager storage;
    late IdeasProvider provider;
    late ThemeProvider themeProvider;
    late IdeaListPreferencesRepo sortPreferencesRepo;

    setUpAll(() {
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
    });

    setUp(() async {
      storage = MemoryLocalStorageManager();
      sortPreferencesRepo = IdeaListPreferencesRepo(storage);
      themeProvider = ThemeProvider(ThemeRepo(storage));
      provider = IdeasProvider(
        InMemoryIdeasRepo(),
        IdeaEditorStateRepo(storage),
      );
      await provider.ensureLoaded();
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
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: MaterialApp(
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
      expect(provider.ideas.single.title, 'Untitled Idea');

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
      expect(find.text('1 section'), findsOneWidget);
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
      expect(provider.ideas.single.title, 'Untitled Idea');
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

      await expectTooltip(Icons.title, 'Text');
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
      expect(find.text('Edit Idea'), findsOneWidget);

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
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const Key('ideas-delete-button')), findsOneWidget);

      await tester.tap(find.text('Second delete target'));
      await settleUi(tester);
      expect(find.text('2 selected'), findsOneWidget);

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

      expect(find.text('No ideas match your search'), findsOneWidget);
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
      expect(provider.ideas.single.title, 'Untitled Idea');

      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Failure visible',
      );
      await tester.pump();

      failingRepo.failWrites = true;
      await settlePersistenceAction(tester);

      expect(find.byKey(const Key('idea-editor-save-failed')), findsOneWidget);
      expect(provider.ideas.single.title, 'Untitled Idea');

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
