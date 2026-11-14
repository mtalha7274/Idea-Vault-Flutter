import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/config/config.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/core/services/note_lock_session_guard.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/random_addition.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/random_additions_screen.dart';
import 'package:idea_vault/widgets/selection/selection_check_badge.dart';
import 'package:idea_vault/widgets/selection/selection_style.dart';
import 'package:provider/provider.dart';

import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/in_memory_random_additions_repo.dart';
import '../helpers/memory_local_storage.dart';

void main() {
  dotenv.loadFromString(envString: 'DEBUG=false');
  GoogleFonts.config.allowRuntimeFetching = false;

  late MemoryLocalStorageManager storage;
  late _FlakyIdeasRepo ideasRepo;
  late IdeasProvider ideasProvider;
  late RandomAdditionsProvider additionsProvider;
  late ThemeProvider themeProvider;
  late List<String> clipboardWrites;

  setUp(() async {
    storage = MemoryLocalStorageManager();
    ideasRepo = _FlakyIdeasRepo();
    ideasProvider = IdeasProvider(ideasRepo, IdeaEditorStateRepo(storage));
    additionsProvider = RandomAdditionsProvider(InMemoryRandomAdditionsRepo());
    themeProvider = ThemeProvider(ThemeRepo(storage));
    themeProvider.setTheme(theme: Config.light);
    await ideasProvider.ensureLoaded();
    await additionsProvider.ensureLoaded();
    NoteLockSecureWindow.resetForTesting();
    clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(arguments['text']! as String);
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    if (sl.isRegistered<NoteLockAuthService>()) {
      await sl.unregister<NoteLockAuthService>();
    }
    if (sl.isRegistered<NoteLockBiometricService>()) {
      await sl.unregister<NoteLockBiometricService>();
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 6; round++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<IdeasProvider>.value(value: ideasProvider),
          ChangeNotifierProvider<RandomAdditionsProvider>.value(
            value: additionsProvider,
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
          builder: (context, child) => Directionality(
            textDirection: textDirection,
            child: child!,
          ),
          home: const RandomAdditionsScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<List<RandomAddition>> addNotes(
    WidgetTester tester,
    List<String> contents,
  ) async {
    final added = <RandomAddition>[];
    await tester.runAsync(() async {
      for (final content in contents) {
        added.add((await additionsProvider.addAddition(content))!);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    });
    return added;
  }

  Finder row(RandomAddition addition) =>
      find.byKey(Key('random-addition-row-${addition.id}'));
  Finder band(RandomAddition addition) =>
      find.byKey(Key('random-addition-band-${addition.id}'));
  Finder bubble(RandomAddition addition) =>
      find.byKey(Key('random-addition-bubble-${addition.id}'));

  Color? bandColor(WidgetTester tester, RandomAddition addition) {
    final container = tester.widget<AnimatedContainer>(band(addition));
    return (container.decoration as BoxDecoration?)?.color;
  }

  Color bubbleColor(WidgetTester tester, RandomAddition addition) {
    final material = tester.widget<Material>(
      find
          .ancestor(of: bubble(addition), matching: find.byType(Material))
          .first,
    );
    return material.color!;
  }

  testWidgets('selected row gets an edge-to-edge band, bubble keeps colours',
      (tester) async {
    final notes = await addNotes(tester, ['First', 'Second', 'Third']);
    await pumpScreen(tester);
    final theme = themeProvider.baseTheme;
    final screenWidth = tester.getSize(find.byType(Scaffold)).width;

    expect(bubbleColor(tester, notes[0]), theme.primary);

    await tester.longPress(bubble(notes[0]));
    await settle(tester);
    await tester.tap(row(notes[1]));
    await settle(tester);

    expect(bandColor(tester, notes[0]), selectionBandColor(theme));
    expect(bandColor(tester, notes[1]), selectionBandColor(theme));
    expect(bandColor(tester, notes[2]), Colors.transparent);
    expect(bubbleColor(tester, notes[0]), theme.primary);

    final firstBand = tester.getRect(band(notes[0]));
    final secondBand = tester.getRect(band(notes[1]));
    expect(firstBand.left, 0);
    expect(firstBand.width, screenWidth);
    expect((firstBand.bottom - secondBand.top).abs(), lessThan(0.5));

    final checks = tester
        .widgetList<SelectionCheckBadge>(find.byType(SelectionCheckBadge))
        .toList();
    expect(checks, hasLength(3));
    expect(checks.where((check) => check.isSelected), hasLength(2));
  });

  testWidgets('whole row is the tap target and last deselect exits',
      (tester) async {
    final notes = await addNotes(tester, ['Only note']);
    await pumpScreen(tester);

    await tester.longPress(bubble(notes.single));
    await settle(tester);
    expect(
      find.byKey(const Key('random-additions-selection-count')),
      findsOneWidget,
    );

    final rowRect = tester.getRect(row(notes.single));
    await tester.tapAt(Offset(rowRect.left + 4, rowRect.center.dy));
    await settle(tester);

    expect(
      find.byKey(const Key('random-additions-selection-count')),
      findsNothing,
    );
    expect(find.byType(SelectionCheckBadge), findsNothing);
    expect(find.text(ViewConstants.randomAdditionsTitle), findsOneWidget);
  });

  testWidgets('tapping a note outside selection still opens the filing sheet',
      (tester) async {
    final notes = await addNotes(tester, ['Tap me']);
    await pumpScreen(tester);

    await tester.tap(bubble(notes.single));
    await settle(tester);

    expect(find.byKey(const Key('random-additions-no-ideas')), findsOneWidget);
    expect(
      find.byKey(const Key('random-additions-selection-count')),
      findsNothing,
    );
  });

  testWidgets('back exits selection before leaving the screen', (tester) async {
    final notes = await addNotes(tester, ['Stay here']);
    await pumpScreen(tester);

    await tester.longPress(bubble(notes.single));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(find.byKey(const Key('random-additions-screen')), findsOneWidget);
    expect(
      find.byKey(const Key('random-additions-selection-count')),
      findsNothing,
    );
  });

  testWidgets('copy joins the selected notes in time order', (tester) async {
    final notes = await addNotes(tester, ['Early', 'Middle', 'Late']);
    await pumpScreen(tester);

    await tester.longPress(bubble(notes[2]));
    await settle(tester);
    await tester.tap(row(notes[0]));
    await settle(tester);

    await tester.tap(find.byKey(const Key('random-additions-copy-button')));
    await settle(tester);

    expect(clipboardWrites, ['Early\n\nLate']);
    expect(find.text(ViewConstants.selectionCopiedMany), findsOneWidget);
    expect(
      find.byKey(const Key('random-additions-selection-count')),
      findsNothing,
    );
    expect(additionsProvider.additions, hasLength(3));
  });

  testWidgets('files selected notes into one section in time order',
      (tester) async {
    late Idea idea;
    await tester.runAsync(() async {
      idea = (await ideasProvider.saveIdea(
        title: 'Destination',
        sections: const [
          IdeaSection(id: 'dest-section', name: 'Notes', content: 'Start'),
        ],
      ))!;
    });
    final notes = await addNotes(tester, ['One', 'Two', 'Three']);
    await pumpScreen(tester);

    await tester.longPress(bubble(notes[2]));
    await settle(tester);
    await tester.tap(row(notes[0]));
    await settle(tester);

    await tester.tap(find.byKey(const Key('random-additions-file-button')));
    await settle(tester);
    await tester.tap(find.byKey(Key('random-addition-idea-${idea.id}')));
    await settle(tester);
    await tester
        .tap(find.byKey(const Key('random-addition-section-dest-section')));
    await settle(tester);

    expect(
      ideasProvider.findById(idea.id)!.sections.single.content,
      'Start\n\nOne\n\nThree',
    );
    expect(additionsProvider.additions.map((note) => note.content), ['Two']);
    expect(
      find.byKey(const Key('random-additions-selection-count')),
      findsNothing,
    );
    expect(find.text(ViewConstants.selectionFiledManySnackbar), findsOneWidget);
  });

  testWidgets('a failed save keeps the remaining notes selected',
      (tester) async {
    late Idea idea;
    await tester.runAsync(() async {
      idea = (await ideasProvider.saveIdea(
        title: 'Flaky',
        sections: const [
          IdeaSection(id: 'flaky-section', name: 'Notes', content: 'Base'),
        ],
      ))!;
    });
    final notes = await addNotes(tester, ['Saved', 'Lost', 'Pending']);
    await pumpScreen(tester);

    await tester.longPress(bubble(notes[0]));
    await settle(tester);
    await tester.tap(row(notes[1]));
    await settle(tester);
    await tester.tap(row(notes[2]));
    await settle(tester);

    ideasRepo.failAfterWrites = 1;
    await tester.tap(find.byKey(const Key('random-additions-file-button')));
    await settle(tester);
    await tester.tap(find.byKey(Key('random-addition-idea-${idea.id}')));
    await settle(tester);
    await tester
        .tap(find.byKey(const Key('random-addition-section-flaky-section')));
    await settle(tester);

    expect(
      ideasProvider.findById(idea.id)!.sections.single.content,
      'Base\n\nSaved',
    );
    expect(
      additionsProvider.additions.map((note) => note.content),
      ['Lost', 'Pending'],
    );
    expect(
        find.text(ViewConstants.selectionFilePartialFailure), findsOneWidget);
    final selected = tester
        .widgetList<SelectionCheckBadge>(find.byType(SelectionCheckBadge))
        .where((check) => check.isSelected);
    expect(selected, hasLength(2));
  });

  testWidgets('filing a selection into a locked idea unlocks first',
      (tester) async {
    final secureStorage = <String, String>{};
    final authService = NoteLockAuthService(
      random: Random(1),
      readValue: (key) async => secureStorage[key],
      writeValue: (key, value) async {
        secureStorage[key] = value;
      },
      deleteValue: (key) async {
        secureStorage.remove(key);
      },
    );
    await authService.createPin('2468');
    sl.registerSingleton<NoteLockAuthService>(authService);
    sl.registerSingleton<NoteLockBiometricService>(
      NoteLockBiometricService(
        readValue: (key) async => secureStorage[key],
        writeValue: (key, value) async {
          secureStorage[key] = value;
        },
        isDeviceSupported: () async => false,
        canCheckBiometrics: () async => false,
        authenticate: ({
          required String localizedReason,
          bool biometricOnly = false,
          bool persistAcrossBackgrounding = false,
        }) async =>
            false,
      ),
    );
    late Idea locked;
    await tester.runAsync(() async {
      locked = (await ideasProvider.saveIdea(
        title: 'Locked plans',
        sections: const [
          IdeaSection(id: 'secret-section', name: 'Hidden', content: 'Old'),
        ],
      ))!;
      await ideasProvider.setIdeaLocked(ideaId: locked.id, isLocked: true);
    });
    final notes = await addNotes(tester, ['Alpha', 'Beta']);
    await pumpScreen(tester);

    await tester.longPress(bubble(notes[1]));
    await settle(tester);
    await tester.tap(row(notes[0]));
    await settle(tester);
    await tester.tap(find.byKey(const Key('random-additions-file-button')));
    await settle(tester);

    final ideaTile = find.byKey(Key('random-addition-idea-${locked.id}'));
    expect(
      find.descendant(
        of: ideaTile,
        matching: find.byIcon(Icons.lock_outline_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(ideaTile);
    await settle(tester);

    expect(find.byKey(const Key('note-lock-pin-screen')), findsOneWidget);
    expect(find.text('Hidden'), findsNothing);

    await tester.enterText(find.byType(TextField).last, '2468');
    await settle(tester);
    await tester
        .tap(find.byKey(const Key('random-addition-section-secret-section')));
    await settle(tester);

    expect(
      ideasProvider.findById(locked.id)!.sections.single.content,
      'Old\n\nAlpha\n\nBeta',
    );
    expect(additionsProvider.additions, isEmpty);
    expect(authService.isIdeaUnlocked(locked.id), isFalse);
  });

  testWidgets('composer stays usable during selection', (tester) async {
    final notes = await addNotes(tester, ['Selected note']);
    await pumpScreen(tester);

    await tester.longPress(bubble(notes.single));
    await settle(tester);

    await tester.enterText(
      find.byKey(const Key('random-additions-composer')),
      'Fresh capture',
    );
    await tester.tap(find.byKey(const Key('random-additions-send')));
    await settle(tester);

    expect(additionsProvider.additions, hasLength(2));
    expect(
      find.byKey(const Key('random-additions-selection-count')),
      findsOneWidget,
    );
    final selected = tester
        .widgetList<SelectionCheckBadge>(find.byType(SelectionCheckBadge))
        .where((check) => check.isSelected);
    expect(selected, hasLength(1));
  });

  testWidgets('delete dialog uses translated strings', (tester) async {
    final notes = await addNotes(tester, ['Delete me']);
    await pumpScreen(tester);

    await tester.longPress(bubble(notes.single));
    await settle(tester);
    await tester.tap(find.byKey(const Key('random-additions-delete-button')));
    await settle(tester);

    expect(
        find.text(ViewConstants.selectionDeleteNoteTitleOne), findsOneWidget);
    expect(find.text(ViewConstants.selectionDeleteNoteBodyOne), findsOneWidget);
    expect(find.text(ViewConstants.cancel), findsOneWidget);
    expect(find.text(ViewConstants.selectionDeleteConfirm), findsOneWidget);

    await tester.tap(find.byKey(const Key('random-additions-delete-confirm')));
    await settle(tester);

    expect(additionsProvider.additions, isEmpty);
    expect(find.byKey(const Key('random-additions-empty')), findsOneWidget);
  });

  testWidgets('selected row is announced as selected', (tester) async {
    final semantics = tester.ensureSemantics();
    final notes = await addNotes(tester, ['Announce', 'Other']);
    await pumpScreen(tester);

    await tester.longPress(bubble(notes[0]));
    await settle(tester);

    expect(
      tester.getSemantics(row(notes[0])),
      containsSemantics(isSelected: true),
    );
    semantics.dispose();
  });

  testWidgets('band and check mirror in right-to-left layouts', (tester) async {
    final notes = await addNotes(tester, ['Mirrored']);
    await pumpScreen(tester, textDirection: TextDirection.rtl);
    final screenWidth = tester.getSize(find.byType(Scaffold)).width;

    await tester.longPress(bubble(notes.single));
    await settle(tester);

    final bandRect = tester.getRect(band(notes.single));
    final checkRect = tester
        .getRect(find.byKey(Key('random-addition-check-${notes.single.id}')));
    final bubbleRect = tester.getRect(bubble(notes.single));
    expect(bandRect.left, 0);
    expect(bandRect.width, screenWidth);
    expect(checkRect.center.dx, greaterThan(screenWidth / 2));
    expect(bubbleRect.center.dx, lessThan(checkRect.center.dx));
  });

  testWidgets('band is visible against the background in the dark theme',
      (tester) async {
    themeProvider.setTheme(theme: Config.dark);
    final notes = await addNotes(tester, ['Dark note']);
    await pumpScreen(tester);
    final theme = themeProvider.baseTheme;

    await tester.longPress(bubble(notes.single));
    await settle(tester);

    final bandOnBackground =
        Color.alphaBlend(bandColor(tester, notes.single)!, theme.background);
    expect(
      _contrast(bandOnBackground, theme.background),
      greaterThan(1.3),
    );
    expect(_contrast(theme.primary, bandOnBackground), greaterThan(3));
    expect(bubbleColor(tester, notes.single), theme.primary);
  });
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = max(first, second);
  final darker = min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

class _FlakyIdeasRepo extends InMemoryIdeasRepo {
  int? failAfterWrites;
  int _writes = 0;

  @override
  Future<void> upsertIdea(Idea idea) async {
    final limit = failAfterWrites;
    if (limit != null) {
      if (_writes >= limit) {
        throw StateError('write failed');
      }
      _writes += 1;
    }
    await super.upsertIdea(idea);
  }
}
