import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../data/managers/local/local_storage.dart';
import '../../../data/repositories/local/ideas.dart';
import '../../../data/repositories/local/note_vault_repo.dart';
import '../../../models/backup/cloud_backup_restore.dart';
import '../../../models/idea.dart';
import '../../../models/vault/vault_lock_block.dart';
import 'vault_crypto.dart';

enum NoteVaultState { none, ready, needsUnwrap }

class NoteVaultService {
  NoteVaultService({
    required NoteVaultRepo vaultRepo,
    required IdeasRepo ideasRepo,
    VaultKdf? kdf,
    VaultCipher? cipher,
    Random? random,
    FlutterSecureStorage? secureStorage,
    Future<String?> Function(String key)? readValue,
    Future<void> Function(String key, String value)? writeValue,
    Future<void> Function(String key)? deleteValue,
    LocalStorageManager? Function()? preferences,
    DateTime Function()? clock,
  })  : _vaultRepo = vaultRepo,
        _ideasRepo = ideasRepo,
        _random = random ?? Random.secure(),
        _preferences = preferences,
        _clock = clock ?? DateTime.now,
        _readValue = readValue ??
            ((key) => (secureStorage ?? const FlutterSecureStorage()).read(
                  key: key,
                )),
        _writeValue = writeValue ??
            ((key, value) =>
                (secureStorage ?? const FlutterSecureStorage()).write(
                  key: key,
                  value: value,
                )),
        _deleteValue = deleteValue ??
            ((key) => (secureStorage ?? const FlutterSecureStorage()).delete(
                  key: key,
                )) {
    _cipher = cipher ?? VaultCipher(random: _random);
    _kdf = kdf ?? DefaultVaultKdf(random: _random);
  }

  static const String keyStorageKey = 'note_vault_key_v1';
  static const String keyIdStorageKey = 'note_vault_key_id_v1';
  static const String hideTitlesPreferenceKey = 'note_vault_hide_titles_v1';
  static const String ideaAadPrefix = 'idea-vault:idea:v1:';
  static const String wrapAadPrefix = 'idea-vault:vault-key:v1:';

  final NoteVaultRepo _vaultRepo;
  final IdeasRepo _ideasRepo;
  final Random _random;
  final LocalStorageManager? Function()? _preferences;
  final DateTime Function() _clock;
  final Future<String?> Function(String key) _readValue;
  final Future<void> Function(String key, String value) _writeValue;
  final Future<void> Function(String key) _deleteValue;
  late final VaultCipher _cipher;
  late final VaultKdf _kdf;

  List<int>? _memoryKey;
  String? _memoryKeyId;
  int _openSessions = 0;

  VaultCipher get cipher => _cipher;
  VaultKdf get kdf => _kdf;
  bool get holdsKeyInMemory => _memoryKey != null;
  int get openSessions => _openSessions;

  static List<int> ideaAssociatedData(String ideaId) =>
      utf8.encode('$ideaAadPrefix$ideaId');

  static List<int> wrapAssociatedData(String keyId, VaultWrapKind kind) =>
      utf8.encode('$wrapAadPrefix$keyId:${kind.name}');

  Future<VaultLockBlock?> lockBlock() => _vaultRepo.read();

  Future<bool> isSetUp() async => await lockBlock() != null;

  Future<NoteVaultState> state() async {
    final block = await lockBlock();
    if (block == null) {
      return NoteVaultState.none;
    }
    final key = await _cachedKeyFor(block.keyId);
    return key == null ? NoteVaultState.needsUnwrap : NoteVaultState.ready;
  }

  Future<bool> hasEncryptedIdeas() => _ideasRepo.hasEncryptedIdeas();

  Future<List<int>?> _cachedKeyFor(String keyId) async {
    final memoryKey = _memoryKey;
    if (memoryKey != null && _memoryKeyId == keyId) {
      return memoryKey;
    }
    final storedId = await _readValue(keyIdStorageKey);
    final storedKey = await _readValue(keyStorageKey);
    if (storedId != keyId || storedKey == null) {
      return null;
    }
    try {
      final bytes = base64.decode(storedKey);
      if (bytes.length != VaultCipher.keyLength) {
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>?> loadKey() async {
    final block = await lockBlock();
    if (block == null) {
      return null;
    }
    final key = await _cachedKeyFor(block.keyId);
    if (key != null) {
      _memoryKey = key;
      _memoryKeyId = block.keyId;
    }
    return key;
  }

  Future<List<int>> _requireKey() async {
    final key = await loadKey();
    if (key == null) {
      throw const VaultCryptoException(
        VaultCryptoErrorType.wrongKey,
        'vault key unavailable',
      );
    }
    return key;
  }

  Future<String?> currentKeyId() async => (await lockBlock())?.keyId;

  void openSession() {
    _openSessions += 1;
  }

  void closeSession() {
    if (_openSessions > 0) {
      _openSessions -= 1;
    }
    if (_openSessions == 0) {
      dropKey();
    }
  }

  void dropKey() {
    _memoryKey = null;
    _memoryKeyId = null;
  }

  void releaseIfIdle() {
    if (_openSessions == 0) {
      dropKey();
    }
  }

  Future<void> _cacheKey(String keyId, List<int> key) async {
    await _writeValue(keyStorageKey, base64.encode(key));
    await _writeValue(keyIdStorageKey, keyId);
    _memoryKey = List<int>.of(key);
    _memoryKeyId = keyId;
  }

  Future<void> forgetCachedKey() async {
    dropKey();
    if (await _readValue(keyStorageKey) != null) {
      await _deleteValue(keyStorageKey);
    }
    if (await _readValue(keyIdStorageKey) != null) {
      await _deleteValue(keyIdStorageKey);
    }
  }

  String _newKeyId() {
    final buffer = StringBuffer();
    for (var index = 0; index < 8; index++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Future<VaultKeyWrap> _wrap({
    required List<int> key,
    required String keyId,
    required VaultWrapKind kind,
    required String secret,
    required VaultKdfParams params,
    NoteLockPinKind? pinKind,
  }) async {
    final wrappingKey = await _kdf.deriveKey(secret, params);
    final box = await _cipher.seal(
      key: wrappingKey,
      plainText: key,
      associatedData: wrapAssociatedData(keyId, kind),
    );
    return VaultKeyWrap(
      kind: kind,
      kdf: params,
      nonce: box.nonce,
      cipherText: box.cipherText,
      pinKind: pinKind,
    );
  }

  Future<String> setUp({
    required String pin,
    required NoteLockPinKind pinKind,
  }) async {
    final key = _cipher.newKey();
    final keyId = _newKeyId();
    final recoveryCode = VaultRecoveryCode.generate(_random);
    final pinWrap = await _wrap(
      key: key,
      keyId: keyId,
      kind: VaultWrapKind.pin,
      secret: pin,
      params: await _kdf.newPinParams(),
      pinKind: pinKind,
    );
    final recoveryWrap = await _wrap(
      key: key,
      keyId: keyId,
      kind: VaultWrapKind.recovery,
      secret: recoveryCode,
      params: _kdf.newRecoveryParams(),
    );
    await _cacheKey(keyId, key);
    await _vaultRepo.write(
      VaultLockBlock(
        keyId: keyId,
        createdAt: _clock().toUtc(),
        pinWrap: pinWrap,
        recoveryWrap: recoveryWrap,
      ),
    );
    return recoveryCode;
  }

  Future<List<int>> unwrapKey(
    VaultLockBlock block,
    String secret,
    VaultWrapKind kind,
  ) async {
    final wrap = kind == VaultWrapKind.pin ? block.pinWrap : block.recoveryWrap;
    final normalized = kind == VaultWrapKind.recovery
        ? VaultRecoveryCode.normalize(secret)
        : secret;
    if (normalized == null) {
      throw const VaultCryptoException(VaultCryptoErrorType.wrongKey);
    }
    final wrappingKey = await _kdf.deriveKey(normalized, wrap.kdf);
    try {
      final key = await _cipher.open(
        key: wrappingKey,
        nonce: wrap.nonce,
        cipherText: wrap.cipherText,
        associatedData: wrapAssociatedData(block.keyId, kind),
      );
      if (key.length != VaultCipher.keyLength) {
        throw const VaultCryptoException(VaultCryptoErrorType.malformed);
      }
      return key;
    } on VaultCryptoException catch (error) {
      if (error.type == VaultCryptoErrorType.tampered) {
        throw const VaultCryptoException(VaultCryptoErrorType.wrongKey);
      }
      rethrow;
    }
  }

  Future<bool> unlockWith(String secret, VaultWrapKind kind) async {
    final block = await lockBlock();
    if (block == null) {
      return false;
    }
    try {
      final key = await unwrapKey(block, secret, kind);
      await _cacheKey(block.keyId, key);
      return true;
    } on VaultCryptoException {
      return false;
    }
  }

  Future<void> rewrapPin({
    required String newPin,
    required NoteLockPinKind pinKind,
    String? oldPin,
  }) async {
    final block = await lockBlock();
    if (block == null) {
      return;
    }
    var key = await loadKey();
    if (key == null && oldPin != null) {
      key = await unwrapKey(block, oldPin, VaultWrapKind.pin);
      await _cacheKey(block.keyId, key);
    }
    if (key == null) {
      throw const VaultCryptoException(VaultCryptoErrorType.wrongKey);
    }
    final pinWrap = await _wrap(
      key: key,
      keyId: block.keyId,
      kind: VaultWrapKind.pin,
      secret: newPin,
      params: await _kdf.newPinParams(),
      pinKind: pinKind,
    );
    await _vaultRepo.write(block.copyWith(pinWrap: pinWrap));
    releaseIfIdle();
  }

  Future<String> regenerateRecoveryCode() async {
    final block = await lockBlock();
    final key = await _requireKey();
    if (block == null) {
      throw const VaultCryptoException(VaultCryptoErrorType.wrongKey);
    }
    final recoveryCode = VaultRecoveryCode.generate(_random);
    final recoveryWrap = await _wrap(
      key: key,
      keyId: block.keyId,
      kind: VaultWrapKind.recovery,
      secret: recoveryCode,
      params: _kdf.newRecoveryParams(),
    );
    await _vaultRepo.write(block.copyWith(recoveryWrap: recoveryWrap));
    releaseIfIdle();
    return recoveryCode;
  }

  bool get hideTitles {
    final storage = _preferences?.call();
    return storage?.getString(key: hideTitlesPreferenceKey) == 'true';
  }

  Future<void> _storeHideTitles(bool hide) async {
    final storage = _preferences?.call();
    await storage?.setString(
      key: hideTitlesPreferenceKey,
      value: hide.toString(),
    );
  }

  Future<String> sealPayload({
    required String ideaId,
    required LockedIdeaPayload payload,
    required List<int> key,
    required String keyId,
  }) async {
    final box = await _cipher.seal(
      key: key,
      plainText: utf8.encode(payload.encode()),
      associatedData: ideaAssociatedData(ideaId),
    );
    return EncryptedIdeaEnvelope(
      keyId: keyId,
      nonce: box.nonce,
      cipherText: box.cipherText,
    ).encode();
  }

  Future<LockedIdeaPayload> openPayload({
    required String ideaId,
    required String encryptedPayload,
    required List<int> key,
    String? expectedKeyId,
  }) async {
    final EncryptedIdeaEnvelope envelope;
    try {
      envelope = EncryptedIdeaEnvelope.decode(encryptedPayload);
    } on VaultFormatException catch (error) {
      throw VaultCryptoException(
        VaultCryptoErrorType.malformed,
        error.message,
      );
    }
    if (expectedKeyId != null && envelope.keyId != expectedKeyId) {
      throw const VaultCryptoException(
        VaultCryptoErrorType.wrongKey,
        'note was locked with a different key',
      );
    }
    final plain = await _cipher.open(
      key: key,
      nonce: envelope.nonce,
      cipherText: envelope.cipherText,
      associatedData: ideaAssociatedData(ideaId),
    );
    try {
      return LockedIdeaPayload.decode(utf8.decode(plain));
    } on FormatException {
      throw const VaultCryptoException(VaultCryptoErrorType.malformed);
    } on VaultFormatException catch (error) {
      throw VaultCryptoException(
        VaultCryptoErrorType.malformed,
        error.message,
      );
    }
  }

  Future<Idea> encryptIdea(
    Idea idea, {
    List<int>? key,
    String? keyId,
    bool? hideTitle,
  }) async {
    if (idea.isEncrypted) {
      return idea;
    }
    final usedKey = key ?? await _requireKey();
    final usedKeyId = keyId ?? await currentKeyId();
    if (usedKeyId == null) {
      throw const VaultCryptoException(VaultCryptoErrorType.wrongKey);
    }
    final hide = hideTitle ?? hideTitles;
    final payload = LockedIdeaPayload(
      title: hide ? idea.title : null,
      sections: idea.sections,
    );
    final sealed = await sealPayload(
      ideaId: idea.id,
      payload: payload,
      key: usedKey,
      keyId: usedKeyId,
    );
    return Idea(
      id: idea.id,
      title: hide ? '' : idea.title,
      createdAt: idea.createdAt,
      updatedAt: idea.updatedAt,
      lastOpenedSectionId: idea.lastOpenedSectionId,
      isLocked: true,
      encryptedPayload: sealed,
      titleHidden: hide,
      sections: const [],
    );
  }

  Future<Idea> decryptIdea(
    Idea idea, {
    List<int>? key,
    String? keyId,
  }) async {
    final payload = idea.encryptedPayload;
    if (payload == null) {
      return idea;
    }
    final usedKey = key ?? await _requireKey();
    final usedKeyId = key == null ? await currentKeyId() : keyId;
    final opened = await openPayload(
      ideaId: idea.id,
      encryptedPayload: payload,
      key: usedKey,
      expectedKeyId: usedKeyId,
    );
    return Idea(
      id: idea.id,
      title: opened.title ?? idea.title,
      createdAt: idea.createdAt,
      updatedAt: idea.updatedAt,
      lastOpenedSectionId: idea.lastOpenedSectionId,
      isLocked: idea.isLocked,
      sections: opened.sections,
    );
  }

  Future<Idea> reencryptIdea(
    Idea idea, {
    required List<int> fromKey,
    required String? fromKeyId,
    required List<int> toKey,
    required String toKeyId,
    String? newId,
    String Function(String prefix)? newSectionId,
  }) async {
    final plain = await decryptIdea(idea, key: fromKey, keyId: fromKeyId);
    final targetId = newId ?? idea.id;
    final generate = newSectionId ?? generateIdeaVaultId;
    final remapped = <String, String>{};
    final sections = newId == null
        ? plain.sections
        : [
            for (final section in plain.sections)
              section.copyWith(
                id: remapped[section.id] = generate('section'),
              ),
          ];
    final lastOpened = plain.lastOpenedSectionId;
    final moved = Idea(
      id: targetId,
      title: plain.title,
      createdAt: plain.createdAt,
      updatedAt: plain.updatedAt,
      lastOpenedSectionId:
          lastOpened == null ? null : remapped[lastOpened] ?? lastOpened,
      isLocked: true,
      sections: sections,
    );
    return encryptIdea(
      moved,
      key: toKey,
      keyId: toKeyId,
      hideTitle: idea.titleHidden,
    );
  }

  Future<int> encryptPlaintextLockedIdeas() async {
    final keyId = await currentKeyId();
    if (keyId == null) {
      return 0;
    }
    final key = await _requireKey();
    final ideas = await _ideasRepo.getIdeas();
    final encrypted = <Idea>[];
    for (final idea in ideas) {
      if (idea.isLocked && !idea.isEncrypted) {
        encrypted.add(await encryptIdea(idea, key: key, keyId: keyId));
      }
    }
    if (encrypted.isEmpty) {
      releaseIfIdle();
      return 0;
    }
    await _ideasRepo.writeIdeasAtomically(encrypted);
    await _ideasRepo.compact();
    releaseIfIdle();
    return encrypted.length;
  }

  Future<LocalVaultContent> encryptLockedIn(LocalVaultContent content) async {
    final block = await lockBlock();
    if (block == null) {
      return content;
    }
    final key = await _requireKey();
    final ideas = <Idea>[];
    for (final idea in content.ideas) {
      ideas.add(
        idea.isLocked && !idea.isEncrypted
            ? await encryptIdea(idea, key: key, keyId: block.keyId)
            : idea,
      );
    }
    return LocalVaultContent(
      ideas: ideas,
      randomAdditions: content.randomAdditions,
      lock: block,
    );
  }

  Future<int> setHideTitles(bool hide) async {
    await _storeHideTitles(hide);
    if (!await isSetUp()) {
      return 0;
    }
    final key = await loadKey();
    if (key == null) {
      return 0;
    }
    final keyId = await currentKeyId();
    final ideas = await _ideasRepo.getIdeas();
    final rewritten = <Idea>[];
    for (final idea in ideas) {
      if (!idea.isEncrypted || idea.titleHidden == hide) {
        continue;
      }
      final plain = await decryptIdea(idea, key: key, keyId: keyId);
      rewritten.add(
        await encryptIdea(plain, key: key, keyId: keyId, hideTitle: hide),
      );
    }
    if (rewritten.isNotEmpty) {
      await _ideasRepo.writeIdeasAtomically(rewritten);
      await _ideasRepo.compact();
    }
    releaseIfIdle();
    return rewritten.length;
  }

  Future<int> resetAll() async {
    final ideas = await _ideasRepo.getIdeas();
    final lockedIds = [
      for (final idea in ideas)
        if (idea.isLocked) idea.id,
    ];
    await _ideasRepo.deleteIdeas(lockedIds);
    await _vaultRepo.clear();
    await forgetCachedKey();
    await _ideasRepo.compact();
    return lockedIds.length;
  }
}
