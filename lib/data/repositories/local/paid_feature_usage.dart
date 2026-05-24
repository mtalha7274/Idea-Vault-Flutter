import '../../../config/config.dart';
import '../../managers/local/local_storage.dart';

class PaidFeatureUsageRepo {
  const PaidFeatureUsageRepo(this._localStorage);

  static const String _key = 'paid_feature_usage_count_v1';
  static const String _halfLimitReviewRequestedKey =
      'paid_feature_half_limit_review_requested_v1';

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

  Future<void> clear() async {
    await _localStorage.delete(key: _key);
    await _localStorage.delete(key: _halfLimitReviewRequestedKey);
  }
}
