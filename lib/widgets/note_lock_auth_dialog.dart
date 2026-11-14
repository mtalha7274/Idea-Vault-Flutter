import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../core/constants/view_constants.dart';
import '../core/services/backup/restore_safety_copy_store.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/services/note_lock_biometric_service.dart';
import '../core/services/vault/note_vault_service.dart';
import '../core/services/vault/vault_crypto.dart';
import '../injection_container.dart';
import '../models/vault/vault_lock_block.dart';
import '../viewmodels/providers/backup/cloud_backup_provider.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/random_additions_provider.dart';
import '../views/note_lock_pin_screen.dart';
import '../views/vault_recovery_code_screen.dart';
import 'translated_text.dart';

NoteVaultService? resolveNoteVault([NoteVaultService? vault]) {
  if (vault != null) {
    return vault;
  }
  return sl.isRegistered<NoteVaultService>() ? sl<NoteVaultService>() : null;
}

Future<bool> ensureNoteLockReady(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService, {
  NoteVaultService? vault,
}) async {
  final noteVault = resolveNoteVault(vault);
  if (noteVault == null) {
    if (await authService.hasPin()) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }
    return showCreateNoteLockPinDialog(context, authService, biometricService);
  }

  final state = await noteVault.state();
  if (!context.mounted) {
    return false;
  }
  switch (state) {
    case NoteVaultState.ready:
      return true;
    case NoteVaultState.needsUnwrap:
      final screen =
          await _unwrapScreen(authService, biometricService, noteVault);
      if (!context.mounted) {
        return false;
      }
      final result = await AppRouter.push<bool>(context, screen);
      return result == true;
    case NoteVaultState.none:
      if (await authService.hasPin()) {
        if (!context.mounted) {
          return false;
        }
        final result = await AppRouter.push<bool>(
          context,
          _migrationScreen(authService, biometricService, noteVault),
        );
        return result == true;
      }
      if (!context.mounted) {
        return false;
      }
      return showCreateNoteLockPinDialog(
        context,
        authService,
        biometricService,
        vault: noteVault,
      );
  }
}

Future<bool> showCreateNoteLockPinDialog(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService, {
  NoteVaultService? vault,
}) async {
  final noteVault = resolveNoteVault(vault);
  String? recoveryCode;
  final result = await AppRouter.push<bool>(
    context,
    NoteLockPinScreen(
      mode: NoteLockPinMode.setup,
      authService: authService,
      biometricService: biometricService,
      onPinCreated: noteVault == null
          ? null
          : (pin, kind, _) async {
              recoveryCode = await noteVault.setUp(pin: pin, pinKind: kind);
              await authService.createPin(pin, kind: kind);
            },
    ),
  );
  if (result != true) {
    return false;
  }
  final code = recoveryCode;
  if (code != null && context.mounted) {
    await _showRecoveryCode(context, code);
  }
  if (noteVault != null && context.mounted) {
    await _encryptPending(context, noteVault);
  }
  return true;
}

Future<bool> authenticateForNoteLock(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService, {
  String? ideaId,
  NoteVaultService? vault,
}) async {
  final noteVault = resolveNoteVault(vault);
  final state = noteVault == null ? null : await noteVault.state();
  if (!context.mounted) {
    return false;
  }

  if (state == NoteVaultState.needsUnwrap) {
    final screen =
        await _unwrapScreen(authService, biometricService, noteVault!);
    if (!context.mounted) {
      return false;
    }
    final result = await AppRouter.push<bool>(context, screen);
    if (result == true && ideaId != null) {
      authService.markIdeaUnlocked(ideaId);
    }
    return result == true;
  }

  if (!await authService.hasPin()) {
    if (!context.mounted) {
      return false;
    }
    final didCreatePin = await showCreateNoteLockPinDialog(
      context,
      authService,
      biometricService,
      vault: noteVault,
    );
    if (!didCreatePin) {
      return false;
    }
    if (ideaId != null) {
      authService.markIdeaUnlocked(ideaId);
    }
    return true;
  }

  if (ideaId != null &&
      authService.isIdeaUnlocked(ideaId) &&
      state != NoteVaultState.none) {
    return true;
  }
  if (ideaId != null && authService.isIdeaUnlocked(ideaId) && state == null) {
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  final screen = state == NoteVaultState.none
      ? _migrationScreen(authService, biometricService, noteVault!)
      : _unlockScreen(authService, biometricService, noteVault);
  final result = await AppRouter.push<bool>(context, screen);

  if (result == true && ideaId != null) {
    authService.markIdeaUnlocked(ideaId);
  }
  return result == true;
}

Future<void> authenticateAndOpenNote(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService, {
  required String ideaId,
  required Widget Function() nextRoute,
  NoteVaultService? vault,
}) async {
  final noteVault = resolveNoteVault(vault);
  final state = noteVault == null ? null : await noteVault.state();
  if (!context.mounted) {
    return;
  }

  if (state == NoteVaultState.needsUnwrap) {
    final screen = await _unwrapScreen(
      authService,
      biometricService,
      noteVault!,
      ideaId: ideaId,
      nextRoute: nextRoute,
    );
    if (!context.mounted) {
      return;
    }
    await AppRouter.push<void>(context, screen);
    return;
  }

  if (!await authService.hasPin()) {
    if (!context.mounted) {
      return;
    }
    final didCreatePin = await showCreateNoteLockPinDialog(
      context,
      authService,
      biometricService,
      vault: noteVault,
    );
    if (!didCreatePin) {
      return;
    }
    authService.markIdeaUnlocked(ideaId);
    if (!context.mounted) {
      authService.markIdeaLocked(ideaId);
      return;
    }
    await AppRouter.push(context, nextRoute());
    authService.markIdeaLocked(ideaId);
    return;
  }

  if (!context.mounted) {
    return;
  }

  final screen = state == NoteVaultState.none
      ? _migrationScreen(
          authService,
          biometricService,
          noteVault!,
          ideaId: ideaId,
          nextRoute: nextRoute,
        )
      : _unlockScreen(
          authService,
          biometricService,
          noteVault,
          ideaId: ideaId,
          nextRoute: nextRoute,
        );
  await AppRouter.push<void>(context, screen);
}

Future<List<int>?> promptBackupVaultKey(
  BuildContext context,
  VaultLockBlock block, {
  NoteLockAuthService? authService,
  NoteLockBiometricService? biometricService,
  NoteVaultService? vault,
}) async {
  final noteVault = resolveNoteVault(vault);
  if (noteVault == null) {
    return null;
  }
  final auth = authService ??
      (sl.isRegistered<NoteLockAuthService>()
          ? sl<NoteLockAuthService>()
          : NoteLockAuthService());
  final biometric = biometricService ??
      (sl.isRegistered<NoteLockBiometricService>()
          ? sl<NoteLockBiometricService>()
          : NoteLockBiometricService());
  List<int>? key;
  final result = await AppRouter.push<bool>(
    context,
    NoteLockPinScreen(
      mode: NoteLockPinMode.unlock,
      authService: auth,
      biometricService: biometric,
      pinKind: block.pinKind,
      allowBiometric: false,
      titleKey: ViewConstants.vaultBackupUnwrapTitle,
      bodyKey: ViewConstants.vaultBackupUnwrapBody,
      verifySecret: (secret) => auth.attemptWith(() async {
        try {
          key = await noteVault.unwrapKey(block, secret, VaultWrapKind.pin);
          return true;
        } on VaultCryptoException {
          return false;
        }
      }),
      alternativeActionKey: ViewConstants.vaultUseRecoveryCode,
      onAlternativeAction: (screenContext) async {
        final ok = await AppRouter.push<bool>(
          screenContext,
          VaultRecoveryCodeEntryScreen(
            authService: auth,
            verify: (code) async {
              try {
                key = await noteVault.unwrapKey(
                  block,
                  code,
                  VaultWrapKind.recovery,
                );
                return true;
              } on VaultCryptoException {
                return false;
              }
            },
          ),
        );
        return ok == true ? const NoteLockRecoveryOutcome.unlocked() : null;
      },
    ),
  );
  return result == true ? key : null;
}

Widget _unlockScreen(
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService,
  NoteVaultService? vault, {
  String? ideaId,
  Widget Function()? nextRoute,
}) {
  return NoteLockPinScreen(
    mode: NoteLockPinMode.unlock,
    authService: authService,
    biometricService: biometricService,
    ideaId: ideaId,
    nextRoute: nextRoute,
    onUnlocked: vault == null
        ? null
        : (screenContext, _) async {
            await _encryptPending(screenContext, vault);
            return true;
          },
    onForgotPin: vault == null
        ? null
        : (screenContext) => _forgotPin(
              screenContext,
              authService,
              biometricService,
              vault,
              canUseRecovery: true,
              canUseBiometric: true,
            ),
  );
}

Widget _migrationScreen(
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService,
  NoteVaultService vault, {
  String? ideaId,
  Widget Function()? nextRoute,
}) {
  return NoteLockPinScreen(
    mode: NoteLockPinMode.unlock,
    authService: authService,
    biometricService: biometricService,
    ideaId: ideaId,
    nextRoute: nextRoute,
    allowBiometric: false,
    bodyKey: ViewConstants.vaultMigrationBody,
    onUnlocked: (screenContext, secret) async {
      if (secret == null) {
        return true;
      }
      await runNoteVaultMigration(
        screenContext,
        authService,
        biometricService,
        vault,
        pin: secret,
      );
      return true;
    },
    onForgotPin: (screenContext) => _forgotPin(
      screenContext,
      authService,
      biometricService,
      vault,
      canUseRecovery: false,
      canUseBiometric: true,
    ),
  );
}

Future<Widget> _unwrapScreen(
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService,
  NoteVaultService vault, {
  String? ideaId,
  Widget Function()? nextRoute,
}) async {
  final block = await vault.lockBlock();
  final kind = block?.pinKind ?? NoteLockPinKind.digits4;
  return NoteLockPinScreen(
    mode: NoteLockPinMode.unlock,
    authService: authService,
    biometricService: biometricService,
    ideaId: ideaId,
    nextRoute: nextRoute,
    pinKind: kind,
    allowBiometric: false,
    titleKey: ViewConstants.vaultUnwrapTitle,
    bodyKey: ViewConstants.vaultUnwrapBody,
    verifySecret: (secret) => authService.attemptWith(
      () => vault.unlockWith(secret, VaultWrapKind.pin),
    ),
    onUnlocked: (screenContext, secret) async {
      if (secret != null) {
        await authService.createPin(secret, kind: kind);
      }
      if (screenContext.mounted) {
        await _offerBiometric(screenContext, biometricService);
      }
      if (screenContext.mounted) {
        await _encryptPending(screenContext, vault);
      }
      return true;
    },
    alternativeActionKey: ViewConstants.vaultUseRecoveryCode,
    onAlternativeAction: (screenContext) => _recoverWithCode(
      screenContext,
      authService,
      biometricService,
      vault,
    ),
    onForgotPin: (screenContext) => _forgotPin(
      screenContext,
      authService,
      biometricService,
      vault,
      canUseRecovery: true,
      canUseBiometric: false,
    ),
  );
}

Future<void> runNoteVaultMigration(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService,
  NoteVaultService vault, {
  required String pin,
}) async {
  var usedPin = pin;
  var kind = await authService.pinKind();
  if (!context.mounted) {
    return;
  }
  if (kind == NoteLockPinKind.digits4) {
    final upgrade = await _confirm(
      context,
      titleKey: ViewConstants.vaultUpgradeTitle,
      bodyKey: ViewConstants.vaultUpgradeBody,
      confirmKey: ViewConstants.vaultUpgradeAction,
      cancelKey: ViewConstants.vaultUpgradeSkip,
      confirmKeyName: 'vault-upgrade-pin',
      cancelKeyName: 'vault-upgrade-skip',
    );
    if (upgrade && context.mounted) {
      final created =
          await _chooseNewPin(context, authService, biometricService);
      if (created != null) {
        usedPin = created.$1;
        kind = created.$2;
        await authService.createPin(usedPin, kind: kind);
      }
    }
  }
  final String code;
  try {
    code = await vault.setUp(pin: usedPin, pinKind: kind);
  } catch (_) {
    if (context.mounted) {
      _snack(context, ViewConstants.vaultSetupFailed);
    }
    return;
  }
  if (context.mounted) {
    await _showRecoveryCode(context, code);
  }
  if (context.mounted) {
    final count = await _encryptPending(context, vault, forceFollowUp: true);
    if (context.mounted && count >= 0) {
      _snack(context, ViewConstants.vaultMigrationDone);
    }
  }
}

Future<(String, NoteLockPinKind)?> _chooseNewPin(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService, {
  Future<void> Function(String pin, NoteLockPinKind kind)? onCreated,
}) async {
  (String, NoteLockPinKind)? created;
  final result = await AppRouter.push<bool>(
    context,
    NoteLockPinScreen(
      mode: NoteLockPinMode.setup,
      authService: authService,
      biometricService: biometricService,
      titleKey: ViewConstants.vaultNewPinTitle,
      offerBiometricAfterSetup: false,
      onPinCreated: (pin, kind, _) async {
        await onCreated?.call(pin, kind);
        created = (pin, kind);
      },
    ),
  );
  return result == true ? created : null;
}

Future<NoteLockRecoveryOutcome?> _recoverWithCode(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService,
  NoteVaultService vault,
) async {
  final ok = await AppRouter.push<bool>(
    context,
    VaultRecoveryCodeEntryScreen(
      authService: authService,
      verify: (code) => vault.unlockWith(code, VaultWrapKind.recovery),
    ),
  );
  if (ok != true || !context.mounted) {
    return null;
  }
  final created = await _chooseNewPin(
    context,
    authService,
    biometricService,
    onCreated: (pin, kind) async {
      await vault.rewrapPin(newPin: pin, pinKind: kind);
      await authService.createPin(pin, kind: kind);
    },
  );
  if (created == null) {
    return const NoteLockRecoveryOutcome.unlocked();
  }
  return NoteLockRecoveryOutcome.unlocked(newSecret: created.$1);
}

Future<NoteLockRecoveryOutcome?> _forgotPin(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService,
  NoteVaultService vault, {
  required bool canUseRecovery,
  required bool canUseBiometric,
}) async {
  final state = await vault.state();
  final biometricReady = canUseBiometric &&
      state != NoteVaultState.needsUnwrap &&
      await biometricService.canUseBiometricUnlock();
  final recoveryReady = canUseRecovery && state != NoteVaultState.none;
  if (!context.mounted) {
    return null;
  }
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TranslatedText(
              ViewConstants.vaultForgotTitle,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            TranslatedText(ViewConstants.vaultForgotBody),
            const SizedBox(height: 12),
            if (recoveryReady)
              ListTile(
                key: const Key('vault-forgot-recovery'),
                leading: const Icon(Icons.key_rounded),
                title: Text(ViewConstants.vaultUseRecoveryCode.tr()),
                onTap: () => Navigator.of(sheetContext).pop('recovery'),
              ),
            if (biometricReady)
              ListTile(
                key: const Key('vault-forgot-biometric'),
                leading: const Icon(Icons.fingerprint_rounded),
                title: Text(ViewConstants.vaultForgotUseBiometric.tr()),
                onTap: () => Navigator.of(sheetContext).pop('biometric'),
              ),
            ListTile(
              key: const Key('vault-forgot-reset'),
              leading: Icon(
                Icons.delete_forever_rounded,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(ViewConstants.vaultForgotReset.tr()),
              onTap: () => Navigator.of(sheetContext).pop('reset'),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || choice == null) {
    return null;
  }
  switch (choice) {
    case 'recovery':
      return _recoverWithCode(context, authService, biometricService, vault);
    case 'biometric':
      final result = await biometricService.authenticate(
        ViewConstants.noteLockBiometricReason.tr(),
      );
      if (result != BiometricAuthResult.success || !context.mounted) {
        return null;
      }
      final isSetUp = state == NoteVaultState.ready;
      final created = await _chooseNewPin(
        context,
        authService,
        biometricService,
        onCreated: (pin, kind) async {
          if (isSetUp) {
            await vault.rewrapPin(newPin: pin, pinKind: kind);
          }
          await authService.createPin(pin, kind: kind);
        },
      );
      if (created == null) {
        return null;
      }
      return NoteLockRecoveryOutcome.unlocked(newSecret: created.$1);
    case 'reset':
      final didReset = await resetAllLockedNotes(
        context,
        authService,
        biometricService,
        vault,
      );
      return didReset ? const NoteLockRecoveryOutcome.reset() : null;
  }
  return null;
}

Future<bool> resetAllLockedNotes(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService,
  NoteVaultService vault,
) async {
  final first = await _confirm(
    context,
    titleKey: ViewConstants.vaultResetConfirmTitle,
    bodyKey: ViewConstants.vaultResetConfirmBody,
    confirmKey: ViewConstants.vaultResetConfirmAction,
    cancelKey: ViewConstants.vaultCancel,
    confirmKeyName: 'vault-reset-confirm',
    destructive: true,
  );
  if (!first || !context.mounted) {
    return false;
  }
  final second = await _confirm(
    context,
    titleKey: ViewConstants.vaultResetFinalTitle,
    bodyKey: ViewConstants.vaultResetFinalBody,
    confirmKey: ViewConstants.vaultResetFinalAction,
    cancelKey: ViewConstants.vaultCancel,
    confirmKeyName: 'vault-reset-final',
    destructive: true,
  );
  if (!second) {
    return false;
  }
  await vault.resetAll();
  await authService.clearPin();
  await biometricService.clearBiometricUnlock();
  if (context.mounted) {
    final ideasProvider = _maybeRead<IdeasProvider>(context);
    await ideasProvider?.clearEditorState();
    await ideasProvider?.reloadFromStorage();
  }
  if (context.mounted) {
    _snack(context, ViewConstants.vaultResetDone);
  }
  return true;
}

Future<int> _encryptPending(
  BuildContext context,
  NoteVaultService vault, {
  bool forceFollowUp = false,
}) async {
  final ideasProvider = _maybeRead<IdeasProvider>(context);
  final additionsProvider = _maybeRead<RandomAdditionsProvider>(context);
  final backupProvider = _maybeRead<CloudBackupProvider>(context);
  final hasPlainLocked =
      ideasProvider?.ideas.any((idea) => idea.isLocked && !idea.isEncrypted) ??
          false;
  if ((forceFollowUp || hasPlainLocked) &&
      (backupProvider?.state.enabled ?? false)) {
    await backupProvider!.markPlaintextCleanupPending();
  }
  var count = 0;
  try {
    count = ideasProvider != null
        ? await ideasProvider.encryptPendingLockedIdeas()
        : await vault.encryptPlaintextLockedIdeas();
  } catch (_) {
    return -1;
  }
  if (count > 0 || forceFollowUp) {
    await _afterEncryption(
      vault,
      ideasProvider: ideasProvider,
      additionsProvider: additionsProvider,
      backupProvider: backupProvider,
    );
  }
  return count;
}

Future<void> _afterEncryption(
  NoteVaultService vault, {
  IdeasProvider? ideasProvider,
  RandomAdditionsProvider? additionsProvider,
  CloudBackupProvider? backupProvider,
}) async {
  if (sl.isRegistered<RestoreSafetyCopyStore>()) {
    try {
      await sl<RestoreSafetyCopyStore>().rewriteAll(vault.encryptLockedIn);
    } catch (_) {}
  }
  vault.releaseIfIdle();
  if (backupProvider == null || !backupProvider.state.enabled) {
    return;
  }
  await backupProvider.markPlaintextCleanupPending();
  if (ideasProvider == null) {
    return;
  }
  unawaited(
    backupProvider.runPlaintextCleanup(
      ideasProvider.ideas,
      randomAdditions: additionsProvider?.additions ?? const [],
    ),
  );
}

Future<void> _showRecoveryCode(BuildContext context, String code) async {
  await AppRouter.push<bool>(context, VaultRecoveryCodeScreen(code: code));
}

Future<void> showRecoveryCodeScreen(BuildContext context, String code) {
  return _showRecoveryCode(context, code);
}

Future<void> _offerBiometric(
  BuildContext context,
  NoteLockBiometricService biometricService,
) async {
  if (await biometricService.isBiometricUnlockEnabled() ||
      !await biometricService.canOfferBiometricEnrollment()) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final enable = await _confirm(
    context,
    titleKey: ViewConstants.noteLockEnableBiometricTitle,
    bodyKey: ViewConstants.noteLockEnableBiometricBody,
    confirmKey: ViewConstants.noteLockEnableBiometricAction,
    cancelKey: ViewConstants.noteLockEnableBiometricSkip,
  );
  if (enable) {
    await biometricService.enableBiometricUnlock(
      ViewConstants.noteLockEnableBiometricReason.tr(),
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String titleKey,
  required String bodyKey,
  required String confirmKey,
  required String cancelKey,
  String? confirmKeyName,
  String? cancelKeyName,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: TranslatedText(titleKey),
      content: TranslatedText(bodyKey),
      actions: [
        TextButton(
          key: cancelKeyName == null ? null : Key(cancelKeyName),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelKey.tr()),
        ),
        TextButton(
          key: confirmKeyName == null ? null : Key(confirmKeyName),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            confirmKey.tr(),
            style: destructive
                ? TextStyle(color: Theme.of(dialogContext).colorScheme.error)
                : null,
          ),
        ),
      ],
    ),
  );
  return result == true;
}

void _snack(BuildContext context, String key) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(key.tr())),
  );
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}
