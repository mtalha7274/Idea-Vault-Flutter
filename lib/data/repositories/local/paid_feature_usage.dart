import 'dart:math';

import '../../../config/config.dart';
import '../../../models/backup/cloud_usage_metadata.dart';
import '../../managers/local/local_storage.dart';

class PaidFeatureUsageRepo {
  const PaidFeatureUsageRepo(this._localStorage);

  static const String _key = 'paid_feature_usage_count_v1';
  static const String _halfLimitReviewRequestedKey =
      'paid_feature_half_limit_review_requested_v1';
  static const String _freeUsageGrantLimitKey = 'free_usage_grant_limit_v1';
  static const String _freeUsageIntroSeenKey = 'free_usage_intro_seen_v1';

  final LocalStorageManager _localStorage;

  int get usageCount {
    final raw = _localStorage.getString(key: _key);
    final parsed = raw == null ? null : int.tryParse(raw);
    if (parsed == null || parsed < 0) {
      return 0;
    }
    return parsed;
  }

  bool get hasReachedFreeLimit =>
      usageCount >= Config.paidFeatureFreeUsageLimit;

  bool get hasRequestedHalfLimitReview =>
      _localStorage.getString(key: _halfLimitReviewRequestedKey) == 'true';

  int? get freeUsageGrantLimit {
    final raw = _localStorage.getString(key: _freeUsageGrantLimitKey);
    final parsed = raw == null ? null : int.tryParse(raw);
    if (parsed == null || parsed < 0) {
      return null;
    }
    return parsed;
  }

  bool get hasFreeUsageGrant => freeUsageGrantLimit != null;

  bool get hasSeenFreeUsageIntro =>
      _localStorage.getString(key: _freeUsageIntroSeenKey) == 'true';

  bool get hasFreeUsageIntroMetadata =>
      hasFreeUsageGrant || hasSeenFreeUsageIntro;

  Future<int> incrementUsage() async {
    final nextCount = usageCount + 1;
    await _localStorage.setString(key: _key, value: nextCount.toString());
    return nextCount;
  }

  Future<void> markHalfLimitReviewRequested() {
    return _localStorage.setString(
      key: _halfLimitReviewRequestedKey,
      value: 'true',
    );
  }

  Future<void> initializeFreeUsageGrantIfNeeded() {
    if (hasFreeUsageGrant) {
      return Future<void>.value();
    }

    return _localStorage.setString(
      key: _freeUsageGrantLimitKey,
      value: Config.paidFeatureFreeUsageLimit.toString(),
    );
  }

  Future<void> markFreeUsageIntroSeen() {
    return _localStorage.setString(
      key: _freeUsageIntroSeenKey,
      value: 'true',
    );
  }

  CloudUsageMetadata toCloudUsageMetadata() {
    return CloudUsageMetadata(
      version: CloudUsageMetadata.currentVersion,
      updatedAt: DateTime.now().toUtc(),
      usageCount: usageCount,
      freeUsageGrantLimit: freeUsageGrantLimit,
      introSeen: hasSeenFreeUsageIntro,
      halfLimitReviewRequested: hasRequestedHalfLimitReview,
    );
  }

  Future<void> mergeCloudUsageMetadata(CloudUsageMetadata metadata) async {
    final nextUsageCount = max(usageCount, metadata.usageCount);
    await _localStorage.setString(
      key: _key,
      value: nextUsageCount.toString(),
    );

    final remoteGrantLimit = metadata.freeUsageGrantLimit;
    final localGrantLimit = freeUsageGrantLimit;
    final nextGrantLimit = max(
      localGrantLimit ?? Config.paidFeatureFreeUsageLimit,
      remoteGrantLimit ?? Config.paidFeatureFreeUsageLimit,
    );
    await _localStorage.setString(
      key: _freeUsageGrantLimitKey,
      value: nextGrantLimit.toString(),
    );

    if (metadata.introSeen || hasSeenFreeUsageIntro) {
      await markFreeUsageIntroSeen();
    }
    if (metadata.halfLimitReviewRequested || hasRequestedHalfLimitReview) {
      await markHalfLimitReviewRequested();
    }
  }

  Future<void> clear() async {
    await _localStorage.delete(key: _key);
    await _localStorage.delete(key: _halfLimitReviewRequestedKey);
    await _localStorage.delete(key: _freeUsageGrantLimitKey);
    await _localStorage.delete(key: _freeUsageIntroSeenKey);
  }
}
