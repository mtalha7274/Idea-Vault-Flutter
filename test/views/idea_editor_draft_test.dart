import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/editor/note_editor_preferences.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/core/services/note_lock_session_guard.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/idea_editor.dart';
import 'package:idea_vault/widgets/editor/note_editing_controller.dart';
import 'package:provider/provider.dart';

import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/memory_local_storage.dart';

class _FailingIdeasRepo extends InMemoryIdeasRepo {
  bool failWrites = false;

  @override
  Future<void> upsertIdea(Idea idea) async {
    if (failWrites) {
      throw StateError('write failed');
    }
    await super.upsertIdea(idea);
  }
}

void main() {
  dotenv.loadFromString(envString: 'DEBUG=false');
  GoogleFonts.config.allowRuntimeFetching = false;

  late MemoryLocalStorageManager storage;
  late InMemoryIdeasRepo ideasRepo;
  late IdeasProvider provider;
  late ThemeProvider themeProvider;
  late NoteLockAuthService authService;

  setUp(() async {
    storage = MemoryLocalStorageManager();
    ideasRepo = InMemoryIdeasRepo();
    provider = IdeasProvider(ideasRepo, IdeaEditorStateRepo(storage));
    themeProvider = ThemeProvider(ThemeRepo(storage));
    await provider.ensureLoaded();

    final secureStorage = <String, String>{};
    authService = NoteLockAuthService(
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
    final biometricService = NoteLockBiometricService(
      readValue: (key) async => secureStorage[key],
      writeValue: (key, value) async {
        secureStorage[key] = value;
      },
      isDeviceSupported: () async => false,
      canCheckBiometrics: () async => false,
    );
    if (sl.isRegistered<NoteLockAuthService>()) {
      await sl.unregister<NoteLockAuthService>();
    }
    if (sl.isRegistered<NoteLockBiometricService>()) {
      await sl.unregister<NoteLockBiometricService>();
    }
    sl.registerSingleton<NoteLockAuthService>(authService);
    sl.registerSingleton<NoteLockBiometricService>(biometricService);
    NoteLockSecureWindow.resetForTesting();
    NoteLockSessionGuard.resetForTesting();
  });

  tearDown(() async {
    NoteEditorPreferences.storageOverride = null;
    if (sl.isRegistered<NoteLockAuthService>()) {
      await sl.unregister<NoteLockAuthService>();
    }
    if (sl.isRegistered<NoteLockBiometricService>()) {
      await sl.unregister<NoteLockBiometricService>();
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pump();
  }

  Future<void> pumpHost(
    WidgetTester tester,
    Widget Function() editorBuilder,
  ) async {
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('open-editor'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => editorBuilder()),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-editor')));
    await settle(tester);
  }

  Future<void> closeEditor(WidgetTester tester) async {
    tester
        .widget<IconButton>(find.byKey(const Key('idea-editor-close')))
        .onPressed!
        .call();
    await settle(tester);
  }

  void sendLifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  const toBackground = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  Future<Idea> saveExistingIdea({
    String title = 'Existing',
    List<IdeaSection>? sections,
    bool isLocked = false,
  }) async {
    final saved = await provider.saveIdea(
      title: title,
      sections: sections ??
          const [IdeaSection(id: 'existing-s1', name: 'Idea', content: 'Body')],
    );
    if (isLocked) {
      await provider.setIdeaLocked(ideaId: saved!.id, isLocked: true);
    }
    return provider.findById(saved!.id)!;
  }

  group('new idea drafts', () {
    testWidgets('opening and closing a new idea stores nothing',
        (tester) async {
      await pumpHost(tester, () => const IdeaEditorScreen());

      for (var round = 0; round < 3; round++) {
        await openEditor(tester);
        expect(find.byKey(const Key('idea-editor-title')), findsOneWidget);
        expect(provider.ideas, isEmpty);
        await closeEditor(tester);
      }

      await openEditor(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);

      expect(provider.ideas, isEmpty);
      expect(await ideasRepo.getIdeas(), isEmpty);
      expect(provider.resumeEditorState, isNull);
      expect(find.byKey(const Key('idea-editor-save-failed')), findsNothing);
    });

    testWidgets('a draft emptied again in the same session is deleted',
        (tester) async {
      await pumpHost(tester, () => const IdeaEditorScreen());
      await openEditor(tester);

      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Temporary',
      );
      await settle(tester);
      expect(provider.ideas, hasLength(1));

      await tester.enterText(find.byKey(const Key('idea-editor-title')), '');
      await settle(tester);
      await closeEditor(tester);

      expect(provider.ideas, isEmpty);
      expect(await ideasRepo.getIdeas(), isEmpty);
    });

    testWidgets('typed content is saved as an untitled idea', (tester) async {
      await pumpHost(tester, () => const IdeaEditorScreen());
      await openEditor(tester);

      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'Content first',
      );
      await closeEditor(tester);

      expect(provider.ideas, hasLength(1));
      expect(provider.ideas.single.title, ViewConstants.ideaEditorUntitledIdea);
    });

    testWidgets('adding a section alone makes the draft worth keeping',
        (tester) async {
      await pumpHost(tester, () => const IdeaEditorScreen());
      await openEditor(tester);

      await tester.tap(find.byKey(const Key('idea-editor-add-section')));
      await settle(tester);
      await closeEditor(tester);

      expect(provider.ideas, hasLength(1));
      expect(provider.ideas.single.sections, hasLength(2));
    });

    testWidgets('an unsaved draft offers Discard instead of export and delete',
        (tester) async {
      await pumpHost(tester, () => const IdeaEditorScreen());
      await openEditor(tester);

      await tester.tap(find.byKey(const Key('idea-editor-menu')));
      await settle(tester);

      expect(
          find.byKey(const Key('idea-editor-option-discard')), findsOneWidget);
      expect(
        find.byKey(const Key('idea-editor-option-export-ai')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('idea-editor-option-delete-idea')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('idea-editor-option-discard')));
      await settle(tester);

      expect(find.byKey(const Key('idea-editor-title')), findsNothing);
      expect(provider.ideas, isEmpty);
    });

    testWidgets('a saved draft shows export and delete options',
        (tester) async {
      await pumpHost(tester, () => const IdeaEditorScreen());
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Saved draft',
      );
      await tester.tap(find.byKey(const Key('idea-editor-menu')));
      await settle(tester);

      expect(find.byKey(const Key('idea-editor-option-discard')), findsNothing);
      expect(
        find.byKey(const Key('idea-editor-option-delete-idea')),
        findsOneWidget,
      );
      expect(provider.ideas, hasLength(1));
    });

    testWidgets('save failed indicator stays hidden when nothing needs saving',
        (tester) async {
      final failingRepo = _FailingIdeasRepo()..failWrites = true;
      provider = IdeasProvider(failingRepo, IdeaEditorStateRepo(storage));
      await provider.ensureLoaded();
      await pumpHost(tester, () => const IdeaEditorScreen());
      await openEditor(tester);

      expect(find.byKey(const Key('idea-editor-save-failed')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('idea-editor-title')),
        'Will fail',
      );
      await settle(tester);
      expect(find.byKey(const Key('idea-editor-save-failed')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('idea-editor-title')), '');
      await settle(tester);
      expect(find.byKey(const Key('idea-editor-save-failed')), findsNothing);
      expect(provider.ideas, isEmpty);
    });
  });

  group('existing ideas', () {
    testWidgets('an existing idea emptied by the user is kept', (tester) async {
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea();
      });
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      await tester.enterText(find.byKey(const Key('idea-editor-title')), '');
      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        '',
      );
      await closeEditor(tester);

      expect(provider.ideas, hasLength(1));
      expect(provider.ideas.single.id, idea.id);
      expect(provider.ideas.single.sections.single.content, isEmpty);
    });

    testWidgets('opens the requested initial section', (tester) async {
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(
          sections: const [
            IdeaSection(id: 'a', name: 'Idea', content: 'First'),
            IdeaSection(id: 'b', name: 'Notes', content: 'Second'),
            IdeaSection(id: 'c', name: 'Later', content: 'Third'),
          ],
        );
      });
      await pumpHost(
        tester,
        () => IdeaEditorScreen(ideaId: idea.id, initialSectionId: 'c'),
      );
      await openEditor(tester);

      final editor = tester.widget<TextField>(
        find.byKey(const Key('idea-markdown-text-field')),
      );
      expect(editor.controller?.text, 'Third');
      expect(provider.findById(idea.id)?.lastOpenedSectionId, 'c');
    });
  });

  group('formatted editor', () {
    TextField editorField(WidgetTester tester) => tester.widget<TextField>(
          find.byKey(const Key('idea-markdown-text-field')),
        );

    testWidgets('opening a formatted note without edits never rewrites it',
        (tester) async {
      const stored = '## Plan\n**bold** and 2*3*4 and snake_case\n'
          '* old bullet\n- [ ] todo\n\n```\n  code\n```\n';
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(
          sections: const [
            IdeaSection(id: 'f1', name: 'Idea', content: stored),
            IdeaSection(id: 'f2', name: 'More', content: '_x_'),
          ],
        );
      });
      final updatedAt = idea.updatedAt;
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      expect(
        editorField(tester).controller?.text,
        'Plan\nbold and 2*3*4 and snake_case\n• old bullet\n\u2003 todo\n\n'
        '  code\n',
      );
      await tester.tap(find.byKey(const Key('idea-editor-section-tab-f2')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('idea-editor-section-tab-f1')));
      await settle(tester);
      await closeEditor(tester);

      final saved = provider.findById(idea.id)!;
      expect(saved.sections.first.content, stored);
      expect(saved.sections.last.content, '_x_');
      expect(saved.updatedAt, updatedAt);
    });

    testWidgets('toolbar formatting is saved as readable markup',
        (tester) async {
      await pumpHost(tester, () => const IdeaEditorScreen());
      await openEditor(tester);

      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'make this loud',
      );
      editorField(tester).controller!.selection =
          const TextSelection(baseOffset: 10, extentOffset: 14);
      await tester.tap(find.byKey(const Key('idea-editor-toolbar-bold')));
      await tester.pump();
      expect(editorField(tester).controller?.text, 'make this loud');
      await closeEditor(tester);

      expect(
        provider.ideas.single.sections.single.content,
        'make this **loud**',
      );
    });

    testWidgets('each section keeps its own document and undo history',
        (tester) async {
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(
          sections: const [
            IdeaSection(id: 'u1', name: 'Idea', content: 'one'),
            IdeaSection(id: 'u2', name: 'More', content: 'two'),
          ],
        );
      });
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      final first = editorField(tester).controller! as NoteEditingController;
      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'one edited',
      );
      await tester.tap(find.byKey(const Key('idea-editor-section-tab-u2')));
      await settle(tester);
      final second = editorField(tester).controller! as NoteEditingController;
      expect(identical(first, second), isFalse);
      expect(second.canUndo, isFalse);

      await tester.tap(find.byKey(const Key('idea-editor-section-tab-u1')));
      await settle(tester);
      final again = editorField(tester).controller! as NoteEditingController;
      expect(identical(first, again), isTrue);
      expect(again.text, 'one edited');
      expect(again.canUndo, isTrue);
      await closeEditor(tester);

      final saved = provider.findById(idea.id)!;
      expect(saved.sections.first.content, 'one edited');
      expect(saved.sections.last.content, 'two');
    });

    testWidgets('undo and redo live in the top bar and follow the section',
        (tester) async {
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(
          sections: const [
            IdeaSection(id: 'h1', name: 'Idea', content: 'one'),
            IdeaSection(id: 'h2', name: 'More', content: 'two'),
          ],
        );
      });
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      IconButton button(String key) =>
          tester.widget<IconButton>(find.byKey(Key(key)));

      expect(find.byKey(const Key('idea-editor-lock-toggle')), findsNothing);
      expect(button('idea-editor-toolbar-undo').onPressed, isNull);
      expect(button('idea-editor-toolbar-redo').onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'one edited',
      );
      await tester.pump();
      expect(button('idea-editor-toolbar-undo').onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('idea-editor-section-tab-h2')));
      await settle(tester);
      expect(button('idea-editor-toolbar-undo').onPressed, isNull);

      await tester.tap(find.byKey(const Key('idea-editor-section-tab-h1')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('idea-editor-toolbar-undo')));
      await tester.pump();
      expect(editorField(tester).controller!.text, 'one');
      expect(button('idea-editor-toolbar-redo').onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('idea-editor-toolbar-redo')));
      await tester.pump();
      expect(editorField(tester).controller!.text, 'one edited');
      await closeEditor(tester);
    });

    testWidgets('lock and unlock are offered in the options sheet',
        (tester) async {
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea();
      });
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      await tester.tap(find.byKey(const Key('idea-editor-menu')));
      await settle(tester);
      expect(find.byKey(const Key('idea-editor-option-lock')), findsOneWidget);
      expect(
        find.text(ViewConstants.ideaEditorOptionsLockNote),
        findsOneWidget,
      );
    });

    testWidgets('an unsaved draft does not offer locking', (tester) async {
      await pumpHost(tester, () => const IdeaEditorScreen());
      await openEditor(tester);

      await tester.tap(find.byKey(const Key('idea-editor-menu')));
      await settle(tester);
      expect(find.byKey(const Key('idea-editor-option-lock')), findsNothing);
    });

    testWidgets('the hidden switch opens notes in the classic editor',
        (tester) async {
      final storage = MemoryLocalStorageManager();
      await storage.setString(
        key: NoteEditorPreferences.forceClassicKey,
        value: 'true',
      );
      NoteEditorPreferences.storageOverride = storage;
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(
          sections: const [
            IdeaSection(id: 'c1', name: 'Idea', content: '**raw**'),
          ],
        );
      });
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      expect(
          editorField(tester).controller, isNot(isA<NoteEditingController>()));
      expect(editorField(tester).controller?.text, '**raw**');
      expect(
        find.byKey(const Key('idea-editor-plain-text-marker')),
        findsOneWidget,
      );
      await closeEditor(tester);
      expect(provider.findById(idea.id)!.sections.single.content, '**raw**');
    });

    testWidgets('sections the converter cannot keep open as plain text',
        (tester) async {
      final storage = MemoryLocalStorageManager();
      NoteEditorPreferences.storageOverride = storage;
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(
          sections: const [
            IdeaSection(id: 'p1', name: 'Idea', content: '**flagged**'),
          ],
        );
        await NoteEditorPreferences.storeFormatCheck(
          NoteFormatCheckResult(
            checkedCount: 1,
            failingKeys: [NoteEditorPreferences.sectionKey(idea.id, 'p1')],
          ),
        );
      });
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      expect(editorField(tester).controller?.text, '**flagged**');
      expect(
        find.byKey(const Key('idea-editor-plain-text-marker')),
        findsOneWidget,
      );
      await closeEditor(tester);
    });
  });

  group('locked ideas', () {
    testWidgets('re-locks on pause after saving and shows the overlay',
        (tester) async {
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(title: 'Secret', isLocked: true);
      });
      authService.markIdeaUnlocked(idea.id);
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      expect(find.text(ViewConstants.noteLockEditorTitle), findsNothing);
      expect(NoteLockSecureWindow.isSecure, isTrue);
      await tester.enterText(
        find.byKey(const Key('idea-markdown-text-field')),
        'Typed before leaving',
      );

      sendLifecycle(tester, toBackground);
      await settle(tester);
      sendLifecycle(tester, toForeground);
      await settle(tester);

      expect(authService.isIdeaUnlocked(idea.id), isFalse);
      expect(find.text(ViewConstants.noteLockEditorTitle), findsOneWidget);
      expect(
        provider.findById(idea.id)?.sections.single.content,
        'Typed before leaving',
      );

      await closeEditor(tester);
      expect(NoteLockSecureWindow.isSecure, isFalse);
    });

    testWidgets('a locked editor is read only under the overlay',
        (tester) async {
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(title: 'Secret', isLocked: true);
      });
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      expect(find.text(ViewConstants.noteLockEditorTitle), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('idea-markdown-text-field')),
            )
            .readOnly,
        isTrue,
      );
    });

    testWidgets('does not re-lock while the app shows its own prompt',
        (tester) async {
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(title: 'Secret', isLocked: true);
      });
      authService.markIdeaUnlocked(idea.id);
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      await NoteLockSessionGuard.runWithoutRelock(() async {
        sendLifecycle(tester, toBackground);
        sendLifecycle(tester, toForeground);
      });
      await settle(tester);

      expect(authService.isIdeaUnlocked(idea.id), isTrue);
      expect(find.text(ViewConstants.noteLockEditorTitle), findsNothing);
    });

    testWidgets('turns keyboard learning off only for locked ideas',
        (tester) async {
      late Idea locked;
      late Idea open;
      await tester.runAsync(() async {
        locked = await saveExistingIdea(title: 'Secret', isLocked: true);
        open = await saveExistingIdea(title: 'Open');
      });
      authService.markIdeaUnlocked(locked.id);
      var targetId = locked.id;
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: targetId));
      await openEditor(tester);

      bool learning(String key) => tester
          .widget<TextField>(find.byKey(Key(key)))
          .enableIMEPersonalizedLearning;

      expect(learning('idea-editor-title'), isFalse);
      expect(learning('idea-markdown-text-field'), isFalse);
      await closeEditor(tester);

      targetId = open.id;
      await openEditor(tester);
      expect(learning('idea-editor-title'), isTrue);
      expect(learning('idea-markdown-text-field'), isTrue);
      expect(NoteLockSecureWindow.isSecure, isFalse);
      await closeEditor(tester);
    });

    testWidgets('covers a locked note when the iOS app becomes inactive',
        (tester) async {
      late Idea idea;
      await tester.runAsync(() async {
        idea = await saveExistingIdea(title: 'Secret', isLocked: true);
      });
      authService.markIdeaUnlocked(idea.id);
      await pumpHost(tester, () => IdeaEditorScreen(ideaId: idea.id));
      await openEditor(tester);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        sendLifecycle(tester, const [AppLifecycleState.inactive]);
        await tester.pump();
        expect(
          find.byKey(const Key('idea-editor-privacy-cover')),
          findsOneWidget,
        );

        sendLifecycle(tester, const [AppLifecycleState.resumed]);
        await tester.pump();
        expect(
            find.byKey(const Key('idea-editor-privacy-cover')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
