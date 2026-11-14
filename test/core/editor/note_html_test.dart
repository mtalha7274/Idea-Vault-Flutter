import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/editor/note_html.dart';
import 'package:idea_vault/core/editor/note_markup.dart';

void main() {
  String html(String markup) => noteDocumentToHtml(NoteMarkup.parse(markup));

  test('every stored line stays its own line in the PDF', () {
    expect(html('one\ntwo\n\nthree'),
        '<p>one</p><p>two</p><p>&nbsp;</p><p>three</p>');
  });

  test('blocks and inline styles become matching html', () {
    expect(
      html('## Plan\n- a\n- [x] b\n2. c\n> q\n```\n<x>\n```'),
      '<h4>Plan</h4><ul><li>a</li><li class="check">&#9745; b</li></ul>'
      '<ol><li value="2">c</li></ol><blockquote><p>q</p></blockquote>'
      '<pre><code>&lt;x&gt;</code></pre>',
    );
    expect(
      html('**b** _i_ `c` [l](https://x.y) https://a.b'),
      '<p><strong>b</strong> <em>i</em> <code>c</code> '
      '<a href="https://x.y">l</a> <a href="https://a.b">https://a.b</a></p>',
    );
  });

  test('literal markers and html are escaped', () {
    expect(html('2*3 & <b>'), '<p>2*3 &amp; &lt;b&gt;</p>');
  });
}
