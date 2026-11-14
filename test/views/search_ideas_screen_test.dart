import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/idea_list_preferences.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/search_ideas_screen.dart';
import 'package:idea_vault/widgets/editor/note_editing_controller.dart';
import 'package:provider/provider.dart';

import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/memory_local_storage.dart';

void main() {
  dotenv.loadFromString(envString: 'DEBUG=false');
  GoogleFonts.config.allowRuntimeFetching = false;

  late MemoryLocalStorageManager storage;
  late IdeasProvider provider;
  late ThemeProvider themeProvider;

  setUp(() async {
    storage = MemoryLocalStorageManager();
    provider = IdeasProvider(InMemoryIdeasRepo(), IdeaEditorStateRepo(storage));
    themeProvider = ThemeProvider(ThemeRepo(storage));
    await provider.ensureLoaded();
    if (sl.isRegistered<IdeaListPreferencesRepo>()) {
      await sl.unregister<IdeaListPreferencesRepo>();
    }
    sl.registerSingleton<IdeaListPreferencesRepo>(
      IdeaListPreferencesRepo(storage),
    );
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpSearch(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<IdeasProvider>.value(value: provider),
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
          home: const SearchIdeasScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('finds text in a later section and opens that section',
      (tester) async {
    late Idea idea;
    await tester.runAsync(() async {
      idea = (await provider.saveIdea(
        title: 'Weekend market',
        sections: const [
          IdeaSection(id: 's1', name: 'Idea', content: 'Sell plants'),
          IdeaSection(id: 's2', name: 'Design', content: 'Green stall'),
          IdeaSection(
            id: 's3',
            name: 'Pricing',
            content: 'Offer a **loyalty** card for regulars',
          ),
        ],
      ))!;
    });
    await pumpSearch(tester);

    expect(find.text(ViewConstants.searchIdeasEmptyPromptAll), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ideas-search-field')),
      'LOYALTY regulars',
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(Key('idea-card-${idea.id}')), findsNothing);

    await settle(tester);

    expect(find.byKey(Key('idea-card-${idea.id}')), findsOneWidget);
    expect(find.byKey(const Key('idea-card-search-section')), findsOneWidget);
    final snippet = tester.widget<Text>(
      find.byKey(const Key('idea-card-search-snippet-text')),
    );
    expect(snippet.textSpan!.toPlainText(), contains('loyalty card'));
    expect(snippet.textSpan!.toPlainText(), isNot(contains('**')));

    await tester.tap(find.byKey(Key('idea-card-${idea.id}')));
    await settle(tester);

    final editor = tester.widget<TextField>(
      find.byKey(const Key('idea-markdown-text-field')),
    );
    expect(editor.controller?.text, 'Offer a loyalty card for regulars');
    expect(
      (editor.controller! as NoteEditingController).markup,
      'Offer a **loyalty** card for regulars',
    );
  });

  testWidgets('matches locked ideas by title only without a snippet',
      (tester) async {
    late Idea locked;
    await tester.runAsync(() async {
      locked = (await provider.saveIdea(
        title: 'Private diary',
        sections: const [
          IdeaSection(id: 'p1', name: 'Idea', content: 'buried treasure'),
        ],
      ))!;
      await provider.setIdeaLocked(ideaId: locked.id, isLocked: true);
    });
    await pumpSearch(tester);

    await tester.enterText(
      find.byKey(const Key('ideas-search-field')),
      'treasure',
    );
    await settle(tester);
    expect(find.byKey(Key('idea-card-${locked.id}')), findsNothing);
    expect(find.text(ViewConstants.homepageNoSearchResults), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ideas-search-field')),
      'diary',
    );
    await settle(tester);
    expect(find.byKey(Key('idea-card-${locked.id}')), findsOneWidget);
    expect(find.byKey(const Key('idea-card-search-snippet')), findsNothing);
    expect(find.textContaining('treasure'), findsNothing);
  });

  testWidgets('a query of only spaces shows the prompt', (tester) async {
    await tester.runAsync(() async {
      await provider.saveIdea(
        title: 'Anything',
        sections: const [IdeaSection(id: 'x', name: 'Idea', content: 'text')],
      );
    });
    await pumpSearch(tester);

    await tester.enterText(find.byKey(const Key('ideas-search-field')), '   ');
    await settle(tester);

    expect(find.byKey(const Key('search-ideas-empty-prompt')), findsOneWidget);
  });

  testWidgets('results update when a matching idea changes', (tester) async {
    late Idea idea;
    await tester.runAsync(() async {
      idea = (await provider.saveIdea(
        title: 'Live update',
        sections: const [IdeaSection(id: 'l1', name: 'Idea', content: 'old')],
      ))!;
    });
    await pumpSearch(tester);
    await tester.enterText(
      find.byKey(const Key('ideas-search-field')),
      'fresh',
    );
    await settle(tester);
    expect(find.byKey(Key('idea-card-${idea.id}')), findsNothing);

    await tester.runAsync(() async {
      await provider.saveIdea(
        ideaId: idea.id,
        title: idea.title,
        sections: const [
          IdeaSection(id: 'l1', name: 'Idea', content: 'fresh words'),
        ],
      );
    });
    await settle(tester);

    expect(find.byKey(Key('idea-card-${idea.id}')), findsOneWidget);
  });
}
