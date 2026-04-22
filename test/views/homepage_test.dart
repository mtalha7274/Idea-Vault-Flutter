import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/data/repositories/local/ideas.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/views/homepage.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../helpers/memory_local_storage.dart';

void main() {
  group('Homepage ideas flow', () {
    late MemoryLocalStorageManager storage;
    late IdeasProvider provider;

    setUpAll(() {
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
    });

    setUp(() {
      storage = MemoryLocalStorageManager();
      provider = IdeasProvider(IdeasRepo(storage));
    });

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
      await tester.pumpAndSettle();
    }

    testWidgets('shows the empty state and fab', (tester) async {
      await pumpIdeasApp(tester);

      expect(find.byKey(const Key('ideas-empty-state')), findsOneWidget);
      expect(find.byKey(const Key('ideas-fab')), findsOneWidget);
    });

    testWidgets('opens the editor from the fab', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('idea-editor-title')), findsOneWidget);
      expect(find.byKey(const Key('idea-editor-save')), findsOneWidget);
      expect(find.byKey(const Key('idea-markdown-text-field')), findsOneWidget);

      await tester.tap(find.byKey(const Key('idea-editor-close')));
      await tester.pumpAndSettle();
    });

    testWidgets('saves a new idea and returns to the list', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Solar Rooftop Co-op',
      );

      await tester.tap(find.byKey(const Key('idea-editor-save')));
      await tester.pumpAndSettle();

      expect(find.text('Solar Rooftop Co-op'), findsOneWidget);
      expect(provider.ideas, hasLength(1));
    });

    testWidgets('opens an existing idea with populated data', (tester) async {
      await provider.saveIdea(
        title: 'Existing Idea',
        sections: provider.createDefaultSections(),
      );

      await pumpIdeasApp(tester);

      await tester.tap(find.text('Existing Idea'));
      await tester.pumpAndSettle();

      final titleField = tester.widget<TextField>(
        find.byKey(const Key('idea-editor-title')),
      );

      expect(titleField.controller?.text, 'Existing Idea');
      expect(find.text('Requirements'), findsOneWidget);
      expect(find.text('Design'), findsOneWidget);

      await tester.tap(find.byKey(const Key('idea-editor-close')));
      await tester.pumpAndSettle();
    });

    testWidgets('adds a custom section and persists it after save',
        (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Audio journal prompts',
      );

      await tester.tap(find.byKey(const Key('idea-editor-add-section')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('idea-editor-section-name')),
        'Notes',
      );
      await tester.tap(find.byKey(const Key('idea-editor-create-section')));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('idea-editor-save')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Audio journal prompts'));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);
      expect(provider.ideas.first.sections, hasLength(4));

      await tester.tap(find.byKey(const Key('idea-editor-close')));
      await tester.pumpAndSettle();
    });

    testWidgets('preserves tab edits while switching sections', (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'Vision',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Requirements'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Idea'));
      await tester.pumpAndSettle();

      final editor = tester.widget<TextField>(
        find.byKey(const Key('idea-markdown-text-field')),
      );
      expect(editor.controller?.text, contains('Vision'));

      await tester.tap(find.byKey(const Key('idea-markdown-preview-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownWidget), findsOneWidget);

      await tester.tap(find.byKey(const Key('idea-editor-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
    });

    testWidgets('shows a discard dialog when closing a dirty draft',
        (tester) async {
      await pumpIdeasApp(tester);

      await tester.tap(find.byKey(const Key('ideas-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Unsaved concept',
      );

      await tester.tap(find.byKey(const Key('idea-editor-close')));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('idea-editor-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
    });
  });
}
