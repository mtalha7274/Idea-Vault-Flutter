class BackupDeviceIdentity {
  const BackupDeviceIdentity({
    required this.id,
    required this.name,
  });

  static const int shortIdLength = 8;

  final String id;
  final String name;

  String get shortId {
    final normalized =
        id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.length <= shortIdLength
        ? normalized
        : normalized.substring(0, shortIdLength);
  }
}
