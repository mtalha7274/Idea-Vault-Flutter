import '../editor/note_markup.dart';

class NormalizedSearchText {
  const NormalizedSearchText({
    required this.text,
    required this.sourceStarts,
    required this.sourceEnds,
  });

  final String text;
  final List<int> sourceStarts;
  final List<int> sourceEnds;

  static const NormalizedSearchText empty = NormalizedSearchText(
    text: '',
    sourceStarts: [],
    sourceEnds: [],
  );

  (int, int) sourceRange(int start, int end) {
    if (start >= end || start >= sourceStarts.length) {
      return (0, 0);
    }
    final clampedEnd = end > sourceEnds.length ? sourceEnds.length : end;
    return (sourceStarts[start], sourceEnds[clampedEnd - 1]);
  }
}

const Map<String, String> _foldPairs = {
  'àáâãäåāăąǎȁȃạảấầẩẫậắằẳẵặ': 'a',
  'çćĉċč': 'c',
  'ďđ': 'd',
  'èéêëēĕėęěȅȇẹẻẽếềểễệ': 'e',
  'ĝğġģ': 'g',
  'ĥħ': 'h',
  'ìíîïĩīĭįıǐȉȋịỉ': 'i',
  'ĵ': 'j',
  'ķ': 'k',
  'ĺļľŀł': 'l',
  'ñńņňŉ': 'n',
  'òóôõöøōŏőǒȍȏọỏốồổỗộớờởỡợơ': 'o',
  'ŕŗř': 'r',
  'śŝşšș': 's',
  'ţťŧț': 't',
  'ùúûüũūŭůűųǔưụủứừửữự': 'u',
  'ŵ': 'w',
  'ýÿŷỳỵỷỹ': 'y',
  'źżž': 'z',
  'أإآٱ': 'ا',
  'يى': 'ی',
  'ك': 'ک',
};

const Map<String, String> _multiFolds = {
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'þ': 'th',
};

final Map<int, String> _foldTable = _buildFoldTable();

Map<int, String> _buildFoldTable() {
  final table = <int, String>{};
  _foldPairs.forEach((sources, target) {
    for (final rune in sources.runes) {
      table[rune] = target;
    }
  });
  _multiFolds.forEach((source, target) {
    table[source.runes.first] = target;
  });
  return table;
}

bool _isIgnorableMark(int rune) {
  return (rune >= 0x0300 && rune <= 0x036F) ||
      (rune >= 0x0610 && rune <= 0x061A) ||
      (rune >= 0x064B && rune <= 0x065F) ||
      rune == 0x0670 ||
      rune == 0x0640 ||
      (rune >= 0x06D6 && rune <= 0x06DC) ||
      (rune >= 0x06DF && rune <= 0x06E4) ||
      rune == 0x06E7 ||
      rune == 0x06E8 ||
      (rune >= 0x06EA && rune <= 0x06ED) ||
      rune == 0x200C ||
      rune == 0x200D ||
      rune == 0xFE0F;
}

bool _isWhitespace(int rune) {
  return rune == 0x20 ||
      (rune >= 0x09 && rune <= 0x0D) ||
      rune == 0xA0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200A) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202F ||
      rune == 0x205F ||
      rune == 0x3000;
}

String _foldRune(int rune) {
  final lower = String.fromCharCode(rune).toLowerCase();
  final buffer = StringBuffer();
  for (final lowerRune in lower.runes) {
    if (_isIgnorableMark(lowerRune)) {
      continue;
    }
    buffer.write(_foldTable[lowerRune] ?? String.fromCharCode(lowerRune));
  }
  return buffer.toString();
}

NormalizedSearchText normalizeForSearch(String source) {
  if (source.isEmpty) {
    return NormalizedSearchText.empty;
  }
  final buffer = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  var lastWasSpace = true;
  var offset = 0;
  for (final rune in source.runes) {
    final runeLength = rune > 0xFFFF ? 2 : 1;
    final runeStart = offset;
    final runeEnd = offset + runeLength;
    offset = runeEnd;

    if (_isWhitespace(rune)) {
      if (!lastWasSpace) {
        buffer.write(' ');
        starts.add(runeStart);
        ends.add(runeEnd);
        lastWasSpace = true;
      }
      continue;
    }
    if (_isIgnorableMark(rune)) {
      continue;
    }
    final folded = _foldRune(rune);
    if (folded.isEmpty) {
      continue;
    }
    buffer.write(folded);
    for (var index = 0; index < folded.length; index++) {
      starts.add(runeStart);
      ends.add(runeEnd);
    }
    lastWasSpace = false;
  }

  var text = buffer.toString();
  if (text.endsWith(' ')) {
    text = text.substring(0, text.length - 1);
    starts.removeLast();
    ends.removeLast();
  }
  return NormalizedSearchText(
    text: text,
    sourceStarts: List.unmodifiable(starts),
    sourceEnds: List.unmodifiable(ends),
  );
}

String normalizeSearchQuery(String query) => normalizeForSearch(query).text;

List<String> searchQueryTerms(String query) {
  final normalized = normalizeSearchQuery(query);
  if (normalized.isEmpty) {
    return const [];
  }
  final terms = <String>[];
  for (final term in normalized.split(' ')) {
    if (term.isEmpty || terms.contains(term)) {
      continue;
    }
    terms.add(term);
  }
  return terms;
}

final RegExp _whitespaceRun = RegExp(r'\s+');

String stripFormattingMarkers(String markdown) {
  if (markdown.isEmpty) {
    return '';
  }
  return NoteMarkup.plainText(markdown).replaceAll(_whitespaceRun, ' ').trim();
}
