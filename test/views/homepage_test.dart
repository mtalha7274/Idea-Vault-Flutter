import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
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

    setUpAll(() {
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
    });

    setUp(() async {
      storage = MemoryLocalStorageManager();
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
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await settleUi(tester);
    }

    Future<void> pumpIdeasApp(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<IdeasProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            home: const Homepage(),
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
      await settleUi(tester);

      expect(find.byKey(const Key('idea-editor-title')), findsOneWidget);
      expect(find.byKey(const Key('idea-editor-save')), findsOneWidget);
      expect(find.byKey(const Key('idea-markdown-text-field')), findsOneWidget);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settleUi(tester);
    });

    testWidgets('saves a new idea and returns to the list', (tester) async {
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

      final saveButton = tester.widget<FilledButton>(
        find.byKey(const Key('idea-editor-save')),
      );
      saveButton.onPressed!.call();
      await settlePersistenceAction(tester);

      expect(find.text('Solar Rooftop Co-op'), findsOneWidget);
      expect(provider.ideas, hasLength(1));
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
      expect(find.text('Requirements'), findsOneWidget);
      expect(find.text('Design'), findsOneWidget);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settleUi(tester);
    });

    testWidgets('adds a custom section and persists it after save',
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

      final saveButton = tester.widget<FilledButton>(
        find.byKey(const Key('idea-editor-save')),
      );
      saveButton.onPressed!.call();
      await settlePersistenceAction(tester);

      await tester.tap(find.text('Audio journal prompts'));
      await settleUi(tester);

      expect(find.text('Notes'), findsOneWidget);
      expect(provider.ideas.first.sections, hasLength(4));

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settleUi(tester);
    });

    testWidgets('preserves tab edits while switching sections', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await settleUi(tester);

      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'Vision',
      );
      await tester.pump();

      await tester.tap(find.text('Requirements'));
      await settleUi(tester);
      await tester.tap(find.text('Idea'));
      await settleUi(tester);

      final editor = tester.widget<TextField>(
        find.byKey(const Key('idea-markdown-text-field')),
      );
      expect(editor.controller?.text, contains('Vision'));

      await tester.tap(find.byKey(const Key('idea-markdown-preview-toggle')));
      await settleUi(tester);
      expect(find.byType(MarkdownWidget), findsOneWidget);

      final closeButton = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButton.onPressed!.call();
      await settleUi(tester);
      await tester.tap(find.text('Discard'));
      await settleUi(tester);
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
        sectionId = savedIdea.sections[1].id;

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

    testWidgets('shows a discard dialog when closing a dirty draft',
        (tester) async {
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
      await settleUi(tester);

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await settleUi(tester);
      final closeButtonAgain = tester.widget<IconButton>(
        find.byKey(const Key('idea-editor-close')),
      );
      closeButtonAgain.onPressed!.call();
      await settleUi(tester);
      await tester.tap(find.text('Discard'));
      await settleUi(tester);
    });
  });
}
