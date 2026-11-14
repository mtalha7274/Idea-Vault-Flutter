import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NoteLockSessionGuard {
  NoteLockSessionGuard._();

  static int _suppressionDepth = 0;

  static bool get isRelockSuppressed => _suppressionDepth > 0;

  static Future<T> runWithoutRelock<T>(Future<T> Function() action) async {
    _suppressionDepth += 1;
    try {
      return await action();
    } finally {
      _suppressionDepth -= 1;
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _suppressionDepth = 0;
  }
}

class NoteLockSecureWindow {
  NoteLockSecureWindow._();

  static const MethodChannel channel =
      MethodChannel('com.pocketmicros.ideavault/privacy');

  static int _holders = 0;
  static bool? _appliedValue;

  @visibleForTesting
  static bool? debugIsAndroidOverride;

  static bool get isSecure => _holders > 0;

  static bool get _isAndroid =>
      debugIsAndroidOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static void acquire() {
    _holders += 1;
    _apply();
  }

  static void release() {
    if (_holders > 0) {
      _holders -= 1;
    }
    _apply();
  }

  static void _apply() {
    final secure = _holders > 0;
    if (_appliedValue == secure || !_isAndroid) {
      return;
    }
    _appliedValue = secure;
    channel.invokeMethod<void>('setSecure', {'secure': secure}).catchError(
      (Object _) {
        _appliedValue = null;
      },
    );
  }

  @visibleForTesting
  static void resetForTesting() {
    _holders = 0;
    _appliedValue = null;
    debugIsAndroidOverride = null;
  }
}
