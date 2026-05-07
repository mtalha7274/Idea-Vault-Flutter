import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static final bool debug = dotenv.env['DEBUG'] == 'true';

  static const bool bypassPaywall = false;

  // Themes
  static const String light = 'light';
  static const String dark = 'dark';

  // Config
  static const String fontFamily = 'Inter';

  // TODO: Add your own bundle id and apple id
  // Example: bundleId = 'com.example.app';
  // Example: appleId = '1234567890';
  static const String bundleId = 'com.pocketmicros.ideavault';
  static const String appleId = '6765999984';
  static const String appPlaystoreUrl =
      'https://play.google.com/store/apps/details?id=$bundleId';
  static const String appAppstoreUrl = 'https://apps.apple.com/app/id$appleId';
  // TODO: Add your own privacy policy url and terms of use url and contact us email
  static const String privacyPolicyUrl =
      'https://ideavault.pocketmicros.com/privacy-policy/';
  static const String termsOfUseUrl =
      'https://ideavault.pocketmicros.com/terms/';
  static const String contactUsEmail = 'support@pocketmicros.com';
  // TODO: Update this flag after firebase setup
  // TODO: Use flutterfire cli for firebase setup and override current implementations
  static const bool firebaseEnabled = false;
  static const String logPrefix = '[DEV LOG]';
}
