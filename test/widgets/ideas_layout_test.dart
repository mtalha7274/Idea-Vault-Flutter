import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/config/config.dart';
import 'package:idea_vault/core/utils/idea_search.dart';
import 'package:idea_vault/data/repositories/local/idea_list_preferences.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/widgets/ideas/ideas_layout.dart';
import 'package:idea_vault/widgets/selection/selection_check_badge.dart';
import 'package:idea_vault/widgets/selection/selection_style.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('locked idea card keeps title visible with icon only overlay',
      (tester) async {
    final themeProvider = ThemeProvider(ThemeRepo(MemoryLocalStorageManager()));
    final idea = Idea(
      id: 'idea-1',
      title: 'Visible Title',
      createdAt: DateTime.utc(2026, 6, 24),
      updatedAt: DateTime.utc(2026, 6, 24),
      isLocked: true,
      sections: const [
        IdeaSection(
          id: 'section-1',
          name: 'Idea',
          content: 'Private preview',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          theme: themeProvider.baseTheme.themeData,
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 190,
              child: IdeaCard(
                idea: idea,
                layout: IdeaCardLayout.list,
                isSelected: false,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Visible Title'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.text('Private preview'), findsNothing);
    expect(find.text('homepageIdeaCardOneSection'), findsNothing);
    expect(find.text('Locked note'), findsNothing);
  });

  testWidgets('search result card shows the matched section and snippet',
      (tester) async {
    final themeProvider = ThemeProvider(ThemeRepo(MemoryLocalStorageManager()));
    Idea buildIdea({required bool isLocked}) => Idea(
          id: isLocked ? 'locked' : 'open',
          title: isLocked ? 'Locked title' : 'Open title',
          createdAt: DateTime.utc(2026, 6, 24),
          updatedAt: DateTime.utc(2026, 6, 24),
          isLocked: isLocked,
          sections: const [
            IdeaSection(id: 'first', name: 'Idea', content: 'Opening words'),
            IdeaSection(id: 'later', name: 'Budget', content: 'Rent a van'),
          ],
        );
    const snippet = IdeaSearchSnippet(
      text: 'Rent a van',
      highlights: [TextRange(start: 7, end: 10)],
    );

    Future<void> pumpCard(Idea idea) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            theme: themeProvider.baseTheme.themeData,
            home: Scaffold(
              body: SingleChildScrollView(
                child: IdeasLayout(
                  ideas: [idea],
                  layoutOption: IdeaLayoutOption.list,
                  onTap: (_) {},
                  searchResults: {
                    idea.id: IdeaSearchResult(
                      idea: idea,
                      tier: IdeaSearchMatchTier.content,
                      sectionId: 'later',
                      sectionName: 'Budget',
                      snippet: snippet,
                    ),
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpCard(buildIdea(isLocked: false));

    expect(find.byKey(const Key('idea-card-search-section')), findsOneWidget);
    expect(find.text('Opening words'), findsNothing);
    final text = tester.widget<Text>(
      find.byKey(const Key('idea-card-search-snippet-text')),
    );
    final highlighted = (text.textSpan! as TextSpan)
        .children!
        .whereType<TextSpan>()
        .where((span) => span.style?.backgroundColor != null)
        .map((span) => span.text)
        .toList();
    expect(highlighted, ['van']);

    await pumpCard(buildIdea(isLocked: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('idea-card-search-snippet')), findsNothing);
    expect(find.text('Locked title'), findsOneWidget);
  });

  group('selected idea cards', () {
    Idea buildIdea(String id, {bool isLocked = false}) => Idea(
          id: id,
          title: 'Card $id with a fairly long title that wraps',
          createdAt: DateTime.utc(2026, 6, 24),
          updatedAt: DateTime.utc(2026, 6, 24),
          isLocked: isLocked,
          sections: const [
            IdeaSection(id: 'section', name: 'Idea', content: 'Preview'),
          ],
        );

    Future<ThemeProvider> pumpLayout(
      WidgetTester tester, {
      required String themeName,
      required Set<String> selectedIds,
      TextDirection textDirection = TextDirection.ltr,
      bool isSelectionActive = true,
    }) async {
      final storage = MemoryLocalStorageManager();
      final themeProvider = ThemeProvider(ThemeRepo(storage));
      themeProvider.setTheme(theme: themeName);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            theme: themeProvider.baseTheme.themeData,
            home: Directionality(
              textDirection: textDirection,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: IdeasLayout(
                    ideas: [
                      buildIdea('a'),
                      buildIdea('b'),
                      buildIdea('c', isLocked: true),
                    ],
                    layoutOption: IdeaLayoutOption.grid,
                    selectedIdeaIds: selectedIds,
                    isSelectionActive: isSelectionActive,
                    onTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return themeProvider;
    }

    BoxDecoration cardDecoration(WidgetTester tester, String id) {
      final ink = tester.widget<Ink>(
        find.descendant(
          of: find.byKey(Key('idea-card-$id')),
          matching: find.byType(Ink),
        ),
      );
      return ink.decoration! as BoxDecoration;
    }

    for (final themeName in [Config.light, Config.dark]) {
      testWidgets('selected card has border, fill and check in $themeName',
          (tester) async {
        final themeProvider = await pumpLayout(
          tester,
          themeName: themeName,
          selectedIds: {'a', 'c'},
        );
        final theme = themeProvider.baseTheme;

        final selected = cardDecoration(tester, 'a');
        final border = selected.border! as Border;
        expect(border.top.width, 2);
        expect(border.top.color, theme.primary);
        expect(selected.color, selectionCardFillColor(theme));
        expect(selected.color, isNot(theme.surface));

        final unselected = cardDecoration(tester, 'b');
        expect((unselected.border! as Border).top.color, Colors.transparent);
        expect(unselected.color, theme.surface);

        SelectionCheckBadge badge(String id) => tester.widget(
              find.byKey(Key('idea-card-badge-$id')),
            );
        expect(badge('a').isSelected, isTrue);
        expect(badge('b').isSelected, isFalse);
        expect(badge('c').isSelected, isTrue);

        expect(
          _contrast(theme.primary, selectionCardFillColor(theme)),
          greaterThan(3),
        );
        expect(
          _contrast(theme.onPrimary, theme.primary),
          greaterThan(3),
        );
        expect(_contrast(theme.textMuted, theme.surface), greaterThan(3));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('no badges outside selection mode', (tester) async {
      await pumpLayout(
        tester,
        themeName: Config.light,
        selectedIds: const {},
        isSelectionActive: false,
      );

      expect(find.byType(SelectionCheckBadge), findsNothing);
    });

    testWidgets('badge sits top-right and mirrors to top-left in RTL',
        (tester) async {
      await pumpLayout(tester, themeName: Config.light, selectedIds: {'a'});
      final ltrCard = tester.getRect(find.byKey(const Key('idea-card-a')));
      final ltrBadge =
          tester.getRect(find.byKey(const Key('idea-card-badge-a')));
      expect(ltrBadge.center.dx, greaterThan(ltrCard.center.dx));
      expect(ltrBadge.center.dy, lessThan(ltrCard.center.dy));

      await pumpLayout(
        tester,
        themeName: Config.light,
        selectedIds: {'a'},
        textDirection: TextDirection.rtl,
      );
      final rtlCard = tester.getRect(find.byKey(const Key('idea-card-a')));
      final rtlBadge =
          tester.getRect(find.byKey(const Key('idea-card-badge-a')));
      expect(rtlBadge.center.dx, lessThan(rtlCard.center.dx));
      expect(rtlBadge.center.dy, lessThan(rtlCard.center.dy));
    });
  });
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}
