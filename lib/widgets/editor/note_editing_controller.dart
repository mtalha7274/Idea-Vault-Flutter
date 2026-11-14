import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/editor/note_document.dart';
import '../../core/editor/note_inline_codec.dart';
import '../../core/editor/note_markup.dart';
import 'note_editor_theme.dart';

enum NoteInlineAttribute { bold, italic, strike, code }

@immutable
class NoteEditLine implements NoteEditLineKind {
  const NoteEditLine({
    this.type = NoteBlockType.paragraph,
    this.text = '',
    this.styles = const [],
    this.checked = false,
    this.number = '',
    this.codeBlockStart = false,
    this.codeInfo = '',
  });

  factory NoteEditLine.fromNoteLine(NoteLine line) {
    final styles = <NoteInlineStyle>[];
    for (final span in line.spans) {
      for (var i = 0; i < span.text.length; i++) {
        styles.add(span.style);
      }
    }
    return NoteEditLine(
      type: line.type,
      text: line.text,
      styles: List.unmodifiable(styles),
      checked: line.checked,
      number: line.number,
      codeBlockStart: line.codeBlockStart,
      codeInfo: line.codeInfo,
    );
  }

  factory NoteEditLine.styled(
    String text,
    NoteInlineStyle style, {
    NoteBlockType type = NoteBlockType.paragraph,
  }) {
    final effective =
        type == NoteBlockType.code ? NoteInlineStyle.plain : style;
    return NoteEditLine(
      type: type,
      text: text,
      styles: List.filled(text.length, effective),
    );
  }

  @override
  final NoteBlockType type;
  final String text;
  final List<NoteInlineStyle> styles;
  @override
  final bool checked;
  final String number;
  final bool codeBlockStart;
  final String codeInfo;

  String get prefix {
    switch (type) {
      case NoteBlockType.bullet:
        return '• ';
      case NoteBlockType.numbered:
        return '${number.isEmpty ? '1' : number}. ';
      case NoteBlockType.checklist:
        return '$noteChecklistMarker ';
      case NoteBlockType.quote:
        return '│ ';
      case NoteBlockType.paragraph:
      case NoteBlockType.heading1:
      case NoteBlockType.heading2:
      case NoteBlockType.heading3:
      case NoteBlockType.code:
        return '';
    }
  }

  String get display => '$prefix$text';

  NoteLine toNoteLine() {
    final spans = <NoteSpan>[];
    var index = 0;
    while (index < text.length) {
      var end = index + 1;
      while (end < text.length && styles[end] == styles[index]) {
        end++;
      }
      spans.add(NoteSpan(text.substring(index, end), styles[index]));
      index = end;
    }
    return NoteLine(
      type: type,
      spans: List.unmodifiable(spans),
      checked: type == NoteBlockType.checklist && checked,
      number:
          type == NoteBlockType.numbered ? (number.isEmpty ? '1' : number) : '',
      codeBlockStart: type == NoteBlockType.code && codeBlockStart,
      codeInfo: type == NoteBlockType.code && codeBlockStart ? codeInfo : '',
    );
  }

  NoteEditLine copyWith({
    NoteBlockType? type,
    String? text,
    List<NoteInlineStyle>? styles,
    bool? checked,
    String? number,
    bool? codeBlockStart,
    String? codeInfo,
  }) {
    return NoteEditLine(
      type: type ?? this.type,
      text: text ?? this.text,
      styles: styles ?? this.styles,
      checked: checked ?? this.checked,
      number: number ?? this.number,
      codeBlockStart: codeBlockStart ?? this.codeBlockStart,
      codeInfo: codeInfo ?? this.codeInfo,
    );
  }

  NoteEditLine withType(NoteBlockType nextType, {String number = '1'}) {
    final isCode = nextType == NoteBlockType.code;
    return NoteEditLine(
      type: nextType,
      text: text,
      styles: isCode || type == NoteBlockType.code
          ? List.filled(text.length, NoteInlineStyle.plain)
          : styles,
      checked: false,
      number: nextType == NoteBlockType.numbered ? number : '',
    );
  }

  NoteEditLine asParagraph() => withType(NoteBlockType.paragraph);

  NoteEditLine slice(int start, [int? end]) {
    final stop = end ?? text.length;
    return copyWith(
      text: text.substring(start, stop),
      styles: styles.sublist(start, stop),
    );
  }

  NoteEditLine replaceRange(
      int start, int end, String insert, NoteInlineStyle style) {
    final effective =
        type == NoteBlockType.code ? NoteInlineStyle.plain : style;
    return copyWith(
      text: text.replaceRange(start, end, insert),
      styles: [
        ...styles.sublist(0, start),
        ...List.filled(insert.length, effective),
        ...styles.sublist(end),
      ],
    );
  }

  NoteEditLine append(NoteEditLine other) {
    final otherStyles = type == NoteBlockType.code
        ? List.filled(other.text.length, NoteInlineStyle.plain)
        : other.styles;
    return copyWith(
      text: text + other.text,
      styles: [...styles, ...otherStyles],
    );
  }

  NoteEditLine prepend(NoteEditLine other) {
    final otherStyles = type == NoteBlockType.code
        ? List.filled(other.text.length, NoteInlineStyle.plain)
        : other.styles;
    return copyWith(
      text: other.text + text,
      styles: [...otherStyles, ...styles],
    );
  }
}

class NoteToolbarState {
  const NoteToolbarState({
    required this.bold,
    required this.italic,
    required this.inlineCode,
    required this.link,
    required this.blockType,
    required this.canUndo,
    required this.canRedo,
  });

  final bool bold;
  final bool italic;
  final bool inlineCode;
  final bool link;
  final NoteBlockType? blockType;
  final bool canUndo;
  final bool canRedo;
}

class NoteLinkRange {
  const NoteLinkRange(this.lineIndex, this.start, this.end, this.url);

  final int lineIndex;
  final int start;
  final int end;
  final String url;
}

const String noteChecklistMarker = '\u2003';

class NoteChecklistMark {
  const NoteChecklistMark(this.offset, {required this.checked});

  final int offset;
  final bool checked;
}

class NoteLinkSpan {
  const NoteLinkSpan({
    required this.start,
    required this.end,
    required this.url,
    required this.isAuto,
  });

  final int start;
  final int end;
  final String url;
  final bool isAuto;
}

class _Snapshot {
  const _Snapshot(this.lines, this.selection);

  final List<NoteEditLine> lines;
  final TextSelection selection;
}

class NoteEditingController extends TextEditingController {
  factory NoteEditingController({String markup = ''}) {
    final parsed = NoteMarkup.parseWithSources(markup);
    final lines = [
      for (final line in parsed.document.lines) NoteEditLine.fromNoteLine(line),
    ];
    if (lines.isEmpty) {
      lines.add(const NoteEditLine());
    }
    return NoteEditingController._(
      lines,
      parsed.sources,
      parsed.document,
      markup,
    );
  }

  NoteEditingController._(
    List<NoteEditLine> lines,
    this._sources,
    this._initialDocument,
    this._initialMarkup,
  )   : _lines = lines,
        super(text: _displayOf(lines)) {
    _rebuildIndex();
  }

  static const Duration _undoCoalesceWindow = Duration(milliseconds: 900);
  static const int _undoLimit = 100;

  final Map<NoteLine, String> _sources;
  final NoteDocument _initialDocument;
  final String _initialMarkup;
  List<NoteEditLine> _lines;
  late String _display;
  List<int> _lineStarts = const [0];

  final ValueNotifier<int> contentRevision = ValueNotifier<int>(0);
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  DateTime _lastEditAt = DateTime.fromMillisecondsSinceEpoch(0);

  NoteInlineStyle? _pendingStyle;
  int _pendingOffset = -1;

  List<NoteEditLine> get lines => List.unmodifiable(_lines);

  NoteDocument get document =>
      NoteDocument([for (final line in _lines) line.toNoteLine()]);

  String get markup {
    final current = document;
    if (current == _initialDocument) {
      return _initialMarkup;
    }
    return NoteMarkup.serialize(current, sources: _sources);
  }

  String get plainText => _lines.map((line) => line.text).join('\n');

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  static String _displayOf(List<NoteEditLine> lines) {
    return lines.map((line) => line.display).join('\n');
  }

  void _rebuildIndex() {
    final buffer = StringBuffer();
    final starts = <int>[];
    var offset = 0;
    for (var i = 0; i < _lines.length; i++) {
      starts.add(offset);
      final display = _lines[i].display;
      buffer.write(display);
      offset += display.length;
      if (i < _lines.length - 1) {
        buffer.write('\n');
        offset += 1;
      }
    }
    _display = buffer.toString();
    _lineStarts = starts;
  }

  (int, int) locate(int offset) {
    final clamped = offset.clamp(0, _display.length);
    var low = 0;
    var high = _lineStarts.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_lineStarts[mid] <= clamped) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return (result, clamped - _lineStarts[result]);
  }

  int offsetOf(int lineIndex, int contentColumn) {
    final line = _lines[lineIndex];
    return _lineStarts[lineIndex] +
        line.prefix.length +
        contentColumn.clamp(0, line.text.length);
  }

  (int, int) _contentPosition(int offset) {
    final (lineIndex, column) = locate(offset);
    final prefixLength = _lines[lineIndex].prefix.length;
    return (lineIndex, math.max(0, column - prefixLength));
  }

  @override
  set value(TextEditingValue newValue) {
    var next = newValue;
    if (next.text != _display) {
      final (start, end, inserted) = _diff(_display, next);
      _recordUndo();
      _applyReplace(start, end, inserted, normalize: false);
      _commitModel();
      if (next.text != _display) {
        final offset = next.selection.isValid
            ? next.selection.extentOffset.clamp(0, _display.length)
            : _display.length;
        next = TextEditingValue(
          text: _display,
          selection: TextSelection.collapsed(offset: offset),
        );
      }
    }
    _trackPending(next.selection);
    super.value = next;
  }

  TextEditingValue formatUserEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text == _display) {
      return newValue;
    }
    final (start, end, inserted) = _diff(_display, newValue);
    _recordUndo();
    final caret = _applyReplace(start, end, inserted, normalize: true);
    _commitModel();
    if (_display == newValue.text) {
      return newValue;
    }
    return TextEditingValue(
      text: _display,
      selection: TextSelection.collapsed(
        offset: caret.clamp(0, _display.length),
      ),
    );
  }

  void _trackPending(TextSelection selection) {
    if (_pendingStyle == null) {
      return;
    }
    if (!selection.isValid ||
        !selection.isCollapsed ||
        selection.baseOffset != _pendingOffset) {
      _pendingStyle = null;
      _pendingOffset = -1;
    }
  }

  (int, int, String) _diff(String oldText, TextEditingValue next) {
    final newText = next.text;
    final selection = next.selection;
    if (selection.isValid && selection.isCollapsed) {
      final caret = selection.extentOffset;
      if (caret >= 0 && caret <= newText.length) {
        final suffixLength = newText.length - caret;
        if (suffixLength <= oldText.length &&
            oldText.endsWith(newText.substring(caret))) {
          final oldEnd = oldText.length - suffixLength;
          final limit = math.min(caret, oldEnd);
          var prefix = 0;
          while (prefix < limit &&
              oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
            prefix++;
          }
          return (prefix, oldEnd, newText.substring(prefix, caret));
        }
      }
    }
    final limit = math.min(oldText.length, newText.length);
    var prefix = 0;
    while (prefix < limit &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < limit - prefix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) ==
            newText.codeUnitAt(newText.length - 1 - suffix)) {
      suffix++;
    }
    return (
      prefix,
      oldText.length - suffix,
      newText.substring(prefix, newText.length - suffix),
    );
  }

  NoteInlineStyle _styleForInsertion(int lineIndex, int column, int offset) {
    final line = _lines[lineIndex];
    if (line.type == NoteBlockType.code) {
      return NoteInlineStyle.plain;
    }
    final pending = _pendingStyle;
    if (pending != null && _pendingOffset == offset) {
      return pending;
    }
    if (line.text.isEmpty) {
      return NoteInlineStyle.plain;
    }
    if (column > 0) {
      final previous = line.styles[column - 1];
      final next = column < line.text.length ? line.styles[column] : null;
      var style = previous;
      if (style.link != null && next?.link != style.link) {
        style = style.copyWith(clearLink: true);
      }
      return style;
    }
    return line.styles.first.copyWith(clearLink: true, code: false);
  }

  int _applyReplace(
    int start,
    int end,
    String inserted, {
    required bool normalize,
  }) {
    final (lineA, columnA) = locate(start);
    final (lineB, columnB) = locate(end);
    final first = _lines[lineA];
    final last = _lines[lineB];
    final prefixA = first.prefix.length;
    final prefixB = last.prefix.length;
    final style = _styleForInsertion(
      lineA,
      math.max(0, columnA - prefixA),
      start,
    );
    _pendingStyle = null;
    _pendingOffset = -1;
    final lines = [..._lines];

    if (normalize &&
        inserted.isEmpty &&
        lineB == lineA + 1 &&
        columnB == 0 &&
        columnA == first.display.length &&
        last.prefix.isEmpty &&
        last.type != NoteBlockType.paragraph &&
        !(last.type == NoteBlockType.code &&
            first.type == NoteBlockType.code)) {
      lines[lineB] = last.asParagraph();
      _lines = lines;
      return _offsetIn(lines, lineB, 0);
    }

    var lineIndex = lineA;
    int column;
    if (lineA == lineB) {
      if (end > start && columnA < prefixA) {
        final contentEnd = math.max(0, columnB - prefixA);
        lines[lineA] =
            first.asParagraph().replaceRange(0, contentEnd, '', style);
        column = 0;
      } else {
        final contentStart = math.max(0, columnA - prefixA);
        final contentEnd = math.max(contentStart, columnB - prefixA);
        lines[lineA] = first.replaceRange(contentStart, contentEnd, '', style);
        column = contentStart;
      }
    } else {
      final contentStart = math.max(0, columnA - prefixA);
      final contentEnd = math.max(0, columnB - prefixB);
      final merged = first
          .slice(0, contentStart)
          .append(last.slice(math.min(contentEnd, last.text.length)));
      lines.replaceRange(lineA, lineB + 1, [merged]);
      column = contentStart;
    }

    if (inserted.isNotEmpty) {
      final parts = inserted.split('\n');
      if (parts.length == 1) {
        lines[lineIndex] =
            lines[lineIndex].replaceRange(column, column, inserted, style);
        column += inserted.length;
      } else if (normalize && parts.length == 2) {
        (lineIndex, column) =
            _enter(lines, lineIndex, column, parts[0], parts[1], style);
      } else {
        (lineIndex, column) =
            _pasteLines(lines, lineIndex, column, inserted, style, normalize);
      }
    }

    if (normalize && inserted == ' ') {
      column = _applyShortcut(lines, lineIndex, column);
    }
    _lines = lines;
    return _offsetIn(lines, lineIndex, column);
  }

  int _offsetIn(List<NoteEditLine> lines, int lineIndex, int column) {
    var offset = 0;
    for (var i = 0; i < lineIndex; i++) {
      offset += lines[i].display.length + 1;
    }
    return offset + lines[lineIndex].prefix.length + column;
  }

  bool _isLastOfCodeBlock(List<NoteEditLine> lines, int index) {
    if (index + 1 >= lines.length) {
      return true;
    }
    final next = lines[index + 1];
    return next.type != NoteBlockType.code || next.codeBlockStart;
  }

  String _nextNumber(String number) {
    final value = int.tryParse(number) ?? 0;
    return (value + 1).toString().padLeft(number.length, '0');
  }

  (int, int) _enter(
    List<NoteEditLine> lines,
    int lineIndex,
    int column,
    String before,
    String after,
    NoteInlineStyle style,
  ) {
    var line = lines[lineIndex].replaceRange(column, column, before, style);
    final splitAt = column + before.length;
    if (after.isEmpty && splitAt == line.text.length) {
      final fence = RegExp(r'^```([^`]*)$').firstMatch(line.text);
      if (fence != null && line.type == NoteBlockType.paragraph) {
        lines[lineIndex] = NoteEditLine(
          type: NoteBlockType.code,
          codeBlockStart: true,
          codeInfo: fence.group(1)!,
        );
        return (lineIndex, 0);
      }
    }
    final endsBlock = line.text.isEmpty &&
        (line.type.continuesOnEnter ||
            (line.type == NoteBlockType.code &&
                _isLastOfCodeBlock(lines, lineIndex)));
    if (endsBlock) {
      line = line.asParagraph();
      lines[lineIndex] = line.replaceRange(0, 0, after, style);
      return (lineIndex, after.length);
    }
    final head = line.slice(0, splitAt);
    final tail = line.slice(splitAt);
    NoteEditLine next;
    switch (line.type) {
      case NoteBlockType.bullet:
      case NoteBlockType.quote:
        next = tail.copyWith(checked: false);
      case NoteBlockType.numbered:
        next = tail.copyWith(number: _nextNumber(line.number));
      case NoteBlockType.checklist:
        next = tail.copyWith(checked: false);
      case NoteBlockType.heading1:
      case NoteBlockType.heading2:
      case NoteBlockType.heading3:
        next = tail.text.isEmpty ? tail.asParagraph() : tail;
      case NoteBlockType.code:
        next = tail.copyWith(codeBlockStart: false, codeInfo: '');
      case NoteBlockType.paragraph:
        next = tail;
    }
    next = next.replaceRange(0, 0, after, style);
    lines[lineIndex] = head;
    lines.insert(lineIndex + 1, next);
    return (lineIndex + 1, after.length);
  }

  (int, int) _pasteLines(
    List<NoteEditLine> lines,
    int lineIndex,
    int column,
    String inserted,
    NoteInlineStyle style,
    bool normalize,
  ) {
    final line = lines[lineIndex];
    final head = line.slice(0, column);
    final tail = line.slice(column);
    List<NoteEditLine> pasted;
    if (normalize &&
        line.type != NoteBlockType.code &&
        NoteMarkup.looksLikeMarkdown(inserted)) {
      pasted = [
        for (final parsed in NoteMarkup.parse(inserted).lines)
          NoteEditLine.fromNoteLine(parsed),
      ];
    } else {
      final pastedType = line.type == NoteBlockType.code
          ? NoteBlockType.code
          : NoteBlockType.paragraph;
      pasted = [
        for (final part in inserted.split('\n'))
          NoteEditLine.styled(part, style, type: pastedType),
      ];
    }
    final firstPasted = pasted.first;
    final NoteEditLine firstLine;
    if (head.text.isEmpty && line.type == NoteBlockType.paragraph) {
      firstLine = firstPasted;
    } else {
      firstLine = head.append(firstPasted);
    }
    final lastPasted = pasted.last;
    final lastLine = lastPasted.append(tail);
    final replacement = [
      firstLine,
      ...pasted.sublist(1, pasted.length - 1),
      lastLine,
    ];
    lines.replaceRange(lineIndex, lineIndex + 1, replacement);
    return (lineIndex + replacement.length - 1, lastPasted.text.length);
  }

  static final RegExp _numberShortcut = RegExp(r'^(\d{1,9})\. $');

  int _applyShortcut(List<NoteEditLine> lines, int lineIndex, int column) {
    final line = lines[lineIndex];
    if (column > line.text.length || column > 7) {
      return column;
    }
    final typed = line.text.substring(0, column);
    NoteEditLine? converted;
    if (line.type == NoteBlockType.paragraph) {
      final number = _numberShortcut.firstMatch(typed);
      converted = switch (typed) {
        '- ' || '* ' || '+ ' => line.withType(NoteBlockType.bullet),
        '# ' => line.withType(NoteBlockType.heading1),
        '## ' => line.withType(NoteBlockType.heading2),
        '### ' => line.withType(NoteBlockType.heading3),
        '> ' => line.withType(NoteBlockType.quote),
        '[] ' || '[ ] ' => line.withType(NoteBlockType.checklist),
        _ => number == null
            ? null
            : line.withType(NoteBlockType.numbered, number: number.group(1)!),
      };
    } else if (line.type == NoteBlockType.bullet) {
      if (typed == '[] ' || typed == '[ ] ') {
        converted = line.withType(NoteBlockType.checklist);
      } else if (typed == '[x] ' || typed == '[X] ') {
        converted = line.withType(NoteBlockType.checklist).copyWith(
              checked: true,
            );
      }
    }
    if (converted == null) {
      return column;
    }
    lines[lineIndex] = converted.slice(column);
    return 0;
  }

  void _normalizeLines() {
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.type == NoteBlockType.code) {
        final previousIsCode =
            i > 0 && _lines[i - 1].type == NoteBlockType.code;
        final start = previousIsCode ? line.codeBlockStart : true;
        if (start != line.codeBlockStart ||
            (!start && line.codeInfo.isNotEmpty)) {
          _lines[i] = line.copyWith(
            codeBlockStart: start,
            codeInfo: start ? line.codeInfo : '',
          );
        }
      } else if (line.codeBlockStart || line.codeInfo.isNotEmpty) {
        _lines[i] = line.copyWith(codeBlockStart: false, codeInfo: '');
      }
    }
  }

  void _commitModel() {
    if (_lines.isEmpty) {
      _lines = [const NoteEditLine()];
    }
    _normalizeLines();
    _rebuildIndex();
    contentRevision.value = contentRevision.value + 1;
  }

  void _publish(TextSelection selection) {
    final clamped = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, _display.length),
      extentOffset: selection.extentOffset.clamp(0, _display.length),
    );
    super.value = TextEditingValue(text: _display, selection: clamped);
  }

  void _recordUndo({bool force = false}) {
    final now = DateTime.now();
    final coalesce = !force &&
        _undo.isNotEmpty &&
        now.difference(_lastEditAt) < _undoCoalesceWindow;
    _lastEditAt = force ? DateTime.fromMillisecondsSinceEpoch(0) : now;
    _redo.clear();
    if (coalesce) {
      return;
    }
    _undo.add(_Snapshot(List.of(_lines), selection));
    if (_undo.length > _undoLimit) {
      _undo.removeAt(0);
    }
  }

  void undo() {
    if (_undo.isEmpty) {
      return;
    }
    _redo.add(_Snapshot(List.of(_lines), selection));
    final snapshot = _undo.removeLast();
    _lines = List.of(snapshot.lines);
    _lastEditAt = DateTime.fromMillisecondsSinceEpoch(0);
    _commitModel();
    _publish(snapshot.selection.isValid
        ? snapshot.selection
        : TextSelection.collapsed(offset: _display.length));
  }

  void redo() {
    if (_redo.isEmpty) {
      return;
    }
    _undo.add(_Snapshot(List.of(_lines), selection));
    final snapshot = _redo.removeLast();
    _lines = List.of(snapshot.lines);
    _lastEditAt = DateTime.fromMillisecondsSinceEpoch(0);
    _commitModel();
    _publish(snapshot.selection.isValid
        ? snapshot.selection
        : TextSelection.collapsed(offset: _display.length));
  }

  TextSelection get _safeSelection {
    final current = selection;
    if (current.isValid) {
      return current;
    }
    return TextSelection.collapsed(offset: _display.length);
  }

  (int, int) _selectedLineRange() {
    final current = _safeSelection;
    final (startLine, _) = locate(current.start);
    final (endLine, _) = locate(current.end);
    return (startLine, endLine);
  }

  NoteInlineStyle _styleAtCaret(int offset) {
    final (lineIndex, column) = _contentPosition(offset);
    final pending = _pendingStyle;
    if (pending != null && _pendingOffset == offset) {
      return pending;
    }
    final line = _lines[lineIndex];
    if (line.text.isEmpty || line.type == NoteBlockType.code) {
      return NoteInlineStyle.plain;
    }
    if (column > 0) {
      return line.styles[column - 1];
    }
    return line.styles.first;
  }

  bool _selectionHas(NoteInlineAttribute attribute) {
    final current = _safeSelection;
    if (current.isCollapsed) {
      return _has(_styleAtCaret(current.start), attribute);
    }
    var sawAny = false;
    for (final (lineIndex, start, end) in _contentRanges(current)) {
      final line = _lines[lineIndex];
      for (var i = start; i < end; i++) {
        if (isNoteSpaceCode(line.text.codeUnitAt(i))) {
          continue;
        }
        sawAny = true;
        if (!_has(line.styles[i], attribute)) {
          return false;
        }
      }
    }
    return sawAny;
  }

  List<(int, int, int)> _contentRanges(TextSelection current) {
    final (startLine, startColumn) = _contentPosition(current.start);
    final (endLine, endColumn) = _contentPosition(current.end);
    return [
      for (var i = startLine; i <= endLine; i++)
        (
          i,
          i == startLine ? startColumn : 0,
          i == endLine
              ? math.max(i == startLine ? startColumn : 0, endColumn)
              : _lines[i].text.length,
        ),
    ];
  }

  bool _has(NoteInlineStyle style, NoteInlineAttribute attribute) {
    return switch (attribute) {
      NoteInlineAttribute.bold => style.bold,
      NoteInlineAttribute.italic => style.italic,
      NoteInlineAttribute.strike => style.strike,
      NoteInlineAttribute.code => style.code,
    };
  }

  NoteInlineStyle _set(
    NoteInlineStyle style,
    NoteInlineAttribute attribute,
    bool value,
  ) {
    return switch (attribute) {
      NoteInlineAttribute.bold => style.copyWith(bold: value),
      NoteInlineAttribute.italic => style.copyWith(italic: value),
      NoteInlineAttribute.strike => style.copyWith(strike: value),
      NoteInlineAttribute.code => style.copyWith(code: value),
    };
  }

  NoteToolbarState get toolbarState {
    final (startLine, endLine) = _selectedLineRange();
    final type = _lines[startLine].type;
    var sameType = true;
    for (var i = startLine + 1; i <= endLine; i++) {
      if (_lines[i].type != type) {
        sameType = false;
        break;
      }
    }
    return NoteToolbarState(
      bold: _selectionHas(NoteInlineAttribute.bold),
      italic: _selectionHas(NoteInlineAttribute.italic),
      inlineCode: _selectionHas(NoteInlineAttribute.code),
      link: linkAtSelection != null,
      blockType: sameType ? type : null,
      canUndo: canUndo,
      canRedo: canRedo,
    );
  }

  static final RegExp _wordCharacter =
      RegExp(r'[\p{L}\p{N}\p{M}_]', unicode: true);

  static bool _isWordCode(int code) {
    return _wordCharacter.hasMatch(String.fromCharCode(code));
  }

  void toggleInline(NoteInlineAttribute attribute) {
    final current = _safeSelection;
    if (current.isCollapsed) {
      final (lineIndex, _) = locate(current.start);
      if (_lines[lineIndex].type == NoteBlockType.code) {
        return;
      }
      final style = _styleAtCaret(current.start);
      _pendingStyle = _set(style, attribute, !_has(style, attribute));
      _pendingOffset = current.start;
      notifyListeners();
      return;
    }
    final enable = !_selectionHas(attribute);
    _recordUndo(force: true);
    final lines = [..._lines];
    for (var (lineIndex, start, end) in _contentRanges(current)) {
      final line = lines[lineIndex];
      if (line.type == NoteBlockType.code || start >= end) {
        continue;
      }
      while (start > 0 &&
          start < line.text.length &&
          _isWordCode(line.text.codeUnitAt(start - 1)) &&
          _isWordCode(line.text.codeUnitAt(start))) {
        start--;
      }
      while (end < line.text.length &&
          end > 0 &&
          _isWordCode(line.text.codeUnitAt(end - 1)) &&
          _isWordCode(line.text.codeUnitAt(end))) {
        end++;
      }
      final styles = [...line.styles];
      for (var i = start; i < end; i++) {
        styles[i] = _set(styles[i], attribute, enable);
      }
      lines[lineIndex] = line.copyWith(styles: styles);
    }
    _lines = lines;
    _commitModel();
    _publish(current);
  }

  void toggleBlock(NoteBlockType type) {
    final current = _safeSelection;
    final (startLine, startColumn) = _contentPosition(current.baseOffset);
    final (endLine, endColumn) = _contentPosition(current.extentOffset);
    final (firstLine, lastLine) = _selectedLineRange();
    final allSame = [
      for (var i = firstLine; i <= lastLine; i++) _lines[i].type,
    ].every((lineType) => lineType == type);
    _recordUndo(force: true);
    final lines = [..._lines];
    var number = 1;
    if (firstLine > 0 && lines[firstLine - 1].type == NoteBlockType.numbered) {
      number = (int.tryParse(lines[firstLine - 1].number) ?? 0) + 1;
    }
    for (var i = firstLine; i <= lastLine; i++) {
      if (allSame) {
        lines[i] = lines[i].asParagraph();
      } else {
        lines[i] = lines[i].withType(type, number: '$number');
        number++;
      }
    }
    _lines = lines;
    _commitModel();
    _publish(TextSelection(
      baseOffset: offsetOf(startLine, startColumn),
      extentOffset: offsetOf(endLine, endColumn),
    ));
  }

  void cycleHeading() {
    final (firstLine, _) = _selectedLineRange();
    final next = switch (_lines[firstLine].type) {
      NoteBlockType.heading2 => NoteBlockType.heading3,
      NoteBlockType.heading1 ||
      NoteBlockType.heading3 =>
        NoteBlockType.paragraph,
      _ => NoteBlockType.heading2,
    };
    final current = _safeSelection;
    final (startLine, startColumn) = _contentPosition(current.baseOffset);
    final (endLine, endColumn) = _contentPosition(current.extentOffset);
    final (from, to) = _selectedLineRange();
    _recordUndo(force: true);
    final lines = [..._lines];
    for (var i = from; i <= to; i++) {
      lines[i] = lines[i].withType(next);
    }
    _lines = lines;
    _commitModel();
    _publish(TextSelection(
      baseOffset: offsetOf(startLine, startColumn),
      extentOffset: offsetOf(endLine, endColumn),
    ));
  }

  int get lineCount => _lines.length;

  NoteEditLine lineAt(int lineIndex) => _lines[lineIndex];

  int lineStartOffset(int lineIndex) => _lineStarts[lineIndex];

  bool toggleChecklistAt(int lineIndex) {
    if (lineIndex < 0 || lineIndex >= _lines.length) {
      return false;
    }
    final line = _lines[lineIndex];
    if (line.type != NoteBlockType.checklist) {
      return false;
    }
    final previous = selection;
    _recordUndo(force: true);
    final lines = [..._lines];
    lines[lineIndex] = line.copyWith(checked: !line.checked);
    _lines = lines;
    _commitModel();
    if (previous.isValid) {
      _publish(previous);
    } else {
      super.value = TextEditingValue(text: _display);
    }
    return true;
  }

  NoteLinkRange? get linkAtSelection {
    final current = _safeSelection;
    final (lineIndex, column) = _contentPosition(current.start);
    final line = _lines[lineIndex];
    String? url;
    var anchor = -1;
    if (column < line.text.length && line.styles[column].link != null) {
      url = line.styles[column].link;
      anchor = column;
    } else if (column > 0 && line.styles[column - 1].link != null) {
      url = line.styles[column - 1].link;
      anchor = column - 1;
    }
    if (url == null) {
      return null;
    }
    var start = anchor;
    while (start > 0 && line.styles[start - 1].link == url) {
      start--;
    }
    var end = anchor + 1;
    while (end < line.text.length && line.styles[end].link == url) {
      end++;
    }
    return NoteLinkRange(lineIndex, start, end, url);
  }

  String get selectedPlainText {
    final current = _safeSelection;
    if (current.isCollapsed) {
      return '';
    }
    return [
      for (final (lineIndex, start, end) in _contentRanges(current))
        _lines[lineIndex].text.substring(start, end),
    ].join('\n');
  }

  static String normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(trimmed)) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  void applyLink(String url, {String? label}) {
    final href = normalizeUrl(url);
    if (href.isEmpty) {
      return;
    }
    final current = _safeSelection;
    final existing = linkAtSelection;
    _recordUndo(force: true);
    final lines = [..._lines];
    if (current.isCollapsed && existing != null) {
      final line = lines[existing.lineIndex];
      final styles = [...line.styles];
      for (var i = existing.start; i < existing.end; i++) {
        styles[i] = styles[i].copyWith(link: href);
      }
      lines[existing.lineIndex] = line.copyWith(styles: styles);
      _lines = lines;
      _commitModel();
      _publish(current);
      return;
    }
    if (current.isCollapsed) {
      final (lineIndex, column) = _contentPosition(current.start);
      final line = lines[lineIndex];
      if (line.type == NoteBlockType.code) {
        return;
      }
      final trimmedLabel = label?.trim() ?? '';
      final text = trimmedLabel.isEmpty ? url.trim() : trimmedLabel;
      final base = _styleAtCaret(current.start).copyWith(
        code: false,
        clearLink: true,
      );
      final needsSpaceBefore =
          column > 0 && !isNoteOpenEdgeAt(line.text, column - 1);
      final needsSpaceAfter =
          column < line.text.length && !isNoteCloseEdgeAt(line.text, column);
      var next = line;
      var cursor = column;
      if (needsSpaceBefore) {
        next = next.replaceRange(cursor, cursor, ' ', base);
        cursor += 1;
      }
      next = next.replaceRange(cursor, cursor, text, base.copyWith(link: href));
      cursor += text.length;
      if (needsSpaceAfter) {
        next = next.replaceRange(cursor, cursor, ' ', base);
        cursor += 1;
      }
      lines[lineIndex] = next;
      _lines = lines;
      _commitModel();
      _publish(TextSelection.collapsed(offset: offsetOf(lineIndex, cursor)));
      return;
    }
    for (final (lineIndex, rangeStart, rangeEnd) in _contentRanges(current)) {
      final line = lines[lineIndex];
      if (line.type == NoteBlockType.code) {
        continue;
      }
      final text = line.text;
      var start = rangeStart;
      var end = rangeEnd;
      while (start < end && isNoteSpaceCode(text.codeUnitAt(start))) {
        start++;
      }
      while (end > start && isNoteSpaceCode(text.codeUnitAt(end - 1))) {
        end--;
      }
      if (start >= end) {
        continue;
      }
      while (start > 0 && !isNoteOpenEdgeAt(text, start - 1)) {
        start--;
      }
      while (end < text.length && !isNoteCloseEdgeAt(text, end)) {
        end++;
      }
      final styles = [...line.styles];
      for (var i = start; i < end; i++) {
        styles[i] = styles[i].copyWith(link: href);
      }
      lines[lineIndex] = line.copyWith(styles: styles);
    }
    _lines = lines;
    _commitModel();
    _publish(current);
  }

  void removeLink() {
    final current = _safeSelection;
    final existing = linkAtSelection;
    final ranges = current.isCollapsed
        ? existing == null
            ? const <(int, int, int)>[]
            : [(existing.lineIndex, existing.start, existing.end)]
        : _contentRanges(current);
    if (ranges.isEmpty) {
      return;
    }
    _recordUndo(force: true);
    final lines = [..._lines];
    for (final (lineIndex, start, end) in ranges) {
      final line = lines[lineIndex];
      final styles = [...line.styles];
      for (var i = start; i < end; i++) {
        styles[i] = styles[i].copyWith(clearLink: true);
      }
      lines[lineIndex] = line.copyWith(styles: styles);
    }
    _lines = lines;
    _commitModel();
    _publish(current);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final theme = NoteEditorTheme.maybeOf(context) ??
        NoteEditorThemeData(
          textColor: base.color ?? const Color(0xFF000000),
          mutedColor: const Color(0xFF777777),
          accentColor: const Color(0xFF3355CC),
          codeBackground: const Color(0x14000000),
        );
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final children = <InlineSpan>[];
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final lineStyle = theme.lineStyle(base, line);
      final prefix = line.prefix;
      if (prefix.isNotEmpty) {
        final prefixStyle = theme.prefixStyle(lineStyle, line);
        final gapBeforeContent = line.type != NoteBlockType.code &&
            line.text.isNotEmpty &&
            line.styles.first.code;
        if (gapBeforeContent) {
          if (prefix.length > 1) {
            children.add(TextSpan(
              text: prefix.substring(0, prefix.length - 1),
              style: prefixStyle,
            ));
          }
          children.add(TextSpan(
            text: prefix.substring(prefix.length - 1),
            style: prefixStyle.copyWith(
              letterSpacing: (prefixStyle.letterSpacing ?? 0) +
                  NoteEditorThemeData.inlineCodeGap,
            ),
          ));
        } else {
          children.add(TextSpan(text: prefix, style: prefixStyle));
        }
      }
      final contentStart = _lineStarts[i] + prefix.length;
      _addContentSpans(
        children,
        line,
        i,
        contentStart,
        lineStyle,
        theme,
        composing,
      );
      if (i < _lines.length - 1) {
        children.add(TextSpan(text: '\n', style: lineStyle));
      }
    }
    return TextSpan(style: base, children: children);
  }

  void _addContentSpans(
    List<InlineSpan> children,
    NoteEditLine line,
    int lineIndex,
    int contentStart,
    TextStyle lineStyle,
    NoteEditorThemeData theme,
    TextRange composing,
  ) {
    final text = line.text;
    if (text.isEmpty) {
      return;
    }
    final autoLinks = line.type == NoteBlockType.code
        ? const <NoteBareUrl>[]
        : NoteInlineCodec.findBareUrls(text);
    final cuts = <int>{0, text.length};
    for (var i = 1; i < text.length; i++) {
      if (line.styles[i] != line.styles[i - 1]) {
        cuts.add(i);
      }
    }
    for (final url in autoLinks) {
      cuts
        ..add(url.start)
        ..add(url.end);
    }
    if (composing.isValid && !composing.isCollapsed) {
      final start = composing.start - contentStart;
      final end = composing.end - contentStart;
      if (start > 0 && start < text.length) {
        cuts.add(start);
      }
      if (end > 0 && end < text.length) {
        cuts.add(end);
      }
    }
    final gapAfter = <int>{};
    if (line.type != NoteBlockType.code) {
      var index = 0;
      while (index < text.length) {
        if (!line.styles[index].code) {
          index++;
          continue;
        }
        var end = index;
        while (end < text.length && line.styles[end].code) {
          end++;
        }
        if (index > 0) {
          gapAfter.add(index - 1);
          cuts.add(index - 1);
        }
        gapAfter.add(end - 1);
        cuts
          ..add(index)
          ..add(end - 1)
          ..add(end);
        index = end;
      }
    }
    final sorted = cuts.where((cut) => cut >= 0 && cut <= text.length).toList()
      ..sort();
    var autoIndex = 0;
    for (var c = 0; c < sorted.length - 1; c++) {
      final start = sorted[c];
      final end = sorted[c + 1];
      if (start >= end) {
        continue;
      }
      final inline = line.type == NoteBlockType.code
          ? NoteInlineStyle.plain
          : line.styles[start];
      while (
          autoIndex < autoLinks.length && autoLinks[autoIndex].end <= start) {
        autoIndex++;
      }
      String? href = inline.link;
      if (href == null &&
          !inline.code &&
          autoIndex < autoLinks.length &&
          autoLinks[autoIndex].start <= start) {
        href = autoLinks[autoIndex].href;
      }
      var spanStyle =
          theme.inlineStyle(lineStyle, inline, isLink: href != null);
      final absoluteStart = contentStart + start;
      final absoluteEnd = contentStart + end;
      if (composing.isValid &&
          !composing.isCollapsed &&
          absoluteStart >= composing.start &&
          absoluteEnd <= composing.end) {
        final existing = spanStyle.decoration;
        spanStyle = spanStyle.copyWith(
          decoration: existing == null || existing == TextDecoration.none
              ? TextDecoration.underline
              : TextDecoration.combine([existing, TextDecoration.underline]),
        );
      }
      if (end - start == 1 && gapAfter.contains(start)) {
        spanStyle = spanStyle.copyWith(
          letterSpacing: (spanStyle.letterSpacing ?? 0) +
              NoteEditorThemeData.inlineCodeGap,
        );
      }
      children.add(TextSpan(
        text: text.substring(start, end),
        style: spanStyle,
      ));
    }
  }

  NoteLinkSpan? linkSpanAt(int offset) {
    final (lineIndex, column) = locate(offset);
    final line = _lines[lineIndex];
    final prefixLength = line.prefix.length;
    final contentColumn = column - prefixLength;
    if (contentColumn < 0 || line.type == NoteBlockType.code) {
      return null;
    }
    final base = _lineStarts[lineIndex] + prefixLength;
    var anchor = -1;
    if (contentColumn < line.text.length &&
        line.styles[contentColumn].link != null) {
      anchor = contentColumn;
    } else if (contentColumn > 0 &&
        line.styles[contentColumn - 1].link != null) {
      anchor = contentColumn - 1;
    }
    if (anchor >= 0) {
      final url = line.styles[anchor].link!;
      var start = anchor;
      while (start > 0 && line.styles[start - 1].link == url) {
        start--;
      }
      var end = anchor + 1;
      while (end < line.text.length && line.styles[end].link == url) {
        end++;
      }
      return NoteLinkSpan(
        start: base + start,
        end: base + end,
        url: url,
        isAuto: false,
      );
    }
    for (final url in NoteInlineCodec.findBareUrls(line.text)) {
      if (url.start <= contentColumn &&
          contentColumn <= url.end &&
          !line.styles[url.start].code) {
        return NoteLinkSpan(
          start: base + url.start,
          end: base + url.end,
          url: url.href,
          isAuto: true,
        );
      }
    }
    return null;
  }

  String? linkUrlAt(int offset) => linkSpanAt(offset)?.url;

  List<TextRange> get inlineCodeRanges {
    final ranges = <TextRange>[];
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.type == NoteBlockType.code) {
        continue;
      }
      final base = _lineStarts[i] + line.prefix.length;
      var index = 0;
      while (index < line.text.length) {
        if (!line.styles[index].code) {
          index++;
          continue;
        }
        var end = index;
        while (end < line.text.length && line.styles[end].code) {
          end++;
        }
        ranges.add(TextRange(start: base + index, end: base + end));
        index = end;
      }
    }
    return ranges;
  }

  List<NoteChecklistMark> get checklistMarks {
    return [
      for (var i = 0; i < _lines.length; i++)
        if (_lines[i].type == NoteBlockType.checklist)
          NoteChecklistMark(_lineStarts[i], checked: _lines[i].checked),
    ];
  }

  List<TextRange> get codeBlockRanges {
    final ranges = <TextRange>[];
    var i = 0;
    while (i < _lines.length) {
      if (_lines[i].type != NoteBlockType.code) {
        i++;
        continue;
      }
      var last = i;
      while (last + 1 < _lines.length &&
          _lines[last + 1].type == NoteBlockType.code &&
          !_lines[last + 1].codeBlockStart) {
        last++;
      }
      ranges.add(TextRange(
        start: _lineStarts[i],
        end: _lineStarts[last] + _lines[last].display.length,
      ));
      i = last + 1;
    }
    return ranges;
  }

  @override
  void dispose() {
    contentRevision.dispose();
    super.dispose();
  }
}

class NoteInputFormatter extends TextInputFormatter {
  NoteInputFormatter(this.controller);

  final NoteEditingController controller;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return controller.formatUserEdit(oldValue, newValue);
  }
}

class ClassicBulletListFormatter extends TextInputFormatter {
  static final _bulletPattern = RegExp(r'^(\s*)(- )(.*)$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) {
      return newValue;
    }
    final oldText = oldValue.text;
    final newText = newValue.text;
    if (newText.length <= oldText.length) {
      return newValue;
    }
    final start = oldValue.selection.start < 0 ? 0 : oldValue.selection.start;
    final insertedEnd = start + (newText.length - oldText.length);
    if (insertedEnd > newText.length) {
      return newValue;
    }
    final insertedText = newText.substring(start, insertedEnd);
    if (insertedText != '\n') {
      return newValue;
    }
    final cursorOffset = start;
    final lineStart =
        cursorOffset == 0 ? 0 : newText.lastIndexOf('\n', cursorOffset - 1) + 1;
    final lineEnd = newText.indexOf('\n', cursorOffset);
    final actualLineEnd = lineEnd == -1 ? newText.length : lineEnd;
    final previousLine = newText.substring(lineStart, cursorOffset);
    final match = _bulletPattern.firstMatch(previousLine);
    if (match == null) {
      return newValue;
    }
    final indent = match.group(1) ?? '';
    final bullet = match.group(2) ?? '';
    final content = match.group(3) ?? '';
    if (content.trim().isEmpty) {
      final beforeBullet = newText.substring(0, lineStart);
      final afterLine = actualLineEnd < newText.length
          ? newText.substring(actualLineEnd)
          : '';
      return TextEditingValue(
        text: beforeBullet + afterLine,
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }
    final beforeCursor = newText.substring(0, cursorOffset + 1);
    final afterCursor = newText.substring(cursorOffset + 1);
    return TextEditingValue(
      text: '$beforeCursor$indent$bullet$afterCursor',
      selection: TextSelection.collapsed(
        offset: cursorOffset + 1 + indent.length + bullet.length,
      ),
    );
  }
}
