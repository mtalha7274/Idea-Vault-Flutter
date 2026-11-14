import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
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
import '../config/router/app_router.dart';
import '../config/theme/base.dart';
import '../core/constants/app_assets.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/view_constants.dart';
import '../core/editor/note_editor_preferences.dart';
import '../core/services/note_lock_auth_service.dart';
import '../core/services/note_lock_biometric_service.dart';
import '../core/services/vault/note_vault_service.dart';
import '../core/utils/helpers.dart';
import '../injection_container.dart';
import '../main.dart';
import '../viewmodels/providers/ideas_provider.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../views/note_lock_pin_screen.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/note_lock_auth_dialog.dart';
import '../widgets/translated_text.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  final ValueNotifier<bool> inAsyncCall = ValueNotifier(false);
  late final NoteLockAuthService _authService;
  late final NoteLockBiometricService _biometricService;
  bool _hasPinSetup = false;
  bool _canOfferBiometrics = false;
  bool _isBiometricEnabled = false;
  bool _isUpdatingBiometric = false;
  NoteVaultService? _vault;
  bool _vaultReady = false;
  bool _hideTitles = false;
  bool _isUpdatingHideTitles = false;
  int _titleTapCount = 0;
  DateTime _lastTitleTap = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _authService = sl.isRegistered<NoteLockAuthService>()
        ? sl<NoteLockAuthService>()
        : NoteLockAuthService();
    _biometricService = sl.isRegistered<NoteLockBiometricService>()
        ? sl<NoteLockBiometricService>()
        : NoteLockBiometricService();
    _vault = resolveNoteVault();
    _loadPinStatus();
  }

  Future<void> _loadPinStatus() async {
    final hasPin = await _authService.hasPin();
    final canOfferBiometrics =
        hasPin && await _biometricService.canOfferBiometricEnrollment();
    final isBiometricEnabled =
        hasPin && await _biometricService.isBiometricUnlockEnabled();
    final vault = _vault;
    final vaultReady =
        vault != null && await vault.state() == NoteVaultState.ready;
    if (mounted) {
      setState(() {
        _vaultReady = vaultReady;
        _hideTitles = vault?.hideTitles ?? false;
        _hasPinSetup = hasPin;
        _canOfferBiometrics = canOfferBiometrics;
        _isBiometricEnabled = isBiometricEnabled;
      });
    }
  }

  void _handleTitleTap() {
    final now = DateTime.now();
    if (now.difference(_lastTitleTap) > const Duration(seconds: 2)) {
      _titleTapCount = 0;
    }
    _lastTitleTap = now;
    _titleTapCount++;
    if (_titleTapCount >= 7) {
      _titleTapCount = 0;
      _toggleClassicEditor();
    }
  }

  Future<void> _toggleClassicEditor() async {
    final next = !NoteEditorPreferences.forceClassicEditor;
    await NoteEditorPreferences.setForceClassicEditor(next);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: TranslatedText(
          next
              ? ViewConstants.editorClassicEditorOn
              : ViewConstants.editorClassicEditorOff,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: themeProvider.baseTheme.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: GestureDetector(
          key: const Key('settings-title-tap-area'),
          behavior: HitTestBehavior.translucent,
          onTap: _handleTitleTap,
          child: IdeaVaultSubpageAppBar(
            titleKey: ViewConstants.settings,
          ),
        ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _settingsGroup(
                      themeProvider,
                      [
                        appearanceTile(themeProvider),
                        if (_hasPinSetup) _changePinTile(themeProvider),
                        if (_hasPinSetup && _canOfferBiometrics)
                          _biometricTile(themeProvider),
                        if (_vaultReady) _hideTitlesTile(themeProvider),
                        if (_vaultReady && _hasPinSetup)
                          _recoveryCodeTile(themeProvider),
                      ],
                    ),
                    Gap(AppConstants.gap10Px),
                    _settingsGroup(
                      themeProvider,
                      [
                        actionTile(themeProvider, ViewConstants.privacyPolicy,
                            AppAssets.privacyPolicy,
                            size: 18.0,
                            onTap: privacyPolicy,
                            trailingIcon: Icons.open_in_new_rounded),
                        actionTile(
                            themeProvider,
                            ViewConstants.termsAndConditions,
                            AppAssets.termsAndConditions,
                            size: 16.0,
                            onTap: termsAndConditions,
                            trailingIcon: Icons.open_in_new_rounded),
                        actionTile(themeProvider, ViewConstants.rateApp,
                            AppAssets.rateApp,
                            onTap: rateApp,
                            trailingIcon: Icons.open_in_new_rounded),
                        actionTile(themeProvider, ViewConstants.shareApp,
                            AppAssets.shareApp,
                            onTap: shareApp, trailingIcon: Icons.share_rounded),
                        actionTile(themeProvider, ViewConstants.contactUs,
                            AppAssets.contactUs,
                            onTap: contactUs,
                            trailingIcon: Icons.mail_outline_rounded),
                      ],
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      )),
    );
  }

  Widget _settingsGroup(ThemeProvider themeProvider, List<Widget> tiles) {
    if (tiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final base = themeProvider.baseTheme;
    final dividerColor = base.outline.withValues(alpha: 0.3);
    return Container(
      decoration: BoxDecoration(
        color: base.surface,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < tiles.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1.5,
                thickness: 1.5,
                color: dividerColor,
              ),
            tiles[index],
          ],
        ],
      ),
    );
  }

  Widget appearanceTile(ThemeProvider themeProvider) {
    final base = themeProvider.baseTheme;
    final isDark = themeProvider.themeType == Config.dark;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (AppConstants.gap14Px).w,
        vertical: (AppConstants.gap12Px).h,
      ),
      child: Row(
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
            child: TranslatedText(
              ViewConstants.settingsAppearance,
              style: TextStyle(
                color: base.settings.tileTitle,
                fontSize: AppConstants.font14Px,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _appearanceThemeToggle(themeProvider, base, isDark),
        ],
      ),
    );
  }

  Widget _appearanceThemeToggle(
    ThemeProvider themeProvider,
    BaseTheme base,
    bool isDark,
  ) {
    final hintColor = base.textMuted.withValues(alpha: 0.75);
    return GestureDetector(
      onTap: () {
        themeProvider.setTheme(
          theme: isDark ? Config.light : Config.dark,
        );
      },
      child: SizedBox(
        width: 58.w,
        height: 38.h,
        child: Stack(
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: base.surfaceLow,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: base.outlineSoft, width: 1),
              ),
              child: SizedBox(width: 58.w, height: 38.h),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.asset(
                    AppAssets.sun,
                    width: 15,
                    height: 15,
                    colorFilter: ColorFilter.mode(
                      hintColor,
                      BlendMode.srcIn,
                    ),
                  ),
                  SvgPicture.asset(
                    AppAssets.moon,
                    width: 14,
                    height: 14,
                    colorFilter: ColorFilter.mode(
                      hintColor,
                      BlendMode.srcIn,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 2.5.w),
                child: Container(
                  width: 30.d,
                  height: 30.d,
                  decoration: BoxDecoration(
                    color: isDark ? base.primary : base.settings.switchThumb,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: base.overlay.withValues(alpha: 0.35),
                        blurRadius: 5,
                        offset: Offset(0, 2.h),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    isDark ? AppAssets.moon : AppAssets.sun,
                    width: 15,
                    height: 15,
                    colorFilter: ColorFilter.mode(
                      isDark ? base.onPrimary : base.primary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _changePinTile(ThemeProvider themeProvider) {
    final base = themeProvider.baseTheme;
    return GestureDetector(
      onTap: _changePin,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: (AppConstants.gap14Px + 1).w,
          vertical: (AppConstants.gap12Px + 1).h,
        ),
        child: Row(
          children: [
            Container(
              height: 31.h,
              width: 31.4.w,
              decoration: BoxDecoration(
                color: base.settings.iconBackground,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.lock_reset_rounded,
                size: 17.h,
                color: base.settings.icon,
              ),
            ),
            Gap((AppConstants.gap10Px + 1.6).w),
            Expanded(
              child: TranslatedText(
                ViewConstants.settingsChangePin,
                style: TextStyle(
                  color: base.settings.tileTitle,
                  fontSize: AppConstants.font14Px,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _settingsTrailingIcon(
              themeProvider,
              Icons.chevron_right_rounded,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _biometricTile(ThemeProvider themeProvider) {
    final base = themeProvider.baseTheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (AppConstants.gap14Px + 1).w,
        vertical: (AppConstants.gap12Px - 4).h,
      ),
      child: Row(
        children: [
          Container(
            height: 31.h,
            width: 31.4.w,
            decoration: BoxDecoration(
              color: base.settings.iconBackground,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.fingerprint_rounded,
              size: 18.h,
              color: base.settings.icon,
            ),
          ),
          Gap((AppConstants.gap10Px + 1.6).w),
          Expanded(
            child: TranslatedText(
              ViewConstants.noteLockSettingsBiometric,
              style: TextStyle(
                color: base.settings.tileTitle,
                fontSize: AppConstants.font14Px,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch.adaptive(
            key: const Key('settings-biometric-toggle'),
            value: _isBiometricEnabled,
            activeTrackColor: base.primary,
            onChanged: _isUpdatingBiometric
                ? null
                : (value) => _setBiometricEnabled(value),
          ),
        ],
      ),
    );
  }

  Future<void> _setBiometricEnabled(bool enabled) async {
    setState(() {
      _isUpdatingBiometric = true;
    });
    try {
      if (!enabled) {
        await _biometricService.setBiometricUnlockEnabled(false);
        if (!mounted) {
          return;
        }
        setState(() {
          _isBiometricEnabled = false;
        });
        _showSettingsSnackBar(ViewConstants.noteLockBiometricDisabledSnackbar);
        return;
      }

      final verified = await AppRouter.push<bool>(
        context,
        NoteLockPinScreen(
          mode: NoteLockPinMode.verify,
          authService: _authService,
          biometricService: _biometricService,
        ),
      );
      if (verified != true || !mounted) {
        return;
      }
      final result = await _biometricService.enableBiometricUnlock(
        ViewConstants.noteLockEnableBiometricReason.tr(),
      );
      if (!mounted || result != BiometricAuthResult.success) {
        return;
      }
      setState(() {
        _isBiometricEnabled = true;
      });
      _showSettingsSnackBar(ViewConstants.noteLockBiometricEnabledSnackbar);
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingBiometric = false;
        });
      }
    }
  }

  void _showSettingsSnackBar(String messageKey) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(messageKey.tr())),
    );
  }

  Future<void> _changePin() async {
    final ctx = context;
    final vault = _vault;
    final vaultState = vault == null ? null : await vault.state();
    if (!ctx.mounted) {
      return;
    }
    String? newPin;
    final result = await AppRouter.push<bool>(
      ctx,
      NoteLockPinScreen(
        mode: NoteLockPinMode.changePin,
        authService: _authService,
        biometricService: _biometricService,
        onPinCreated: vault == null
            ? null
            : (pin, kind, previousPin) async {
                if (vaultState != NoteVaultState.none) {
                  await vault.rewrapPin(
                    newPin: pin,
                    pinKind: kind,
                    oldPin: previousPin,
                  );
                }
                await _authService.createPin(pin, kind: kind);
                newPin = pin;
              },
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ViewConstants.noteLockChangePinSuccess.tr()),
        ),
      );
      final pin = newPin;
      if (vault != null && vaultState == NoteVaultState.none && pin != null) {
        await runNoteVaultMigration(
          context,
          _authService,
          _biometricService,
          vault,
          pin: pin,
        );
      }
      await _loadPinStatus();
    }
  }

  Widget _hideTitlesTile(ThemeProvider themeProvider) {
    final base = themeProvider.baseTheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (AppConstants.gap14Px + 1).w,
        vertical: (AppConstants.gap12Px - 4).h,
      ),
      child: Row(
        children: [
          Container(
            height: 31.h,
            width: 31.4.w,
            decoration: BoxDecoration(
              color: base.settings.iconBackground,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.visibility_off_outlined,
              size: 18.h,
              color: base.settings.icon,
            ),
          ),
          Gap((AppConstants.gap10Px + 1.6).w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TranslatedText(
                  ViewConstants.vaultSettingsHideTitles,
                  style: TextStyle(
                    color: base.settings.tileTitle,
                    fontSize: AppConstants.font14Px,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TranslatedText(
                  ViewConstants.vaultSettingsHideTitlesBody,
                  style: TextStyle(
                    color: base.textMuted,
                    fontSize: AppConstants.font12Px,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: const Key('settings-hide-titles-toggle'),
            value: _hideTitles,
            activeTrackColor: base.primary,
            onChanged: _isUpdatingHideTitles ? null : _setHideTitles,
          ),
        ],
      ),
    );
  }

  Future<void> _setHideTitles(bool hide) async {
    final vault = _vault;
    if (vault == null) {
      return;
    }
    final ideasProvider = _maybeIdeasProvider();
    setState(() {
      _isUpdatingHideTitles = true;
    });
    try {
      await vault.setHideTitles(hide);
      await ideasProvider?.reloadFromStorage();
      if (mounted) {
        setState(() {
          _hideTitles = hide;
        });
      }
    } catch (_) {
      if (mounted) {
        _showSettingsSnackBar(ViewConstants.vaultNeedsUnlockFirst);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingHideTitles = false;
        });
      }
    }
  }

  IdeasProvider? _maybeIdeasProvider() {
    try {
      return context.read<IdeasProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Widget _recoveryCodeTile(ThemeProvider themeProvider) {
    final base = themeProvider.baseTheme;
    return GestureDetector(
      key: const Key('settings-recovery-code'),
      onTap: _regenerateRecoveryCode,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: (AppConstants.gap14Px + 1).w,
          vertical: (AppConstants.gap12Px + 1).h,
        ),
        child: Row(
          children: [
            Container(
              height: 31.h,
              width: 31.4.w,
              decoration: BoxDecoration(
                color: base.settings.iconBackground,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.key_rounded,
                size: 17.h,
                color: base.settings.icon,
              ),
            ),
            Gap((AppConstants.gap10Px + 1.6).w),
            Expanded(
              child: TranslatedText(
                ViewConstants.vaultSettingsRecoveryCode,
                style: TextStyle(
                  color: base.settings.tileTitle,
                  fontSize: AppConstants.font14Px,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _settingsTrailingIcon(
              themeProvider,
              Icons.chevron_right_rounded,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _regenerateRecoveryCode() async {
    final vault = _vault;
    if (vault == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: TranslatedText(ViewConstants.vaultRecoveryRegenerateTitle),
        content: TranslatedText(ViewConstants.vaultRecoveryRegenerateBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(ViewConstants.vaultCancel.tr()),
          ),
          TextButton(
            key: const Key('settings-recovery-code-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(ViewConstants.vaultRecoveryRegenerateAction.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final verified = await AppRouter.push<bool>(
      context,
      NoteLockPinScreen(
        mode: NoteLockPinMode.verify,
        authService: _authService,
        biometricService: _biometricService,
        bodyKey: ViewConstants.vaultVerifyPinBody,
      ),
    );
    if (verified != true || !mounted) {
      return;
    }
    try {
      final code = await vault.regenerateRecoveryCode();
      if (!mounted) {
        return;
      }
      await showRecoveryCodeScreen(context, code);
    } catch (_) {
      if (mounted) {
        _showSettingsSnackBar(ViewConstants.vaultNeedsUnlockFirst);
      }
    }
  }

  Widget _settingsTrailingIcon(
    ThemeProvider themeProvider,
    IconData icon, {
    double size = 18,
  }) {
    final base = themeProvider.baseTheme;
    return Icon(
      icon,
      size: size.h,
      color: base.textMuted.withValues(alpha: 0.75),
    );
  }

  GestureDetector actionTile(
      ThemeProvider themeProvider, String title, String icon,
      {double size = 17.0, Function()? onTap, IconData? trailingIcon}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: (AppConstants.gap14Px + 1).w,
          vertical: (AppConstants.gap12Px + 1).h,
        ),
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
            Expanded(
              child: TranslatedText(
                title,
                style: TextStyle(
                    color: themeProvider.baseTheme.settings.tileTitle,
                    fontSize: AppConstants.font14Px,
                    fontWeight: FontWeight.w500),
              ),
            ),
            if (trailingIcon != null)
              _settingsTrailingIcon(
                themeProvider,
                trailingIcon,
              ),
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
    await SharePlus.instance.share(
      ShareParams(
        uri: Uri.parse(url),
        // Required for iOS tablets otherwise an error is thrown.
        sharePositionOrigin: Rect.fromLTWH(
          0,
          0,
          MediaQuery.sizeOf(context).width,
          MediaQuery.sizeOf(context).height / 2,
        ),
      ),
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
