import 'note_document.dart';
import 'note_inline_codec.dart';

class NoteParseResult {
  const NoteParseResult(this.document, this.sources);

  final NoteDocument document;
  final Map<NoteLine, String> sources;
}

class _BlockMatch {
  const _BlockMatch(
    this.type,
    this.contentStart, {
    this.checked = false,
    this.number = '',
  });

  final NoteBlockType type;
  final int contentStart;
  final bool checked;
  final String number;
}

class NoteMarkup {
  const NoteMarkup._();

  static final RegExp _fenceOpen = RegExp(r'^(`{3,})([^`]*)$');
  static final RegExp _heading = RegExp(r'^(#{1,3}) ');
  static final RegExp _checklist = RegExp(r'^[-*+] \[([ xX])\] ');
  static final RegExp _bullet = RegExp(r'^[-*+] ');
  static final RegExp _numbered = RegExp(r'^(\d{1,9})\. ');
  static final RegExp _checkboxContent = RegExp(r'^\[[ xX]\] ');
  static final RegExp _leadingBackslashes = RegExp(r'^\\+');
  static final RegExp _backtickOnlyLine = RegExp(r'^(`{3,})[ \t]*$');

  static NoteDocument parse(String markup) => parseWithSources(markup).document;

  static NoteParseResult parseWithSources(String markup) {
    final rawLines = markup.split('\n');
    final lines = <NoteLine>[];
    final sources = <NoteLine, String>{};
    var index = 0;
    while (index < rawLines.length) {
      final raw = rawLines[index];
      final fence = _fenceOpen.firstMatch(raw);
      final fenceLength = fence?.group(1)!.length ?? 0;
      final info = fence?.group(2)! ?? '';
      var cursor = index + 1;
      if (fence != null) {
        while (cursor < rawLines.length &&
            !_closesFence(rawLines[cursor], fenceLength)) {
          cursor++;
        }
      }
      final isFence =
          fence != null && (cursor < rawLines.length || info.trim().isEmpty);
      if (isFence) {
        final codeLines = rawLines.sublist(index + 1, cursor);
        if (codeLines.isEmpty) {
          codeLines.add('');
        }
        for (var i = 0; i < codeLines.length; i++) {
          lines.add(
            NoteLine(
              type: NoteBlockType.code,
              spans: codeLines[i].isEmpty ? const [] : [NoteSpan(codeLines[i])],
              codeBlockStart: i == 0,
              codeInfo: i == 0 ? info : '',
            ),
          );
        }
        index = cursor < rawLines.length ? cursor + 1 : cursor;
        continue;
      }
      final line = parseLine(raw);
      lines.add(line);
      if (fence == null) {
        sources.putIfAbsent(line, () => raw);
      }
      index++;
    }
    return NoteParseResult(NoteDocument(List.unmodifiable(lines)), sources);
  }

  static bool _closesFence(String line, int fenceLength) {
    final match = _backtickOnlyLine.firstMatch(line);
    return match != null && match.group(1)!.length >= fenceLength;
  }

  static _BlockMatch? _matchBlock(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    if (_fenceOpen.hasMatch(raw)) {
      return const _BlockMatch(NoteBlockType.code, 0);
    }
    final heading = _heading.firstMatch(raw);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final type = switch (level) {
        1 => NoteBlockType.heading1,
        2 => NoteBlockType.heading2,
        _ => NoteBlockType.heading3,
      };
      return _BlockMatch(type, heading.end);
    }
    final checklist = _checklist.firstMatch(raw);
    if (checklist != null) {
      return _BlockMatch(
        NoteBlockType.checklist,
        checklist.end,
        checked: checklist.group(1)!.toLowerCase() == 'x',
      );
    }
    final bullet = _bullet.firstMatch(raw);
    if (bullet != null) {
      return _BlockMatch(NoteBlockType.bullet, bullet.end);
    }
    final numbered = _numbered.firstMatch(raw);
    if (numbered != null) {
      return _BlockMatch(
        NoteBlockType.numbered,
        numbered.end,
        number: numbered.group(1)!,
      );
    }
    if (raw.startsWith('> ')) {
      return const _BlockMatch(NoteBlockType.quote, 2);
    }
    return null;
  }

  static NoteLine parseLine(String raw) {
    if (raw.startsWith('\\')) {
      final rest = raw.substring(1);
      final probe = rest.replaceFirst(_leadingBackslashes, '');
      if (_matchBlock(probe) != null) {
        return NoteLine(spans: NoteInlineCodec.parse(rest));
      }
    }
    final match = _matchBlock(raw);
    if (match == null || match.type == NoteBlockType.code) {
      return NoteLine(spans: NoteInlineCodec.parse(raw));
    }
    var content = raw.substring(match.contentStart);
    if (match.type == NoteBlockType.bullet && content.startsWith('\\')) {
      final probe = content.substring(1).replaceFirst(_leadingBackslashes, '');
      if (_checkboxContent.hasMatch(probe)) {
        content = content.substring(1);
      }
    }
    return NoteLine(
      type: match.type,
      spans: NoteInlineCodec.parse(content),
      checked: match.checked,
      number: match.number,
    );
  }

  static String serialize(
    NoteDocument document, {
    Map<NoteLine, String>? sources,
  }) {
    final out = <String>[];
    final lines = document.lines;
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      if (line.type == NoteBlockType.code) {
        var end = index + 1;
        while (end < lines.length &&
            lines[end].type == NoteBlockType.code &&
            !lines[end].codeBlockStart) {
          end++;
        }
        _writeCodeBlock(lines.sublist(index, end), out);
        index = end;
        continue;
      }
      final source = sources?[line];
      out.add(source ?? writeLine(line));
      index++;
    }
    return out.join('\n');
  }

  static void _writeCodeBlock(List<NoteLine> block, List<String> out) {
    var longest = 2;
    for (final line in block) {
      final match = _backtickOnlyLine.firstMatch(line.text);
      if (match != null && match.group(1)!.length > longest) {
        longest = match.group(1)!.length;
      }
    }
    final fence = '`' * (longest + 1);
    var info = block.first.codeInfo;
    if (info.contains('`')) {
      info = '';
    }
    out.add('$fence$info');
    for (final line in block) {
      out.add(line.text);
    }
    out.add(fence);
  }

  static String writeLine(NoteLine line) {
    final content = NoteInlineCodec.serialize(line.spans);
    switch (line.type) {
      case NoteBlockType.heading1:
        return '# $content';
      case NoteBlockType.heading2:
        return '## $content';
      case NoteBlockType.heading3:
        return '### $content';
      case NoteBlockType.bullet:
        final probe = content.replaceFirst(_leadingBackslashes, '');
        if (_checkboxContent.hasMatch(probe)) {
          return '- \\$content';
        }
        return '- $content';
      case NoteBlockType.numbered:
        final number = line.number.isEmpty ? '1' : line.number;
        return '$number. $content';
      case NoteBlockType.checklist:
        return '- [${line.checked ? 'x' : ' '}] $content';
      case NoteBlockType.quote:
        return '> $content';
      case NoteBlockType.code:
        return line.text;
      case NoteBlockType.paragraph:
        final probe = content.replaceFirst(_leadingBackslashes, '');
        if (_matchBlock(probe) != null) {
          return '\\$content';
        }
        return content;
    }
  }

  static String plainText(String markup) {
    if (markup.isEmpty) {
      return '';
    }
    return parse(markup).plainText;
  }

  static String escapeLiteral(String plain) {
    final document = NoteDocument([
      for (final line in plain.split('\n')) NoteLine.plain(line),
    ]);
    return serialize(document);
  }

  static bool isRoundTripSafe(String markup) {
    try {
      final first = parse(markup);
      final written = serialize(first);
      final second = parse(written);
      return first == second;
    } catch (_) {
      return false;
    }
  }

  static bool looksLikeMarkdown(String text) {
    if (!text.contains('\n')) {
      return false;
    }
    for (final line in text.split('\n')) {
      if (line.isEmpty) {
        continue;
      }
      if (_matchBlock(line) != null) {
        return true;
      }
    }
    return RegExp(r'(^|\s)\*\*\S[^\n]*?\S?\*\*(\s|$)').hasMatch(text) ||
        RegExp(r'\[[^\]\n]+\]\((https?://|www\.)[^\s)]+\)').hasMatch(text);
  }
}
