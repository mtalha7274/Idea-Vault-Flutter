import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/models/backup/cloud_usage_metadata.dart';

void main() {
  group('CloudUsageMetadata', () {
    test('round trips json', () {
      final metadata = CloudUsageMetadata(
        version: CloudUsageMetadata.currentVersion,
        updatedAt: DateTime.utc(2026, 6, 25),
        usageCount: 12,
        freeUsageGrantLimit: 50,
        introSeen: true,
        halfLimitReviewRequested: true,
      );

      final decoded = CloudUsageMetadata.fromJson(metadata.toJson());

      expect(decoded.version, metadata.version);
      expect(decoded.updatedAt, metadata.updatedAt);
      expect(decoded.usageCount, metadata.usageCount);
      expect(decoded.freeUsageGrantLimit, metadata.freeUsageGrantLimit);
      expect(decoded.introSeen, isTrue);
      expect(decoded.halfLimitReviewRequested, isTrue);
    });

    test('uses defaults for missing fields', () {
      final metadata = CloudUsageMetadata.fromJson(const {});

      expect(metadata.version, CloudUsageMetadata.currentVersion);
      expect(metadata.usageCount, 0);
      expect(metadata.freeUsageGrantLimit, isNull);
      expect(metadata.introSeen, isFalse);
      expect(metadata.halfLimitReviewRequested, isFalse);
    });
  });
}
