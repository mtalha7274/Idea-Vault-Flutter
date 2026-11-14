import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization_loader/easy_localization_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/config/config.dart';
import 'package:idea_vault/config/languages/language_config.dart';
import 'package:idea_vault/core/constants/app_assets.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/idea_list_preferences.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/homepage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import '../test/helpers/in_memory_ideas_repo.dart';
import '../test/helpers/in_memory_random_additions_repo.dart';
import '../test/helpers/memory_local_storage.dart';

const _editorIdeaTitle = 'Weekend Market App';

final _sampleIdeas = <(String, List<(String, String)>)>[
  (
    'Plant Care Reminders',
    [
      (
        'Idea',
        'Snap a photo of each plant and get watering reminders that adapt to the season.',
      ),
      ('Features', '- Light level tips\n- Shared plants for flatmates'),
    ],
  ),
  (
    'Recipe Swap Club',
    [
      (
        'Idea',
        'A tiny club where neighbours trade one home-cooked dish every Friday.',
      ),
    ],
  ),
  (
    'Focus Timer for Writers',
    [
      (
        'Idea',
        'Pomodoro timer that counts words written instead of minutes spent.',
      ),
      ('Design', '## Calm screen\nOnly the text and a soft progress bar.'),
    ],
  ),
  (
    'Bike Route Journal',
    [
      (
        'Idea',
        'Log rides with notes and photos, then turn them into a shareable map.',
      ),
    ],
  ),
  (
    _editorIdeaTitle,
    [
      (
        'Idea',
        '## Fresh food, booked ahead\n'
            'Let local stalls take **pre-orders** so nothing goes to waste. '
            'Pickup codes work _offline_.\n'
            '- [x] Interview five stall owners\n'
            '- [x] Sketch the order flow\n'
            '- [ ] Build a prototype with `flutter create`\n'
            '- [ ] Share it on [the market forum](https://example.com)',
      ),
      ('Requirements', '- Works without signal\n- Simple stall dashboard'),
      ('Marketing', 'Posters at the entrance with a QR code.'),
    ],
  ),
];

const _sampleNotes = [
  'Ask Sara about the farmers market Wi-Fi',
  'Idea: loyalty stamps for repeat buyers',
  'Try a darker green for the order button',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dotenv.loadFromString(envString: 'DEBUG=false');

  testWidgets('capture README screenshots', (tester) async {
    await EasyLocalization.ensureInitialized();
    final storage = MemoryLocalStorageManager();
    final listPreferences = IdeaListPreferencesRepo(storage);
    final secureValues = <String, String>{};
    Future<String?> read(String key) async => secureValues[key];
    Future<void> write(String key, String value) async {
      secureValues[key] = value;
    }

    Future<void> delete(String key) async {
      secureValues.remove(key);
    }

    for (final register in <void Function()>[
      () => sl.registerSingleton<IdeaListPreferencesRepo>(listPreferences),
      () => sl.registerSingleton<NoteLockAuthService>(
            NoteLockAuthService(
              readValue: read,
              writeValue: write,
              deleteValue: delete,
            ),
          ),
      () => sl.registerSingleton<NoteLockBiometricService>(
            NoteLockBiometricService(
              readValue: read,
              writeValue: write,
              deleteValue: delete,
              isDeviceSupported: () async => false,
              canCheckBiometrics: () async => false,
            ),
          ),
    ]) {
      register();
    }

    final themeProvider = ThemeProvider(ThemeRepo(storage))
      ..setTheme(theme: Config.light);
    final ideasProvider =
        IdeasProvider(InMemoryIdeasRepo(), IdeaEditorStateRepo(storage));
    final notesProvider = RandomAdditionsProvider(
      InMemoryRandomAdditionsRepo(),
    );
    String? editorIdeaId;
    String? editorSectionId;
    await ideasProvider.ensureLoaded();
    await notesProvider.ensureLoaded();
    for (final (title, sections) in _sampleIdeas) {
      final saved = await ideasProvider.saveIdea(
        title: title,
        sections: [
          for (final (name, content) in sections)
            IdeaSection.empty(name: name).copyWith(content: content),
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (title == _editorIdeaTitle) {
        editorIdeaId = saved!.id;
        editorSectionId = saved.sections.first.id;
      }
    }
    await ideasProvider.saveLastOpenedSectionId(
      ideaId: editorIdeaId!,
      sectionId: editorSectionId!,
    );
    for (final note in _sampleNotes) {
      await notesProvider.addAddition(note);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    await tester.pumpWidget(
      EasyLocalization(
        assetLoader: CsvAssetLoader(),
        path: AppAssets.translations,
        fallbackLocale: LanguageConfig.defaultLanguage.locale,
        supportedLocales: LanguageConfig.locales,
        saveLocale: false,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<IdeasProvider>.value(value: ideasProvider),
            ChangeNotifierProvider<RandomAdditionsProvider>.value(
              value: notesProvider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: Builder(
            builder: (context) {
              final theme = context.watch<ThemeProvider>().baseTheme;
              return MaterialApp(
                navigatorKey: navigatorKey,
                debugShowCheckedModeBanner: false,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                theme: theme.themeData,
                home: Homepage(sortPreferencesRepo: listPreferences),
              );
            },
          ),
        ),
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      try {
        await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 10));
      } catch (_) {}
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> capture(String name) async {
      await settle();
      await binding.takeScreenshot(name);
    }

    Future<void> goBack() async {
      await tester.binding.handlePopRoute();
      await settle();
    }

    Future<void> captureAll(String suffix) async {
      await capture('home$suffix');

      await tester.tap(find.byKey(Key('idea-card-$editorIdeaId')));
      await capture('editor$suffix');
      await tester.tap(find.byKey(const Key('idea-editor-close')));
      await settle();

      await tester.tap(find.byKey(const Key('ideas-search-button')));
      await settle();
      await tester.enterText(find.byType(TextField).first, 'stall');
      FocusManager.instance.primaryFocus?.unfocus();
      await capture('search$suffix');
      await goBack();

      await tester.tap(find.byKey(const Key('home-quick-note-button')));
      await settle();
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      final firstNote = notesProvider.additions.first;
      await tester.longPress(
        find.byKey(Key('random-addition-bubble-${firstNote.id}')),
      );
      await capture('random_notes$suffix');
      await goBack();
      await goBack();
    }

    await captureAll('');
    themeProvider.setTheme(theme: Config.dark);
    await settle();
    await captureAll('_dark');
  });
}
