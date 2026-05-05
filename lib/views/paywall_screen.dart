import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';

import '../config/theme/base.dart';
import '../core/constants/view_constants.dart';
import '../models/premium/paywall_offering.dart';
import '../viewmodels/providers/premium/paywall_view_model.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

abstract final class _PaywallColors {
  _PaywallColors._();

  static const Color scaffoldBackground = Color(0xFFFAFAF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color accentGreen = Color(0xFF5E7F6D);
  static const Color accentGreenDark = Color(0xFF2F5544);
  static const Color selectedTint = Color(0xFFEAF1EC);
  static const Color secondaryBadgeBackground = Color(0xFFFFE8DD);
  static const Color borderSubtle = Color(0xFFE9E7E1);
  static const Color borderNeutral = Color(0xFFC9C6BE);
  static const Color secondaryBadgeForeground = Color(0xFF8E4E33);
  static const Color onDark = Color(0xFFFFFFFF);
  static const Color inverse = Color(0xFF000000);
}

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  static const String _yearlyMonthlyEquivalent = r'$1.67';
  static const String _yearlyPrice = r'$19.99';
  static const String _monthlyPrice = r'$2.99';
  static const String _trialDays = '3';
  static const String _savePercent = '44';

  static const List<String> _proFeatureKeys = [
    ViewConstants.paywallFeatureAiOrganize,
    ViewConstants.paywallFeatureAiBrainstorm,
    ViewConstants.paywallFeatureSpeechToText,
    ViewConstants.paywallFeatureCloudBackup,
    ViewConstants.paywallFeatureExportPdf,
    ViewConstants.paywallFeatureEarlyAccess,
    ViewConstants.paywallFeaturePrioritySupport,
  ];

  static const _termsUrl = '';
  static const _privacyUrl = '';

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final paywall = context.watch<PaywallViewModel>();
    final isYearlySelected = paywall.selectedPlan == PaywallPlan.yearly;
    final yearlyPackage = paywall.offering?.yearly;
    final monthlyPackage = paywall.offering?.monthly;

    return Scaffold(
      backgroundColor: _PaywallColors.scaffoldBackground,
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
                        padding: EdgeInsets.fromLTRB(22.w, 48.h, 22.w, 18.h),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _HeroHeader(theme: theme),
                            const Spacer(),
                            _IncludedPanel(featureKeys: _proFeatureKeys),
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
                            titleKey: ViewConstants.paywallPlanYearly,
                            priceKey: ViewConstants.paywallYearlyPriceLine,
                            priceText: yearlyPackage?.priceLabel,
                            subtitleKey: ViewConstants.paywallYearlySubtitle,
                            trialLabelKey: ViewConstants.paywallTrialLabel,
                            trialLabelText: yearlyPackage?.trialLabel,
                            badgeKey: ViewConstants.paywallBadgeSave,
                            leadingBadgeKey:
                                ViewConstants.paywallBadgeMostPopular,
                            priceNamedArgs: const {
                              'monthlyPrice': _yearlyMonthlyEquivalent,
                            },
                            subtitleNamedArgs: const {
                              'yearlyPrice': _yearlyPrice,
                            },
                            trialNamedArgs: const {'days': _trialDays},
                            badgeNamedArgs: const {'percent': _savePercent},
                            isSelected:
                                paywall.selectedPlan == PaywallPlan.yearly,
                            onTap: () => paywall.selectPlan(PaywallPlan.yearly),
                          ),
                          Gap(10.h),
                          _PlanOption(
                            titleKey: ViewConstants.paywallPlanMonthly,
                            priceKey: ViewConstants.paywallMonthlyPriceLine,
                            priceText: monthlyPackage?.priceLabel,
                            subtitleKey: ViewConstants.paywallMonthlySubtitle,
                            priceNamedArgs: const {
                              'monthlyPrice': _monthlyPrice,
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
                                ? TranslatedText(
                                    ViewConstants.paywallFooterYearly,
                                    key: const ValueKey('footer-yearly'),
                                    namedArgs: const {
                                      'trialDays': _trialDays,
                                      'yearlyPrice': _yearlyPrice,
                                    },
                                    textAlign: TextAlign.center,
                                    style: ideaVaultLabel(
                                      context,
                                      size: 13.f,
                                      weight: FontWeight.w700,
                                      color: _PaywallColors.accentGreenDark,
                                      height: 1.35,
                                    ),
                                  )
                                : TranslatedText(
                                    ViewConstants.paywallFooterMonthly,
                                    key: const ValueKey('footer-monthly'),
                                    namedArgs: const {
                                      'monthlyPrice': _monthlyPrice,
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
                                backgroundColor: _PaywallColors.accentGreenDark,
                                foregroundColor: _PaywallColors.onDark,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              child: TranslatedText(
                                isYearlySelected
                                    ? ViewConstants.paywallCtaStartTrial
                                    : ViewConstants.paywallCtaGetMonthly,
                                style: ideaVaultLabel(
                                  context,
                                  size: 16.f,
                                  weight: FontWeight.w800,
                                  color: _PaywallColors.onDark,
                                ),
                              ),
                            ),
                          ),
                          Gap(16.h),
                          _LegalLinks(
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
    debugPrint('Terms of Service tapped: $_termsUrl');
    _showComingSoon();
  }

  void _handlePrivacyPressed() {
    debugPrint('Privacy Policy tapped: $_privacyUrl');
    _showComingSoon();
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
  });

  final List<String> featureKeys;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(18.d),
      decoration: BoxDecoration(
        color: _PaywallColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _PaywallColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FeatureGroup(
            titleKey: ViewConstants.paywallProUnlocks,
            featureKeys: featureKeys,
            iconColor: _PaywallColors.onDark,
            iconBackground: _PaywallColors.inverse,
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
    required this.iconColor,
    required this.iconBackground,
  });

  final String titleKey;
  final List<String> featureKeys;
  final Color iconColor;
  final Color iconBackground;

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
            iconColor: iconColor,
            iconBackground: iconBackground,
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
    required this.iconColor,
    required this.iconBackground,
  });

  final String labelKey;
  final Color iconColor;
  final Color iconBackground;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;

    return Row(
      children: [
        Container(
          width: 20.d,
          height: 20.d,
          decoration: BoxDecoration(
            color: iconBackground.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              '✓',
              style: ideaVaultLabel(
                context,
                size: 14.f,
                weight: FontWeight.w700,
                color: iconColor,
                height: 1,
              ),
            ),
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
    required this.titleKey,
    required this.priceKey,
    required this.subtitleKey,
    required this.isSelected,
    required this.onTap,
    this.priceText,
    this.trialLabelText,
    this.trialLabelKey,
    this.badgeKey,
    this.leadingBadgeKey,
    this.priceNamedArgs,
    this.subtitleNamedArgs,
    this.trialNamedArgs,
    this.badgeNamedArgs,
  });

  final String titleKey;
  final String priceKey;
  final String subtitleKey;
  final String? priceText;
  final String? trialLabelText;
  final String? trialLabelKey;
  final String? badgeKey;
  final String? leadingBadgeKey;
  final Map<String, String>? priceNamedArgs;
  final Map<String, String>? subtitleNamedArgs;
  final Map<String, String>? trialNamedArgs;
  final Map<String, String>? badgeNamedArgs;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final cardColor =
        isSelected ? _PaywallColors.selectedTint : _PaywallColors.surface;
    final borderColor =
        isSelected ? _PaywallColors.accentGreen : _PaywallColors.borderSubtle;
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
              padding: EdgeInsets.all(16.d),
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
                            ? _PaywallColors.accentGreenDark
                            : _PaywallColors.borderNeutral,
                        width: 1.5,
                      ),
                    ),
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 160),
                      scale: isSelected ? 1 : 0,
                      child: Container(
                        margin: EdgeInsets.all(4.d),
                        decoration: const BoxDecoration(
                          color: _PaywallColors.accentGreenDark,
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
                            if (badgeKey != null) ...[
                              Gap(8.w),
                              _Badge(
                                labelKey: badgeKey!,
                                namedArgs: badgeNamedArgs,
                              ),
                            ],
                          ],
                        ),
                        if (trialLabelText != null ||
                            trialLabelKey != null) ...[
                          Gap(6.h),
                          if (trialLabelText != null)
                            Text(
                              trialLabelText!,
                              style: ideaVaultLabel(
                                context,
                                size: 12.f,
                                weight: FontWeight.w800,
                                color: _PaywallColors.accentGreenDark,
                                height: 1.2,
                              ),
                            )
                          else
                            TranslatedText(
                              trialLabelKey!,
                              namedArgs: trialNamedArgs,
                              style: ideaVaultLabel(
                                context,
                                size: 12.f,
                                weight: FontWeight.w800,
                                color: _PaywallColors.accentGreenDark,
                                height: 1.2,
                              ),
                            ),
                        ],
                        Gap(6.h),
                        TranslatedText(
                          subtitleKey,
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
                    ),
                  ),
                  Gap(12.w),
                  if (priceText != null)
                    Text(
                      priceText!,
                      textAlign: TextAlign.right,
                      style: ideaVaultHeadline(
                        context,
                        size: 18.f,
                        weight: FontWeight.w900,
                        color: theme.primaryText,
                        height: 1.1,
                      ),
                    )
                  else
                    TranslatedText(
                      priceKey,
                      namedArgs: priceNamedArgs,
                      textAlign: TextAlign.right,
                      style: ideaVaultHeadline(
                        context,
                        size: 18.f,
                        weight: FontWeight.w900,
                        color: theme.primaryText,
                        height: 1.1,
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
              labelKey: leadingBadgeKey!,
              isPrimary: true,
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.labelKey,
    this.isPrimary = false,
    this.namedArgs,
  });

  final String labelKey;
  final bool isPrimary;
  final Map<String, String>? namedArgs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: isPrimary
            ? _PaywallColors.inverse
            : _PaywallColors.secondaryBadgeBackground,
        borderRadius: BorderRadius.circular(99),
      ),
      child: TranslatedText(
        labelKey,
        namedArgs: namedArgs,
        style: ideaVaultLabel(
          context,
          size: 10.f,
          weight: FontWeight.w900,
          color: isPrimary
              ? _PaywallColors.onDark
              : _PaywallColors.secondaryBadgeForeground,
        ),
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks({
    required this.onRestorePressed,
    required this.onTermsPressed,
    required this.onPrivacyPressed,
  });

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
        _FooterDot(color: _PaywallColors.borderNeutral),
        _LegalLink(
          labelKey: ViewConstants.privacyPolicy,
          onPressed: onPrivacyPressed,
          color: theme.textMuted,
        ),
        _FooterDot(color: _PaywallColors.borderNeutral),
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
