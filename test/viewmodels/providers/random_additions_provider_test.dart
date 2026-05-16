import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/models/random_addition.dart';
import 'package:idea_vault/viewmodels/providers/random_additions_provider.dart';

import '../../helpers/in_memory_random_additions_repo.dart';

void main() {
  group('RandomAdditionsProvider', () {
    late InMemoryRandomAdditionsRepo repo;
    late RandomAdditionsProvider provider;

    setUp(() async {
      repo = InMemoryRandomAdditionsRepo();
      provider = RandomAdditionsProvider(repo);
      await provider.ensureLoaded();
    });

    test('adds and loads random additions', () async {
      final addition = await provider.addAddition('First loose thought');

      expect(addition, isNotNull);
      expect(provider.additions, hasLength(1));
      expect(provider.additions.single.content, 'First loose thought');

      final restoredProvider = RandomAdditionsProvider(repo);
      await restoredProvider.ensureLoaded();

      expect(restoredProvider.additions, hasLength(1));
      expect(restoredProvider.additions.single.content, 'First loose thought');
    });

    test('ignores blank additions', () async {
      final addition = await provider.addAddition('   ');

      expect(addition, isNull);
      expect(provider.additions, isEmpty);
    });

    test('deletes random additions', () async {
      final addition = await provider.addAddition('Remove me');

      await provider.deleteAddition(addition!.id);

      expect(provider.additions, isEmpty);
    });

    test('replaces random additions on restore', () async {
      await provider.addAddition('Local draft');
      final restoredAddition = RandomAddition(
        id: 'restored-random',
        content: 'Restored from cloud',
        createdAt: DateTime.utc(2026, 5, 16),
      );

      await provider.replaceAdditions([restoredAddition]);

      expect(provider.additions, [restoredAddition]);
    });
  });
}
