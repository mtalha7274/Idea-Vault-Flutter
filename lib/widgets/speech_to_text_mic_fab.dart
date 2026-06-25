import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants/view_constants.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../views/ideas/idea_vault_theme.dart';
import 'translated_text.dart';

class SpeechToTextMicFab extends StatefulWidget {
  const SpeechToTextMicFab({
    super.key,
    required this.isListening,
    required this.isActivating,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    this.tooltipKey,
  });

  final bool isListening;
  final bool isActivating;
  final VoidCallback onTap;
  final Future<void> Function() onLongPressStart;
  final Future<void> Function() onLongPressEnd;
  final GlobalKey<TooltipState>? tooltipKey;

  @override
  State<SpeechToTextMicFab> createState() => _SpeechToTextMicFabState();
}

class _SpeechToTextMicFabState extends State<SpeechToTextMicFab>
    with TickerProviderStateMixin {
  static const _micSize = 56.0;
  static const _rippleCount = 3;

  late final AnimationController _pressController;
  late final AnimationController _phaseController;
  late final AnimationController _breathController;
  late final AnimationController _listenLabelController;
  late final AnimationController _rippleController;
  late final Animation<double> _pressScaleAnimation;
  late final Animation<double> _phaseScaleAnimation;
  late final Animation<double> _breathScaleAnimation;
  late final Animation<Offset> _listenLabelSlideAnimation;
  late final Animation<double> _listenLabelFadeAnimation;

  bool _isFingerDown = false;

  @override
  void initState() {
    super.initState();

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _pressScaleAnimation = Tween<double>(begin: 1, end: 0.94).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
    );

    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _phaseScaleAnimation = Tween<double>(begin: 1, end: 1.06).animate(
      CurvedAnimation(parent: _phaseController, curve: Curves.easeOutBack),
    );

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _breathScaleAnimation = Tween<double>(begin: 1, end: 1.08).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    _listenLabelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _listenLabelSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _listenLabelController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _listenLabelFadeAnimation = CurvedAnimation(
      parent: _listenLabelController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _syncAnimations();
  }

  @override
  void didUpdateWidget(SpeechToTextMicFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isListening != widget.isListening ||
        oldWidget.isActivating != widget.isActivating) {
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    final isActive = widget.isActivating || widget.isListening;

    if (isActive) {
      if (_phaseController.status != AnimationStatus.completed &&
          _phaseController.status != AnimationStatus.forward) {
        _phaseController.forward();
      }
    } else if (_phaseController.value > 0) {
      _phaseController.reverse();
    }

    if (widget.isListening || widget.isActivating) {
      if (!_breathController.isAnimating) {
        _breathController
          ..reset()
          ..repeat(reverse: true);
      }
    } else {
      _breathController
        ..stop()
        ..reset();
    }

    if (widget.isListening) {
      _startRippleLoop();
      if (_listenLabelController.status != AnimationStatus.completed) {
        _listenLabelController.forward();
      }
    } else {
      if (widget.isActivating) {
        _startRippleLoop();
      } else {
        _stopRipples();
      }
      if (_listenLabelController.value > 0) {
        _listenLabelController.reverse();
      }
    }
  }

  void _startRippleLoop() {
    if (_rippleController.isAnimating) {
      return;
    }
    _rippleController
      ..reset()
      ..repeat();
  }

  void _stopRipples() {
    _rippleController
      ..stop()
      ..reset();
  }

  @override
  void dispose() {
    _pressController.dispose();
    _phaseController.dispose();
    _breathController.dispose();
    _listenLabelController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  void _handleLongPressStart() {
    HapticFeedback.selectionClick();
    unawaited(widget.onLongPressStart());
  }

  void _handleLongPressEnd() {
    unawaited(widget.onLongPressEnd());
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() {
      _isFingerDown = true;
    });
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _releasePress();
  }

  void _handleTapCancel() {
    _releasePress();
  }

  void _releasePress() {
    if (!_isFingerDown) {
      return;
    }
    setState(() {
      _isFingerDown = false;
    });
    _pressController.reverse();
  }

  double _resolveMicScale() {
    var scale = 1.0;

    if (widget.isListening) {
      scale *= _breathScaleAnimation.value;
    } else if (widget.isActivating) {
      scale *= _phaseScaleAnimation.value;
      if (_breathController.isAnimating) {
        scale *= _breathScaleAnimation.value;
      }
    }

    if (_isFingerDown) {
      scale *= _pressScaleAnimation.value;
    }

    return scale;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final primaryColor = theme.primary;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return AnimatedScale(
      scale: isKeyboardVisible ? 0 : 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      child: AnimatedOpacity(
        opacity: isKeyboardVisible ? 0 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedBuilder(
              animation: _listenLabelController,
              builder: (context, child) {
                final showLabel = widget.isListening ||
                    _listenLabelController.value > 0;
                if (!showLabel) {
                  return const SizedBox.shrink();
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FadeTransition(
                      opacity: _listenLabelFadeAnimation,
                      child: SlideTransition(
                        position: _listenLabelSlideAnimation,
                        child: child,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                );
              },
              child: IgnorePointer(
                ignoring: !widget.isListening,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: TranslatedText(
                    ViewConstants.ideaEditorListening,
                    style: ideaVaultLabel(
                      context,
                      size: 13,
                      weight: FontWeight.w700,
                      color: primaryColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
            Tooltip(
              key: widget.tooltipKey,
              message: ViewConstants.ideaEditorMicLongPressToTalk.tr(),
              triggerMode: TooltipTriggerMode.manual,
              showDuration: const Duration(seconds: 3),
              child: GestureDetector(
                key: const Key('idea-editor-mic-fab'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onLongPress: _handleLongPressStart,
                onLongPressEnd: (_) => _handleLongPressEnd(),
                onTapDown: _handleTapDown,
                onTapUp: _handleTapUp,
                onTapCancel: _handleTapCancel,
                child: SizedBox(
                  width: _micSize * 2.4,
                  height: _micSize * 2.4,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _rippleController,
                          builder: (context, child) {
                            return CustomPaint(
                              size: Size.square(_micSize * 2.4),
                              painter: _SpeechRipplePainter(
                                progress: _rippleController.value,
                                color: primaryColor,
                                activeCount: widget.isListening
                                    ? _rippleCount
                                    : widget.isActivating
                                        ? 1
                                        : 0,
                              ),
                            );
                          },
                        ),
                      ),
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _pressController,
                          _phaseController,
                          _breathController,
                        ]),
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _resolveMicScale(),
                            child: child,
                          );
                        },
                        child: Material(
                          elevation: widget.isListening ? 8 : 6,
                          shadowColor: primaryColor.withValues(alpha: 0.35),
                          color: primaryColor,
                          shape: const CircleBorder(),
                          child: SizedBox.square(
                            dimension: _micSize,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              switchInCurve: Curves.easeOutBack,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                                );
                              },
                              child: Icon(
                                widget.isListening
                                    ? Icons.graphic_eq_rounded
                                    : Icons.mic_rounded,
                                key: ValueKey<bool>(widget.isListening),
                                size: 28,
                                color: theme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeechRipplePainter extends CustomPainter {
  _SpeechRipplePainter({
    required this.progress,
    required this.color,
    required this.activeCount,
  });

  static const _rippleCount = 3;

  final double progress;
  final Color color;
  final int activeCount;

  @override
  void paint(Canvas canvas, Size size) {
    if (activeCount <= 0) {
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.18;

    for (var index = 0; index < activeCount; index++) {
      final phase = index / _rippleCount;
      final ringProgress = (progress + phase) % 1.0;
      if (ringProgress <= 0) {
        continue;
      }

      final radius = baseRadius + (baseRadius * 1.4 * ringProgress);
      final opacity = (1 - ringProgress).clamp(0.0, 1.0) * 0.28;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 - (ringProgress * 1.2)
        ..color = color.withValues(alpha: opacity);

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SpeechRipplePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.activeCount != activeCount;
  }
}
