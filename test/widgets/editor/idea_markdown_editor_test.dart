import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/config/config.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/editor/note_document.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/widgets/editor/note_editing_controller.dart';
import 'package:idea_vault/widgets/editor/note_editor_theme.dart';
import 'package:idea_vault/widgets/idea_markdown_editor.dart';
import 'package:provider/provider.dart';

import '../../helpers/memory_local_storage.dart';

void main() {
  dotenv.loadFromString(envString: 'DEBUG=false');
  GoogleFonts.config.allowRuntimeFetching = false;

  late ThemeProvider themeProvider;

  setUp(() {
    themeProvider = ThemeProvider(ThemeRepo(MemoryLocalStorageManager()));
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    required TextEditingController controller,
    required FocusNode focusNode,
    bool readOnly = false,
    bool learning = true,
    ValueChanged<String>? onOpenLink,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _Pinned(
                    IdeaEditorToolbarContainer(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !readOnly,
                    ),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: IdeaMarkdownEditor(
                    controller: controller,
                    focusNode: focusNode,
                    placeholder: 'Write',
                    readOnly: readOnly,
                    enablePersonalizedLearning: learning,
                    onOpenLink: onOpenLink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  TextField field(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('idea-markdown-text-field')));

  testWidgets('renders formatting without showing markers', (tester) async {
    final controller = NoteEditingController(
      markup: '## Plan\n**bold** and _soft_\n- item\n```\ncode\n```',
    );
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);

    expect(controller.text, 'Plan\nbold and soft\n• item\ncode');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    final span = controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      style: editable.style,
      withComposing: false,
    );
    expect(span.toPlainText(), controller.text);
    final spans = <TextSpan>[];
    span.visitChildren((child) {
      if (child is TextSpan && child.text != null) {
        spans.add(child);
      }
      return true;
    });
    final bold = spans.firstWhere((child) => child.text == 'bold');
    expect(bold.style?.fontWeight, FontWeight.w800);
    final soft = spans.firstWhere((child) => child.text == 'soft');
    expect(soft.style?.fontStyle, FontStyle.italic);
    final heading = spans.firstWhere((child) => child.text == 'Plan');
    expect(
      heading.style!.fontSize!,
      greaterThan(editable.style.fontSize!),
    );
    final code = spans.firstWhere((child) => child.text == 'code');
    expect(code.style?.fontFamily, 'monospace');
    expect(controller.codeBlockRanges, hasLength(1));
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('typing with enterText and the bold button saves markup',
      (tester) async {
    final controller = NoteEditingController();
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);

    await tester.enterText(
      find.byKey(const Key('idea-markdown-text-field')),
      'make this loud',
    );
    controller.selection =
        const TextSelection(baseOffset: 10, extentOffset: 14);
    await tester.tap(find.byKey(const Key('idea-editor-toolbar-bold')));
    await tester.pump();

    expect(controller.text, 'make this loud');
    expect(controller.markup, 'make this **loud**');
    final button = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('idea-editor-toolbar-bold')),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.isSelected, isTrue);

    expect(find.byKey(const Key('idea-editor-toolbar-undo')), findsNothing);
    controller.undo();
    await tester.pump();
    expect(controller.markup, 'make this loud');
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('list buttons and Enter continue a list through the IME',
      (tester) async {
    final controller = NoteEditingController();
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);

    await tester.tap(find.byKey(const Key('idea-markdown-text-field')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('idea-editor-toolbar-bullet')));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '${controller.text}milk',
        selection: TextSelection.collapsed(offset: controller.text.length + 4),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '${controller.text}\n',
        selection: TextSelection.collapsed(offset: controller.text.length + 1),
      ),
    );
    await tester.pump();

    expect(controller.text, '• milk\n• ');
    expect(controller.markup, '- milk\n- ');
    controller.dispose();
    focusNode.dispose();
  });

  RenderEditable editableOf(WidgetTester tester) {
    return tester.renderObject<RenderEditable>(
      find.descendant(
        of: find.byType(EditableText),
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_Editable',
        ),
      ),
    );
  }

  Offset centerOfOffset(WidgetTester tester, int offset) {
    final editable = editableOf(tester);
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    );
    return editable.localToGlobal(boxes.first.toRect().center);
  }

  testWidgets('tapping a link while reading shows a preview that opens it',
      (tester) async {
    final controller =
        NoteEditingController(markup: 'Docs at https://flutter.dev');
    final focusNode = FocusNode();
    final opened = <String>[];
    await pumpEditor(
      tester,
      controller: controller,
      focusNode: focusNode,
      onOpenLink: opened.add,
    );

    await tester.tapAt(centerOfOffset(tester, 10));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(focusNode.hasFocus, isFalse);
    expect(find.byKey(const Key('note-link-preview')), findsOneWidget);
    expect(find.text('flutter.dev'), findsOneWidget);
    expect(find.text('https://flutter.dev'), findsOneWidget);
    expect(find.byKey(const Key('note-link-edit')), findsNothing);

    await tester.tap(find.byKey(const Key('note-link-open')));
    await tester.pumpAndSettle();

    expect(opened, ['https://flutter.dev']);
    expect(find.byKey(const Key('note-link-preview')), findsNothing);
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('inline code uses a distinct colour on a grey box',
      (tester) async {
    for (final themeName in [Config.light, Config.dark]) {
      themeProvider.setTheme(theme: themeName);
      final controller =
          NoteEditingController(markup: 'run `build` now\n```\nblock\n```');
      final focusNode = FocusNode();
      await pumpEditor(tester, controller: controller, focusNode: focusNode);

      final context = tester.element(find.byType(EditableText));
      final root = controller.buildTextSpan(
        context: context,
        style: const TextStyle(color: Color(0xFF123456)),
        withComposing: false,
      );
      TextStyle? styleOf(String text) {
        TextStyle? found;
        root.visitChildren((span) {
          if (span is TextSpan && span.text == text) {
            found = span.style;
            return false;
          }
          return true;
        });
        return found;
      }

      final isDark = themeName == Config.dark;
      final inline = styleOf('buil')!;
      expect(
        inline.color,
        isDark
            ? NoteEditorThemeData.darkInlineCodeColor
            : NoteEditorThemeData.lightInlineCodeColor,
      );
      expect(inline.backgroundColor, isNull);
      expect(inline.letterSpacing, isNull);
      final last = styleOf('d')!;
      expect(last.color, inline.color);
      expect(last.letterSpacing, NoteEditorThemeData.inlineCodeGap);
      final before = styleOf(' ')!;
      expect(before.letterSpacing, NoteEditorThemeData.inlineCodeGap);
      final plain = styleOf('run')!;
      expect(plain.color, isNot(inline.color));
      expect(plain.letterSpacing, isNull);
      final block = styleOf('block')!;
      expect(block.backgroundColor, isNull);
      expect(block.color, isNot(inline.color));
      expect(controller.inlineCodeRanges, [const TextRange(start: 4, end: 9)]);
      expect(controller.codeBlockRanges, [const TextRange(start: 14, end: 19)]);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      focusNode.dispose();
    }
  });

  testWidgets('the link preview stands out from the page in both themes',
      (tester) async {
    for (final themeName in [Config.light, Config.dark]) {
      themeProvider.setTheme(theme: themeName);
      final controller = NoteEditingController(markup: 'Go https://dart.dev');
      final focusNode = FocusNode();
      await pumpEditor(tester, controller: controller, focusNode: focusNode);

      await tester.tapAt(centerOfOffset(tester, 8));
      await tester.pumpAndSettle();

      final card = tester.widget<Material>(
        find.byKey(const Key('note-link-preview')),
      );
      final page = themeProvider.baseTheme.surface;
      final side = (card.shape! as RoundedRectangleBorder).side;
      if (themeName == Config.dark) {
        expect(card.color, isNot(page));
      }
      expect(side.color, isNot(themeProvider.baseTheme.outlineSoft));
      expect(side.color.a, greaterThan(0.1));
      expect(card.elevation, greaterThan(8));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      focusNode.dispose();
    }
  });

  testWidgets('tapping a link while editing shows the preview with edit',
      (tester) async {
    final controller =
        NoteEditingController(markup: 'See [the docs](https://flutter.dev) ok');
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);

    await tester.tapAt(centerOfOffset(tester, 14));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);
    expect(find.byKey(const Key('note-link-preview')), findsNothing);

    await tester.tapAt(centerOfOffset(tester, 6));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-link-preview')), findsOneWidget);
    expect(find.byKey(const Key('note-link-edit')), findsOneWidget);

    await tester.tapAt(centerOfOffset(tester, 14));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-link-preview')), findsNothing);

    await tester.tapAt(centerOfOffset(tester, 6));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-link-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-link-preview')), findsNothing);
    expect(find.text(ViewConstants.editorLinkSheetEditTitle), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('note-link-url')),
      'dart.dev',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('note-link-save')));
    await tester.pumpAndSettle();
    expect(controller.markup, 'See [the docs](https://dart.dev) ok');
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('the link preview closes when the text changes', (tester) async {
    final controller = NoteEditingController(markup: 'Go https://flutter.dev');
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);

    await tester.tapAt(centerOfOffset(tester, 8));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-link-preview')), findsOneWidget);

    controller.selection = const TextSelection.collapsed(offset: 0);
    controller.toggleBlock(NoteBlockType.bullet);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-link-preview')), findsNothing);
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('the link button opens a sheet that adds a link', (tester) async {
    final controller = NoteEditingController(markup: 'Read ');
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);
    controller.selection = const TextSelection.collapsed(offset: 5);

    await tester.tap(find.byKey(const Key('idea-editor-toolbar-link')));
    await tester.pumpAndSettle();
    expect(find.text(ViewConstants.editorLinkSheetAddTitle), findsOneWidget);
    expect(find.byKey(const Key('note-link-remove')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('note-link-save')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('note-link-url')),
      'flutter.dev',
    );
    await tester.enterText(find.byKey(const Key('note-link-label')), 'docs');
    await tester.pump();
    await tester.tap(find.byKey(const Key('note-link-save')));
    await tester.pumpAndSettle();

    expect(controller.markup, 'Read [docs](https://flutter.dev)');
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('tapping a checkbox ticks it without opening the keyboard',
      (tester) async {
    final controller =
        NoteEditingController(markup: '- [ ] milk\n- [ ] eggs\nplain');
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);

    await tester.tapAt(centerOfOffset(tester, 0));
    await tester.pump();
    expect(controller.markup, '- [x] milk\n- [ ] eggs\nplain');
    expect(focusNode.hasFocus, isFalse);

    final secondBox = centerOfOffset(tester, controller.lineStartOffset(1));
    await tester.tapAt(secondBox + const Offset(14, 0));
    await tester.pump();
    expect(controller.markup, '- [x] milk\n- [x] eggs\nplain');

    await tester.tapAt(centerOfOffset(tester, 0));
    await tester.pump();
    expect(controller.markup, '- [ ] milk\n- [x] eggs\nplain');
    expect(focusNode.hasFocus, isFalse);

    await tester.tapAt(centerOfOffset(tester, 4));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    expect(controller.markup, '- [ ] milk\n- [x] eggs\nplain');

    await tester.tapAt(centerOfOffset(tester, 0));
    await tester.pump();
    expect(controller.markup, '- [x] milk\n- [x] eggs\nplain');
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('checkboxes cannot be ticked in a read-only note',
      (tester) async {
    final controller = NoteEditingController(markup: '- [ ] milk');
    final focusNode = FocusNode();
    await pumpEditor(
      tester,
      controller: controller,
      focusNode: focusNode,
      readOnly: true,
    );

    await tester.tapAt(centerOfOffset(tester, 0));
    await tester.pump();
    expect(controller.markup, '- [ ] milk');
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('a narrow toolbar steps one tool at a time and flips at the end',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = NoteEditingController(markup: 'text');
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);
    await tester.pumpAndSettle();

    final scrollFinder = find.byKey(const Key('idea-editor-toolbar-scroll'));
    expect(tester.getTopLeft(scrollFinder).dx, 0);
    expect(tester.getTopRight(scrollFinder).dx, 360);
    expect(find.byKey(const Key('idea-editor-toolbar-more')), findsOneWidget);
    expect(find.byKey(const Key('idea-editor-toolbar-back')), findsNothing);

    final linkCenter =
        tester.getCenter(find.byKey(const Key('idea-editor-toolbar-link')));
    final headingCenter =
        tester.getCenter(find.byKey(const Key('idea-editor-toolbar-heading')));
    expect(linkCenter.dx, lessThan(headingCenter.dx));

    final actionSize = tester.getSize(
      find.descendant(
        of: find.byKey(const Key('idea-editor-toolbar-bold')),
        matching: find.byType(IconButton),
      ),
    );
    final arrowFinder = find.byKey(const Key('idea-editor-toolbar-more'));
    expect(tester.getSize(arrowFinder), actionSize);
    final arrow = tester.widget<IconButton>(arrowFinder);
    final action = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('idea-editor-toolbar-bold')),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      arrow.style?.backgroundColor?.resolve({}),
      isNot(action.style?.backgroundColor?.resolve({})),
    );
    expect(
      arrow.style?.foregroundColor?.resolve({}),
      isNot(action.style?.foregroundColor?.resolve({})),
    );

    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: scrollFinder, matching: find.byType(Scrollable)),
    );
    final position = scrollable.position;
    expect(position.maxScrollExtent, greaterThan(0));

    final step = tester
            .getCenter(find.byKey(const Key('idea-editor-toolbar-heading')))
            .dx -
        tester.getCenter(find.byKey(const Key('idea-editor-toolbar-link'))).dx;
    expect(step, greaterThan(0));

    double arrowTurns() => tester
        .widget<AnimatedRotation>(
          find.descendant(
            of: find.byKey(const Key('idea-editor-toolbar-more')),
            matching: find.byType(AnimatedRotation),
          ),
        )
        .turns;

    expect(arrowTurns(), 0);
    await tester.tap(find.byKey(const Key('idea-editor-toolbar-more')));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(step, 0.5));
    expect(find.byKey(const Key('idea-editor-toolbar-back')), findsNothing);
    expect(arrowTurns(), 0);

    var taps = 1;
    while (position.pixels < position.maxScrollExtent - 1 && taps < 20) {
      final before = position.pixels;
      await tester.tap(find.byKey(const Key('idea-editor-toolbar-more')));
      await tester.pumpAndSettle();
      taps++;
      expect(position.pixels - before, lessThanOrEqualTo(step + 0.5));
      if (position.pixels < position.maxScrollExtent - 1) {
        expect(arrowTurns(), 0);
      }
    }
    expect(position.pixels, position.maxScrollExtent);
    expect(arrowTurns(), 0.5);
    expect(find.byKey(const Key('idea-editor-toolbar-back')), findsNothing);

    final lastTool = tester.getRect(
      find.byKey(const Key('idea-editor-toolbar-inline-code')),
    );
    final arrowRect =
        tester.getRect(find.byKey(const Key('idea-editor-toolbar-more')));
    expect(lastTool.right, lessThanOrEqualTo(arrowRect.left));

    await tester.tap(find.byKey(const Key('idea-editor-toolbar-more')));
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
    expect(arrowTurns(), 0);
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('a wide toolbar shows no scroll arrows', (tester) async {
    final controller = NoteEditingController(markup: 'text');
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('idea-editor-toolbar-more')), findsNothing);
    expect(find.byKey(const Key('idea-editor-toolbar-back')), findsNothing);
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('locked notes are read only with keyboard learning off',
      (tester) async {
    final controller = NoteEditingController(markup: 'secret');
    final focusNode = FocusNode();
    await pumpEditor(
      tester,
      controller: controller,
      focusNode: focusNode,
      readOnly: true,
      learning: false,
    );

    expect(field(tester).readOnly, isTrue);
    expect(field(tester).enableIMEPersonalizedLearning, isFalse);
    expect(field(tester).textCapitalization, TextCapitalization.sentences);
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('a plain controller shows the classic editor marker',
      (tester) async {
    final controller = TextEditingController(text: '**raw**');
    final focusNode = FocusNode();
    await pumpEditor(tester, controller: controller, focusNode: focusNode);

    expect(
        find.byKey(const Key('idea-editor-plain-text-marker')), findsOneWidget);
    expect(field(tester).controller?.text, '**raw**');
    controller.dispose();
    focusNode.dispose();
  });
}

class _Pinned extends SliverPersistentHeaderDelegate {
  _Pinned(this.child);

  final Widget child;

  @override
  double get minExtent => 62;

  @override
  double get maxExtent => 62;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _Pinned oldDelegate) => true;
}
