import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_assets.dart';
import '../core/constants/view_constants.dart';
import '../core/extensions/int.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/free_usage_progress_ring.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

class FreeUsageScreen extends StatefulWidget {
  const FreeUsageScreen({
    super.key,
    required this.usageCount,
    required this.usageLimit,
    this.animationCompleted = false,
  });

  final int usageCount;
  final int usageLimit;
  final bool animationCompleted;

  @override
  State<FreeUsageScreen> createState() => _FreeUsageScreenState();
}

class _FreeUsageScreenState extends State<FreeUsageScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _giftController;
  late bool _showContent;

  @override
  void initState() {
    super.initState();
    _showContent = widget.animationCompleted;
    _giftController = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) {
          return;
        }
        setState(() {
          _showContent = true;
        });
      });
  }

  @override
  void dispose() {
    _giftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final progress =
        widget.usageLimit <= 0 ? 1.0 : widget.usageCount / widget.usageLimit;
    final titleKey = widget.animationCompleted
        ? ViewConstants.freeUsageScreenDrawerTitle
        : ViewConstants.freeUsageScreenTitle;
    final bodyKey = widget.animationCompleted
        ? ViewConstants.freeUsageScreenDrawerBody
        : ViewConstants.freeUsageScreenBody;
    final actionKey = widget.animationCompleted
        ? ViewConstants.freeUsageScreenDrawerAction
        : ViewConstants.freeUsageScreenAction;
    final progressSemanticLabel = ViewConstants.freeUsageProgressSemantic.tr(
      namedArgs: {
        'used': widget.usageCount.toString(),
        'limit': widget.usageLimit.toString(),
      },
    );

    return Scaffold(
      key: const Key('free-usage-screen'),
      backgroundColor: theme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(28.w, 20.h, 28.w, 28.h),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 232.d,
                    child: Lottie.asset(
                      AppAssets.giftAnimation,
                      controller: _giftController,
                      fit: BoxFit.contain,
                      repeat: false,
                      onLoaded: (composition) {
                        _giftController.duration = composition.duration;
                        if (widget.animationCompleted) {
                          _giftController.value = 1;
                          return;
                        }
                        _giftController.forward(from: 0);
                      },
                    ),
                  ),
                  Gap(42.h),
                  IgnorePointer(
                    key: const Key('free-usage-content'),
                    ignoring: !_showContent,
                    child: Column(
                      children: [
                        _StaggeredReveal(
                          key: const Key('free-usage-title-reveal'),
                          visible: _showContent,
                          delay: Duration.zero,
                          child: TranslatedText(
                            titleKey,
                            textAlign: TextAlign.center,
                            style: ideaVaultHeadline(
                              context,
                              size: 30.f,
                              weight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                        Gap(14.h),
                        _StaggeredReveal(
                          key: const Key('free-usage-body-reveal'),
                          visible: _showContent,
                          delay: const Duration(milliseconds: 110),
                          child: TranslatedText(
                            bodyKey,
                            textAlign: TextAlign.center,
                            style: ideaVaultBody(
                              context,
                              size: 15.f,
                              weight: FontWeight.w600,
                              color: theme.onSurface,
                              height: 1.45,
                            ),
                          ),
                        ),
                        Gap(28.h),
                        _StaggeredReveal(
                          key: const Key('free-usage-tile-reveal'),
                          visible: _showContent,
                          delay: const Duration(milliseconds: 220),
                          child: _CurrentProUsageTile(
                            progress: progress,
                            semanticLabel: progressSemanticLabel,
                          ),
                        ),
                        Gap(34.h),
                        _StaggeredReveal(
                          key: const Key('free-usage-action-reveal'),
                          visible: _showContent,
                          delay: const Duration(milliseconds: 330),
                          child: SizedBox(
                            width: double.infinity,
                            height: 54.h,
                            child: FilledButton(
                              key: const Key('free-usage-primary-action'),
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.primary,
                                foregroundColor: theme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                textStyle: ideaVaultLabel(
                                  context,
                                  size: 15.f,
                                  weight: FontWeight.w800,
                                  color: theme.onPrimary,
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: TranslatedText(actionKey),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentProUsageTile extends StatelessWidget {
  const _CurrentProUsageTile({
    required this.progress,
    required this.semanticLabel,
  });

  final double progress;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;

    return Material(
      key: const Key('free-usage-current-usage-tile'),
      color: theme.surface,
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.outlineSoft),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          child: Row(
            children: [
              Expanded(
                child: TranslatedText(
                  ViewConstants.freeUsageCurrentUsageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ideaVaultBody(
                    context,
                    size: 15.f,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              Gap(14.w),
              FreeUsageProgressRing(
                progress: progress,
                size: 34.d,
                strokeWidth: 3.4,
                semanticLabel: semanticLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaggeredReveal extends StatefulWidget {
  const _StaggeredReveal({
    super.key,
    required this.visible,
    required this.delay,
    required this.child,
  });

  final bool visible;
  final Duration delay;
  final Widget child;

  @override
  State<_StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<_StaggeredReveal> {
  Timer? _timer;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      _scheduleReveal();
    }
  }

  @override
  void didUpdateWidget(covariant _StaggeredReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible &&
        widget.delay == oldWidget.delay) {
      return;
    }

    _timer?.cancel();
    if (!widget.visible) {
      setState(() {
        _isVisible = false;
      });
      return;
    }
    _scheduleReveal();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleReveal() {
    if (widget.delay == Duration.zero) {
      _show();
      return;
    }

    _timer = Timer(widget.delay, _show);
  }

  void _show() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isVisible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _isVisible ? Offset.zero : const Offset(0, 0.12),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutBack,
      child: AnimatedScale(
        scale: _isVisible ? 1 : 0.96,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _isVisible ? 1 : 0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
