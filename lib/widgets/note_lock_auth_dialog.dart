import 'package:flutter/material.dart';

import '../config/router/app_router.dart';
import '../core/services/note_lock_auth_service.dart';
import '../views/note_lock_pin_screen.dart';

Future<bool> ensureNoteLockReady(
  BuildContext context,
  NoteLockAuthService authService,
) async {
  if (await authService.hasPin()) {
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  return showCreateNoteLockPinDialog(context, authService);
}

Future<bool> showCreateNoteLockPinDialog(
  BuildContext context,
  NoteLockAuthService authService,
) async {
  final result = await AppRouter.push<bool>(
    context,
    NoteLockPinScreen(
      mode: NoteLockPinMode.setup,
      authService: authService,
    ),
  );
  return result == true;
}

Future<bool> authenticateForNoteLock(
  BuildContext context,
  NoteLockAuthService authService, {
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
    ),
  );

  if (result == true && ideaId != null) {
    authService.markIdeaUnlocked(ideaId);
  }
  return result == true;
}
