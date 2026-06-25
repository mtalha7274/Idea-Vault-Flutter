import 'package:flutter/material.dart';

import '../config/router/app_router.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/services/note_lock_biometric_service.dart';
import '../views/note_lock_pin_screen.dart';

Future<bool> ensureNoteLockReady(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService,
) async {
  if (await authService.hasPin()) {
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  return showCreateNoteLockPinDialog(
    context,
    authService,
    biometricService,
  );
}

Future<bool> showCreateNoteLockPinDialog(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService,
) async {
  final result = await AppRouter.push<bool>(
    context,
    NoteLockPinScreen(
      mode: NoteLockPinMode.setup,
      authService: authService,
      biometricService: biometricService,
    ),
  );
  return result == true;
}

Future<bool> authenticateForNoteLock(
  BuildContext context,
  NoteLockAuthService authService,
  NoteLockBiometricService biometricService, {
  String? ideaId,
}) async {
  if (ideaId != null && authService.isIdeaUnlocked(ideaId)) {
    return true;
  }

  if (!await authService.hasPin()) {
    if (!context.mounted) {
      return false;
    }
    final didCreatePin = await showCreateNoteLockPinDialog(
      context,
      authService,
      biometricService,
    );
    if (!didCreatePin) {
      return false;
    }
  }

  if (!context.mounted) {
    return false;
  }

  final result = await AppRouter.push<bool>(
    context,
    NoteLockPinScreen(
      mode: NoteLockPinMode.unlock,
      authService: authService,
      biometricService: biometricService,
    ),
  );

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
}) async {
  if (authService.isIdeaUnlocked(ideaId)) {
    await AppRouter.push(context, nextRoute());
    authService.markIdeaLocked(ideaId);
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
    );
    if (!didCreatePin) {
      return;
    }
  }

  if (!context.mounted) {
    return;
  }

  await AppRouter.push<void>(
    context,
    NoteLockPinScreen(
      mode: NoteLockPinMode.unlock,
      authService: authService,
      biometricService: biometricService,
      ideaId: ideaId,
      nextRoute: nextRoute,
    ),
  );
}
