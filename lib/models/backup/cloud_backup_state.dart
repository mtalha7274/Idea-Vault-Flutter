class CloudBackupState {
  const CloudBackupState({
    required this.enabled,
    required this.autoBackupEnabled,
    required this.email,
    required this.lastBackupAt,
    required this.lastBackupSizeBytes,
    required this.isBusy,
    required this.restorePromptAvailable,
  });

  const CloudBackupState.initial()
      : enabled = false,
        autoBackupEnabled = true,
        email = null,
        lastBackupAt = null,
        lastBackupSizeBytes = null,
        isBusy = false,
        restorePromptAvailable = false;

  final bool enabled;
  final bool autoBackupEnabled;
  final String? email;
  final DateTime? lastBackupAt;
  final int? lastBackupSizeBytes;
  final bool isBusy;
  final bool restorePromptAvailable;

  CloudBackupState copyWith({
    bool? enabled,
    bool? autoBackupEnabled,
    String? email,
    bool clearEmail = false,
    DateTime? lastBackupAt,
    bool clearLastBackupAt = false,
    int? lastBackupSizeBytes,
    bool clearLastBackupSizeBytes = false,
    bool? isBusy,
    bool? restorePromptAvailable,
  }) {
    return CloudBackupState(
      enabled: enabled ?? this.enabled,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      email: clearEmail ? null : email ?? this.email,
      lastBackupAt:
          clearLastBackupAt ? null : lastBackupAt ?? this.lastBackupAt,
      lastBackupSizeBytes: clearLastBackupSizeBytes
          ? null
          : lastBackupSizeBytes ?? this.lastBackupSizeBytes,
      isBusy: isBusy ?? this.isBusy,
      restorePromptAvailable:
          restorePromptAvailable ?? this.restorePromptAvailable,
    );
  }
}
