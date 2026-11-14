import 'note_document.dart';

const String _openPunctuation = '([{"\'“‘«¿¡';
const String _closePunctuation = ')]}"\'”’».,;:!?…،؛؟۔';
const String _urlTrailingTrim = '.,;:!?\'"*~”’»…،؛؟۔';

const int _backslash = 0x5C;
const int _star = 0x2A;
const int _underscore = 0x5F;
const int _tilde = 0x7E;
const int _backtick = 0x60;
const int _openBracket = 0x5B;

bool isNoteSpaceCode(int code) {
  return code == 0x20 ||
      (code >= 0x09 && code <= 0x0D) ||
      code == 0xA0 ||
      code == 0x1680 ||
      (code >= 0x2000 && code <= 0x200A) ||
      code == 0x2028 ||
      code == 0x2029 ||
      code == 0x202F ||
      code == 0x205F ||
      code == 0x3000;
}

bool _isMarkerCode(int code) {
  return code == _star ||
      code == _underscore ||
      code == _tilde ||
      code == _backtick ||
      code == _openBracket;
}

bool _isEscapableCode(int code) => _isMarkerCode(code) || code == _backslash;

enum _EmphasisKind { bold, italic, strike }

class NoteBareUrl {
  const NoteBareUrl(this.start, this.end, this.href);

  final int start;
  final int end;
  final String href;
}

class NoteInlineCodec {
  const NoteInlineCodec._();

  static List<NoteSpan> parse(String source) {
    if (source.isEmpty) {
      return const [];
    }
    final pieces = <NoteSpan>[];
    _InlineParser(source).parseInto(NoteInlineStyle.plain, pieces);
    return normalizeNoteSpans(pieces);
  }

  static List<NoteBareUrl> findBareUrls(String text) {
    final result = <NoteBareUrl>[];
    if (text.isEmpty) {
      return result;
    }
    final parser = _InlineParser(text);
    var index = 0;
    while (index < text.length) {
      final end = parser.matchBareUrl(index, index - 1);
      if (end > index) {
        result.add(
          NoteBareUrl(index, end, hrefForBareUrl(text.substring(index, end))),
        );
        index = end;
      } else {
        index++;
      }
    }
    return result;
  }

  static String hrefForBareUrl(String text) {
    final lower = text.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return text;
    }
    return 'https://$text';
  }

  static String serialize(List<NoteSpan> spans) {
    final normalized = normalizeNoteSpans(spans);
    if (normalized.isEmpty) {
      return '';
    }
    final trimmed = _trimStyleWhitespace(normalized);
    final attempts = <List<NoteSpan>>[
      trimmed,
      _expandStylesToEdges(trimmed),
    ];
    for (final attempt in attempts) {
      final written = _writeAnyMarker(attempt);
      if (written != null) {
        return written;
      }
    }
    var degraded = _expandStylesToEdges(trimmed);
    for (final drop in _dropOrder) {
      degraded = normalizeNoteSpans(degraded.map(drop));
      final written = _writeAnyMarker(degraded);
      if (written != null) {
        return written;
      }
    }
    final plain = normalizeNoteSpans([
      for (final span in normalized) NoteSpan(span.text),
    ]);
    return _writeWithEscapes(plain) ?? plain.map((span) => span.text).join();
  }

  static final List<NoteSpan Function(NoteSpan)> _dropOrder = [
    (span) => NoteSpan(span.text, span.style.copyWith(strike: false)),
    (span) => NoteSpan(span.text, span.style.copyWith(code: false)),
    (span) => NoteSpan(span.text, span.style.copyWith(italic: false)),
    (span) => NoteSpan(span.text, span.style.copyWith(bold: false)),
    (span) => NoteSpan(span.text, span.style.copyWith(clearLink: true)),
  ];

  static String? _writeAnyMarker(List<NoteSpan> spans) {
    final written = _writeWithEscapes(spans);
    if (written != null || !spans.any((span) => span.style.italic)) {
      return written;
    }
    return _writeWithEscapes(spans, italicMarker: '*');
  }

  static String? _writeWithEscapes(
    List<NoteSpan> spans, {
    String italicMarker = '_',
  }) {
    final chars = _flatten(spans);
    final escapes = <int>{};
    final limit = chars.length + 2;
    for (var attempt = 0; attempt <= limit; attempt++) {
      final written = _render(spans, escapes, italicMarker);
      final parsed = parse(written);
      if (_sameSpans(parsed, spans)) {
        return written;
      }
      final divergence = _firstDivergence(chars, _flatten(parsed));
      final candidate = _escapeCandidate(chars, escapes, divergence);
      if (candidate == null) {
        return null;
      }
      escapes.add(candidate);
    }
    return null;
  }

  static bool _sameSpans(List<NoteSpan> a, List<NoteSpan> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static int? _escapeCandidate(
    List<(int, NoteInlineStyle)> chars,
    Set<int> escapes,
    int divergence,
  ) {
    final start = divergence >= chars.length ? chars.length - 1 : divergence;
    for (var index = start; index >= 0; index--) {
      final (code, style) = chars[index];
      if (style.code || escapes.contains(index)) {
        continue;
      }
      if (_isEscapableCode(code)) {
        return index;
      }
    }
    for (var index = start + 1; index < chars.length; index++) {
      final (code, style) = chars[index];
      if (style.code || escapes.contains(index)) {
        continue;
      }
      if (_isEscapableCode(code)) {
        return index;
      }
    }
    return null;
  }

  static List<(int, NoteInlineStyle)> _flatten(List<NoteSpan> spans) {
    final result = <(int, NoteInlineStyle)>[];
    for (final span in spans) {
      for (final code in span.text.codeUnits) {
        result.add((code, span.style));
      }
    }
    return result;
  }

  static int _firstDivergence(
    List<(int, NoteInlineStyle)> expected,
    List<(int, NoteInlineStyle)> actual,
  ) {
    final length =
        expected.length < actual.length ? expected.length : actual.length;
    for (var i = 0; i < length; i++) {
      if (expected[i].$1 != actual[i].$1 || expected[i].$2 != actual[i].$2) {
        return i;
      }
    }
    return length;
  }

  static String _render(
    List<NoteSpan> spans,
    Set<int> escapes,
    String italicMarker,
  ) {
    final buffer = StringBuffer();
    _renderRuns(
      spans,
      _StyleAttribute.values.toSet(),
      buffer,
      escapes,
      _RenderCursor(italicMarker),
    );
    return buffer.toString();
  }

  static void _renderRuns(
    List<NoteSpan> spans,
    Set<_StyleAttribute> available,
    StringBuffer buffer,
    Set<int> escapes,
    _RenderCursor cursor,
  ) {
    var index = 0;
    while (index < spans.length) {
      final style = spans[index].style;
      _StyleAttribute? best;
      var bestEnd = index;
      for (final attribute in _renderPriority) {
        if (!available.contains(attribute) || !attribute.has(style)) {
          continue;
        }
        if (attribute == _StyleAttribute.code &&
            available.any(
              (other) => other != _StyleAttribute.code && other.has(style),
            )) {
          continue;
        }
        final value = attribute.value(style);
        var end = index + 1;
        while (end < spans.length &&
            attribute.has(spans[end].style) &&
            attribute.value(spans[end].style) == value) {
          end++;
        }
        if (end > bestEnd) {
          best = attribute;
          bestEnd = end;
        }
      }
      if (best == null) {
        _renderLiteral(spans[index], buffer, escapes, cursor);
        index++;
        continue;
      }
      final group = spans.sublist(index, bestEnd);
      final inner = {...available}..remove(best);
      switch (best) {
        case _StyleAttribute.link:
          buffer.write('[');
          _renderRuns(group, inner, buffer, escapes, cursor);
          buffer
            ..write('](')
            ..write(style.link)
            ..write(')');
        case _StyleAttribute.bold:
          buffer.write('**');
          _renderRuns(group, inner, buffer, escapes, cursor);
          buffer.write('**');
        case _StyleAttribute.italic:
          buffer.write(cursor.italicMarker);
          _renderRuns(group, inner, buffer, escapes, cursor);
          buffer.write(cursor.italicMarker);
        case _StyleAttribute.strike:
          buffer.write('~~');
          _renderRuns(group, inner, buffer, escapes, cursor);
          buffer.write('~~');
        case _StyleAttribute.code:
          buffer.write('`');
          for (final span in group) {
            buffer.write(span.text);
            cursor.offset += span.text.length;
          }
          buffer.write('`');
      }
      index = bestEnd;
    }
  }

  static const List<_StyleAttribute> _renderPriority = [
    _StyleAttribute.link,
    _StyleAttribute.bold,
    _StyleAttribute.italic,
    _StyleAttribute.strike,
    _StyleAttribute.code,
  ];

  static void _renderLiteral(
    NoteSpan span,
    StringBuffer buffer,
    Set<int> escapes,
    _RenderCursor cursor,
  ) {
    for (var i = 0; i < span.text.length; i++) {
      if (escapes.contains(cursor.offset)) {
        buffer.writeCharCode(_backslash);
      }
      buffer.writeCharCode(span.text.codeUnitAt(i));
      cursor.offset++;
    }
  }

  static List<NoteSpan> _trimStyleWhitespace(List<NoteSpan> spans) {
    final chars = _flatten(spans);
    final styles = [for (final entry in chars) entry.$2];
    final codes = [for (final entry in chars) entry.$1];
    for (final attribute in _StyleAttribute.values) {
      var index = 0;
      while (index < styles.length) {
        if (!attribute.has(styles[index])) {
          index++;
          continue;
        }
        var end = index;
        final value = attribute.value(styles[index]);
        while (end < styles.length &&
            attribute.value(styles[end]) == value &&
            attribute.has(styles[end])) {
          end++;
        }
        var left = index;
        while (left < end && isNoteSpaceCode(codes[left])) {
          styles[left] = attribute.remove(styles[left]);
          left++;
        }
        var right = end - 1;
        while (right >= left && isNoteSpaceCode(codes[right])) {
          styles[right] = attribute.remove(styles[right]);
          right--;
        }
        index = end;
      }
    }
    return _rebuild(codes, styles);
  }

  static List<NoteSpan> _expandStylesToEdges(List<NoteSpan> spans) {
    final chars = _flatten(spans);
    final styles = [for (final entry in chars) entry.$2];
    final codes = [for (final entry in chars) entry.$1];
    final text = String.fromCharCodes(codes);
    for (final attribute in _StyleAttribute.values) {
      if (attribute == _StyleAttribute.link) {
        continue;
      }
      var index = 0;
      while (index < styles.length) {
        if (!attribute.has(styles[index])) {
          index++;
          continue;
        }
        var end = index;
        while (end < styles.length && attribute.has(styles[end])) {
          end++;
        }
        var left = index;
        while (left > 0 && !_isOpenEdgeAt(text, left - 1)) {
          left--;
        }
        var right = end;
        while (right < styles.length && !_isCloseEdgeAt(text, right)) {
          right++;
        }
        for (var i = left; i < right; i++) {
          styles[i] = attribute.add(styles[i]);
        }
        index = right;
      }
    }
    return _trimStyleWhitespace(_rebuild(codes, styles));
  }

  static List<NoteSpan> _rebuild(
    List<int> codes,
    List<NoteInlineStyle> styles,
  ) {
    final result = <NoteSpan>[];
    var index = 0;
    while (index < codes.length) {
      var end = index + 1;
      while (end < codes.length && styles[end] == styles[index]) {
        end++;
      }
      result.add(
        NoteSpan(
            String.fromCharCodes(codes.sublist(index, end)), styles[index]),
      );
      index = end;
    }
    return normalizeNoteSpans(result);
  }
}

class _RenderCursor {
  _RenderCursor(this.italicMarker);

  final String italicMarker;
  int offset = 0;
}

enum _StyleAttribute {
  bold,
  italic,
  strike,
  code,
  link;

  bool has(NoteInlineStyle style) {
    return switch (this) {
      _StyleAttribute.bold => style.bold,
      _StyleAttribute.italic => style.italic,
      _StyleAttribute.strike => style.strike,
      _StyleAttribute.code => style.code,
      _StyleAttribute.link => style.link != null,
    };
  }

  Object? value(NoteInlineStyle style) {
    return this == _StyleAttribute.link ? style.link : has(style);
  }

  NoteInlineStyle remove(NoteInlineStyle style) {
    return switch (this) {
      _StyleAttribute.bold => style.copyWith(bold: false),
      _StyleAttribute.italic => style.copyWith(italic: false),
      _StyleAttribute.strike => style.copyWith(strike: false),
      _StyleAttribute.code => style.copyWith(code: false),
      _StyleAttribute.link => style.copyWith(clearLink: true),
    };
  }

  NoteInlineStyle add(NoteInlineStyle style) {
    return switch (this) {
      _StyleAttribute.bold => style.copyWith(bold: true),
      _StyleAttribute.italic => style.copyWith(italic: true),
      _StyleAttribute.strike => style.copyWith(strike: true),
      _StyleAttribute.code => style.copyWith(code: true),
      _StyleAttribute.link => style,
    };
  }
}

bool isNoteOpenEdgeAt(String text, int previousIndex) =>
    _isOpenEdgeAt(text, previousIndex);

bool isNoteCloseEdgeAt(String text, int nextIndex) =>
    _isCloseEdgeAt(text, nextIndex);

bool _isOpenEdgeAt(String text, int previousIndex) {
  if (previousIndex < 0) {
    return true;
  }
  final code = text.codeUnitAt(previousIndex);
  return isNoteSpaceCode(code) ||
      _openPunctuation.contains(String.fromCharCode(code));
}

bool _isCloseEdgeAt(String text, int nextIndex) {
  if (nextIndex >= text.length) {
    return true;
  }
  final code = text.codeUnitAt(nextIndex);
  return isNoteSpaceCode(code) ||
      _closePunctuation.contains(String.fromCharCode(code));
}

class _LinkMatch {
  const _LinkMatch(this.textEnd, this.url, this.end);

  final int textEnd;
  final String url;
  final int end;
}

class _InlineParser {
  _InlineParser(this.source, [this.enclosing = const {}]);

  final String source;
  final Set<int> enclosing;

  int get _length => source.length;

  int _code(int index) => source.codeUnitAt(index);

  int _runLength(int index, int code) {
    var end = index;
    while (end < _length && _code(end) == code) {
      end++;
    }
    return end - index;
  }

  _EmphasisKind? _kindFor(int code, int run) {
    if (code == _star) {
      if (run == 1) {
        return _EmphasisKind.italic;
      }
      if (run == 2) {
        return _EmphasisKind.bold;
      }
      return null;
    }
    if (code == _underscore) {
      return run == 1 ? _EmphasisKind.italic : null;
    }
    if (code == _tilde) {
      return run == 2 ? _EmphasisKind.strike : null;
    }
    return null;
  }

  int findEmphasisCloser(int index, int previousIndex) {
    final code = _code(index);
    final run = _runLength(index, code);
    if (_kindFor(code, run) == null) {
      return -1;
    }
    if (!_isOpenEdgeAt(source, previousIndex)) {
      return -1;
    }
    final after = index + run;
    if (after >= _length || isNoteSpaceCode(_code(after))) {
      return -1;
    }
    var cursor = after;
    while (cursor < _length) {
      final current = _code(cursor);
      if (current == _backslash) {
        final slashes = _runLength(cursor, _backslash);
        final next = cursor + slashes;
        if (slashes.isOdd && next < _length && _code(next) == code) {
          cursor = next + 1;
        } else {
          cursor = next;
        }
        continue;
      }
      if (current == code) {
        final closingRun = _runLength(cursor, code);
        if (closingRun == run &&
            cursor > after &&
            !isNoteSpaceCode(_code(cursor - 1)) &&
            _isCloseEdgeAt(source, cursor + closingRun)) {
          return cursor;
        }
        cursor += closingRun;
        continue;
      }
      cursor++;
    }
    return -1;
  }

  int findCodeCloser(int index, int previousIndex) {
    if (_runLength(index, _backtick) != 1) {
      return -1;
    }
    if (!_isOpenEdgeAt(source, previousIndex)) {
      return -1;
    }
    final after = index + 1;
    if (after >= _length || isNoteSpaceCode(_code(after))) {
      return -1;
    }
    var cursor = source.indexOf('`', after);
    while (cursor != -1) {
      final run = _runLength(cursor, _backtick);
      if (run == 1 &&
          !isNoteSpaceCode(_code(cursor - 1)) &&
          _isCloseEdgeAt(source, cursor + 1)) {
        return cursor;
      }
      cursor = source.indexOf('`', cursor + run);
    }
    return -1;
  }

  _LinkMatch? matchLink(int index, int previousIndex) {
    if (!_isOpenEdgeAt(source, previousIndex)) {
      return null;
    }
    final textStart = index + 1;
    final textEnd = source.indexOf('](', textStart);
    if (textEnd <= textStart) {
      return null;
    }
    for (var i = textStart; i < textEnd; i++) {
      final code = _code(i);
      if (code == _openBracket || code == 0x5D) {
        return null;
      }
    }
    if (isNoteSpaceCode(_code(textStart)) ||
        isNoteSpaceCode(_code(textEnd - 1))) {
      return null;
    }
    final urlStart = textEnd + 2;
    var depth = 0;
    var cursor = urlStart;
    while (cursor < _length) {
      final code = _code(cursor);
      if (isNoteSpaceCode(code)) {
        return null;
      }
      if (code == 0x28) {
        depth++;
      } else if (code == 0x29) {
        if (depth == 0) {
          break;
        }
        depth--;
      }
      cursor++;
    }
    if (cursor >= _length || cursor == urlStart) {
      return null;
    }
    final end = cursor + 1;
    if (!_isCloseEdgeAt(source, end)) {
      return null;
    }
    return _LinkMatch(textEnd, source.substring(urlStart, cursor), end);
  }

  int matchBareUrl(int index, int previousIndex) {
    final first = _code(index);
    if (first != 0x68 && first != 0x48 && first != 0x77 && first != 0x57) {
      return -1;
    }
    if (!_isOpenEdgeAt(source, previousIndex)) {
      return -1;
    }
    final lower = source
        .substring(index, index + 8 > _length ? _length : index + 8)
        .toLowerCase();
    int schemeLength;
    if (lower.startsWith('https://')) {
      schemeLength = 8;
    } else if (lower.startsWith('http://')) {
      schemeLength = 7;
    } else if (lower.startsWith('www.')) {
      schemeLength = 4;
    } else {
      return -1;
    }
    var end = index + schemeLength;
    while (end < _length && !isNoteSpaceCode(_code(end))) {
      end++;
    }
    while (end > index + schemeLength) {
      final last = source[end - 1];
      if (_urlTrailingTrim.contains(last)) {
        end--;
        continue;
      }
      if (last == ')' || last == ']') {
        final opener = last == ')' ? '(' : '[';
        final segment = source.substring(index, end);
        final opens = opener.allMatches(segment).length;
        final closes = last.allMatches(segment).length;
        if (closes > opens) {
          end--;
          continue;
        }
      }
      break;
    }
    if (end <= index + schemeLength) {
      return -1;
    }
    return end;
  }

  bool wouldOpenAt(int index, int previousIndex) {
    if (index >= _length) {
      return false;
    }
    final code = _code(index);
    if (code == _star || code == _underscore || code == _tilde) {
      return findEmphasisCloser(index, previousIndex) != -1;
    }
    if (code == _backtick) {
      return findCodeCloser(index, previousIndex) != -1;
    }
    if (code == _openBracket) {
      return matchLink(index, previousIndex) != null;
    }
    return false;
  }

  void parseInto(NoteInlineStyle style, List<NoteSpan> out) {
    final literal = StringBuffer();

    void flush() {
      if (literal.isNotEmpty) {
        out.add(NoteSpan(literal.toString(), style));
        literal.clear();
      }
    }

    var index = 0;
    var overrideAt = -1;
    var overridePrevious = -1;
    while (index < _length) {
      final code = _code(index);
      final previous = index == overrideAt ? overridePrevious : index - 1;
      if (code == _backslash) {
        final slashes = _runLength(index, _backslash);
        final markerIndex = index + slashes;
        if (markerIndex < _length) {
          final marker = _code(markerIndex);
          if (_isMarkerCode(marker) &&
              (enclosing.contains(marker) ||
                  wouldOpenAt(markerIndex, previous))) {
            for (var i = 0; i < slashes ~/ 2; i++) {
              literal.writeCharCode(_backslash);
            }
            if (slashes.isOdd) {
              literal.writeCharCode(marker);
              index = markerIndex + 1;
            } else {
              overrideAt = markerIndex;
              overridePrevious = previous;
              index = markerIndex;
            }
            continue;
          }
        }
        for (var i = 0; i < slashes; i++) {
          literal.writeCharCode(_backslash);
        }
        index = markerIndex;
        continue;
      }
      if (style.link == null) {
        final urlEnd = matchBareUrl(index, previous);
        if (urlEnd > index) {
          literal.write(source.substring(index, urlEnd));
          index = urlEnd;
          continue;
        }
      }
      if (code == _star || code == _underscore || code == _tilde) {
        final run = _runLength(index, code);
        final closer = findEmphasisCloser(index, previous);
        if (closer != -1) {
          flush();
          final kind = _kindFor(code, run)!;
          final inner = source.substring(index + run, closer);
          _InlineParser(inner, {...enclosing, code})
              .parseInto(_withKind(style, kind), out);
          index = closer + run;
          continue;
        }
        literal.write(source.substring(index, index + run));
        index += run;
        continue;
      }
      if (code == _backtick) {
        final closer = findCodeCloser(index, previous);
        if (closer != -1) {
          flush();
          out.add(
            NoteSpan(
              source.substring(index + 1, closer),
              style.copyWith(code: true),
            ),
          );
          index = closer + 1;
          continue;
        }
        final run = _runLength(index, code);
        literal.write(source.substring(index, index + run));
        index += run;
        continue;
      }
      if (code == _openBracket) {
        final link = matchLink(index, previous);
        if (link != null) {
          flush();
          _InlineParser(source.substring(index + 1, link.textEnd), enclosing)
              .parseInto(style.copyWith(link: link.url), out);
          index = link.end;
          continue;
        }
      }
      literal.writeCharCode(code);
      index++;
    }
    flush();
  }

  NoteInlineStyle _withKind(NoteInlineStyle style, _EmphasisKind kind) {
    return switch (kind) {
      _EmphasisKind.bold => style.copyWith(bold: true),
      _EmphasisKind.italic => style.copyWith(italic: true),
      _EmphasisKind.strike => style.copyWith(strike: true),
    };
  }
}
