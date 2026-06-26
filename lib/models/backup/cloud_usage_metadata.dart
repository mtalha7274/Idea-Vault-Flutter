class CloudUsageMetadata {
  const CloudUsageMetadata({
    required this.version,
    required this.updatedAt,
    required this.usageCount,
    required this.introSeen,
    required this.halfLimitReviewRequested,
    this.freeUsageGrantLimit,
  });

  static const int currentVersion = 1;

  factory CloudUsageMetadata.fromJson(Map<String, dynamic> json) {
    return CloudUsageMetadata(
      version: json['version'] as int? ?? currentVersion,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      usageCount: json['usageCount'] as int? ?? 0,
      freeUsageGrantLimit: json['freeUsageGrantLimit'] as int?,
      introSeen: json['introSeen'] as bool? ?? false,
      halfLimitReviewRequested:
          json['halfLimitReviewRequested'] as bool? ?? false,
    );
  }

  final int version;
  final DateTime updatedAt;
  final int usageCount;
  final int? freeUsageGrantLimit;
  final bool introSeen;
  final bool halfLimitReviewRequested;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'usageCount': usageCount,
      'freeUsageGrantLimit': freeUsageGrantLimit,
      'introSeen': introSeen,
      'halfLimitReviewRequested': halfLimitReviewRequested,
    };
  }
}
