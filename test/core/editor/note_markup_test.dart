import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/editor/note_document.dart';
import 'package:idea_vault/core/editor/note_inline_codec.dart';
import 'package:idea_vault/core/editor/note_markup.dart';

import 'note_corpus.dart';

void main() {
  group('corpus guarantee', () {
    for (final entry in noteCorpus.entries) {
      test('round trips: ${entry.key}', () {
        final first = NoteMarkup.parse(entry.value);
        final written = NoteMarkup.serialize(first);
        final second = NoteMarkup.parse(written);
        expect(second, first);
        expect(second.plainText, first.plainText);
        expect(NoteMarkup.isRoundTripSafe(entry.value), isTrue);
      });

      test('reopening without edits reproduces stored text: ${entry.key}', () {
        final parsed = NoteMarkup.parseWithSources(entry.value);
        final written = NoteMarkup.serialize(
          parsed.document,
          sources: parsed.sources,
        );
        if (noteCorpusCanonicalisedOnWrite.contains(entry.key)) {
          expect(NoteMarkup.parse(written), parsed.document);
        } else {
          expect(written, entry.value);
        }
      });
    }

    test('keeps every visible character of existing notes', () {
      for (final entry in noteCorpusVisibleText.entries) {
        expect(
          NoteMarkup.plainText(noteCorpus[entry.key]!),
          entry.value,
          reason: entry.key,
        );
      }
    });
  });

  group('reading rules', () {
    NoteLine line(String raw) => NoteMarkup.parse(raw).lines.single;

    test('old toolbar markup becomes formatting', () {
      expect(line('**x**').spans, [
        const NoteSpan('x', NoteInlineStyle(bold: true)),
      ]);
      expect(line('_x_').spans, [
        const NoteSpan('x', NoteInlineStyle(italic: true)),
      ]);
      expect(line('*x*').spans, [
        const NoteSpan('x', NoteInlineStyle(italic: true)),
      ]);
      expect(line('~~x~~').spans, [
        const NoteSpan('x', NoteInlineStyle(strike: true)),
      ]);
      expect(line('`x`').spans, [
        const NoteSpan('x', NoteInlineStyle(code: true)),
      ]);
      expect(line('## Plan').type, NoteBlockType.heading2);
      expect(line('# Plan').type, NoteBlockType.heading1);
      expect(line('### Plan').type, NoteBlockType.heading3);
      expect(line('- item').type, NoteBlockType.bullet);
      expect(line('* item').type, NoteBlockType.bullet);
      expect(line('+ item').type, NoteBlockType.bullet);
      expect(line('3. item').number, '3');
      expect(line('- [x] done').checked, isTrue);
      expect(line('- [ ] todo').type, NoteBlockType.checklist);
      expect(line('> said').type, NoteBlockType.quote);
    });

    test('markers without a same-line partner at a word edge stay literal', () {
      for (final raw in [
        'snake_case_name',
        '2 * 3 * 4',
        '2*3*4',
        'x**2 + y**2',
        '**',
        '** alone',
        '__init__.py',
        '/usr/local/_bin_/x',
        r'C:\new\*.txt',
        'callbacks[i](event)',
        '#hashtag',
        '##no space',
        '>no space',
        '---',
        'a ~single~ tilde',
        '``double``',
      ]) {
        final parsed = line(raw);
        expect(parsed.type, NoteBlockType.paragraph, reason: raw);
        expect(parsed.spans, [NoteSpan(raw)], reason: raw);
      }
    });

    test('markers on different lines never pair', () {
      final document = NoteMarkup.parse('**start\nend**');
      expect(document.plainText, '**start\nend**');
    });

    test('an unclosed fence makes the rest a code block', () {
      final document = NoteMarkup.parse('text\n```\ncode\nmore *code*');
      expect(document.lines.map((line) => line.type).toList(), [
        NoteBlockType.paragraph,
        NoteBlockType.code,
        NoteBlockType.code,
      ]);
      expect(document.plainText, 'text\ncode\nmore *code*');
    });

    test('code blocks keep tabs, indentation and markers', () {
      final document = NoteMarkup.parse('```\n\tif (a) {\n  **b**\n```');
      expect(document.lines.map((line) => line.text).toList(), [
        '\tif (a) {',
        '  **b**',
      ]);
    });

    test('nested list indentation is kept as literal leading spaces', () {
      final document = NoteMarkup.parse('- top\n  - nested\n    - deeper');
      expect(document.lines[0].type, NoteBlockType.bullet);
      expect(document.lines[1].type, NoteBlockType.paragraph);
      expect(document.lines[1].text, '  - nested');
      expect(document.lines[2].text, '    - deeper');
    });

    test('bare urls stay literal and protect their underscores', () {
      final document =
          NoteMarkup.parse('see https://x.com/_a_ and www.y.com/*b*');
      expect(document.lines.single.spans, [
        const NoteSpan('see https://x.com/_a_ and www.y.com/*b*'),
      ]);
      final urls = NoteInlineCodec.findBareUrls(document.plainText);
      expect(urls.map((url) => url.href).toList(), [
        'https://x.com/_a_',
        'https://www.y.com/*b',
      ]);
    });

    test('links keep their target', () {
      expect(line('[docs](https://flutter.dev).').spans, [
        const NoteSpan('docs', NoteInlineStyle(link: 'https://flutter.dev')),
        const NoteSpan('.'),
      ]);
    });

    test('bold inside headings and italic inside list items', () {
      expect(line('## A **big** plan').spans, [
        const NoteSpan('A '),
        const NoteSpan('big', NoteInlineStyle(bold: true)),
        const NoteSpan(' plan'),
      ]);
      expect(line('- an _soft_ item').spans[1],
          const NoteSpan('soft', NoteInlineStyle(italic: true)));
    });
  });

  group('writing rules', () {
    String write(List<NoteLine> lines) =>
        NoteMarkup.serialize(NoteDocument(lines));

    test('ordinary text is stored untouched', () {
      for (final text in [
        'Plain text',
        '2*3 = 6',
        'snake_case_name',
        'a * b',
        'price: 5\$ (approx)',
        'https://example.com/a_b_c',
      ]) {
        expect(write([NoteLine.plain(text)]), text);
      }
    });

    test('escapes only where text would read as formatting', () {
      expect(write([NoteLine.plain('*a* b')]), r'\*a* b');
      expect(write([NoteLine.plain('- not a list')]), r'\- not a list');
      expect(write([NoteLine.plain('## not a heading')]), r'\## not a heading');
      expect(write([NoteLine.plain('1. not numbered')]), r'\1. not numbered');
      expect(write([NoteLine.plain('```')]), r'\```');
      expect(
        write([NoteLine.plain('[x] box', type: NoteBlockType.bullet)]),
        r'- \[x] box',
      );
    });

    test('writes the standard form for every block', () {
      expect(
        write(const [
          NoteLine(type: NoteBlockType.heading2, spans: [NoteSpan('H')]),
          NoteLine(type: NoteBlockType.bullet, spans: [NoteSpan('b')]),
          NoteLine(
            type: NoteBlockType.numbered,
            number: '2',
            spans: [NoteSpan('n')],
          ),
          NoteLine(
            type: NoteBlockType.checklist,
            checked: true,
            spans: [NoteSpan('c')],
          ),
          NoteLine(type: NoteBlockType.quote, spans: [NoteSpan('q')]),
          NoteLine(
            type: NoteBlockType.code,
            codeBlockStart: true,
            spans: [NoteSpan('x = 1')],
          ),
          NoteLine(),
        ]),
        '## H\n- b\n2. n\n- [x] c\n> q\n```\nx = 1\n```\n',
      );
    });

    test('formatting is written with markers', () {
      expect(
        write(const [
          NoteLine(spans: [
            NoteSpan('a '),
            NoteSpan('bold', NoteInlineStyle(bold: true)),
            NoteSpan(' '),
            NoteSpan('both', NoteInlineStyle(bold: true, italic: true)),
            NoteSpan(' '),
            NoteSpan('code', NoteInlineStyle(code: true)),
            NoteSpan(' '),
            NoteSpan('site', NoteInlineStyle(link: 'https://a.com')),
          ]),
        ]),
        'a **bold** **_both_** `code` [site](https://a.com)',
      );
    });

    test('code lines containing fences get a longer fence', () {
      final written = write(const [
        NoteLine(
          type: NoteBlockType.code,
          codeBlockStart: true,
          spans: [NoteSpan('```')],
        ),
      ]);
      expect(written, '````\n```\n````');
      expect(NoteMarkup.parse(written).lines.single.text, '```');
    });

    test('styles that start inside a word are widened to the word', () {
      final written = write(const [
        NoteLine(spans: [
          NoteSpan('foo', NoteInlineStyle(bold: true)),
          NoteSpan('bar'),
        ]),
      ]);
      expect(written, '**foobar**');
    });

    test('escapeLiteral keeps text literal', () {
      for (final text in ['2*3*4', '*a* b', '- x', '**y**', 'snake_case']) {
        final stored = NoteMarkup.escapeLiteral(text);
        expect(NoteMarkup.parse(stored).plainText, text);
        expect(
          NoteMarkup.parse(stored).lines.single.spans,
          [NoteSpan(text)],
        );
      }
      expect(NoteMarkup.escapeLiteral('2*3*4'), '2*3*4');
    });
  });

  group('randomised round trips', () {
    const alphabet = [
      'a',
      'b',
      'c',
      ' ',
      ' ',
      '*',
      '*',
      '_',
      '_',
      '~',
      '`',
      '[',
      ']',
      '(',
      ')',
      '\\',
      '#',
      '-',
      '+',
      '>',
      '1',
      '.',
      '\n',
      '\n',
      'h',
      't',
      'p',
      ':',
      '/',
      'w',
      'x',
      'é',
      'س',
      '😀',
      '\t',
      '!',
      ',',
    ];

    test('random markup parses, writes and parses to the same document', () {
      final random = Random(7);
      for (var round = 0; round < 4000; round++) {
        final length = random.nextInt(40);
        final buffer = StringBuffer();
        for (var i = 0; i < length; i++) {
          buffer.write(alphabet[random.nextInt(alphabet.length)]);
        }
        if (random.nextInt(6) == 0) {
          buffer.write('\n```\n${alphabet[random.nextInt(alphabet.length)]}');
        }
        final markup = buffer.toString();
        final first = NoteMarkup.parse(markup);
        final written = NoteMarkup.serialize(first);
        final second = NoteMarkup.parse(written);
        expect(second, first,
            reason: 'markup: ${_show(markup)}\n'
                'written: ${_show(written)}');
      }
    });

    test('random documents keep their visible text and stay stable', () {
      final random = Random(11);
      const words = [
        'a',
        'bc',
        ' ',
        '  ',
        '*',
        '_',
        '~~',
        '`',
        '[x]',
        '(y)',
        '\\',
        '#',
        '- ',
        '1. ',
        'https://a.com/_b_',
        'www.c.io',
        'snake_case',
        '2*3',
        'é',
        'سلام',
        '😀',
        '**',
        '[t](u)',
        '> ',
        '```',
      ];
      for (var round = 0; round < 3000; round++) {
        final lines = <NoteLine>[];
        final lineCount = 1 + random.nextInt(4);
        for (var l = 0; l < lineCount; l++) {
          final type =
              NoteBlockType.values[random.nextInt(NoteBlockType.values.length)];
          final spans = <NoteSpan>[];
          final spanCount = random.nextInt(4);
          for (var s = 0; s < spanCount; s++) {
            final text = List.generate(
              1 + random.nextInt(3),
              (_) => words[random.nextInt(words.length)],
            ).join();
            final style = type == NoteBlockType.code
                ? NoteInlineStyle.plain
                : NoteInlineStyle(
                    bold: random.nextInt(4) == 0,
                    italic: random.nextInt(4) == 0,
                    strike: random.nextInt(8) == 0,
                    code: random.nextInt(8) == 0,
                    link: random.nextInt(8) == 0 ? 'https://l.ink/x' : null,
                  );
            spans.add(NoteSpan(text.replaceAll('\n', ' '), style));
          }
          lines.add(
            NoteLine(
              type: type,
              spans: normalizeNoteSpans(spans),
              number: type == NoteBlockType.numbered ? '4' : '',
              checked: type == NoteBlockType.checklist && random.nextBool(),
              codeBlockStart: type == NoteBlockType.code &&
                  (l == 0 || lines[l - 1].type != NoteBlockType.code),
            ),
          );
        }
        final document = NoteDocument(lines);
        final written = NoteMarkup.serialize(document);
        final reread = NoteMarkup.parse(written);
        expect(reread.plainText, document.plainText,
            reason: 'doc: $document\nwritten: ${_show(written)}');
        expect(
          reread.lines.map((line) => line.type).toList(),
          lines.map((line) => line.type).toList(),
          reason: 'doc: $document\nwritten: ${_show(written)}',
        );
        final again = NoteMarkup.parse(NoteMarkup.serialize(reread));
        expect(again, reread, reason: 'written: ${_show(written)}');
      }
    });

    test('documents the reader produced are written back exactly', () {
      final random = Random(3);
      const pieces = [
        '**bold**',
        '_it_',
        '*it*',
        '~~s~~',
        '`c`',
        '[l](https://x.y)',
        'word',
        ' ',
        'snake_case',
        '2*3',
        '\\*',
        'https://u.rl/a_b',
        '(**p**)',
        '"_q_"',
        'é',
        'سلام',
      ];
      for (var round = 0; round < 3000; round++) {
        final buffer = StringBuffer();
        final count = random.nextInt(6);
        for (var i = 0; i < count; i++) {
          buffer.write(pieces[random.nextInt(pieces.length)]);
          if (random.nextBool()) {
            buffer.write(' ');
          }
        }
        final markup = buffer.toString();
        final document = NoteMarkup.parse(markup);
        final written = NoteMarkup.serialize(document);
        expect(NoteMarkup.parse(written), document,
            reason: 'markup: ${_show(markup)} written: ${_show(written)}');
      }
    });
  });

  test('a 50k character note parses and writes quickly', () {
    final buffer = StringBuffer();
    var index = 0;
    while (buffer.length < 50000) {
      buffer.writeln(switch (index % 5) {
        0 => '## Heading $index',
        1 => '- item with **bold** and _italic_ $index',
        2 => 'A plain line with snake_case and 2*3 maths $index',
        3 => '1. numbered https://example.com/$index',
        _ => '',
      });
      index++;
    }
    final markup = buffer.toString();
    final stopwatch = Stopwatch()..start();
    final document = NoteMarkup.parse(markup);
    final parseTime = stopwatch.elapsedMilliseconds;
    NoteMarkup.serialize(document);
    stopwatch.stop();
    expect(parseTime, lessThan(400));
    expect(stopwatch.elapsedMilliseconds, lessThan(1500));
  });
}

String _show(String text) =>
    text.replaceAll('\n', r'\n').replaceAll('\t', r'\t');
