import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/config/config.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/widgets/home/quick_note_button.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpButton(
    WidgetTester tester, {
    required int count,
    VoidCallback? onPressed,
    double width = 360,
    TextDirection textDirection = TextDirection.ltr,
    String themeName = Config.light,
  }) async {
    final themeProvider = ThemeProvider(ThemeRepo(MemoryLocalStorageManager()));
    themeProvider.setTheme(theme: themeName);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          theme: themeProvider.baseTheme.themeData,
          home: Directionality(
            textDirection: textDirection,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: QuickNoteButton(
                    unfiledCount: count,
                    onPressed: onPressed ?? () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('hides the badge without unfiled notes', (tester) async {
    await pumpButton(tester, count: 0);

    expect(find.byKey(const Key('home-quick-note-count')), findsNothing);
    expect(
        find.text(ViewConstants.randomAdditionsComposerHint), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('shows the exact count up to 99 and 99+ above', (tester) async {
    await pumpButton(tester, count: 99);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-quick-note-count')),
        matching: find.text('99'),
      ),
      findsOneWidget,
    );

    await pumpButton(tester, count: 100);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-quick-note-count')),
        matching: find.text(ViewConstants.homeQuickNoteCountOverflow),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping anywhere on the pill calls onPressed', (tester) async {
    var taps = 0;
    await pumpButton(tester, count: 3, onPressed: () => taps += 1);

    final rect =
        tester.getRect(find.byKey(const Key('home-quick-note-button')));
    await tester.tapAt(rect.centerLeft + const Offset(12, 0));
    await tester.tapAt(rect.center);
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));

    expect(taps, 3);
    expect(rect.height, greaterThanOrEqualTo(QuickNoteButton.height));
  });

  testWidgets('is announced as a button with the count', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpButton(tester, count: 2);

    final node = tester.getSemantics(find.byType(QuickNoteButton));
    expect(
      node,
      containsSemantics(
        isButton: true,
        isTextField: false,
        hasTapAction: true,
        label:
            '${ViewConstants.randomAdditionsComposerHint}, ${ViewConstants.randomAdditionsCountMany}',
      ),
    );
    semantics.dispose();
  });

  testWidgets('long label ellipsises while badge and arrow keep their size',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpButton(tester, count: 120, width: 260);

    expect(tester.takeException(), isNull);
    final label = tester.widget<Text>(
      find.text(ViewConstants.randomAdditionsComposerHint),
    );
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    final arrowCircle = tester.getSize(
      find
          .ancestor(
            of: find.byIcon(Icons.arrow_forward_rounded),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(arrowCircle, const Size(38, 38));
  });

  testWidgets('arrow and badge move to the left in right-to-left layouts',
      (tester) async {
    await pumpButton(tester, count: 5, textDirection: TextDirection.rtl);

    final button =
        tester.getRect(find.byKey(const Key('home-quick-note-button')));
    final arrow = tester.getRect(find.byIcon(Icons.arrow_forward_rounded));
    final badge =
        tester.getRect(find.byKey(const Key('home-quick-note-count')));
    expect(arrow.center.dx, lessThan(button.center.dx));
    expect(badge.center.dx, lessThan(button.center.dx));
  });

  testWidgets('renders in the dark theme', (tester) async {
    await pumpButton(tester, count: 4, themeName: Config.dark);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('home-quick-note-count')), findsOneWidget);
  });
}
