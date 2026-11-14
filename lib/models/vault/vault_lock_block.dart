import 'dart:convert';

import '../idea.dart';

enum NoteLockPinKind {
  digits4,
  digits6,
  passphrase;

  static const NoteLockPinKind newPinDefault = NoteLockPinKind.digits6;
  static const int minPassphraseLength = 8;

  int? get digitCount => switch (this) {
        NoteLockPinKind.digits4 => 4,
        NoteLockPinKind.digits6 => 6,
        NoteLockPinKind.passphrase => null,
      };

  bool get isDigits => digitCount != null;

  static NoteLockPinKind fromName(String? name) {
    for (final kind in values) {
      if (kind.name == name) {
        return kind;
      }
    }
    return NoteLockPinKind.digits4;
  }

  static NoteLockPinKind? tryFromName(String? name) {
    for (final kind in values) {
      if (kind.name == name) {
        return kind;
      }
    }
    return null;
  }

  bool accepts(String secret) {
    final count = digitCount;
    if (count == null) {
      return secret.length >= minPassphraseLength;
    }
    return secret.length == count && RegExp(r'^\d+$').hasMatch(secret);
  }
}

enum VaultKdfAlgorithm {
  argon2id,
  pbkdf2Sha256,
  hkdfSha256;

  String get wireName => switch (this) {
        VaultKdfAlgorithm.argon2id => 'argon2id',
        VaultKdfAlgorithm.pbkdf2Sha256 => 'pbkdf2-sha256',
        VaultKdfAlgorithm.hkdfSha256 => 'hkdf-sha256',
      };

  static VaultKdfAlgorithm? fromWire(Object? value) {
    for (final algorithm in values) {
      if (algorithm.wireName == value) {
        return algorithm;
      }
    }
    return null;
  }
}

class VaultFormatException implements Exception {
  const VaultFormatException(this.message);

  final String message;

  @override
  String toString() => 'VaultFormatException: $message';
}

List<int> _bytes(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw VaultFormatException('missing $field');
  }
  try {
    return base64.decode(value);
  } catch (_) {
    throw VaultFormatException('bad $field');
  }
}

int _int(Object? value, String field, {int min = 1}) {
  if (value is! int || value < min) {
    throw VaultFormatException('bad $field');
  }
  return value;
}

class VaultKdfParams {
  const VaultKdfParams({
    required this.algorithm,
    required this.salt,
    this.memoryKiB = 0,
    this.iterations = 1,
    this.parallelism = 1,
  });

  factory VaultKdfParams.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const VaultFormatException('kdf missing');
    }
    final algorithm = VaultKdfAlgorithm.fromWire(json['alg']);
    if (algorithm == null) {
      throw const VaultFormatException('unknown kdf');
    }
    final salt = _bytes(json['salt'], 'salt');
    switch (algorithm) {
      case VaultKdfAlgorithm.argon2id:
        return VaultKdfParams(
          algorithm: algorithm,
          salt: salt,
          memoryKiB: _int(json['m'], 'm', min: 8),
          iterations: _int(json['t'], 't'),
          parallelism: _int(json['p'], 'p'),
        );
      case VaultKdfAlgorithm.pbkdf2Sha256:
        return VaultKdfParams(
          algorithm: algorithm,
          salt: salt,
          iterations: _int(json['i'], 'i'),
        );
      case VaultKdfAlgorithm.hkdfSha256:
        return VaultKdfParams(algorithm: algorithm, salt: salt);
    }
  }

  final VaultKdfAlgorithm algorithm;
  final List<int> salt;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() {
    return {
      'alg': algorithm.wireName,
      'salt': base64.encode(salt),
      if (algorithm == VaultKdfAlgorithm.argon2id) ...{
        'm': memoryKiB,
        't': iterations,
        'p': parallelism,
      },
      if (algorithm == VaultKdfAlgorithm.pbkdf2Sha256) 'i': iterations,
    };
  }
}

enum VaultWrapKind { pin, recovery }

class VaultKeyWrap {
  const VaultKeyWrap({
    required this.kind,
    required this.kdf,
    required this.nonce,
    required this.cipherText,
    this.pinKind,
  });

  factory VaultKeyWrap.fromJson(Object? json, VaultWrapKind kind) {
    if (json is! Map<String, dynamic>) {
      throw VaultFormatException('${kind.name} wrap missing');
    }
    return VaultKeyWrap(
      kind: kind,
      kdf: VaultKdfParams.fromJson(json['kdf']),
      nonce: _bytes(json['n'], 'n'),
      cipherText: _bytes(json['c'], 'c'),
      pinKind: kind == VaultWrapKind.pin
          ? NoteLockPinKind.tryFromName(json['pinKind'] as String?) ??
              NoteLockPinKind.digits4
          : null,
    );
  }

  final VaultWrapKind kind;
  final VaultKdfParams kdf;
  final List<int> nonce;
  final List<int> cipherText;
  final NoteLockPinKind? pinKind;

  Map<String, dynamic> toJson() {
    return {
      if (pinKind != null) 'pinKind': pinKind!.name,
      'kdf': kdf.toJson(),
      'n': base64.encode(nonce),
      'c': base64.encode(cipherText),
    };
  }
}

class VaultLockBlock {
  const VaultLockBlock({
    required this.keyId,
    required this.createdAt,
    required this.pinWrap,
    required this.recoveryWrap,
    this.version = currentVersion,
    this.epoch = currentEpoch,
  });

  static const int currentVersion = 1;
  static const int currentEpoch = 1;

  factory VaultLockBlock.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const VaultFormatException('lock block missing');
    }
    final version = json['v'];
    if (version is! int || version < 1) {
      throw const VaultFormatException('bad lock version');
    }
    if (version > currentVersion) {
      throw const VaultFormatException('newer lock version');
    }
    final keyId = json['keyId'];
    if (keyId is! String || keyId.isEmpty) {
      throw const VaultFormatException('missing key id');
    }
    final epoch = json['epoch'];
    return VaultLockBlock(
      version: version,
      epoch: epoch is int ? epoch : currentEpoch,
      keyId: keyId,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      pinWrap: VaultKeyWrap.fromJson(json['pin'], VaultWrapKind.pin),
      recoveryWrap:
          VaultKeyWrap.fromJson(json['recovery'], VaultWrapKind.recovery),
    );
  }

  static VaultLockBlock? tryParse(Object? json) {
    if (json == null) {
      return null;
    }
    try {
      return VaultLockBlock.fromJson(json);
    } on VaultFormatException {
      return null;
    }
  }

  static VaultLockBlock? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  final int version;
  final int epoch;
  final String keyId;
  final DateTime createdAt;
  final VaultKeyWrap pinWrap;
  final VaultKeyWrap recoveryWrap;

  NoteLockPinKind get pinKind => pinWrap.pinKind ?? NoteLockPinKind.digits4;

  VaultLockBlock copyWith({
    VaultKeyWrap? pinWrap,
    VaultKeyWrap? recoveryWrap,
  }) {
    return VaultLockBlock(
      version: version,
      epoch: epoch,
      keyId: keyId,
      createdAt: createdAt,
      pinWrap: pinWrap ?? this.pinWrap,
      recoveryWrap: recoveryWrap ?? this.recoveryWrap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'v': version,
      'encrypted': true,
      'epoch': epoch,
      'keyId': keyId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'pin': pinWrap.toJson(),
      'recovery': recoveryWrap.toJson(),
    };
  }

  String encode() => jsonEncode(toJson());
}

class EncryptedIdeaEnvelope {
  const EncryptedIdeaEnvelope({
    required this.keyId,
    required this.nonce,
    required this.cipherText,
    this.version = currentVersion,
  });

  static const int currentVersion = 1;
  static const String algorithm = 'A256GCM';

  factory EncryptedIdeaEnvelope.decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      throw const VaultFormatException('payload is not JSON');
    }
    if (json is! Map<String, dynamic>) {
      throw const VaultFormatException('payload is not an object');
    }
    final version = json['v'];
    if (version is! int || version < 1 || version > currentVersion) {
      throw const VaultFormatException('bad payload version');
    }
    if (json['alg'] != algorithm) {
      throw const VaultFormatException('bad payload algorithm');
    }
    final keyId = json['kid'];
    if (keyId is! String || keyId.isEmpty) {
      throw const VaultFormatException('payload key id missing');
    }
    final nonce = _bytes(json['n'], 'n');
    final cipherText = _bytes(json['c'], 'c');
    if (nonce.length != 12 || cipherText.length < 16) {
      throw const VaultFormatException('payload too short');
    }
    return EncryptedIdeaEnvelope(
      version: version,
      keyId: keyId,
      nonce: nonce,
      cipherText: cipherText,
    );
  }

  static bool isValid(String raw) {
    try {
      EncryptedIdeaEnvelope.decode(raw);
      return true;
    } on VaultFormatException {
      return false;
    }
  }

  static String? keyIdOf(String raw) {
    try {
      return EncryptedIdeaEnvelope.decode(raw).keyId;
    } on VaultFormatException {
      return null;
    }
  }

  final int version;
  final String keyId;
  final List<int> nonce;
  final List<int> cipherText;

  String encode() {
    return jsonEncode({
      'v': version,
      'alg': algorithm,
      'kid': keyId,
      'n': base64.encode(nonce),
      'c': base64.encode(cipherText),
    });
  }
}

class LockedIdeaPayload {
  const LockedIdeaPayload({
    required this.sections,
    this.title,
  });

  factory LockedIdeaPayload.decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      throw const VaultFormatException('content is not JSON');
    }
    if (json is! Map<String, dynamic>) {
      throw const VaultFormatException('content is not an object');
    }
    final rawSections = json['sections'];
    if (rawSections is! List<dynamic>) {
      throw const VaultFormatException('content sections missing');
    }
    final title = json['title'];
    return LockedIdeaPayload(
      title: title is String ? title : null,
      sections: rawSections
          .whereType<Map<String, dynamic>>()
          .map(IdeaSection.fromJson)
          .toList(growable: false),
    );
  }

  final String? title;
  final List<IdeaSection> sections;

  String encode() {
    return jsonEncode({
      'v': 1,
      if (title != null) 'title': title,
      'sections': sections.map((section) => section.toJson()).toList(),
    });
  }
}
