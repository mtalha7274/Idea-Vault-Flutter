import 'note_document.dart';
import 'note_inline_codec.dart';

String escapeNoteHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String noteDocumentToHtml(NoteDocument document) {
  final buffer = StringBuffer();
  final lines = document.lines;
  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    switch (line.type) {
      case NoteBlockType.bullet:
      case NoteBlockType.checklist:
        buffer.write('<ul>');
        while (index < lines.length &&
            (lines[index].type == NoteBlockType.bullet ||
                lines[index].type == NoteBlockType.checklist)) {
          final item = lines[index];
          if (item.type == NoteBlockType.checklist) {
            buffer.write(
              '<li class="check">${item.checked ? '&#9745;' : '&#9744;'} '
              '${_inlineHtml(item.spans)}</li>',
            );
          } else {
            buffer.write('<li>${_inlineHtml(item.spans)}</li>');
          }
          index++;
        }
        buffer.write('</ul>');
        continue;
      case NoteBlockType.numbered:
        buffer.write('<ol>');
        while (index < lines.length &&
            lines[index].type == NoteBlockType.numbered) {
          final item = lines[index];
          final value = int.tryParse(item.number) ?? 1;
          buffer.write('<li value="$value">${_inlineHtml(item.spans)}</li>');
          index++;
        }
        buffer.write('</ol>');
        continue;
      case NoteBlockType.code:
        buffer.write('<pre><code>');
        var first = true;
        while (index < lines.length &&
            lines[index].type == NoteBlockType.code &&
            (first || !lines[index].codeBlockStart)) {
          if (!first) {
            buffer.write('\n');
          }
          buffer.write(escapeNoteHtml(lines[index].text));
          first = false;
          index++;
        }
        buffer.write('</code></pre>');
        continue;
      case NoteBlockType.quote:
        buffer.write('<blockquote>');
        while (
            index < lines.length && lines[index].type == NoteBlockType.quote) {
          buffer.write('<p>${_lineContent(lines[index])}</p>');
          index++;
        }
        buffer.write('</blockquote>');
        continue;
      case NoteBlockType.heading1:
        buffer.write('<h3>${_lineContent(line)}</h3>');
      case NoteBlockType.heading2:
        buffer.write('<h4>${_lineContent(line)}</h4>');
      case NoteBlockType.heading3:
        buffer.write('<h5>${_lineContent(line)}</h5>');
      case NoteBlockType.paragraph:
        buffer.write('<p>${_lineContent(line)}</p>');
    }
    index++;
  }
  return buffer.toString();
}

String _lineContent(NoteLine line) {
  final html = _inlineHtml(line.spans);
  return html.isEmpty ? '&nbsp;' : html;
}

String _inlineHtml(List<NoteSpan> spans) {
  final buffer = StringBuffer();
  for (final span in spans) {
    var html = span.style.link == null && !span.style.code
        ? _autoLinked(span.text)
        : escapeNoteHtml(span.text);
    final style = span.style;
    if (style.code) {
      html = '<code>$html</code>';
    }
    if (style.strike) {
      html = '<del>$html</del>';
    }
    if (style.italic) {
      html = '<em>$html</em>';
    }
    if (style.bold) {
      html = '<strong>$html</strong>';
    }
    if (style.link != null) {
      html = '<a href="${escapeNoteHtml(style.link!)}">$html</a>';
    }
    buffer.write(html);
  }
  return buffer.toString();
}

String _autoLinked(String text) {
  final urls = NoteInlineCodec.findBareUrls(text);
  if (urls.isEmpty) {
    return escapeNoteHtml(text);
  }
  final buffer = StringBuffer();
  var cursor = 0;
  for (final url in urls) {
    buffer
      ..write(escapeNoteHtml(text.substring(cursor, url.start)))
      ..write('<a href="${escapeNoteHtml(url.href)}">')
      ..write(escapeNoteHtml(text.substring(url.start, url.end)))
      ..write('</a>');
    cursor = url.end;
  }
  buffer.write(escapeNoteHtml(text.substring(cursor)));
  return buffer.toString();
}
