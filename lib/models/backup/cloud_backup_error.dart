enum CloudBackupErrorType {
  offline,
  timeout,
  signInRequired,
  signInCancelled,
  iCloudUnavailable,
  noBackupFound,
  emptyBackup,
  invalidBackup,
  newerVersion,
  integrityFailed,
  unknown;

  static CloudBackupErrorType? fromName(String? name) {
    if (name == null) {
      return null;
    }
    for (final value in CloudBackupErrorType.values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }

  bool get isValidationFailure =>
      this == CloudBackupErrorType.invalidBackup ||
      this == CloudBackupErrorType.newerVersion ||
      this == CloudBackupErrorType.integrityFailed;
}

class CloudBackupException implements Exception {
  const CloudBackupException(this.type, [this.detail]);

  final CloudBackupErrorType type;
  final String? detail;

  @override
  String toString() => 'CloudBackupException(${type.name}: ${detail ?? ''})';
}
