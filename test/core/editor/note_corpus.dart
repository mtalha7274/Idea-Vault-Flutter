const Map<String, String> noteCorpus = {
  'old toolbar output': '## Plan\n'
      '**Bold idea** and _soft_ text\n'
      '- first\n'
      '- second\n'
      '```\n'
      'code here\n'
      '  indented\n'
      '```\n'
      'after',
  'old toolbar code block mid line': 'abc```\nfoo\n```def',
  'old ai style': '# Title\n'
      '* bullet one\n'
      '* bullet two\n'
      '\n'
      '*emphasis* here\n'
      '1. step\n'
      '2. step two',
  'snake case and dunder': 'use snake_case_name and __init__.py and my_var_',
  'maths': '2 * 3 * 4 = 24\n2*3*4\nx**2 + y**2\na * b\n10 * (2 + 3) * 4',
  'lone markers': '**\n** alone\n_ \n~~\n`\n[\n]',
  'paths': '/usr/local/_bin_/x\n'
      r'C:\Users\_temp_\file'
      '\n'
      r'\\server\share'
      '\n'
      r'C:\new\*.txt',
  'urls': 'see https://example.com/a_b_c and www.test.com/x*y* '
      '(https://en.wikipedia.org/wiki/Foo_(bar)).',
  'emoji': '🚀 Launch **day** 🎉\n- 🍎 apples\n👨‍👩‍👧 family _time_',
  'urdu and arabic':
      'یہ کِتاب **اچھی** ہے\n- پہلا\nمرحبا _بالعالم_\n۱. پہلا قدم',
  'mixed direction': 'Hello سلام world\n## عنوان heading\n- item آئٹم',
  'blank lines': '\n\nfirst\n\n\nsecond\n\n',
  'unclosed fence': 'text\n```\ncode\nmore *code*',
  'empty fence': 'before\n```\n```\nafter',
  'fence at end': 'only text\n```',
  'checklists': '- [ ] todo\n- [x] done\n* [X] also\n- [] not a box',
  'links': '[docs](https://flutter.dev) and [x](y) and [ spaced ](z)',
  'existing escapes': 'a \\*b* c\nplain \\ backslash\n\\\\*x*',
  'hashes and quotes': '#hashtag\n##no space\n####### seven\n#### four\n'
      '> quote\n>no space',
  'numbers': '2024. A year\n01. zero\n1) paren\n3.14 pi',
  'trailing spaces': 'line   \n- item  \n  ',
  'tabs and nesting': '\tindented\n- top\n  - nested item\n    - deeper',
  'strike': '~~gone~~ and ~single~',
  'inline code': '`npm install` and `a b` and ``double`` and ` spaced `',
  'rules': '---\n***\n___',
  'nested emphasis': '**bold with *italic* inside**\n_**both**_ and **_both_**',
  'carriage returns': 'line one\r\nline two\r\n',
  'fence with info': '```dart\nvoid main() {}\n```\nafter',
  'adjacent fences': '```\na\n```\n```\nb\n```',
  'empty': '',
  'only spaces': '   ',
  'escaped bullet': '\\- not a bullet\n\\## not a heading',
  'random note appends': 'Old\n\nLoose thought\n\n2*3 and *star*',
  'long single line':
      'This is a long single line with **bold** words repeated many times '
          'and snake_case and maths like 2*3*4 and links https://a.b/c_d '
          'repeated to make it longer and longer and longer and longer.',
  'quote and list mix': '> **Note:** read this\n- a\n\n1. b\n- [ ] c',
  'markers across lines': '**start\nend**\n_open\nclose_',
  'punctuation edges': '(**a**), "_b_". **c**! _d_? [e](https://f.g),',
  'html like': '<b>not bold</b> & <i>x</i>',
};

const Set<String> noteCorpusCanonicalisedOnWrite = {
  'old toolbar code block mid line',
  'unclosed fence',
  'empty fence',
  'fence at end',
};

const Map<String, String> noteCorpusVisibleText = {
  'old toolbar output':
      'Plan\nBold idea and soft text\nfirst\nsecond\ncode here\n  indented\nafter',
  'old toolbar code block mid line': 'abc```\nfoo\n```def',
  'old ai style':
      'Title\nbullet one\nbullet two\n\nemphasis here\nstep\nstep two',
  'snake case and dunder': 'use snake_case_name and __init__.py and my_var_',
  'maths': '2 * 3 * 4 = 24\n2*3*4\nx**2 + y**2\na * b\n10 * (2 + 3) * 4',
  'lone markers': '**\n** alone\n_ \n~~\n`\n[\n]',
  'paths': '/usr/local/_bin_/x\n'
      r'C:\Users\_temp_\file'
      '\n'
      r'\\server\share'
      '\n'
      r'C:\new\*.txt',
  'urls': 'see https://example.com/a_b_c and www.test.com/x*y* '
      '(https://en.wikipedia.org/wiki/Foo_(bar)).',
  'emoji': '🚀 Launch day 🎉\n🍎 apples\n👨‍👩‍👧 family time',
  'urdu and arabic': 'یہ کِتاب اچھی ہے\nپہلا\nمرحبا بالعالم\n۱. پہلا قدم',
  'mixed direction': 'Hello سلام world\nعنوان heading\nitem آئٹم',
  'blank lines': '\n\nfirst\n\n\nsecond\n\n',
  'unclosed fence': 'text\ncode\nmore *code*',
  'checklists': 'todo\ndone\nalso\n[] not a box',
  'links': 'docs and x and [ spaced ](z)',
  'existing escapes': 'a *b* c\nplain \\ backslash\n\\x',
  'hashes and quotes':
      '#hashtag\n##no space\n####### seven\n#### four\nquote\n>no space',
  'numbers': 'A year\nzero\n1) paren\n3.14 pi',
  'trailing spaces': 'line   \nitem  \n  ',
  'tabs and nesting': '\tindented\ntop\n  - nested item\n    - deeper',
  'strike': 'gone and ~single~',
  'inline code': 'npm install and a b and ``double`` and ` spaced `',
  'rules': '---\n***\n___',
  'nested emphasis': 'bold with italic inside\nboth and both',
  'carriage returns': 'line one\r\nline two\r\n',
  'escaped bullet': '- not a bullet\n## not a heading',
  'markers across lines': '**start\nend**\n_open\nclose_',
  'punctuation edges': '(a), "b". c! d? e,',
  'html like': '<b>not bold</b> & <i>x</i>',
};
