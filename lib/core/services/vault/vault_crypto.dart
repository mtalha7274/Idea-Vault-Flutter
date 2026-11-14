import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

import '../../../models/vault/vault_lock_block.dart';

enum VaultCryptoErrorType { wrongKey, tampered, malformed }

class VaultCryptoException implements Exception {
  const VaultCryptoException(this.type, [this.detail = '']);

  final VaultCryptoErrorType type;
  final String detail;

  @override
  String toString() => 'VaultCryptoException(${type.name}): $detail';
}

class VaultSealedBox {
  const VaultSealedBox({required this.nonce, required this.cipherText});

  final List<int> nonce;
  final List<int> cipherText;
}

class VaultCipher {
  VaultCipher({
    Random? random,
    this.isolateThresholdBytes = defaultIsolateThresholdBytes,
  }) : _random = random ?? Random.secure();

  static const int keyLength = 32;
  static const int nonceLength = 12;
  static const int macLength = 16;
  static const int defaultIsolateThresholdBytes = 200 * 1024;

  final Random _random;
  final int isolateThresholdBytes;
  int isolateRuns = 0;

  List<int> randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }

  List<int> newKey() => randomBytes(keyLength);

  Future<VaultSealedBox> seal({
    required List<int> key,
    required List<int> plainText,
    required List<int> associatedData,
    List<int>? nonce,
  }) async {
    _checkKey(key);
    final usedNonce = nonce ?? randomBytes(nonceLength);
    if (usedNonce.length != nonceLength) {
      throw const VaultCryptoException(
        VaultCryptoErrorType.malformed,
        'bad nonce',
      );
    }
    if (plainText.length > isolateThresholdBytes) {
      isolateRuns += 1;
      final keyCopy = List<int>.of(key);
      final textCopy = List<int>.of(plainText);
      final adCopy = List<int>.of(associatedData);
      final nonceCopy = List<int>.of(usedNonce);
      final combined = await Isolate.run(
        () => _sealDart(keyCopy, textCopy, adCopy, nonceCopy),
      );
      return VaultSealedBox(nonce: usedNonce, cipherText: combined);
    }
    final box = await AesGcm.with256bits().encrypt(
      plainText,
      secretKey: SecretKey(List<int>.of(key)),
      nonce: usedNonce,
      aad: associatedData,
    );
    return VaultSealedBox(
      nonce: usedNonce,
      cipherText: [...box.cipherText, ...box.mac.bytes],
    );
  }

  Future<List<int>> open({
    required List<int> key,
    required List<int> nonce,
    required List<int> cipherText,
    required List<int> associatedData,
  }) async {
    _checkKey(key);
    if (nonce.length != nonceLength || cipherText.length < macLength) {
      throw const VaultCryptoException(
        VaultCryptoErrorType.malformed,
        'box too short',
      );
    }
    try {
      if (cipherText.length > isolateThresholdBytes) {
        isolateRuns += 1;
        final keyCopy = List<int>.of(key);
        final nonceCopy = List<int>.of(nonce);
        final textCopy = List<int>.of(cipherText);
        final adCopy = List<int>.of(associatedData);
        return await Isolate.run(
          () => _openDart(keyCopy, nonceCopy, textCopy, adCopy),
        );
      }
      final split = cipherText.length - macLength;
      return await AesGcm.with256bits().decrypt(
        SecretBox(
          cipherText.sublist(0, split),
          nonce: nonce,
          mac: Mac(cipherText.sublist(split)),
        ),
        secretKey: SecretKey(List<int>.of(key)),
        aad: associatedData,
      );
    } on SecretBoxAuthenticationError {
      throw const VaultCryptoException(
        VaultCryptoErrorType.tampered,
        'authentication failed',
      );
    } on VaultCryptoException {
      rethrow;
    } catch (error) {
      if ('$error'.contains('SecretBoxAuthenticationError')) {
        throw const VaultCryptoException(
          VaultCryptoErrorType.tampered,
          'authentication failed',
        );
      }
      rethrow;
    }
  }

  static void _checkKey(List<int> key) {
    if (key.length != keyLength) {
      throw const VaultCryptoException(
        VaultCryptoErrorType.malformed,
        'bad key length',
      );
    }
  }

  static Future<List<int>> _sealDart(
    List<int> key,
    List<int> plainText,
    List<int> associatedData,
    List<int> nonce,
  ) async {
    final box = await DartAesGcm.with256bits().encrypt(
      plainText,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: associatedData,
    );
    return [...box.cipherText, ...box.mac.bytes];
  }

  static Future<List<int>> _openDart(
    List<int> key,
    List<int> nonce,
    List<int> cipherText,
    List<int> associatedData,
  ) async {
    final split = cipherText.length - macLength;
    try {
      return await DartAesGcm.with256bits().decrypt(
        SecretBox(
          cipherText.sublist(0, split),
          nonce: nonce,
          mac: Mac(cipherText.sublist(split)),
        ),
        secretKey: SecretKey(key),
        aad: associatedData,
      );
    } on SecretBoxAuthenticationError {
      throw const VaultCryptoException(
        VaultCryptoErrorType.tampered,
        'authentication failed',
      );
    }
  }
}

abstract class VaultKdf {
  Future<List<int>> deriveKey(String secret, VaultKdfParams params);

  Future<VaultKdfParams> newPinParams();

  VaultKdfParams newRecoveryParams();
}

class DefaultVaultKdf implements VaultKdf {
  DefaultVaultKdf({
    Random? random,
    this.argon2Budget = defaultArgon2Budget,
    this.useIsolate = true,
    VaultKdfParams Function(List<int> salt)? pinParams,
    Future<Duration> Function()? calibrate,
    bool? nativePbkdf2Available,
  })  : _random = random ?? Random.secure(),
        _pinParams = pinParams,
        _calibrate = calibrate,
        _nativePbkdf2Available = nativePbkdf2Available;

  static const int argon2MemoryKiB = 19 * 1024;
  static const int argon2Iterations = 2;
  static const int argon2Parallelism = 1;
  static const int pbkdf2Iterations = 600000;
  static const int saltLength = 16;
  static const int calibrationMemoryKiB = 4096;
  static const int calibrationIterations = 1;
  static const Duration defaultArgon2Budget = Duration(milliseconds: 3000);
  static const String recoveryInfo = 'idea-vault-recovery-v1';

  final Random _random;
  final Duration argon2Budget;
  final bool useIsolate;
  final VaultKdfParams Function(List<int> salt)? _pinParams;
  final Future<Duration> Function()? _calibrate;
  final bool? _nativePbkdf2Available;

  List<int> _salt() =>
      List<int>.generate(saltLength, (_) => _random.nextInt(256));

  static VaultKdfParams argon2idParams(List<int> salt) {
    return VaultKdfParams(
      algorithm: VaultKdfAlgorithm.argon2id,
      salt: salt,
      memoryKiB: argon2MemoryKiB,
      iterations: argon2Iterations,
      parallelism: argon2Parallelism,
    );
  }

  static VaultKdfParams pbkdf2Params(List<int> salt) {
    return VaultKdfParams(
      algorithm: VaultKdfAlgorithm.pbkdf2Sha256,
      salt: salt,
      iterations: pbkdf2Iterations,
    );
  }

  static Duration estimateFullArgon2(Duration calibration) {
    final factor = (argon2MemoryKiB / calibrationMemoryKiB) *
        (argon2Iterations / calibrationIterations);
    return Duration(
      microseconds: (calibration.inMicroseconds * factor).round(),
    );
  }

  bool get _hasNativePbkdf2 =>
      _nativePbkdf2Available ?? FlutterCryptography.isPluginPresent;

  @override
  Future<VaultKdfParams> newPinParams() async {
    final salt = _salt();
    final override = _pinParams;
    if (override != null) {
      return override(salt);
    }
    if (!_hasNativePbkdf2) {
      return argon2idParams(salt);
    }
    try {
      final calibration = await (_calibrate ?? _runCalibration)();
      if (estimateFullArgon2(calibration) <= argon2Budget) {
        return argon2idParams(salt);
      }
    } catch (_) {}
    return pbkdf2Params(salt);
  }

  @override
  VaultKdfParams newRecoveryParams() {
    return VaultKdfParams(
      algorithm: VaultKdfAlgorithm.hkdfSha256,
      salt: _salt(),
    );
  }

  Future<Duration> _runCalibration() async {
    final watch = Stopwatch()..start();
    await _argon2id(
      utf8.encode('calibration'),
      List<int>.filled(saltLength, 0),
      calibrationMemoryKiB,
      calibrationIterations,
      1,
    );
    return watch.elapsed;
  }

  @override
  Future<List<int>> deriveKey(String secret, VaultKdfParams params) async {
    final secretBytes = utf8.encode(secret);
    switch (params.algorithm) {
      case VaultKdfAlgorithm.argon2id:
        return _argon2id(
          secretBytes,
          params.salt,
          params.memoryKiB,
          params.iterations,
          params.parallelism,
        );
      case VaultKdfAlgorithm.pbkdf2Sha256:
        final pbkdf2 = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: params.iterations,
          bits: 256,
        );
        final key = await pbkdf2.deriveKey(
          secretKey: SecretKey(secretBytes),
          nonce: params.salt,
        );
        return key.extractBytes();
      case VaultKdfAlgorithm.hkdfSha256:
        final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
        final key = await hkdf.deriveKey(
          secretKey: SecretKey(secretBytes),
          nonce: params.salt,
          info: utf8.encode(recoveryInfo),
        );
        return key.extractBytes();
    }
  }

  Future<List<int>> _argon2id(
    List<int> secret,
    List<int> salt,
    int memoryKiB,
    int iterations,
    int parallelism,
  ) {
    Future<List<int>> run() =>
        derivePlainArgon2id(secret, salt, memoryKiB, iterations, parallelism);
    if (!useIsolate) {
      return run();
    }
    final secretCopy = List<int>.of(secret);
    final saltCopy = List<int>.of(salt);
    return Isolate.run(
      () => derivePlainArgon2id(
        secretCopy,
        saltCopy,
        memoryKiB,
        iterations,
        parallelism,
      ),
    );
  }

  static Future<List<int>> derivePlainArgon2id(
    List<int> secret,
    List<int> salt,
    int memoryKiB,
    int iterations,
    int parallelism,
  ) async {
    final algorithm = DartArgon2id(
      parallelism: parallelism,
      memory: memoryKiB,
      iterations: iterations,
      hashLength: 32,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
    );
    return key.extractBytes();
  }
}

class VaultRecoveryCode {
  const VaultRecoveryCode._();

  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int byteLength = 20;
  static const int length = 32;
  static const int groupSize = 4;

  static String generate(Random random) {
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return encode(bytes);
  }

  static String encode(List<int> bytes) {
    final buffer = StringBuffer();
    var accumulator = 0;
    var bits = 0;
    for (final byte in bytes) {
      accumulator = (accumulator << 8) | (byte & 0xff);
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        buffer.write(alphabet[(accumulator >> bits) & 0x1f]);
      }
      accumulator &= (1 << bits) - 1;
    }
    if (bits > 0) {
      buffer.write(alphabet[(accumulator << (5 - bits)) & 0x1f]);
    }
    return buffer.toString();
  }

  static String format(String code) {
    final groups = <String>[];
    for (var index = 0; index < code.length; index += groupSize) {
      final end = min(index + groupSize, code.length);
      groups.add(code.substring(index, end));
    }
    return groups.join('-');
  }

  static String? normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toUpperCase().runes) {
      var char = String.fromCharCode(rune);
      if (char == ' ' || char == '-' || char == '\n' || char == '\t') {
        continue;
      }
      if (char == 'O') {
        char = '0';
      } else if (char == 'I' || char == 'L') {
        char = '1';
      }
      if (!alphabet.contains(char)) {
        return null;
      }
      buffer.write(char);
    }
    final normalized = buffer.toString();
    return normalized.length == length ? normalized : null;
  }
}
