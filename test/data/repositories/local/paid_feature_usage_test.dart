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

    test('persists free usage grant limit metadata', () async {
      expect(repo.freeUsageGrantLimit, isNull);
      expect(repo.hasFreeUsageGrant, isFalse);

      await repo.initializeFreeUsageGrantIfNeeded();

      final reloadedRepo = PaidFeatureUsageRepo(storage);
      expect(
          reloadedRepo.freeUsageGrantLimit, Config.paidFeatureFreeUsageLimit);
      expect(reloadedRepo.hasFreeUsageGrant, isTrue);
      expect(reloadedRepo.usageCount, 0);
    });

    test('does not overwrite an existing free usage grant limit', () async {
      await storage.setString(
        key: 'free_usage_grant_limit_v1',
        value: '12',
      );

      await repo.initializeFreeUsageGrantIfNeeded();

      expect(repo.freeUsageGrantLimit, 12);
    });

    test('persists free usage intro seen metadata', () async {
      expect(repo.hasSeenFreeUsageIntro, isFalse);
      expect(repo.hasFreeUsageIntroMetadata, isFalse);

      await repo.markFreeUsageIntroSeen();

      final reloadedRepo = PaidFeatureUsageRepo(storage);
      expect(reloadedRepo.hasSeenFreeUsageIntro, isTrue);
      expect(reloadedRepo.hasFreeUsageIntroMetadata, isTrue);
      expect(reloadedRepo.usageCount, 0);
    });

    test('clears usage and metadata state', () async {
      await repo.incrementUsage();
      await repo.markHalfLimitReviewRequested();
      await repo.initializeFreeUsageGrantIfNeeded();
      await repo.markFreeUsageIntroSeen();

      await repo.clear();

      expect(repo.usageCount, 0);
      expect(repo.hasRequestedHalfLimitReview, isFalse);
      expect(repo.freeUsageGrantLimit, isNull);
      expect(repo.hasSeenFreeUsageIntro, isFalse);
    });
  });
}
