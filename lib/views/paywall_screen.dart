import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/config.dart';
import '../config/theme/base.dart';
import '../core/constants/view_constants.dart';
import '../core/utils/helpers.dart';
import '../models/premium/paywall_offering.dart';
import '../viewmodels/providers/premium/paywall_view_model.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/premium_crown_icon.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

class PaywallPalette {
  const PaywallPalette({
    required this.scaffoldBackground,
    required this.surface,
    required this.accentGreen,
    required this.accentGreenDark,
    required this.selectedTint,
    required this.secondaryBadgeBackground,
    required this.borderSubtle,
    required this.borderNeutral,
    required this.secondaryBadgeForeground,
    required this.ctaForeground,
    required this.featureCheckBackground,
    required this.featureCheckForeground,
    required this.mostPopularGradientStart,
    required this.mostPopularGradientEnd,
    required this.mostPopularShadow,
    required this.mostPopularShadowOpacity,
    required this.mostPopularStroke,
    required this.mostPopularStrokeWidth,
    required this.mostPopularLabel,
    required this.mostPopularOuterGlow,
    required this.mostPopularBadgePadH,
    required this.mostPopularBadgePadV,
    required this.mostPopularBadgeFontSize,
    required this.mostPopularLetterSpacing,
  });

  final Color scaffoldBackground;
  final Color surface;
  final Color accentGreen;
  final Color accentGreenDark;
  final Color selectedTint;
  final Color secondaryBadgeBackground;
  final Color borderSubtle;
  final Color borderNeutral;
  final Color secondaryBadgeForeground;
  final Color ctaForeground;
  final Color featureCheckBackground;
  final Color featureCheckForeground;
  final Color mostPopularGradientStart;
  final Color mostPopularGradientEnd;
  final Color mostPopularShadow;
  final double mostPopularShadowOpacity;
  final Color mostPopularStroke;
  final double mostPopularStrokeWidth;
  final Color mostPopularLabel;
  final Color mostPopularOuterGlow;
  final int mostPopularBadgePadH;
  final int mostPopularBadgePadV;
  final int mostPopularBadgeFontSize;
  final double mostPopularLetterSpacing;

  static PaywallPalette resolve(String themeType) =>
      themeType == Config.dark ? dark : light;

  static const PaywallPalette light = PaywallPalette(
    scaffoldBackground: Color(0xFFFAFAF7),
    surface: Color(0xFFFFFFFF),
    accentGreen: Color(0xFF5E7F6D),
    accentGreenDark: Color(0xFF2F5544),
    selectedTint: Color(0xFFEAF1EC),
    secondaryBadgeBackground: Color(0xFFFFE8DD),
    borderSubtle: Color(0xFFE9E7E1),
    borderNeutral: Color(0xFFC9C6BE),
    secondaryBadgeForeground: Color(0xFF8E4E33),
    ctaForeground: Color(0xFFFFFFFF),
    featureCheckBackground: Color(0xFF1A1C1E),
    featureCheckForeground: Color(0xFFFFFFFF),
    mostPopularGradientStart: Color(0xFF18181B),
    mostPopularGradientEnd: Color(0xFF3F3F46),
    mostPopularShadow: Color(0xFF09090B),
    mostPopularShadowOpacity: 0.32,
    mostPopularStroke: Color(0x33FFFFFF),
    mostPopularStrokeWidth: 1,
    mostPopularLabel: Color(0xFFF4F4F5),
    mostPopularOuterGlow: Color(0x6E18181B),
    mostPopularBadgePadH: 8,
    mostPopularBadgePadV: 4,
    mostPopularBadgeFontSize: 10,
    mostPopularLetterSpacing: 0.2,
  );

  static const PaywallPalette dark = PaywallPalette(
    scaffoldBackground: Color(0xFF121416),
    surface: Color(0xFF1C1F22),
    accentGreen: Color(0xFF5F8F74),
    accentGreenDark: Color(0xFF81B39C),
    selectedTint: Color(0xFF242E2B),
    secondaryBadgeBackground: Color(0xFF3D3028),
    borderSubtle: Color(0xFF2D3236),
    borderNeutral: Color(0xFF3D444A),
    secondaryBadgeForeground: Color(0xFFFFCC80),
    ctaForeground: Color(0xFF1A2421),
    featureCheckBackground: Color(0xFF2D3236),
    featureCheckForeground: Color(0xFF81B39C),
    mostPopularGradientStart: Color(0xFFFFCA28),
    mostPopularGradientEnd: Color(0xFFFF6D00),
    mostPopularShadow: Color(0xFFFF7043),
    mostPopularShadowOpacity: 0.45,
    mostPopularStroke: Color(0x5CFFFFFF),
    mostPopularStrokeWidth: 1.5,
    mostPopularLabel: Color(0xFF1A120E),
    mostPopularOuterGlow: Color(0x7AFFB74D),
    mostPopularBadgePadH: 8,
    mostPopularBadgePadV: 4,
    mostPopularBadgeFontSize: 10,
    mostPopularLetterSpacing: 0.2,
  );
}

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  static const List<String> _proFeatureKeys = [
    ViewConstants.paywallFeatureAiOrganize,
    ViewConstants.paywallFeatureAiBrainstorm,
    ViewConstants.paywallFeatureCloudBackup,
    ViewConstants.paywallFeatureExportPdf,
    ViewConstants.paywallFeatureEarlyAccess,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final palette =
        PaywallPalette.resolve(context.watch<ThemeProvider>().themeType);
    final paywall = context.watch<PaywallViewModel>();
    final isYearlySelected = paywall.selectedPlan == PaywallPlan.yearly;
    final yearlyPackage = paywall.offering?.yearly;
    final monthlyPackage = paywall.offering?.monthly;
    final yearlyTotalForCopy = yearlyPackage?.billingPeriodTotalLabel ??
        yearlyPackage?.priceLabel ??
        '—';
    final yearlyMonthlyEquivalentForCopy =
        yearlyPackage?.monthlyEquivalentPriceLabel ?? '—';
    final monthlyPriceForCopy = monthlyPackage?.priceLabel ?? '—';
    final yearlyTrialDays = yearlyPackage?.freeTrialDays;
    final yearlyHasIntroTrial = yearlyTrialDays != null && yearlyTrialDays > 0;
    final savingsPercent = yearlyPackage?.savingsPercentVsMonthly;

    return Scaffold(
      backgroundColor: palette.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 520.w),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(22.w, 18.h, 22.w, 18.h),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _HeroHeader(theme: theme),
                            const Spacer(),
                            _IncludedPanel(
                              featureKeys: _proFeatureKeys,
                              palette: palette,
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 520.w),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(22.w, 8.h, 22.w, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PlanOption(
                            palette: palette,
                            titleKey: ViewConstants.paywallPlanYearly,
                            priceKey: ViewConstants.paywallYearlyHeadlinePrice,
                            priceText: null,
                            subtitleKey: ViewConstants.paywallYearlyPriceLine,
                            trialLabelKey: yearlyHasIntroTrial
                                ? ViewConstants.paywallTrialLabel
                                : null,
                            trialLabelText: yearlyPackage?.trialLabel,
                            trialNamedArgs: yearlyHasIntroTrial
                                ? {'days': '$yearlyTrialDays'}
                                : null,
                            leadingBadgeKey: savingsPercent != null
                                ? ViewConstants.paywallBadgeSave
                                : null,
                            priceNamedArgs: {
                              'yearlyPrice': yearlyTotalForCopy,
                            },
                            subtitleNamedArgs: {
                              'monthlyPrice': yearlyMonthlyEquivalentForCopy,
                            },
                            badgeNamedArgs: savingsPercent != null
                                ? {'percent': '$savingsPercent'}
                                : null,
                            isSelected:
                                paywall.selectedPlan == PaywallPlan.yearly,
                            onTap: () => paywall.selectPlan(PaywallPlan.yearly),
                          ),
                          Gap(10.h),
                          _PlanOption(
                            palette: palette,
                            titleKey: ViewConstants.paywallPlanMonthly,
                            priceKey: ViewConstants.paywallMonthlyPriceLine,
                            contentPadding: EdgeInsets.fromLTRB(
                              16.d,
                              24.d,
                              16.d,
                              24.d,
                            ),
                            priceNamedArgs: {
                              'monthlyPrice': monthlyPriceForCopy,
                            },
                            isSelected:
                                paywall.selectedPlan == PaywallPlan.monthly,
                            onTap: () =>
                                paywall.selectPlan(PaywallPlan.monthly),
                          ),
                          Gap(14.h),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: isYearlySelected
                                ? (yearlyHasIntroTrial
                                    ? TranslatedText(
                                        ViewConstants.paywallFooterYearly,
                                        key: ValueKey(
                                          'footer-yearly-trial-$yearlyTrialDays-$yearlyTotalForCopy',
                                        ),
                                        namedArgs: {
                                          'trialDays': '$yearlyTrialDays',
                                          'yearlyPrice': yearlyTotalForCopy,
                                        },
                                        textAlign: TextAlign.center,
                                        style: ideaVaultLabel(
                                          context,
                                          size: 13.f,
                                          weight: FontWeight.w700,
                                          color: palette.accentGreenDark,
                                          height: 1.35,
                                        ),
                                      )
                                    : TranslatedText(
                                        ViewConstants
                                            .paywallFooterYearlyNoTrial,
                                        key: ValueKey(
                                          'footer-yearly-$yearlyTotalForCopy',
                                        ),
                                        namedArgs: {
                                          'yearlyPrice': yearlyTotalForCopy,
                                        },
                                        textAlign: TextAlign.center,
                                        style: ideaVaultLabel(
                                          context,
                                          size: 13.f,
                                          weight: FontWeight.w700,
                                          color: palette.accentGreenDark,
                                          height: 1.35,
                                        ),
                                      ))
                                : TranslatedText(
                                    ViewConstants.paywallFooterMonthly,
                                    key: const ValueKey('footer-monthly'),
                                    namedArgs: {
                                      'monthlyPrice': monthlyPriceForCopy,
                                    },
                                    textAlign: TextAlign.center,
                                    style: ideaVaultLabel(
                                      context,
                                      size: 13.f,
                                      weight: FontWeight.w700,
                                      color: theme.textMuted,
                                      height: 1.35,
                                    ),
                                  ),
                          ),
                          Gap(14.h),
                          SizedBox(
                            height: 56.h,
                            child: FilledButton(
                              onPressed: paywall.isPurchasing
                                  ? null
                                  : _handlePurchasePressed,
                              style: FilledButton.styleFrom(
                                backgroundColor: palette.accentGreenDark,
                                foregroundColor: palette.ctaForeground,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              child: TranslatedText(
                                isYearlySelected
                                    ? (yearlyHasIntroTrial
                                        ? ViewConstants.paywallCtaStartTrial
                                        : ViewConstants
                                            .paywallCtaSubscribeYearly)
                                    : ViewConstants.paywallCtaGetMonthly,
                                style: ideaVaultLabel(
                                  context,
                                  size: 16.f,
                                  weight: FontWeight.w800,
                                  color: palette.ctaForeground,
                                ),
                              ),
                            ),
                          ),
                          Gap(16.h),
                          _LegalLinks(
                            palette: palette,
                            onRestorePressed: paywall.isPurchasing
                                ? null
                                : _handleRestorePressed,
                            onTermsPressed: _handleTermsPressed,
                            onPrivacyPressed: _handlePrivacyPressed,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 2.h,
            right: 4.w,
            child: SafeArea(
              bottom: false,
              child: Opacity(
                opacity: 0.62,
                child: IconButton(
                  tooltip: ViewConstants.paywallCloseTooltip.tr(),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: theme.textMuted,
                  iconSize: 21.d,
                  splashRadius: 20.d,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showComingSoon() {
    debugPrint('Coming soon');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: TranslatedText(ViewConstants.paywallComingSoon),
      ),
    );
  }

  void _handleTermsPressed() {
    final url = Config.termsOfUseUrl.trim();
    if (url.isEmpty) {
      _showComingSoon();
      return;
    }
    launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).then((launched) {
      if (!launched && mounted) {
        _showComingSoon();
      }
    }, onError: (Object e, StackTrace stackTrace) {
      printLog('$e\n$stackTrace');
      if (mounted) {
        _showComingSoon();
      }
    });
  }

  void _handlePrivacyPressed() {
    final url = Config.privacyPolicyUrl.trim();
    if (url.isEmpty) {
      _showComingSoon();
      return;
    }
    launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).then((launched) {
      if (!launched && mounted) {
        _showComingSoon();
      }
    }, onError: (Object e, StackTrace stackTrace) {
      printLog('$e\n$stackTrace');
      if (mounted) {
        _showComingSoon();
      }
    });
  }

  Future<void> _handlePurchasePressed() async {
    final paywall = context.read<PaywallViewModel>();
    final didBecomePro = await paywall.purchaseSelectedPlan();
    if (!mounted) {
      return;
    }
    if (didBecomePro) {
      Navigator.of(context).pop(true);
      return;
    }
    _showPurchaseUnavailableMessage();
  }

  Future<void> _handleRestorePressed() async {
    final paywall = context.read<PaywallViewModel>();
    final didBecomePro = await paywall.restorePurchases();
    if (!mounted) {
      return;
    }
    if (didBecomePro) {
      Navigator.of(context).pop(true);
      return;
    }
    _showPurchaseUnavailableMessage();
  }

  void _showPurchaseUnavailableMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: TranslatedText(ViewConstants.paywallPurchaseUnavailable),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.theme,
  });

  final BaseTheme theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PremiumCrownIcon(size: 48.d),
        Gap(14.h),
        TranslatedText(
          ViewConstants.paywallTitle,
          textAlign: TextAlign.center,
          style: ideaVaultHeadline(
            context,
            size: 32.f,
            weight: FontWeight.w900,
            color: theme.primaryText,
            height: 1.05,
          ),
        ),
        Gap(10.h),
        TranslatedText(
          ViewConstants.paywallSubtitle,
          textAlign: TextAlign.center,
          style: ideaVaultBody(
            context,
            size: 15.f,
            weight: FontWeight.w500,
            color: theme.textMuted,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _IncludedPanel extends StatelessWidget {
  const _IncludedPanel({
    required this.featureKeys,
    required this.palette,
  });

  final List<String> featureKeys;
  final PaywallPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(18.d),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FeatureGroup(
            titleKey: ViewConstants.paywallProUnlocks,
            featureKeys: featureKeys,
          ),
        ],
      ),
    );
  }
}

class _FeatureGroup extends StatelessWidget {
  const _FeatureGroup({
    required this.titleKey,
    required this.featureKeys,
  });

  final String titleKey;
  final List<String> featureKeys;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TranslatedText(
          titleKey,
          style: ideaVaultLabel(
            context,
            size: 13.f,
            weight: FontWeight.w800,
            color: theme.primaryText,
          ),
        ),
        Gap(16.h),
        for (var i = 0; i < featureKeys.length; i++) ...[
          _FeatureRow(
            labelKey: featureKeys[i],
          ),
          if (i < featureKeys.length - 1) Gap(12.h),
        ],
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.labelKey,
  });

  final String labelKey;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;

    return Row(
      children: [
        SizedBox(
          width: 20.d,
          height: 20.d,
          child: Center(
            child: PremiumCrownIcon(size: 14.d),
          ),
        ),
        Gap(10.d),
        Expanded(
          child: TranslatedText(
            labelKey,
            style: ideaVaultBody(
              context,
              size: 14.f,
              weight: FontWeight.w500,
              color: theme.primaryText,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.palette,
    required this.titleKey,
    required this.priceKey,
    required this.isSelected,
    required this.onTap,
    this.subtitleKey,
    this.priceText,
    this.trialLabelText,
    this.trialLabelKey,
    this.leadingBadgeKey,
    this.priceNamedArgs,
    this.subtitleNamedArgs,
    this.trialNamedArgs,
    this.badgeNamedArgs,
    this.contentPadding,
  });

  final PaywallPalette palette;
  final String titleKey;
  final String priceKey;
  final String? subtitleKey;
  final String? priceText;
  final String? trialLabelText;
  final String? trialLabelKey;
  final String? leadingBadgeKey;
  final Map<String, String>? priceNamedArgs;
  final Map<String, String>? subtitleNamedArgs;
  final Map<String, String>? trialNamedArgs;
  final Map<String, String>? badgeNamedArgs;
  final EdgeInsetsGeometry? contentPadding;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final cardColor = isSelected ? palette.selectedTint : palette.surface;
    final borderColor = isSelected ? palette.accentGreen : palette.borderSubtle;
    final borderWidth = isSelected ? 1.4 : 1.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: contentPadding ?? EdgeInsets.all(16.d),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: borderColor,
                  width: borderWidth,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22.d,
                    height: 22.d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? palette.accentGreenDark
                            : palette.borderNeutral,
                        width: 1.5,
                      ),
                    ),
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 160),
                      scale: isSelected ? 1 : 0,
                      child: Container(
                        margin: EdgeInsets.all(4.d),
                        decoration: BoxDecoration(
                          color: palette.accentGreenDark,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  Gap(14.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: TranslatedText(
                                titleKey,
                                style: ideaVaultLabel(
                                  context,
                                  size: 15.f,
                                  weight: FontWeight.w900,
                                  color: theme.primaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (trialLabelText != null ||
                            trialLabelKey != null) ...[
                          Gap(6.h),
                          _InlineTrialLabel(
                            labelText: trialLabelText,
                            labelKey: trialLabelKey,
                            namedArgs: trialNamedArgs,
                            color: palette.accentGreenDark,
                          ),
                        ],
                        if (subtitleKey != null) ...[
                          Gap(6.h),
                          TranslatedText(
                            subtitleKey!,
                            namedArgs: subtitleNamedArgs,
                            style: ideaVaultLabel(
                              context,
                              size: 12.f,
                              weight: FontWeight.w600,
                              color: theme.textMuted,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Gap(12.w),
                  if (priceText != null)
                    Text(
                      priceText!,
                      textAlign: TextAlign.right,
                      style: ideaVaultHeadline(
                        context,
                        size: 22.f,
                        weight: FontWeight.w900,
                        color: theme.primaryText,
                        height: 1.08,
                        letterSpacing: -0.35,
                      ),
                    )
                  else
                    TranslatedText(
                      priceKey,
                      namedArgs: priceNamedArgs,
                      textAlign: TextAlign.right,
                      style: ideaVaultHeadline(
                        context,
                        size: 22.f,
                        weight: FontWeight.w900,
                        color: theme.primaryText,
                        height: 1.08,
                        letterSpacing: -0.35,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (leadingBadgeKey != null)
          Positioned(
            top: -10.h,
            right: 16.w,
            child: _Badge(
              palette: palette,
              labelKey: leadingBadgeKey!,
              namedArgs: badgeNamedArgs,
              isPrimary: true,
            ),
          ),
      ],
    );
  }
}

class _InlineTrialLabel extends StatelessWidget {
  const _InlineTrialLabel({
    required this.color,
    this.labelText,
    this.labelKey,
    this.namedArgs,
  });

  final Color color;
  final String? labelText;
  final String? labelKey;
  final Map<String, String>? namedArgs;

  @override
  Widget build(BuildContext context) {
    final style = ideaVaultLabel(
      context,
      size: 12.f,
      weight: FontWeight.w800,
      color: color,
      height: 1.2,
    );

    if (labelText != null) {
      return Text(
        labelText!,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return TranslatedText(
      labelKey!,
      namedArgs: namedArgs,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.palette,
    required this.labelKey,
    this.isPrimary = false,
    this.namedArgs,
  });

  final PaywallPalette palette;
  final String labelKey;
  final bool isPrimary;
  final Map<String, String>? namedArgs;

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      final shadows = <BoxShadow>[
        BoxShadow(
          color: palette.mostPopularShadow
              .withValues(alpha: palette.mostPopularShadowOpacity),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: palette.mostPopularShadow.withValues(
            alpha: palette.mostPopularShadowOpacity * 0.42,
          ),
          blurRadius: 24,
          spreadRadius: -1,
          offset: const Offset(0, 6),
        ),
      ];
      if (palette.mostPopularOuterGlow.a > 0) {
        shadows.add(
          BoxShadow(
            color: palette.mostPopularOuterGlow,
            blurRadius: 28,
            spreadRadius: 1,
            offset: const Offset(0, 5),
          ),
        );
      }

      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: palette.mostPopularBadgePadH.w,
          vertical: palette.mostPopularBadgePadV.h,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              palette.mostPopularGradientStart,
              palette.mostPopularGradientEnd,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: palette.mostPopularStroke,
            width: palette.mostPopularStrokeWidth,
          ),
          boxShadow: shadows,
        ),
        child: TranslatedText(
          labelKey,
          namedArgs: namedArgs,
          style: ideaVaultLabel(
            context,
            size: palette.mostPopularBadgeFontSize.f,
            weight: FontWeight.w900,
            color: palette.mostPopularLabel,
            height: 1,
            letterSpacing: palette.mostPopularLetterSpacing,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: palette.secondaryBadgeBackground,
        borderRadius: BorderRadius.circular(99),
      ),
      child: TranslatedText(
        labelKey,
        namedArgs: namedArgs,
        style: ideaVaultLabel(
          context,
          size: 10.f,
          weight: FontWeight.w900,
          color: palette.secondaryBadgeForeground,
        ),
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks({
    required this.palette,
    required this.onRestorePressed,
    required this.onTermsPressed,
    required this.onPrivacyPressed,
  });

  final PaywallPalette palette;
  final VoidCallback? onRestorePressed;
  final VoidCallback onTermsPressed;
  final VoidCallback onPrivacyPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8.w,
      runSpacing: 2.h,
      children: [
        _LegalLink(
          labelKey: ViewConstants.paywallRestorePurchases,
          onPressed: onRestorePressed,
          color: theme.textMuted,
        ),
        _FooterDot(color: palette.borderNeutral),
        _LegalLink(
          labelKey: ViewConstants.privacyPolicy,
          onPressed: onPrivacyPressed,
          color: theme.textMuted,
        ),
        _FooterDot(color: palette.borderNeutral),
        _LegalLink(
          labelKey: ViewConstants.paywallTermsOfService,
          onPressed: onTermsPressed,
          color: theme.textMuted,
        ),
      ],
    );
  }
}

class _FooterDot extends StatelessWidget {
  const _FooterDot({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return TranslatedText(
      ViewConstants.paywallFooterDot,
      style: ideaVaultLabel(
        context,
        size: 11.f,
        weight: FontWeight.w500,
        color: color,
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.labelKey,
    required this.onPressed,
    required this.color,
  });

  final String labelKey;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: Size.zero,
        padding: EdgeInsets.symmetric(horizontal: 1.w, vertical: 4.h),
      ),
      child: TranslatedText(
        labelKey,
        style: ideaVaultLabel(
          context,
          size: 11.f,
          weight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
