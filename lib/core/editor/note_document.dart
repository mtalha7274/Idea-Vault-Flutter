import 'package:flutter/foundation.dart';

enum NoteBlockType {
  paragraph,
  heading1,
  heading2,
  heading3,
  bullet,
  numbered,
  checklist,
  quote,
  code,
}

extension NoteBlockTypeInfo on NoteBlockType {
  bool get isHeading =>
      this == NoteBlockType.heading1 ||
      this == NoteBlockType.heading2 ||
      this == NoteBlockType.heading3;

  bool get isList =>
      this == NoteBlockType.bullet ||
      this == NoteBlockType.numbered ||
      this == NoteBlockType.checklist;

  bool get continuesOnEnter => isList || this == NoteBlockType.quote;
}

@immutable
class NoteInlineStyle {
  const NoteInlineStyle({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.link,
  });

  static const NoteInlineStyle plain = NoteInlineStyle();

  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
  final String? link;

  bool get isPlain => !bold && !italic && !strike && !code && link == null;

  NoteInlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strike,
    bool? code,
    String? link,
    bool clearLink = false,
  }) {
    return NoteInlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strike: strike ?? this.strike,
      code: code ?? this.code,
      link: clearLink ? null : (link ?? this.link),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NoteInlineStyle &&
        other.bold == bold &&
        other.italic == italic &&
        other.strike == strike &&
        other.code == code &&
        other.link == link;
  }

  @override
  int get hashCode => Object.hash(bold, italic, strike, code, link);

  @override
  String toString() {
    final parts = [
      if (bold) 'b',
      if (italic) 'i',
      if (strike) 's',
      if (code) 'c',
      if (link != null) 'link=$link',
    ];
    return parts.isEmpty ? 'plain' : parts.join('+');
  }
}

@immutable
class NoteSpan {
  const NoteSpan(this.text, [this.style = NoteInlineStyle.plain]);

  final String text;
  final NoteInlineStyle style;

  @override
  bool operator ==(Object other) {
    return other is NoteSpan && other.text == text && other.style == style;
  }

  @override
  int get hashCode => Object.hash(text, style);

  @override
  String toString() => '"$text"[$style]';
}

List<NoteSpan> normalizeNoteSpans(Iterable<NoteSpan> spans) {
  final result = <NoteSpan>[];
  for (final span in spans) {
    if (span.text.isEmpty) {
      continue;
    }
    if (result.isNotEmpty && result.last.style == span.style) {
      final previous = result.removeLast();
      result.add(NoteSpan(previous.text + span.text, span.style));
    } else {
      result.add(span);
    }
  }
  return result;
}

@immutable
class NoteLine {
  const NoteLine({
    this.type = NoteBlockType.paragraph,
    this.spans = const [],
    this.checked = false,
    this.number = '',
    this.codeBlockStart = false,
    this.codeInfo = '',
  });

  factory NoteLine.plain(
    String text, {
    NoteBlockType type = NoteBlockType.paragraph,
  }) {
    return NoteLine(
      type: type,
      spans: text.isEmpty ? const [] : [NoteSpan(text)],
    );
  }

  final NoteBlockType type;
  final List<NoteSpan> spans;
  final bool checked;
  final String number;
  final bool codeBlockStart;
  final String codeInfo;

  String get text {
    if (spans.isEmpty) {
      return '';
    }
    if (spans.length == 1) {
      return spans.single.text;
    }
    final buffer = StringBuffer();
    for (final span in spans) {
      buffer.write(span.text);
    }
    return buffer.toString();
  }

  NoteLine copyWith({
    NoteBlockType? type,
    List<NoteSpan>? spans,
    bool? checked,
    String? number,
    bool? codeBlockStart,
    String? codeInfo,
  }) {
    return NoteLine(
      type: type ?? this.type,
      spans: spans ?? this.spans,
      checked: checked ?? this.checked,
      number: number ?? this.number,
      codeBlockStart: codeBlockStart ?? this.codeBlockStart,
      codeInfo: codeInfo ?? this.codeInfo,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NoteLine &&
        other.type == type &&
        other.checked == checked &&
        other.number == number &&
        other.codeBlockStart == codeBlockStart &&
        other.codeInfo == codeInfo &&
        listEquals(other.spans, spans);
  }

  @override
  int get hashCode => Object.hash(
        type,
        checked,
        number,
        codeBlockStart,
        codeInfo,
        Object.hashAll(spans),
      );

  @override
  String toString() {
    final extras = [
      if (type == NoteBlockType.checklist) 'checked=$checked',
      if (type == NoteBlockType.numbered) 'number=$number',
      if (codeBlockStart) 'start',
      if (codeInfo.isNotEmpty) 'info=$codeInfo',
    ];
    return '${type.name}${extras.isEmpty ? '' : '(${extras.join(',')})'} $spans';
  }
}

@immutable
class NoteDocument {
  const NoteDocument(this.lines);

  final List<NoteLine> lines;

  String get plainText => lines.map((line) => line.text).join('\n');

  @override
  bool operator ==(Object other) {
    return other is NoteDocument && listEquals(other.lines, lines);
  }

  @override
  int get hashCode => Object.hashAll(lines);

  @override
  String toString() => lines.join('\n');
}
