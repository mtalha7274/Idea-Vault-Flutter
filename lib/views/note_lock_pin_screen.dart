import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../core/constants/view_constants.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/utils/helpers.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

enum NoteLockPinMode {
  setup,
  unlock,
  changePin,
}

class NoteLockPinScreen extends StatefulWidget {
  const NoteLockPinScreen({
    super.key,
    required this.mode,
    required this.authService,
    this.ideaId,
    this.nextRoute,
  });

  final NoteLockPinMode mode;
  final NoteLockAuthService authService;
  final String? ideaId;
  final Widget Function()? nextRoute;

  @override
  State<NoteLockPinScreen> createState() => _NoteLockPinScreenState();
}

class _NoteLockPinScreenState extends State<NoteLockPinScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  String _pin = '';
  String? _firstPin;
  String? _errorKey;
  bool _canUseBiometrics = false;
  bool _isCheckingBiometrics = true;
  bool _didScheduleInitialKeyboard = false;
  bool _currentPinVerified = false;
  bool _isError = false;
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  bool get _isSetup => widget.mode == NoteLockPinMode.setup;
  bool get _isChangePin => widget.mode == NoteLockPinMode.changePin;
  bool get _isConfirming => _isSetup && _firstPin != null;

  String get _titleKey {
    if (_isChangePin) {
      if (!_currentPinVerified) {
        return ViewConstants.noteLockVerifyCurrentPinTitle;
      }
      return _firstPin == null
          ? ViewConstants.noteLockNewPinTitle
          : ViewConstants.noteLockConfirmPinTitle;
    }
    if (!_isSetup) {
      return ViewConstants.noteLockEnterPinTitle;
    }
    return _isConfirming
        ? ViewConstants.noteLockConfirmPinTitle
        : ViewConstants.noteLockCreatePinTitle;
  }

  String get _bodyKey {
    if (_isChangePin) {
      if (!_currentPinVerified) {
        return ViewConstants.noteLockVerifyCurrentPinBody;
      }
      return _firstPin == null
          ? ViewConstants.noteLockNewPinBody
          : ViewConstants.noteLockConfirmPinBody;
    }
    if (!_isSetup) {
      return ViewConstants.noteLockUnlockBody;
    }
    return _isConfirming
        ? ViewConstants.noteLockConfirmPinBody
        : ViewConstants.noteLockCreatePinBody;
  }

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween:
            Tween<double>(begin: 0, end: 8).chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 8, end: -8)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 2,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -8, end: 8)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 2,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 8, end: -6)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 2,
      ),
      TweenSequenceItem(
        tween:
            Tween<double>(begin: -6, end: 0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 1,
      ),
    ]).animate(_shakeController);
    _pinController.addListener(_handlePinChanged);
    _loadBiometrics();
    _scheduleInitialKeyboard();
  }

  void _scheduleInitialKeyboard() {
    if (_didScheduleInitialKeyboard) {
      return;
    }
    _didScheduleInitialKeyboard = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _openKeyboard();
      await Future<void>.delayed(const Duration(milliseconds: 320));
      _openKeyboard();
    });
  }

  void _openKeyboard() {
    if (!mounted) {
      return;
    }
    _pinFocusNode.requestFocus();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pinController
      ..removeListener(_handlePinChanged)
      ..dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadBiometrics() async {
    if (_isSetup || _isChangePin) {
      setState(() {
        _isCheckingBiometrics = false;
      });
      return;
    }

    final canUseBiometrics = await widget.authService.canUseBiometrics();
    if (!mounted) {
      return;
    }
    setState(() {
      _canUseBiometrics = canUseBiometrics;
      _isCheckingBiometrics = false;
    });
  }

  void _handlePinChanged() {
    final nextPin = _pinController.text;
    if (nextPin == _pin) {
      return;
    }

    setState(() {
      _pin = nextPin;
      _errorKey = null;
    });

    if (nextPin.length == 4) {
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          _submitPin(nextPin);
        }
      });
    }
  }

  Future<void> _submitPin(String pin) async {
    if (_isSetup) {
      await _submitSetupPin(pin);
      return;
    }

    if (_isChangePin) {
      await _submitChangePinStep(pin);
      return;
    }

    final isValid = await widget.authService.verifyPin(pin);
    if (!mounted) {
      return;
    }
    if (isValid) {
      await _onPinSuccess();
      return;
    }
    _showError(ViewConstants.noteLockWrongPin);
  }

  Future<void> _submitChangePinStep(String pin) async {
    if (!_currentPinVerified) {
      final isValid = await widget.authService.verifyPin(pin);
      if (!mounted) {
        return;
      }
      if (!isValid) {
        _showError(ViewConstants.noteLockWrongPin);
        return;
      }
      setState(() {
        _currentPinVerified = true;
      });
      _clearPin();
      return;
    }

    await _submitSetupPin(pin);
  }

  Future<void> _submitSetupPin(String pin) async {
    final firstPin = _firstPin;
    if (firstPin == null) {
      setState(() {
        _firstPin = pin;
      });
      _clearPin();
      return;
    }

    if (firstPin != pin) {
      _showError(ViewConstants.noteLockPinMismatch);
      return;
    }

    await widget.authService.createPin(pin);
    if (mounted) {
      AppRouter.pop(context, true);
    }
  }

  void _showError(String errorKey) {
    HapticFeedback.heavyImpact();
    setState(() {
      _errorKey = errorKey;
      _isError = true;
    });
    _shakeController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _isError = false;
        });
      }
    });
    _clearPin();
  }

  void _clearPin() {
    _pinController.clear();
    setState(() {
      _pin = '';
    });
    _openKeyboard();
  }

  Future<void> _authenticateWithBiometrics() async {
    _dismissKeyboard();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) {
      return;
    }
    final didAuthenticate = await widget.authService.authenticateWithBiometrics(
      ViewConstants.noteLockBiometricReason.tr(),
    );
    if (!mounted || !didAuthenticate) {
      return;
    }
    await _onPinSuccess();
  }

  Future<void> _onPinSuccess() async {
    final ideaId = widget.ideaId;
    final nextRoute = widget.nextRoute;
    if (nextRoute != null) {
      if (ideaId != null) {
        widget.authService.markIdeaUnlocked(ideaId);
      }
      if (!mounted) {
        return;
      }
      await AppRouter.pushReplacement(context, nextRoute());
      if (ideaId != null) {
        widget.authService.markIdeaLocked(ideaId);
      }
    } else {
      AppRouter.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Scaffold(
      key: const Key('note-lock-pin-screen'),
      backgroundColor: theme.background,
      appBar: IdeaVaultSubpageAppBar(titleKey: _titleKey),
      body: ColoredBox(
        color: theme.background,
        child: KeyboardActions(
          config: keyboardActionbuildConfig(context, [_pinFocusNode]),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissKeyboard,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    28.w,
                    24.h,
                    28.w,
                    MediaQuery.paddingOf(context).bottom + 36.h,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 86.d,
                        height: 86.d,
                        decoration: BoxDecoration(
                          color: theme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 40.d,
                          color: theme.primary,
                        ),
                      ),
                      Gap(24.h),
                      TranslatedText(
                        _titleKey,
                        textAlign: TextAlign.center,
                        style: ideaVaultHeadline(
                          context,
                          size: 28.f,
                          weight: FontWeight.w800,
                          height: 1.12,
                        ),
                      ),
                      Gap(10.h),
                      TranslatedText(
                        _bodyKey,
                        textAlign: TextAlign.center,
                        style: ideaVaultBody(
                          context,
                          size: 15.f,
                          weight: FontWeight.w500,
                          color: theme.textMuted,
                          height: 1.5,
                        ),
                      ),
                      Gap(34.h),
                      AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(_shakeAnimation.value, 0),
                          child: child,
                        ),
                        child: _PinDots(
                          filledCount: _pin.length,
                          isError: _isError,
                          onTap: _openKeyboard,
                        ),
                      ),
                      if (_errorKey != null) ...[
                        Gap(18.h),
                        Text(
                          _errorKey!.tr(),
                          textAlign: TextAlign.center,
                          style: ideaVaultBody(
                            context,
                            size: 14.f,
                            weight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (widget.mode == NoteLockPinMode.unlock &&
                          !_isCheckingBiometrics &&
                          _canUseBiometrics) ...[
                        Gap(28.h),
                        TextButton.icon(
                          onPressed: _authenticateWithBiometrics,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: Text(ViewConstants.noteLockUseBiometric.tr()),
                        ),
                      ],
                      SizedBox(
                        width: 1,
                        height: 1,
                        child: TextField(
                          controller: _pinController,
                          focusNode: _pinFocusNode,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          enableSuggestions: false,
                          autocorrect: false,
                          obscureText: true,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                          ),
                          style: const TextStyle(
                            color: Colors.transparent,
                            height: 0.01,
                          ),
                          cursorColor: Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.filledCount,
    required this.isError,
    required this.onTap,
  });

  final int filledCount;
  final bool isError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final errorColor = Theme.of(context).colorScheme.error;
    final activeColor = isError ? errorColor : theme.primary;
    return GestureDetector(
      key: const Key('note-lock-pin-dots'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 4; index++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: 18.d,
                height: 18.d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index < filledCount || isError
                      ? activeColor
                      : Colors.transparent,
                  border: Border.all(
                    color: activeColor,
                    width: 1.8,
                  ),
                ),
              ),
              if (index != 3) Gap(14.w),
            ],
          ],
        ),
      ),
    );
  }
}
