import 'dart:convert';

class CloudBackupEntry {
  const CloudBackupEntry({
    required this.fileId,
    required this.fileName,
    required this.modifiedAt,
    required this.sizeBytes,
    required this.isLegacy,
    this.formatVersion,
    this.createdAt,
    this.deviceShortId,
    this.deviceName,
    this.ideaCount,
    this.randomAdditionCount,
  });

  static const String legacyFileName = 'idea_vault_backup.json';
  static const String filePrefix = 'idea_vault_backup_v';
  static const int maxEncodedDeviceNameBytes = 24;

  static final RegExp _namePattern = RegExp(
    r'^idea_vault_backup_v(\d+)_(\d{8}T\d{6}Z)_([a-z0-9]+)_i(\d+)_n(\d+)(?:_([A-Za-z0-9_-]+))?\.json$',
  );

  final String fileId;
  final String fileName;
  final DateTime? modifiedAt;
  final int? sizeBytes;
  final bool isLegacy;
  final int? formatVersion;
  final DateTime? createdAt;
  final String? deviceShortId;
  final String? deviceName;
  final int? ideaCount;
  final int? randomAdditionCount;

  bool get hasKnownCounts => ideaCount != null && randomAdditionCount != null;

  bool get isEmpty =>
      !isLegacy && (ideaCount ?? 0) == 0 && (randomAdditionCount ?? 0) == 0;

  DateTime get sortTime =>
      modifiedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  static bool isBackupFileName(String name) {
    return name == legacyFileName || _namePattern.hasMatch(name);
  }

  static CloudBackupEntry? fromFile({
    required String fileId,
    required String fileName,
    DateTime? modifiedAt,
    int? sizeBytes,
  }) {
    if (fileName == legacyFileName) {
      return CloudBackupEntry(
        fileId: fileId,
        fileName: fileName,
        modifiedAt: modifiedAt,
        sizeBytes: sizeBytes,
        isLegacy: true,
      );
    }
    final match = _namePattern.firstMatch(fileName);
    if (match == null) {
      return null;
    }
    return CloudBackupEntry(
      fileId: fileId,
      fileName: fileName,
      modifiedAt: modifiedAt,
      sizeBytes: sizeBytes,
      isLegacy: false,
      formatVersion: int.tryParse(match.group(1)!),
      createdAt: _parseCompactUtc(match.group(2)!),
      deviceShortId: match.group(3),
      ideaCount: int.tryParse(match.group(4)!),
      randomAdditionCount: int.tryParse(match.group(5)!),
      deviceName: _decodeDeviceName(match.group(6)),
    );
  }

  static String buildFileName({
    required int formatVersion,
    required DateTime createdAt,
    required String deviceShortId,
    required int ideaCount,
    required int randomAdditionCount,
    String? deviceName,
  }) {
    final encodedName = _encodeDeviceName(deviceName);
    final namePart = encodedName.isEmpty ? '' : '_$encodedName';
    final safeShortId =
        deviceShortId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '$filePrefix${formatVersion}_${_formatCompactUtc(createdAt)}'
        '_${safeShortId.isEmpty ? 'unknown' : safeShortId}'
        '_i${ideaCount}_n$randomAdditionCount$namePart.json';
  }

  static List<CloudBackupEntry> sortNewestFirst(
    Iterable<CloudBackupEntry> entries,
  ) {
    final sorted = [...entries];
    sorted.sort((a, b) {
      final byCloudTime = b.sortTime.compareTo(a.sortTime);
      if (byCloudTime != 0) {
        return byCloudTime;
      }
      final aCreated = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bCreated = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bCreated.compareTo(aCreated);
    });
    return sorted;
  }

  static String _formatCompactUtc(DateTime time) {
    final utc = time.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
        '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  static DateTime? _parseCompactUtc(String value) {
    if (value.length != 16) {
      return null;
    }
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4, 6));
    final day = int.tryParse(value.substring(6, 8));
    final hour = int.tryParse(value.substring(9, 11));
    final minute = int.tryParse(value.substring(11, 13));
    final second = int.tryParse(value.substring(13, 15));
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  static String _encodeDeviceName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }
    final bytes = utf8.encode(trimmed);
    final limited = bytes.length > maxEncodedDeviceNameBytes
        ? bytes.sublist(0, maxEncodedDeviceNameBytes)
        : bytes;
    return base64Url.encode(limited).replaceAll('=', '');
  }

  static String? _decodeDeviceName(String? encoded) {
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      final decoded = utf8.decode(bytes, allowMalformed: true).trim();
      return decoded.replaceAll('�', '').trim().isEmpty
          ? null
          : decoded.replaceAll('�', '').trim();
    } catch (_) {
      return null;
    }
  }
}
