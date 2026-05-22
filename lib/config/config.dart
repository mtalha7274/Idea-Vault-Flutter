import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static final bool debug = dotenv.env['DEBUG'] == 'true';

  static const bool bypassPaywall = false;
  static final int paidFeatureFreeUsageLimit = Config.debug ? 3 : 50;

  // Themes
  static const String light = 'light';
  static const String dark = 'dark';

  // Config
  static const String fontFamily = 'Inter';

  static const String bundleId = 'com.pocketmicros.ideavault';
  static const String appleId = '6765999984';
  static const String appPlaystoreUrl =
      'https://play.google.com/store/apps/details?id=$bundleId';
  static const String appAppstoreUrl = 'https://apps.apple.com/app/id$appleId';
  static const String privacyPolicyUrl =
      'https://ideavault.pocketmicros.com/privacy-policy/';
  static const String termsOfUseUrl =
      'https://ideavault.pocketmicros.com/terms/';
  static const String contactUsEmail = 'support@pocketmicros.com';
  static const String logPrefix = '[DEV LOG]';
}
