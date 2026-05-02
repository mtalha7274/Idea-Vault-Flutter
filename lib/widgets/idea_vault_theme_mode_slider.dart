import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';

import '../config/theme/base.dart';
import '../core/constants/app_assets.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/view_constants.dart';
import '../core/extensions/int.dart';

import 'translated_text.dart';

class IdeaVaultThemeModeSlider extends StatefulWidget {
  const IdeaVaultThemeModeSlider({
    super.key,
    required this.base,
    required this.isDark,
    required this.onChanged,
  });

  final BaseTheme base;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  @override
  State<IdeaVaultThemeModeSlider> createState() =>
      _IdeaVaultThemeModeSliderState();
}

class _IdeaVaultThemeModeSliderState extends State<IdeaVaultThemeModeSlider>
    with SingleTickerProviderStateMixin {
  static const Duration _snapDuration = Duration(milliseconds: 320);
  static const Curve _snapCurve = Curves.easeOutCubic;

  late final AnimationController _position;

  @override
  void initState() {
    super.initState();
    _position = AnimationController(
      vsync: this,
      value: widget.isDark ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(IdeaVaultThemeModeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) {
      _position.animateTo(
        widget.isDark ? 1.0 : 0.0,
        duration: _snapDuration,
        curve: _snapCurve,
      );
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  void _commitSlide() {
    final targetDark = _position.value >= 0.5;
    final targetT = targetDark ? 1.0 : 0.0;
    if (targetDark != widget.isDark) {
      HapticFeedback.selectionClick();
      widget.onChanged(targetDark);
    } else {
      _position.animateTo(targetT, duration: _snapDuration, curve: _snapCurve);
    }
  }

  void _onTrackTap(double localX, double width) {
    final targetDark = localX >= width * 0.5;
    if (targetDark != widget.isDark) {
      HapticFeedback.selectionClick();
      widget.onChanged(targetDark);
    } else {
      _position.animateTo(
        targetDark ? 1.0 : 0.0,
        duration: _snapDuration,
        curve: _snapCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final trackH = 48.h;
        final inset = 4.w;
        final innerW = (totalW - inset * 2).clamp(1.0, double.infinity);
        final thumbW = innerW * 0.48;
        final travel = (innerW - thumbW).clamp(1.0, double.infinity);

        return SizedBox(
          height: trackH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _onTrackTap(details.localPosition.dx, totalW),
            onHorizontalDragUpdate: (details) {
              final deltaT = details.delta.dx / travel;
              _position.value = (_position.value + deltaT).clamp(0.0, 1.0);
            },
            onHorizontalDragEnd: (_) => _commitSlide(),
            child: AnimatedBuilder(
              animation: _position,
              builder: (context, child) {
                final t = _position.value;
                final thumbLeft = inset + travel * t;
                final labelSize = AppConstants.font14Px;
                final iconBox = 18.d;
                final lightForeground =
                    t < 0.5 ? widget.base.onPrimary : widget.base.primaryText;
                final darkForeground =
                    t >= 0.5 ? widget.base.onPrimary : widget.base.primaryText;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.base.surfaceLow,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: widget.base.outlineSoft,
                          width: 1,
                        ),
                      ),
                      child: SizedBox(height: trackH, width: totalW),
                    ),
                    Positioned(
                      left: thumbLeft,
                      top: 4.h,
                      bottom: 4.h,
                      width: thumbW,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.base.primary,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: widget.base.overlay,
                                blurRadius: 8,
                                offset: Offset(0, 2.h),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: inset, vertical: 4.h),
                      child: Row(
                        children: [
                          Expanded(
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SvgPicture.asset(
                                    AppAssets.sun,
                                    width: iconBox,
                                    height: iconBox,
                                    colorFilter: ColorFilter.mode(
                                      lightForeground,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                  SizedBox(width: 6.w),
                                  TranslatedText(
                                    ViewConstants.settingsThemeLight,
                                    style: TextStyle(
                                      color: lightForeground,
                                      fontSize: labelSize,
                                      fontWeight: t < 0.5
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SvgPicture.asset(
                                    AppAssets.moon,
                                    width: iconBox,
                                    height: iconBox,
                                    colorFilter: ColorFilter.mode(
                                      darkForeground,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                  SizedBox(width: 6.w),
                                  TranslatedText(
                                    ViewConstants.settingsThemeDark,
                                    style: TextStyle(
                                      color: darkForeground,
                                      fontSize: labelSize,
                                      fontWeight: t >= 0.5
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
