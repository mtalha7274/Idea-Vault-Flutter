import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/utils/editor_text_insertion.dart';

void main() {
  group('textOnOwnLine', () {
    test('returns plain text for empty editor content', () {
      expect(textOnOwnLine('', '', 'Captured text'), 'Captured text');
    });

    test('starts on a new line after existing text', () {
      expect(textOnOwnLine('Existing text', '', 'Captured text'),
          '\nCaptured text');
    });

    test('adds a trailing break before following text', () {
      expect(textOnOwnLine('', 'Following text', 'Captured text'),
          'Captured text\n');
    });

    test('keeps inserted text isolated between surrounding text', () {
      expect(textOnOwnLine('Before', 'After', 'Captured text'),
          '\nCaptured text\n');
    });

    test('does not add duplicate breaks when boundaries already exist', () {
      expect(textOnOwnLine('Before\n', '\nAfter', 'Captured text'),
          'Captured text');
    });
  });
}
