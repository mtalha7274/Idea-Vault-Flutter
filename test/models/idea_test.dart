import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/models/idea.dart';

void main() {
  group('Idea', () {
    test('defaults missing isLocked JSON to false', () {
      final idea = Idea.fromJson({
        'id': 'idea-1',
        'title': 'Legacy backup',
        'createdAt': DateTime.utc(2026, 4, 20).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 4, 21).toIso8601String(),
        'sections': const [],
      });

      expect(idea.isLocked, isFalse);
    });

    test('serializes isLocked to JSON', () {
      final idea = Idea(
        id: 'idea-1',
        title: 'Private backup',
        createdAt: DateTime.utc(2026, 4, 20),
        updatedAt: DateTime.utc(2026, 4, 21),
        isLocked: true,
        sections: const [],
      );

      expect(idea.toJson()['isLocked'], isTrue);
    });
  });
}
