import 'dart:async';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../../../core/utils/helpers.dart';
import '../../../models/premium/paywall_offering.dart';
import '../../../models/premium/subscription_state.dart';
import 'subscription_service.dart';

class RevenueCatSubscriptionService implements SubscriptionService {
  RevenueCatSubscriptionService();

  final List<SubscriptionStateListener> _listeners = [];
  bool _initialized = false;
  bool _configured = false;

  String get _entitlementId =>
      dotenv.env['REVENUECAT_ENTITLEMENT_ID']?.trim().isNotEmpty == true
          ? dotenv.env['REVENUECAT_ENTITLEMENT_ID']!.trim()
          : 'pro';

  String get _offeringId =>
      dotenv.env['REVENUECAT_OFFERING_ID']?.trim().isNotEmpty == true
          ? dotenv.env['REVENUECAT_OFFERING_ID']!.trim()
          : 'default';

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    final apiKey = _platformApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      printLog('RevenueCat API key missing for ${Platform.operatingSystem}.');
      return;
    }

    try {
      await rc.Purchases.configure(rc.PurchasesConfiguration(apiKey));
      rc.Purchases.addCustomerInfoUpdateListener((customerInfo) {
        _emit(_mapCustomerInfo(customerInfo));
      });
      _configured = true;
    } catch (error, stackTrace) {
      printLog('RevenueCat configure failed: $error\n$stackTrace');
    }
  }

  @override
  Future<SubscriptionState> getSubscriptionState() async {
    await initialize();
    if (!_configured) {
      return SubscriptionState(
        isPro: false,
        isLoading: false,
        source: 'revenuecat',
        expiresAt: null,
        activeProductId: null,
        lastCheckedAt: DateTime.now(),
      );
    }

    try {
      final customerInfo = await rc.Purchases.getCustomerInfo();
      return _mapCustomerInfo(customerInfo);
    } catch (error, stackTrace) {
      printLog('RevenueCat customer info failed: $error\n$stackTrace');
      return SubscriptionState(
        isPro: false,
        isLoading: false,
        source: 'revenuecat',
        expiresAt: null,
        activeProductId: null,
        lastCheckedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<PaywallOffering?> getOffering() async {
    await initialize();
    if (!_configured) {
      return null;
    }

    try {
      final offerings = await rc.Purchases.getOfferings();
      final offering = offerings.all[_offeringId] ?? offerings.current;
      if (offering == null) {
        return null;
      }
      final packages = offering.availablePackages;
      final monthlyPkg = _packageForType(packages, rc.PackageType.monthly);
      final yearlyPkg = _packageForType(packages, rc.PackageType.annual);
      return PaywallOffering(
        yearly:
            yearlyPkg == null ? null : _mapYearlyPackage(yearlyPkg, monthlyPkg),
        monthly: monthlyPkg == null ? null : _mapMonthlyPackage(monthlyPkg),
      );
    } catch (error, stackTrace) {
      printLog('RevenueCat offerings failed: $error\n$stackTrace');
      return null;
    }
  }

  @override
  Future<SubscriptionState> purchasePackage(PaywallPackage package) async {
    await initialize();
    if (!_configured) {
      return getSubscriptionState();
    }

    final rcPackage = await _findRevenueCatPackage(package.id);
    if (rcPackage == null) {
      return getSubscriptionState();
    }

    try {
      final result =
          await rc.Purchases.purchase(rc.PurchaseParams.package(rcPackage));
      final state = _mapCustomerInfo(result.customerInfo);
      _emit(state);
      return state;
    } catch (error, stackTrace) {
      printLog('RevenueCat purchase failed: $error\n$stackTrace');
      return getSubscriptionState();
    }
  }

  @override
  Future<SubscriptionState> restorePurchases() async {
    await initialize();
    if (!_configured) {
      return getSubscriptionState();
    }

    try {
      final customerInfo = await rc.Purchases.restorePurchases();
      final state = _mapCustomerInfo(customerInfo);
      _emit(state);
      return state;
    } catch (error, stackTrace) {
      printLog('RevenueCat restore failed: $error\n$stackTrace');
      return getSubscriptionState();
    }
  }

  @override
  void addListener(SubscriptionStateListener listener) {
    _listeners.add(listener);
  }

  String? get _platformApiKey {
    if (Platform.isAndroid) {
      return dotenv.env['REVENUECAT_ANDROID_API_KEY']?.trim();
    }
    if (Platform.isIOS) {
      return dotenv.env['REVENUECAT_IOS_API_KEY']?.trim();
    }
    return null;
  }

  SubscriptionState _mapCustomerInfo(rc.CustomerInfo customerInfo) {
    final entitlement = customerInfo.entitlements.all[_entitlementId];
    final isActive = entitlement?.isActive ?? false;
    return SubscriptionState(
      isPro: isActive,
      isLoading: false,
      source: 'revenuecat',
      expiresAt: DateTime.tryParse(entitlement?.expirationDate ?? ''),
      activeProductId: entitlement?.productIdentifier,
      lastCheckedAt: DateTime.now(),
    );
  }

  rc.Package? _packageForType(
    List<rc.Package> packages,
    rc.PackageType type,
  ) {
    for (final package in packages) {
      if (package.packageType == type) {
        return package;
      }
    }
    return null;
  }

  PaywallPackage _mapMonthlyPackage(rc.Package package) {
    final sp = package.storeProduct;
    final intro = sp.introductoryPrice;
    String? trialLabel;
    int? freeTrialDays;
    if (intro != null) {
      if (intro.price <= 0.001) {
        freeTrialDays = _freeTrialDaysFromIntro(intro);
      } else {
        trialLabel = intro.priceString;
      }
    }
    return PaywallPackage(
      id: package.identifier,
      productId: sp.identifier,
      priceLabel: sp.priceString,
      trialLabel: trialLabel,
      billingPeriodTotalLabel: null,
      monthlyEquivalentPriceLabel: null,
      freeTrialDays: freeTrialDays,
      savingsPercentVsMonthly: null,
    );
  }

  PaywallPackage _mapYearlyPackage(
    rc.Package package,
    rc.Package? monthlyPackage,
  ) {
    final sp = package.storeProduct;
    final intro = sp.introductoryPrice;
    String? trialLabel;
    int? freeTrialDays;
    if (intro != null) {
      if (intro.price <= 0.001) {
        freeTrialDays = _freeTrialDaysFromIntro(intro);
      } else {
        trialLabel = intro.priceString;
      }
    }
    int? savingsPercent;
    if (monthlyPackage != null) {
      savingsPercent = _savingsPercentYearlyVsMonthly(
        sp.price,
        monthlyPackage.storeProduct.price,
      );
    }
    return PaywallPackage(
      id: package.identifier,
      productId: sp.identifier,
      priceLabel: sp.priceString,
      trialLabel: trialLabel,
      billingPeriodTotalLabel: sp.priceString,
      monthlyEquivalentPriceLabel: sp.pricePerMonthString,
      freeTrialDays: freeTrialDays,
      savingsPercentVsMonthly: savingsPercent,
    );
  }

  int? _freeTrialDaysFromIntro(rc.IntroductoryPrice intro) {
    if (intro.price > 0.001) {
      return null;
    }
    final cycleCount = intro.cycles < 1 ? 1 : intro.cycles;
    final units = intro.periodNumberOfUnits * cycleCount;
    switch (intro.periodUnit) {
      case rc.PeriodUnit.day:
        return units;
      case rc.PeriodUnit.week:
        return units * 7;
      case rc.PeriodUnit.month:
        return units * 30;
      case rc.PeriodUnit.year:
        return units * 365;
      case rc.PeriodUnit.unknown:
        return null;
    }
  }

  int? _savingsPercentYearlyVsMonthly(
    double yearlyPrice,
    double monthlyPrice,
  ) {
    if (monthlyPrice <= 0 || yearlyPrice <= 0) {
      return null;
    }
    final annualizedMonthly = monthlyPrice * 12.0;
    if (annualizedMonthly <= yearlyPrice) {
      return null;
    }
    return (((annualizedMonthly - yearlyPrice) / annualizedMonthly) * 100)
        .round();
  }

  Future<rc.Package?> _findRevenueCatPackage(String packageId) async {
    final offerings = await rc.Purchases.getOfferings();
    final offering = offerings.all[_offeringId] ?? offerings.current;
    if (offering == null) {
      return null;
    }
    for (final package in offering.availablePackages) {
      if (package.identifier == packageId) {
        return package;
      }
    }
    return null;
  }

  void _emit(SubscriptionState state) {
    for (final listener in _listeners) {
      listener(state);
    }
  }
}
