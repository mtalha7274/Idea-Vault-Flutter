class SubscriptionState {
  const SubscriptionState({
    required this.isPro,
    required this.isLoading,
    required this.source,
    required this.expiresAt,
    required this.activeProductId,
    required this.lastCheckedAt,
  });

  const SubscriptionState.initial()
      : isPro = false,
        isLoading = false,
        source = null,
        expiresAt = null,
        activeProductId = null,
        lastCheckedAt = null;

  final bool isPro;
  final bool isLoading;
  final String? source;
  final DateTime? expiresAt;
  final String? activeProductId;
  final DateTime? lastCheckedAt;

  SubscriptionState copyWith({
    bool? isPro,
    bool? isLoading,
    String? source,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    String? activeProductId,
    bool clearActiveProductId = false,
    DateTime? lastCheckedAt,
  }) {
    return SubscriptionState(
      isPro: isPro ?? this.isPro,
      isLoading: isLoading ?? this.isLoading,
      source: source ?? this.source,
      expiresAt: clearExpiresAt ? null : expiresAt ?? this.expiresAt,
      activeProductId:
          clearActiveProductId ? null : activeProductId ?? this.activeProductId,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}
