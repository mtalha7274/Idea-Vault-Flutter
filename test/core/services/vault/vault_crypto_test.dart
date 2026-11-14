import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/vault/vault_crypto.dart';
import 'package:idea_vault/models/vault/vault_lock_block.dart';

List<int> hex(String value) {
  final clean = value.replaceAll(' ', '');
  return [
    for (var index = 0; index < clean.length; index += 2)
      int.parse(clean.substring(index, index + 2), radix: 16),
  ];
}

String toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Matcher throwsVaultError(VaultCryptoErrorType type) {
  return throwsA(
    isA<VaultCryptoException>().having((error) => error.type, 'type', type),
  );
}

void main() {
  group('AES-256-GCM known answer', () {
    final key = hex(
      'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308',
    );
    final nonce = hex('cafebabefacedbaddecaf888');
    final aad = hex('feedfacedeadbeeffeedfacedeadbeefabaddad2');
    final plain = hex(
      'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
      '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39',
    );
    final expected = hex(
      '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
      '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662'
      '76fc6ece0f4e1768cddf8853bb2d551b',
    );

    test('seal matches the GCM spec test case 16', () async {
      final box = await VaultCipher().seal(
        key: key,
        plainText: plain,
        associatedData: aad,
        nonce: nonce,
      );
      expect(toHex(box.cipherText), toHex(expected));
    });

    test('open recovers the GCM spec plaintext', () async {
      final opened = await VaultCipher().open(
        key: key,
        nonce: nonce,
        cipherText: expected,
        associatedData: aad,
      );
      expect(toHex(opened), toHex(plain));
    });
  });

  group('VaultCipher', () {
    late VaultCipher cipher;
    late List<int> key;

    setUp(() {
      cipher = VaultCipher(random: Random(11));
      key = cipher.newKey();
    });

    test('round trips and uses a fresh nonce every time', () async {
      final text = utf8.encode('hello locked world');
      final first = await cipher.seal(
        key: key,
        plainText: text,
        associatedData: utf8.encode('idea-1'),
      );
      final second = await cipher.seal(
        key: key,
        plainText: text,
        associatedData: utf8.encode('idea-1'),
      );
      expect(first.nonce, isNot(second.nonce));
      expect(first.cipherText, isNot(second.cipherText));
      final opened = await cipher.open(
        key: key,
        nonce: first.nonce,
        cipherText: first.cipherText,
        associatedData: utf8.encode('idea-1'),
      );
      expect(utf8.decode(opened), 'hello locked world');
    });

    test('a wrong key is detected, never returned as garbage', () async {
      final box = await cipher.seal(
        key: key,
        plainText: utf8.encode('secret'),
        associatedData: const [1],
      );
      expect(
        () => cipher.open(
          key: cipher.newKey(),
          nonce: box.nonce,
          cipherText: box.cipherText,
          associatedData: const [1],
        ),
        throwsVaultError(VaultCryptoErrorType.tampered),
      );
    });

    test('a tampered blob is detected', () async {
      final box = await cipher.seal(
        key: key,
        plainText: utf8.encode('secret'),
        associatedData: const [1],
      );
      final tampered = [...box.cipherText];
      tampered[0] ^= 0x01;
      expect(
        () => cipher.open(
          key: key,
          nonce: box.nonce,
          cipherText: tampered,
          associatedData: const [1],
        ),
        throwsVaultError(VaultCryptoErrorType.tampered),
      );
    });

    test('wrong associated data is detected', () async {
      final box = await cipher.seal(
        key: key,
        plainText: utf8.encode('secret'),
        associatedData: utf8.encode('idea-a'),
      );
      expect(
        () => cipher.open(
          key: key,
          nonce: box.nonce,
          cipherText: box.cipherText,
          associatedData: utf8.encode('idea-b'),
        ),
        throwsVaultError(VaultCryptoErrorType.tampered),
      );
    });

    test('large notes are sealed and opened in an isolate', () async {
      final big = List<int>.generate(260 * 1024, (index) => index % 251);
      final box = await cipher.seal(
        key: key,
        plainText: big,
        associatedData: const [9],
      );
      final opened = await cipher.open(
        key: key,
        nonce: box.nonce,
        cipherText: box.cipherText,
        associatedData: const [9],
      );
      expect(opened, big);
      expect(cipher.isolateRuns, 2);
    });

    test('rejects short boxes and wrong key sizes', () {
      expect(
        () => cipher.open(
          key: key,
          nonce: const [1, 2, 3],
          cipherText: const [1],
          associatedData: const [],
        ),
        throwsVaultError(VaultCryptoErrorType.malformed),
      );
      expect(
        () => cipher.seal(
          key: const [1, 2, 3],
          plainText: const [1],
          associatedData: const [],
        ),
        throwsVaultError(VaultCryptoErrorType.malformed),
      );
    });
  });

  group('key derivation', () {
    test('Argon2id primitive matches the RFC 9106 vector', () async {
      final algorithm = DartArgon2id(
        parallelism: 4,
        memory: 32,
        iterations: 3,
        hashLength: 32,
      );
      final key = await algorithm.deriveKey(
        secretKey: SecretKey(List<int>.filled(32, 0x01)),
        nonce: List<int>.filled(16, 0x02),
        optionalSecret: List<int>.filled(8, 0x03),
        associatedData: List<int>.filled(12, 0x04),
      );
      expect(
        toHex(await key.extractBytes()),
        '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
      );
    });

    test('PIN Argon2id derivation is stable in and out of an isolate',
        () async {
      final salt = List<int>.generate(16, (index) => index);
      final params = VaultKdfParams(
        algorithm: VaultKdfAlgorithm.argon2id,
        salt: salt,
        memoryKiB: 256,
        iterations: 2,
        parallelism: 1,
      );
      final inIsolate = await DefaultVaultKdf().deriveKey('123456', params);
      final direct =
          await DefaultVaultKdf(useIsolate: false).deriveKey('123456', params);
      final reference = await DefaultVaultKdf.derivePlainArgon2id(
        utf8.encode('123456'),
        salt,
        256,
        2,
        1,
      );
      expect(inIsolate, reference);
      expect(direct, reference);
      final other =
          await DefaultVaultKdf(useIsolate: false).deriveKey('123457', params);
      expect(other, isNot(reference));
    });

    test('PBKDF2-HMAC-SHA256 matches a known vector', () async {
      final key = await DefaultVaultKdf().deriveKey(
        '123456',
        VaultKdfParams(
          algorithm: VaultKdfAlgorithm.pbkdf2Sha256,
          salt: utf8.encode('0123456789abcdef'),
          iterations: 1000,
        ),
      );
      expect(
        toHex(key),
        '8a68d007111e13d5806b51f02a2d542fa2e19edf549f42624a9d30674e79260a',
      );
    });

    test('recovery derivation depends on the salt', () async {
      final kdf = DefaultVaultKdf(random: Random(4));
      final first = kdf.newRecoveryParams();
      final second = kdf.newRecoveryParams();
      final a = await kdf.deriveKey('ABCD', first);
      final b = await kdf.deriveKey('ABCD', first);
      final c = await kdf.deriveKey('ABCD', second);
      expect(a, b);
      expect(a, isNot(c));
      expect(a, hasLength(32));
    });

    test('chooses Argon2id when the calibration fits the budget', () async {
      final kdf = DefaultVaultKdf(
        nativePbkdf2Available: true,
        calibrate: () async => const Duration(milliseconds: 100),
      );
      final params = await kdf.newPinParams();
      expect(params.algorithm, VaultKdfAlgorithm.argon2id);
      expect(params.memoryKiB, 19 * 1024);
      expect(params.iterations, 2);
      expect(params.parallelism, 1);
      expect(params.salt, hasLength(16));
    });

    test('falls back to PBKDF2 when Argon2id would be too slow', () async {
      final kdf = DefaultVaultKdf(
        nativePbkdf2Available: true,
        calibrate: () async => const Duration(milliseconds: 600),
      );
      final params = await kdf.newPinParams();
      expect(params.algorithm, VaultKdfAlgorithm.pbkdf2Sha256);
      expect(params.iterations, 600000);
    });

    test('falls back to PBKDF2 when Argon2id fails', () async {
      final kdf = DefaultVaultKdf(
        nativePbkdf2Available: true,
        calibrate: () async => throw StateError('no argon2'),
      );
      expect(
          (await kdf.newPinParams()).algorithm, VaultKdfAlgorithm.pbkdf2Sha256);
    });

    test('keeps Argon2id without a native PBKDF2', () async {
      final kdf = DefaultVaultKdf(
        nativePbkdf2Available: false,
        calibrate: () async => const Duration(seconds: 5),
      );
      expect((await kdf.newPinParams()).algorithm, VaultKdfAlgorithm.argon2id);
    });

    test('full Argon2id estimate scales with memory and passes', () {
      expect(
        DefaultVaultKdf.estimateFullArgon2(const Duration(milliseconds: 100)),
        const Duration(milliseconds: 950),
      );
    });

    test('measured full Argon2id cost stays within the budget here', () async {
      final watch = Stopwatch()..start();
      await DefaultVaultKdf().deriveKey(
        '123456',
        DefaultVaultKdf.argon2idParams(List<int>.filled(16, 1)),
      );
      expect(watch.elapsed, lessThan(DefaultVaultKdf.defaultArgon2Budget));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('KDF parameters round trip through JSON', () {
      final params = DefaultVaultKdf.argon2idParams(List<int>.filled(16, 3));
      final decoded = VaultKdfParams.fromJson(params.toJson());
      expect(decoded.algorithm, VaultKdfAlgorithm.argon2id);
      expect(decoded.memoryKiB, params.memoryKiB);
      expect(decoded.salt, params.salt);
      expect(
        () => VaultKdfParams.fromJson({'alg': 'scrypt', 'salt': 'AA=='}),
        throwsA(isA<VaultFormatException>()),
      );
    });
  });

  group('recovery code', () {
    test('has 160 bits shown as 32 grouped characters', () {
      final code = VaultRecoveryCode.generate(Random(5));
      expect(code, hasLength(32));
      final formatted = VaultRecoveryCode.format(code);
      expect(formatted.split('-'), hasLength(8));
      expect(formatted.split('-').every((group) => group.length == 4), isTrue);
    });

    test('normalizes typing mistakes and rejects wrong lengths', () {
      final code = VaultRecoveryCode.generate(Random(6));
      final typed = VaultRecoveryCode.format(code).toLowerCase();
      expect(VaultRecoveryCode.normalize(typed), code);
      expect(VaultRecoveryCode.normalize('O0I1L'), isNull);
      expect(
        VaultRecoveryCode.normalize('${'O' * 16}${'l' * 16}'),
        '${'0' * 16}${'1' * 16}',
      );
      expect(VaultRecoveryCode.normalize('${'A' * 31}U'), isNull);
    });
  });
}
