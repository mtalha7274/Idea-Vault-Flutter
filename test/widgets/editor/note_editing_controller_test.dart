import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/editor/note_document.dart';
import 'package:idea_vault/core/editor/note_markup.dart';
import 'package:idea_vault/widgets/editor/note_editing_controller.dart';

import '../../core/editor/note_corpus.dart';

void main() {
  void userEdit(NoteEditingController controller, TextEditingValue next) {
    controller.value = controller.formatUserEdit(controller.value, next);
  }

  void placeCaret(NoteEditingController controller, int offset) {
    controller.selection = TextSelection.collapsed(offset: offset);
  }

  void type(NoteEditingController controller, String text) {
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final next = value.text.replaceRange(selection.start, selection.end, text);
    userEdit(
      controller,
      TextEditingValue(
        text: next,
        selection:
            TextSelection.collapsed(offset: selection.start + text.length),
      ),
    );
  }

  void backspace(NoteEditingController controller) {
    final value = controller.value;
    final caret = value.selection.start;
    if (caret == 0) {
      return;
    }
    userEdit(
      controller,
      TextEditingValue(
        text: value.text.replaceRange(caret - 1, caret, ''),
        selection: TextSelection.collapsed(offset: caret - 1),
      ),
    );
  }

  group('opening', () {
    test('shows text without markers and keeps stored text unchanged', () {
      for (final entry in noteCorpus.entries) {
        final controller = NoteEditingController(markup: entry.value);
        expect(controller.markup, entry.value, reason: entry.key);
        expect(controller.plainText, NoteMarkup.plainText(entry.value),
            reason: entry.key);
        expect(controller.contentRevision.value, 0);
        controller.dispose();
      }
    });

    test('bullets, numbers and checkboxes show as prefixes', () {
      final controller = NoteEditingController(
        markup: '## Plan\n- one\n3. two\n- [x] done\n**bold**',
      );
      expect(controller.text, 'Plan\n• one\n3. two\n\u2003 done\nbold');
      controller.dispose();
    });
  });

  group('typing', () {
    test('plain typing is passed through untouched', () {
      final controller = NoteEditingController(markup: 'Hello');
      placeCaret(controller, 5);
      final next = TextEditingValue(
        text: 'Hello there',
        selection: const TextSelection.collapsed(offset: 11),
        composing: const TextRange(start: 6, end: 11),
      );
      final result = controller.formatUserEdit(controller.value, next);
      expect(identical(result, next), isTrue);
      controller.value = result;
      expect(controller.markup, 'Hello there');
      expect(controller.contentRevision.value, 1);
      controller.dispose();
    });

    test('a style with no selection applies to what is typed next', () {
      final controller = NoteEditingController(markup: 'Start ');
      placeCaret(controller, 6);
      controller.toggleInline(NoteInlineAttribute.bold);
      expect(controller.toolbarState.bold, isTrue);
      type(controller, 'loud');
      controller.toggleInline(NoteInlineAttribute.bold);
      type(controller, ' quiet');
      expect(controller.markup, 'Start **loud** quiet');
      controller.dispose();
    });

    test('bolding a selection writes markers but shows none', () {
      final controller = NoteEditingController(markup: 'make this bold');
      controller.selection =
          const TextSelection(baseOffset: 10, extentOffset: 14);
      controller.toggleInline(NoteInlineAttribute.bold);
      expect(controller.text, 'make this bold');
      expect(controller.markup, 'make this **bold**');
      expect(controller.toolbarState.bold, isTrue);
      controller.toggleInline(NoteInlineAttribute.bold);
      expect(controller.markup, 'make this bold');
      controller.dispose();
    });

    test('formatting across lines is applied per line', () {
      final controller = NoteEditingController(markup: 'one\ntwo');
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 7);
      controller.toggleInline(NoteInlineAttribute.italic);
      expect(controller.markup, '_one_\n_two_');
      controller.dispose();
    });

    test('typing "- " and "## " at line start converts the line', () {
      final controller = NoteEditingController();
      placeCaret(controller, 0);
      type(controller, '-');
      type(controller, ' ');
      expect(controller.text, '• ');
      type(controller, 'milk');
      expect(controller.markup, '- milk');

      final heading = NoteEditingController();
      placeCaret(heading, 0);
      for (final char in ['#', '#', ' ', 'T', 'o', 'p']) {
        type(heading, char);
      }
      expect(heading.text, 'Top');
      expect(heading.markup, '## Top');
      controller.dispose();
      heading.dispose();
    });

    test('literal markers typed by the user stay literal', () {
      final controller = NoteEditingController();
      placeCaret(controller, 0);
      type(controller, '2*3*4 and *not italic* snake_case');
      expect(controller.text, '2*3*4 and *not italic* snake_case');
      expect(
        NoteMarkup.parse(controller.markup).plainText,
        '2*3*4 and *not italic* snake_case',
      );
      controller.dispose();
    });
  });

  group('lists', () {
    test('Enter continues the list and Enter on an empty item ends it', () {
      final controller = NoteEditingController(markup: '- one');
      placeCaret(controller, controller.text.length);
      type(controller, '\n');
      expect(controller.text, '• one\n• ');
      type(controller, 'two');
      type(controller, '\n');
      type(controller, '\n');
      expect(controller.text, '• one\n• two\n');
      expect(controller.markup, '- one\n- two\n');
      controller.dispose();
    });

    test('numbered lists count up and checklists start unchecked', () {
      final numbered = NoteEditingController(markup: '1. a');
      placeCaret(numbered, numbered.text.length);
      type(numbered, '\nb');
      expect(numbered.markup, '1. a\n2. b');

      final checklist = NoteEditingController(markup: '- [x] a');
      placeCaret(checklist, checklist.text.length);
      type(checklist, '\nb');
      expect(checklist.markup, '- [x] a\n- [ ] b');
      numbered.dispose();
      checklist.dispose();
    });

    test('Backspace at the start of an item removes the bullet', () {
      final controller = NoteEditingController(markup: 'x\n- item');
      placeCaret(controller, 4);
      backspace(controller);
      expect(controller.text, 'x\nitem');
      expect(controller.markup, 'x\nitem');
      backspace(controller);
      expect(controller.text, 'xitem');
      controller.dispose();
    });

    test('toolbar toggles block types for the selected lines', () {
      final controller = NoteEditingController(markup: 'a\nb\nc');
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 3);
      controller.toggleBlock(NoteBlockType.numbered);
      expect(controller.markup, '1. a\n2. b\nc');
      controller.toggleBlock(NoteBlockType.numbered);
      expect(controller.markup, 'a\nb\nc');
      placeCaret(controller, 0);
      controller.toggleBlock(NoteBlockType.checklist);
      expect(controller.markup, '- [ ] a\nb\nc');
      placeCaret(controller, 5);
      expect(controller.toggleChecklistAt(0), isTrue);
      expect(controller.markup, '- [x] a\nb\nc');
      expect(controller.selection.baseOffset, 5);
      expect(controller.toggleChecklistAt(1), isFalse);
      controller.undo();
      expect(controller.markup, '- [ ] a\nb\nc');
      controller.dispose();
    });

    test('code block toggles and keeps typed markers raw', () {
      final controller = NoteEditingController(markup: 'x = **1**');
      placeCaret(controller, 0);
      controller.toggleBlock(NoteBlockType.code);
      expect(controller.text, 'x = 1');
      expect(controller.markup, '```\nx = 1\n```');
      placeCaret(controller, controller.text.length);
      type(controller, '\n**y**');
      expect(controller.markup, '```\nx = 1\n**y**\n```');
      controller.dispose();
    });

    test('heading button cycles heading, subheading and text', () {
      final controller = NoteEditingController(markup: 'Title');
      placeCaret(controller, 2);
      controller.cycleHeading();
      expect(controller.markup, '## Title');
      controller.cycleHeading();
      expect(controller.markup, '### Title');
      controller.cycleHeading();
      expect(controller.markup, 'Title');
      controller.dispose();
    });
  });

  group('paste', () {
    test('plain text pastes as plain text', () {
      final controller = NoteEditingController();
      placeCaret(controller, 0);
      type(controller, 'a *b* c\nsecond line here');
      expect(controller.text, 'a *b* c\nsecond line here');
      controller.dispose();
    });

    test('clearly markdown text arrives formatted', () {
      final controller = NoteEditingController();
      placeCaret(controller, 0);
      type(controller, '## Title\n- one\n- **two**');
      expect(controller.text, 'Title\n• one\n• two');
      expect(controller.markup, '## Title\n- one\n- **two**');
      controller.dispose();
    });
  });

  group('checklists', () {
    test('ticking a box never changes the text layout', () {
      final controller =
          NoteEditingController(markup: '- [ ] milk\n- [x] eggs\nplain');
      final before = controller.text;
      expect(before, '\u2003 milk\n\u2003 eggs\nplain');
      expect(
        controller.checklistMarks.map((mark) => (mark.offset, mark.checked)),
        [(0, false), (7, true)],
      );
      controller.toggleChecklistAt(0);
      expect(controller.text, before);
      expect(controller.checklistMarks.first.checked, isTrue);
      expect(controller.markup, '- [x] milk\n- [x] eggs\nplain');
      controller.dispose();
    });
  });

  group('inline code', () {
    test('inline code keeps going while typing until switched off', () {
      final controller = NoteEditingController(markup: 'run ');
      placeCaret(controller, 4);
      controller.toggleInline(NoteInlineAttribute.code);
      for (final char in ['b', 'u', 'i', 'l', 'd']) {
        type(controller, char);
      }
      expect(controller.markup, 'run `build`');
      controller.toggleInline(NoteInlineAttribute.code);
      type(controller, ' now');
      expect(controller.markup, 'run `build` now');
      controller.dispose();
    });

    test('typing inside existing inline code stays code', () {
      final controller = NoteEditingController(markup: 'run `bld` now');
      placeCaret(controller, 5);
      type(controller, 'ui');
      expect(controller.markup, 'run `build` now');
      controller.dispose();
    });
  });

  group('links', () {
    test('links can be added, edited and removed', () {
      final controller = NoteEditingController(markup: 'see docs now');
      controller.selection =
          const TextSelection(baseOffset: 4, extentOffset: 8);
      controller.applyLink('flutter.dev');
      expect(controller.markup, 'see [docs](https://flutter.dev) now');
      placeCaret(controller, 6);
      expect(controller.linkAtSelection?.url, 'https://flutter.dev');
      controller.applyLink('https://dart.dev');
      expect(controller.markup, 'see [docs](https://dart.dev) now');
      controller.removeLink();
      expect(controller.markup, 'see docs now');
      controller.dispose();
    });

    String reopenedLink(String markup, int offset) {
      final reopened = NoteEditingController(markup: markup);
      final url = reopened.linkUrlAt(offset) ?? '';
      reopened.dispose();
      return url;
    }

    test('a link added right after a word keeps a space and survives saving',
        () {
      final controller =
          NoteEditingController(markup: '- [ ] this is a text this is a');
      placeCaret(controller, controller.text.length);
      controller.applyLink('google.com', label: 'Google');
      expect(controller.text, '\u2003 this is a text this is a Google');
      expect(
        controller.markup,
        '- [ ] this is a text this is a [Google](https://google.com)',
      );
      expect(
        reopenedLink(controller.markup, controller.text.length - 1),
        'https://google.com',
      );
      controller.dispose();
    });

    test('a link added inside a word is spaced on both sides', () {
      final controller = NoteEditingController(markup: 'abcdef');
      placeCaret(controller, 3);
      controller.applyLink('dart.dev', label: '  Dart ');
      expect(controller.text, 'abc Dart def');
      expect(controller.markup, 'abc [Dart](https://dart.dev) def');
      expect(controller.selection.baseOffset, 9);
      controller.dispose();
    });

    test('a link added after a URL stays separate from it', () {
      final controller = NoteEditingController(markup: 'google.com');
      placeCaret(controller, controller.text.length);
      controller.applyLink('google.com', label: 'Google');
      expect(controller.markup, 'google.com [Google](https://google.com)');
      controller.dispose();
    });

    test('punctuation next to a link needs no extra space', () {
      final controller = NoteEditingController(markup: 'see (here).');
      placeCaret(controller, 5);
      controller.applyLink('dart.dev', label: 'docs');
      expect(controller.markup, 'see ([docs](https://dart.dev) here).');
      controller.dispose();

      final between = NoteEditingController(markup: 'see ().');
      placeCaret(between, 5);
      between.applyLink('dart.dev', label: 'docs');
      expect(between.markup, 'see ([docs](https://dart.dev)).');
      between.dispose();
    });

    test('linking part of a word links the whole word', () {
      for (final range in [(6, 9), (7, 10), (5, 13)]) {
        final controller = NoteEditingController(markup: 'visit google now');
        controller.selection =
            TextSelection(baseOffset: range.$1, extentOffset: range.$2);
        controller.applyLink('google.com');
        expect(controller.markup, 'visit [google](https://google.com) now');
        expect(reopenedLink(controller.markup, 8), 'https://google.com');
        controller.dispose();
      }
    });
  });

  group('undo', () {
    test('undo and redo restore text and formatting', () {
      final controller = NoteEditingController(markup: 'word');
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 4);
      controller.toggleInline(NoteInlineAttribute.bold);
      expect(controller.markup, '**word**');
      controller.undo();
      expect(controller.markup, 'word');
      expect(controller.canRedo, isTrue);
      controller.redo();
      expect(controller.markup, '**word**');
      controller.dispose();
    });
  });

  test('programmatic text changes keep the model in sync', () {
    final controller = NoteEditingController(markup: '- a');
    controller.text = 'plain';
    expect(controller.text, 'plain');
    expect(controller.markup, 'plain');
    controller.dispose();
  });

  test('a 50k character note opens and edits quickly', () {
    final buffer = StringBuffer();
    var index = 0;
    while (buffer.length < 50000) {
      buffer.writeln(index.isEven
          ? '- item **$index** with _style_ and words words words'
          : 'Plain line number $index with snake_case words and more text');
      index++;
    }
    final stopwatch = Stopwatch()..start();
    final controller = NoteEditingController(markup: buffer.toString());
    final openTime = stopwatch.elapsedMilliseconds;
    placeCaret(controller, 20);
    stopwatch.reset();
    for (var i = 0; i < 20; i++) {
      type(controller, 'x');
    }
    final perKey = stopwatch.elapsedMilliseconds / 20;
    expect(openTime, lessThan(400));
    expect(perKey, lessThan(40));
    expect(controller.markup.contains('x' * 20), isTrue);
    controller.dispose();
  });
}
