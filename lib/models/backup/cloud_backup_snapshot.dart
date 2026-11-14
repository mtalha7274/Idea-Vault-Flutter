import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../idea.dart';
import '../random_addition.dart';
import '../vault/vault_lock_block.dart';
import 'cloud_backup_error.dart';

class CloudBackupSnapshot {
  const CloudBackupSnapshot({
    required this.version,
    required this.exportedAt,
    required this.ideas,
    required this.randomAdditions,
    this.backupId,
    this.deviceId,
    this.deviceName,
    this.appVersion,
    this.contentHash,
    this.lock,
  });

  static const int currentVersion = 3;
  static const int legacyVersion = 1;
  static const String hashPrefix = 'sha256:';

  factory CloudBackupSnapshot.fromJson(Map<String, dynamic> json) {
    final rawIdeas = json['ideas'] as List<dynamic>? ?? const [];
    final rawRandomAdditions =
        json['randomAdditions'] as List<dynamic>? ?? const [];
    final rawLock = json['lock'];
    return CloudBackupSnapshot(
      version: json['version'] as int? ?? currentVersion,
      exportedAt: DateTime.tryParse(
            json['createdAt'] as String? ?? json['exportedAt'] as String? ?? '',
          ) ??
          DateTime.now(),
      backupId: json['backupId'] as String?,
      deviceId: json['deviceId'] as String?,
      deviceName: json['deviceName'] as String?,
      appVersion: json['appVersion'] as String?,
      contentHash: json['contentHash'] as String?,
      lock: rawLock is Map<String, dynamic> ? rawLock : null,
      ideas: rawIdeas
          .whereType<Map<String, dynamic>>()
          .map(Idea.fromJson)
          .toList(growable: false),
      randomAdditions: rawRandomAdditions
          .whereType<Map<String, dynamic>>()
          .map(RandomAddition.fromJson)
          .toList(growable: false),
    );
  }

  factory CloudBackupSnapshot.fromIdeas(List<Idea> ideas) {
    return CloudBackupSnapshot.fromContent(
      ideas: ideas,
      randomAdditions: const [],
    );
  }

  factory CloudBackupSnapshot.fromContent({
    required List<Idea> ideas,
    required List<RandomAddition> randomAdditions,
    String? deviceId,
    String? deviceName,
    String? appVersion,
    String? backupId,
    DateTime? createdAt,
    VaultLockBlock? lock,
  }) {
    final copiedIdeas =
        ideas.map((idea) => idea.copyWith()).toList(growable: false);
    final copiedAdditions = randomAdditions
        .map((addition) => addition.copyWith())
        .toList(growable: false);
    return CloudBackupSnapshot(
      version: currentVersion,
      exportedAt: (createdAt ?? DateTime.now()).toUtc(),
      backupId: backupId ?? generateBackupId(),
      deviceId: deviceId,
      deviceName: deviceName,
      appVersion: appVersion,
      contentHash: contentHashFor(
        ideas: copiedIdeas,
        randomAdditions: copiedAdditions,
      ),
      lock: lock?.toJson(),
      ideas: copiedIdeas,
      randomAdditions: copiedAdditions,
    );
  }

  final int version;
  final DateTime exportedAt;
  final String? backupId;
  final String? deviceId;
  final String? deviceName;
  final String? appVersion;
  final String? contentHash;
  final Map<String, dynamic>? lock;
  final List<Idea> ideas;
  final List<RandomAddition> randomAdditions;

  DateTime get createdAt => exportedAt;
  int get ideaCount => ideas.length;
  int get randomAdditionCount => randomAdditions.length;
  bool get isEmpty => ideas.isEmpty && randomAdditions.isEmpty;
  VaultLockBlock? get lockBlock => VaultLockBlock.tryParse(lock);
  bool get hasEncryptedIdeas => ideas.any((idea) => idea.isEncrypted);
  bool get isEncryptionEpoch => lock?['encrypted'] == true;
  String? get uploadFingerprint {
    final hash = contentHash;
    final lockJson = lock;
    if (hash == null || lockJson == null) {
      return hash;
    }
    return '$hash:lock:${sha256.convert(utf8.encode(jsonEncode(lockJson)))}';
  }

  bool get hasPlaintextLockedIdeas =>
      ideas.any((idea) => idea.isLocked && !idea.isEncrypted);

  static String generateBackupId() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < 16; index++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String contentHashFor({
    required List<Idea> ideas,
    required List<RandomAddition> randomAdditions,
  }) {
    return _hashRawContent(
      ideas.map((idea) => idea.toJson()).toList(),
      randomAdditions.map((addition) => addition.toJson()).toList(),
    );
  }

  static String _hashRawContent(List<dynamic> ideas, List<dynamic> additions) {
    final canonical = jsonEncode({
      'ideas': ideas,
      'randomAdditions': additions,
    });
    return '$hashPrefix${sha256.convert(utf8.encode(canonical))}';
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'backupId': backupId,
      'createdAt': exportedAt.toIso8601String(),
      'exportedAt': exportedAt.toIso8601String(),
      'deviceId': deviceId,
      'deviceName': deviceName,
      'appVersion': appVersion,
      'counts': {
        'ideas': ideas.length,
        'randomAdditions': randomAdditions.length,
      },
      'contentHash': contentHash,
      'lock': lock,
      'ideas': ideas.map((idea) => idea.toJson()).toList(),
      'randomAdditions':
          randomAdditions.map((addition) => addition.toJson()).toList(),
    };
  }

  String encode() => jsonEncode(toJson());

  static CloudBackupSnapshot decodeAndValidate(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } catch (_) {
      throw const CloudBackupException(
        CloudBackupErrorType.invalidBackup,
        'not valid JSON',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const CloudBackupException(
        CloudBackupErrorType.invalidBackup,
        'top level is not an object',
      );
    }

    final rawVersion = decoded['version'];
    final int version;
    if (rawVersion == null) {
      version = legacyVersion;
    } else if (rawVersion is int) {
      version = rawVersion;
    } else {
      throw const CloudBackupException(
        CloudBackupErrorType.invalidBackup,
        'version is not a number',
      );
    }
    if (version > currentVersion) {
      throw CloudBackupException(
        CloudBackupErrorType.newerVersion,
        'version $version',
      );
    }
    if (version < legacyVersion) {
      throw CloudBackupException(
        CloudBackupErrorType.invalidBackup,
        'version $version',
      );
    }

    final rawIdeas = decoded['ideas'] ?? const <dynamic>[];
    final rawAdditions = decoded['randomAdditions'] ?? const <dynamic>[];
    if (rawIdeas is! List<dynamic> || rawAdditions is! List<dynamic>) {
      throw const CloudBackupException(
        CloudBackupErrorType.invalidBackup,
        'content lists missing',
      );
    }

    final storedHash = decoded['contentHash'];
    if (version >= 3) {
      if (storedHash is! String || storedHash.isEmpty) {
        throw const CloudBackupException(
          CloudBackupErrorType.integrityFailed,
          'missing content hash',
        );
      }
      if (_hashRawContent(rawIdeas, rawAdditions) != storedHash) {
        throw const CloudBackupException(
          CloudBackupErrorType.integrityFailed,
          'content hash mismatch',
        );
      }
    }

    final ideas = <Idea>[];
    final ideaIds = <String>{};
    final sectionIds = <String>{};
    for (final rawIdea in rawIdeas) {
      final idea = _parseIdeaStrict(rawIdea);
      if (!ideaIds.add(idea.id)) {
        throw CloudBackupException(
          CloudBackupErrorType.invalidBackup,
          'duplicate idea ${idea.id}',
        );
      }
      for (final section in idea.sections) {
        if (!sectionIds.add(section.id)) {
          throw CloudBackupException(
            CloudBackupErrorType.invalidBackup,
            'duplicate section ${section.id}',
          );
        }
      }
      ideas.add(idea);
    }

    final additions = <RandomAddition>[];
    final additionIds = <String>{};
    for (final rawAddition in rawAdditions) {
      final addition = _parseAdditionStrict(rawAddition);
      if (!additionIds.add(addition.id)) {
        throw CloudBackupException(
          CloudBackupErrorType.invalidBackup,
          'duplicate note ${addition.id}',
        );
      }
      additions.add(addition);
    }

    final counts = decoded['counts'];
    if (counts is Map<String, dynamic>) {
      final ideaCount = counts['ideas'];
      final additionCount = counts['randomAdditions'];
      if ((ideaCount is int && ideaCount != ideas.length) ||
          (additionCount is int && additionCount != additions.length)) {
        throw const CloudBackupException(
          CloudBackupErrorType.integrityFailed,
          'count mismatch',
        );
      }
    }

    final rawLock = decoded['lock'];
    if (ideas.any((idea) => idea.isEncrypted)) {
      if (rawLock is! Map<String, dynamic>) {
        throw const CloudBackupException(
          CloudBackupErrorType.invalidBackup,
          'encrypted notes without a key block',
        );
      }
      try {
        VaultLockBlock.fromJson(rawLock);
      } on VaultFormatException catch (error) {
        throw CloudBackupException(
          error.message == 'newer lock version'
              ? CloudBackupErrorType.newerVersion
              : CloudBackupErrorType.invalidBackup,
          'lock block: ${error.message}',
        );
      }
    }
    final createdAtRaw = decoded['createdAt'] ?? decoded['exportedAt'];
    final createdAt =
        createdAtRaw is String ? DateTime.tryParse(createdAtRaw) : null;

    return CloudBackupSnapshot(
      version: version,
      exportedAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
      backupId: _optionalString(decoded['backupId']),
      deviceId: _optionalString(decoded['deviceId']),
      deviceName: _optionalString(decoded['deviceName']),
      appVersion: _optionalString(decoded['appVersion']),
      contentHash: storedHash is String ? storedHash : null,
      lock: rawLock is Map<String, dynamic> ? rawLock : null,
      ideas: List.unmodifiable(ideas),
      randomAdditions: List.unmodifiable(additions),
    );
  }

  static String? _optionalString(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  static Never _invalidEntry(String detail) {
    throw CloudBackupException(CloudBackupErrorType.invalidBackup, detail);
  }

  static DateTime _requiredDate(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      _invalidEntry('missing $key');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      _invalidEntry('bad $key');
    }
    return parsed;
  }

  static Idea _parseIdeaStrict(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      _invalidEntry('idea is not an object');
    }
    final id = raw['id'];
    if (id is! String || id.isEmpty) {
      _invalidEntry('idea id missing');
    }
    final title = raw['title'];
    if (title != null && title is! String) {
      _invalidEntry('idea title is not text');
    }
    final isLocked = raw['isLocked'];
    if (isLocked != null && isLocked is! bool) {
      _invalidEntry('idea lock flag invalid');
    }
    final lastOpened = raw['lastOpenedSectionId'];
    if (lastOpened != null && lastOpened is! String) {
      _invalidEntry('idea last section invalid');
    }
    final rawSections = raw['sections'] ?? const <dynamic>[];
    if (rawSections is! List<dynamic>) {
      _invalidEntry('idea sections invalid');
    }
    final encryptedPayload = raw['encryptedPayload'];
    final titleHidden = raw['titleHidden'];
    if (titleHidden != null && titleHidden is! bool) {
      _invalidEntry('idea title flag invalid');
    }
    if (encryptedPayload != null) {
      if (encryptedPayload is! String ||
          !EncryptedIdeaEnvelope.isValid(encryptedPayload)) {
        _invalidEntry('encrypted idea invalid');
      }
      if (isLocked != true || rawSections.isNotEmpty) {
        _invalidEntry('encrypted idea must be locked without sections');
      }
    } else if (titleHidden == true) {
      _invalidEntry('hidden title without encrypted content');
    }
    final sections = <IdeaSection>[];
    for (final rawSection in rawSections) {
      if (rawSection is! Map<String, dynamic>) {
        _invalidEntry('section is not an object');
      }
      final sectionId = rawSection['id'];
      if (sectionId != null && (sectionId is! String || sectionId.isEmpty)) {
        _invalidEntry('section id invalid');
      }
      final name = rawSection['name'];
      if (name != null && name is! String) {
        _invalidEntry('section name invalid');
      }
      final content = rawSection['content'];
      final delta = rawSection['delta'];
      if (content != null && content is! String) {
        _invalidEntry('section content invalid');
      }
      if (content == null && delta != null && delta is! List<dynamic>) {
        _invalidEntry('section delta invalid');
      }
      sections.add(IdeaSection.fromJson(rawSection));
    }
    return Idea(
      id: id,
      title: title as String? ?? '',
      createdAt: _requiredDate(raw, 'createdAt'),
      updatedAt: _requiredDate(raw, 'updatedAt'),
      lastOpenedSectionId: lastOpened as String?,
      isLocked: isLocked as bool? ?? false,
      encryptedPayload: encryptedPayload as String?,
      titleHidden: titleHidden as bool? ?? false,
      sections: sections,
    );
  }

  static RandomAddition _parseAdditionStrict(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      _invalidEntry('note is not an object');
    }
    final id = raw['id'];
    if (id is! String || id.isEmpty) {
      _invalidEntry('note id missing');
    }
    final content = raw['content'];
    if (content is! String) {
      _invalidEntry('note content missing');
    }
    return RandomAddition(
      id: id,
      content: content,
      createdAt: _requiredDate(raw, 'createdAt'),
    );
  }
}
