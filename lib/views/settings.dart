import 'dart:io';

import 'package:flutter/material.dart';
import 'package:idea_vault/core/extensions/double.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/config.dart';
import '../core/constants/app_assets.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/view_constants.dart';
import '../core/utils/helpers.dart';
import '../main.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/idea_vault_theme_mode_slider.dart';
import '../widgets/translated_text.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  final ValueNotifier<bool> inAsyncCall = ValueNotifier(false);

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: themeProvider.baseTheme.background,
      appBar: IdeaVaultSubpageAppBar(
        titleKey: ViewConstants.settings,
      ),
      body: SafeArea(
          child: Padding(
        padding: EdgeInsets.only(
            left: AppConstants.gap20Px.w, right: (AppConstants.gap18Px + 1).w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Gap(AppConstants.gap18Px + 1),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  runSpacing: AppConstants.gap10Px,
                  children: [
                    appearanceTile(themeProvider),
                    actionTile(themeProvider, ViewConstants.privacyPolicy,
                        AppAssets.privacyPolicy,
                        size: 18.0, onTap: privacyPolicy),
                    actionTile(themeProvider, ViewConstants.termsAndConditions,
                        AppAssets.termsAndConditions,
                        size: 16.0, onTap: termsAndConditions),
                    actionTile(
                        themeProvider, ViewConstants.rateApp, AppAssets.rateApp,
                        onTap: rateApp),
                    actionTile(themeProvider, ViewConstants.shareApp,
                        AppAssets.shareApp,
                        onTap: shareApp),
                    actionTile(themeProvider, ViewConstants.contactUs,
                        AppAssets.contactUs,
                        onTap: contactUs),
                  ],
                ),
              ),
            )
          ],
        ),
      )),
    );
  }

  Widget appearanceTile(ThemeProvider themeProvider) {
    final base = themeProvider.baseTheme;
    final isDark = themeProvider.themeType == Config.dark;
    return Container(
      padding: EdgeInsets.only(
        left: (AppConstants.gap14Px + 1).w,
        right: (AppConstants.gap14Px + 1).w,
        top: (AppConstants.gap12Px + 1).h,
        bottom: AppConstants.gap12Px,
      ),
      decoration: BoxDecoration(
        color: base.surface,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 31.h,
                width: 31.4.w,
                decoration: BoxDecoration(
                  color: base.settings.iconBackground,
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  isDark ? AppAssets.moon : AppAssets.sun,
                  height: 17.h,
                  width: 17.w,
                  colorFilter: ColorFilter.mode(
                    base.settings.icon,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              Gap((AppConstants.gap10Px + 1.6).w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TranslatedText(
                      ViewConstants.settingsAppearance,
                      style: TextStyle(
                        color: base.settings.tileTitle,
                        fontSize: AppConstants.font14Px,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Gap(4.h),
                    TranslatedText(
                      ViewConstants.settingsThemeDescription,
                      style: TextStyle(
                        color: base.textMuted,
                        fontSize: AppConstants.font12Px,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Gap((AppConstants.gap12Px + 1).h),
          IdeaVaultThemeModeSlider(
            base: base,
            isDark: isDark,
            onChanged: (dark) {
              themeProvider.setTheme(
                theme: dark ? Config.dark : Config.light,
              );
            },
          ),
        ],
      ),
    );
  }

  GestureDetector actionTile(
      ThemeProvider themeProvider, String title, String icon,
      {double size = 17.0, Function()? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
            left: (AppConstants.gap14Px + 1).w,
            top: (AppConstants.gap12Px + 1).h,
            bottom: AppConstants.gap12Px),
        decoration: BoxDecoration(
            color: themeProvider.baseTheme.surface,
            borderRadius: const BorderRadius.all(Radius.circular(10))),
        child: Row(
          children: [
            Container(
              height: 31.h,
              width: 31.4.w,
              decoration: BoxDecoration(
                  color: themeProvider.baseTheme.settings.iconBackground,
                  borderRadius: const BorderRadius.all(Radius.circular(8))),
              alignment: Alignment.center,
              child: SvgPicture.asset(
                icon,
                height: size.h,
                width: size.w,
                colorFilter: ColorFilter.mode(
                  themeProvider.baseTheme.settings.icon,
                  BlendMode.srcIn,
                ),
              ),
            ),
            Gap((AppConstants.gap10Px + 1.6).w),
            TranslatedText(
              title,
              style: TextStyle(
                  color: themeProvider.baseTheme.settings.tileTitle,
                  fontSize: AppConstants.font14Px,
                  fontWeight: FontWeight.w500),
            )
          ],
        ),
      ),
    );
  }

  void privacyPolicy() {
    _launchUrl(Config.privacyPolicyUrl);
  }

  void termsAndConditions() {
    _launchUrl(Config.termsOfUseUrl);
  }

  void rateApp() async {
    try {
      final InAppReview inAppReview = InAppReview.instance;
      inAppReview.openStoreListing(appStoreId: Config.appleId);
    } catch (e, s) {
      printLog(e.toString());
      printLog(s.toString());
    }
  }

  void shareApp() async {
    final url =
        Platform.isAndroid ? Config.appPlaystoreUrl : Config.appAppstoreUrl;

    final context = navigatorKey.currentContext;
    if (context == null) return;
    Share.shareUri(
      Uri.parse(url),
      // sharePositionOrigin is required for iOS tablets otherwise an error is thrown
      sharePositionOrigin: Rect.fromLTWH(0, 0, MediaQuery.sizeOf(context).width,
          MediaQuery.sizeOf(context).height / 2),
    );
  }

  void _launchUrl(String url,
      {LaunchMode mode = LaunchMode.externalApplication}) async {
    try {
      await launchUrl(Uri.parse(url), mode: mode);
    } catch (e) {
      printLog(e.toString());
    }
  }
}
