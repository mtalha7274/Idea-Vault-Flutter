import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:idea_vault/config/config.dart';
import 'package:idea_vault/data/repositories/local/paid_feature_usage.dart';

import '../../../helpers/memory_local_storage.dart';

void main() {
  dotenv.loadFromString(envString: 'DEBUG=false');

  group('PaidFeatureUsageRepo', () {
    late MemoryLocalStorageManager storage;
    late PaidFeatureUsageRepo repo;

    setUp(() {
      storage = MemoryLocalStorageManager();
      repo = PaidFeatureUsageRepo(storage);
    });

    test('defaults to zero usage', () {
      expect(repo.usageCount, 0);
      expect(repo.hasReachedFreeLimit, isFalse);
    });

    test('increments and persists usage count', () async {
      expect(await repo.incrementUsage(), 1);
      expect(await repo.incrementUsage(), 2);

      final reloadedRepo = PaidFeatureUsageRepo(storage);
      expect(reloadedRepo.usageCount, 2);
    });

    test('falls back to zero for malformed stored value', () async {
      await storage.setString(
        key: 'paid_feature_usage_count_v1',
        value: 'not-a-number',
      );

      expect(repo.usageCount, 0);
      expect(repo.hasReachedFreeLimit, isFalse);
    });

    test('reports the free limit as reached', () async {
      for (var i = 0; i < Config.paidFeatureFreeUsageLimit; i += 1) {
        await repo.incrementUsage();
      }

      expect(repo.usageCount, Config.paidFeatureFreeUsageLimit);
      expect(repo.hasReachedFreeLimit, isTrue);
    });

    test('persists half-limit review prompt state', () async {
      expect(repo.hasRequestedHalfLimitReview, isFalse);

      await repo.markHalfLimitReviewRequested();

      final reloadedRepo = PaidFeatureUsageRepo(storage);
      expect(reloadedRepo.hasRequestedHalfLimitReview, isTrue);
    });

    test('clears usage and half-limit review prompt state', () async {
      await repo.incrementUsage();
      await repo.markHalfLimitReviewRequested();

      await repo.clear();

      expect(repo.usageCount, 0);
      expect(repo.hasRequestedHalfLimitReview, isFalse);
    });
  });
}
