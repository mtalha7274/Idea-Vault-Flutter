import 'package:in_app_review/in_app_review.dart';

import '../../config/config.dart';
import '../utils/helpers.dart';

Future<bool> rateApp() async {
  if (Config.debug) return false;

  try {
    final InAppReview inAppReview = InAppReview.instance;
    if (!await inAppReview.isAvailable()) {
      return false;
    }
    await inAppReview.requestReview();
    return true;
  } catch (error, stackTrace) {
    printLog('Rate app request failed: $error\n$stackTrace');
    return false;
  }
}
