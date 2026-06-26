import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/widgets/speech_to_text_mic_fab.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('SpeechToTextMicFab', () {
    late ThemeProvider themeProvider;

    setUp(() {
      themeProvider = ThemeProvider(ThemeRepo(MemoryLocalStorageManager()));
    });

    Future<void> pumpFab(
      WidgetTester tester, {
      required bool isListening,
      required bool isActivating,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            theme: themeProvider.baseTheme.themeData,
            home: Scaffold(
              floatingActionButton: SpeechToTextMicFab(
                isListening: isListening,
                isActivating: isActivating,
                onTap: () {},
                onLongPressStart: () async {},
                onLongPressEnd: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows mic button with test key in idle state', (tester) async {
      await pumpFab(
        tester,
        isListening: false,
        isActivating: false,
      );

      expect(find.byKey(const Key('idea-editor-mic-fab')), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.text(ViewConstants.ideaEditorListening), findsNothing);
    });

    testWidgets('shows listening label while activating', (tester) async {
      await pumpFab(
        tester,
        isListening: false,
        isActivating: true,
      );

      await tester.pump();

      expect(find.byKey(const Key('idea-editor-mic-fab')), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.text(ViewConstants.ideaEditorListening), findsOneWidget);
    });

    testWidgets('shows listening label immediately when activating',
        (tester) async {
      await pumpFab(
        tester,
        isListening: false,
        isActivating: true,
      );

      await tester.pump();

      expect(find.text(ViewConstants.ideaEditorListening), findsOneWidget);
    });

    testWidgets('keeps listening label when transitioning activating to listening',
        (tester) async {
      await pumpFab(
        tester,
        isListening: false,
        isActivating: true,
      );
      await tester.pump();

      expect(find.text(ViewConstants.ideaEditorListening), findsOneWidget);

      await pumpFab(
        tester,
        isListening: true,
        isActivating: false,
      );
      await tester.pump();

      expect(find.text(ViewConstants.ideaEditorListening), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    });

    testWidgets('shows listening label and active icon when listening',
        (tester) async {
      await pumpFab(
        tester,
        isListening: true,
        isActivating: false,
      );

      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(ViewConstants.ideaEditorListening), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    });

    testWidgets('updates from idle to listening state', (tester) async {
      var isListening = false;
      var isActivating = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            theme: themeProvider.baseTheme.themeData,
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  floatingActionButton: SpeechToTextMicFab(
                    isListening: isListening,
                    isActivating: isActivating,
                    onTap: () {},
                    onLongPressStart: () async {},
                    onLongPressEnd: () async {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(ViewConstants.ideaEditorListening), findsNothing);

      isListening = true;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            theme: themeProvider.baseTheme.themeData,
            home: Scaffold(
              floatingActionButton: SpeechToTextMicFab(
                isListening: true,
                isActivating: false,
                onTap: () {},
                onLongPressStart: () async {},
                onLongPressEnd: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(ViewConstants.ideaEditorListening), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    });
  });
}
