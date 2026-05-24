import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/free_usage_screen.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_local_storage.dart';

void main() {
  dotenv.loadFromString(envString: 'DEBUG=false');
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpScreen(
    WidgetTester tester,
    FreeUsageScreen screen,
  ) async {
    final themeProvider = ThemeProvider(ThemeRepo(MemoryLocalStorageManager()));
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: themeProvider.baseTheme.themeData,
          home: screen,
        ),
      ),
    );
    await tester.pump();
  }

  AnimatedOpacity contentOpacity(WidgetTester tester) {
    return tester.widget<AnimatedOpacity>(
      find
          .descendant(
            of: find.byKey(const Key('free-usage-content')),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
  }

  testWidgets('starts first-run screen with content hidden during animation',
      (tester) async {
    await pumpScreen(
      tester,
      const FreeUsageScreen(
        usageCount: 0,
        usageLimit: 50,
      ),
    );

    expect(find.byKey(const Key('free-usage-screen')), findsOneWidget);
    expect(contentOpacity(tester).opacity, 0);
  });

  testWidgets('shows completed state immediately when opened from drawer',
      (tester) async {
    await pumpScreen(
      tester,
      const FreeUsageScreen(
        usageCount: 10,
        usageLimit: 50,
        animationCompleted: true,
      ),
    );

    expect(contentOpacity(tester).opacity, 1);
    expect(find.text('freeUsageScreenDrawerTitle'), findsOneWidget);
    expect(find.text('freeUsageScreenDrawerBody'), findsOneWidget);
    expect(find.text('freeUsageScreenDrawerAction'), findsOneWidget);
    expect(find.byKey(const Key('free-usage-primary-action')), findsOneWidget);
  });

  testWidgets('renders current usage tile with the progress ring',
      (tester) async {
    await pumpScreen(
      tester,
      const FreeUsageScreen(
        usageCount: 25,
        usageLimit: 50,
        animationCompleted: true,
      ),
    );

    expect(
      find.byKey(const Key('free-usage-current-usage-tile')),
      findsOneWidget,
    );
    expect(find.text('freeUsageCurrentUsageTitle'), findsOneWidget);
    final progress = tester.widget<CircularProgressIndicator>(
      find.byKey(const Key('free-usage-progress-ring')),
    );
    expect(progress.value, 0.5);
  });

  testWidgets('uses fixed 99 button radius', (tester) async {
    await pumpScreen(
      tester,
      const FreeUsageScreen(
        usageCount: 0,
        usageLimit: 50,
        animationCompleted: true,
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('free-usage-primary-action')),
    );
    final styleShape = button.style?.shape?.resolve({});
    expect(styleShape, isA<RoundedRectangleBorder>());
    final shape = styleShape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(99));
  });
}
