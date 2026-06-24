import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';

void main() {
  group('NoteLockAuthService', () {
    test('creates and verifies a salted PIN hash', () async {
      final storage = <String, String>{};
      final service = NoteLockAuthService(
        random: Random(1),
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
      );

      expect(await service.hasPin(), isFalse);

      await service.createPin('1234');

      expect(await service.hasPin(), isTrue);
      expect(await service.verifyPin('1234'), isTrue);
      expect(await service.verifyPin('4321'), isFalse);
      expect(storage.values, isNot(contains('1234')));
    });

    test('tracks unlocked ideas for the current session', () {
      final service = NoteLockAuthService(
        random: Random(1),
        readValue: (_) async => null,
        writeValue: (_, __) async {},
      );

      expect(service.isIdeaUnlocked('idea-1'), isFalse);

      service.markIdeaUnlocked('idea-1');

      expect(service.isIdeaUnlocked('idea-1'), isTrue);

      service.clearSessionUnlocks();

      expect(service.isIdeaUnlocked('idea-1'), isFalse);
    });
  });
}
