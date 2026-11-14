import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../core/constants/view_constants.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/services/note_lock_session_guard.dart';
import '../core/services/vault/vault_crypto.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';
import 'note_lock_pin_screen.dart';

class VaultRecoveryCodeScreen extends StatefulWidget {
  const VaultRecoveryCodeScreen({super.key, required this.code});

  final String code;

  @override
  State<VaultRecoveryCodeScreen> createState() =>
      _VaultRecoveryCodeScreenState();
}

class _VaultRecoveryCodeScreenState extends State<VaultRecoveryCodeScreen> {
  @override
  void initState() {
    super.initState();
    NoteLockSecureWindow.acquire();
  }

  @override
  void dispose() {
    NoteLockSecureWindow.release();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: VaultRecoveryCode.format(widget.code)),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ViewConstants.vaultRecoveryCodeCopied.tr())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final formatted = VaultRecoveryCode.format(widget.code);
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('vault-recovery-code-screen'),
        backgroundColor: theme.background,
        appBar: IdeaVaultSubpageAppBar(
          titleKey: ViewConstants.vaultRecoveryCodeTitle,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 32.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TranslatedText(
                  ViewConstants.vaultRecoveryCodeBody,
                  style: ideaVaultBody(
                    context,
                    size: 15.f,
                    weight: FontWeight.w500,
                    color: theme.textMuted,
                    height: 1.5,
                  ),
                ),
                Gap(24.h),
                Container(
                  padding: EdgeInsets.all(18.d),
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: SelectableText(
                    formatted,
                    key: const Key('vault-recovery-code-text'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18.f,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      height: 1.6,
                      color: theme.primaryText,
                    ),
                  ),
                ),
                Gap(16.h),
                OutlinedButton.icon(
                  key: const Key('vault-recovery-code-copy'),
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(ViewConstants.vaultRecoveryCodeCopy.tr()),
                ),
                Gap(12.h),
                FilledButton(
                  key: const Key('vault-recovery-code-saved'),
                  onPressed: () => AppRouter.pop(context, true),
                  child: Text(ViewConstants.vaultRecoveryCodeSaved.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VaultRecoveryCodeEntryScreen extends StatefulWidget {
  const VaultRecoveryCodeEntryScreen({
    super.key,
    required this.authService,
    required this.verify,
  });

  final NoteLockAuthService authService;
  final Future<bool> Function(String code) verify;

  @override
  State<VaultRecoveryCodeEntryScreen> createState() =>
      _VaultRecoveryCodeEntryScreenState();
}

class _VaultRecoveryCodeEntryScreenState
    extends State<VaultRecoveryCodeEntryScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _errorKey;
  Map<String, String>? _errorArgs;
  Duration _lockout = Duration.zero;
  Timer? _timer;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    NoteLockSecureWindow.acquire();
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    NoteLockSecureWindow.release();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final status = await widget.authService.attemptStatus();
    if (!mounted) {
      return;
    }
    _applyLockout(status.remainingWait);
  }

  void _applyLockout(Duration wait) {
    _timer?.cancel();
    setState(() {
      _lockout = wait;
    });
    if (wait <= Duration.zero) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final next = _lockout - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _timer?.cancel();
        unawaited(_refreshStatus());
        return;
      }
      setState(() {
        _lockout = next;
      });
    });
  }

  Future<void> _submit() async {
    if (_isChecking || _lockout > Duration.zero) {
      return;
    }
    final code = _controller.text;
    if (code.trim().isEmpty) {
      return;
    }
    setState(() {
      _isChecking = true;
      _errorKey = null;
      _errorArgs = null;
    });
    final result = await widget.authService.attemptWith(
      () => widget.verify(code),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isChecking = false;
    });
    switch (result.check) {
      case NoteLockPinCheck.success:
        AppRouter.pop(context, true);
      case NoteLockPinCheck.lockedOut:
        _controller.clear();
        _applyLockout(result.status.remainingWait);
      case NoteLockPinCheck.wrongPin:
        setState(() {
          _errorKey = ViewConstants.vaultRecoveryCodeWrong;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final lockedOut = _lockout > Duration.zero;
    return Scaffold(
      key: const Key('vault-recovery-entry-screen'),
      backgroundColor: theme.background,
      appBar: IdeaVaultSubpageAppBar(
        titleKey: ViewConstants.vaultRecoveryEntryTitle,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 32.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TranslatedText(
                ViewConstants.vaultRecoveryEntryBody,
                style: ideaVaultBody(
                  context,
                  size: 15.f,
                  weight: FontWeight.w500,
                  color: theme.textMuted,
                  height: 1.5,
                ),
              ),
              Gap(20.h),
              TextField(
                key: const Key('vault-recovery-entry-field'),
                controller: _controller,
                readOnly: lockedOut,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                textCapitalization: TextCapitalization.characters,
                keyboardType: TextInputType.visiblePassword,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: ViewConstants.vaultRecoveryEntryHint.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (lockedOut) ...[
                Gap(14.h),
                Text(
                  ViewConstants.noteLockTooManyAttempts.tr(
                    namedArgs: {'time': formatNoteLockWait(_lockout)},
                  ),
                  key: const Key('vault-recovery-lockout'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ] else if (_errorKey != null) ...[
                Gap(14.h),
                Text(
                  _errorKey!.tr(namedArgs: _errorArgs),
                  key: const Key('vault-recovery-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              Gap(20.h),
              FilledButton(
                key: const Key('vault-recovery-entry-submit'),
                onPressed: lockedOut || _isChecking ? null : _submit,
                child: _isChecking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(ViewConstants.vaultContinue.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
