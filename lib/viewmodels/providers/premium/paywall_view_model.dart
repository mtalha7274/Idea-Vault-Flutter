import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/config.dart';
import '../../../config/router/app_router.dart';
import '../../../core/services/backup/cloud_backup_scheduler.dart';
import '../../../core/services/backup/cloud_backup_service.dart';
import '../../../core/services/premium/paywall_provider.dart';
import '../../../core/services/premium/subscription_service.dart';
import '../../../core/services/rate_app.dart';
import '../../../data/repositories/local/cloud_backup_settings.dart';
import '../../../data/repositories/local/paid_feature_usage.dart';
import '../../../models/premium/paywall_offering.dart';
import '../../../models/premium/premium_feature.dart';
import '../../../models/premium/subscription_state.dart';
import '../backup/cloud_backup_provider.dart';

typedef ShowPaywall = Future<bool> Function(BuildContext context);
typedef RequestRateAppReview = Future<bool> Function();

class PaywallViewModel with ChangeNotifier {
  PaywallViewModel(
    this._subscriptionService,
    this._paywallProvider,
    this._paidFeatureUsageRepo,
    this._backupSettingsRepo,
    this._backupService,
    this._backupScheduler, {
    ShowPaywall? showPaywall,
    RequestRateAppReview? requestRateAppReview,
  })  : _showPaywall = showPaywall ?? AppRouter.showPaywall,
        _requestRateAppReview = requestRateAppReview ?? rateApp,
        _subscriptionState = const SubscriptionState.initial() {
    _subscriptionService.addListener(_handleSubscriptionStateChanged);
  }

  final SubscriptionService _subscriptionService;
  final PaywallProvider _paywallProvider;
  final PaidFeatureUsageRepo _paidFeatureUsageRepo;
  final CloudBackupSettingsRepo _backupSettingsRepo;
  final CloudBackupService _backupService;
  final CloudBackupScheduler _backupScheduler;
  final ShowPaywall _showPaywall;
  final RequestRateAppReview _requestRateAppReview;

  SubscriptionState _subscriptionState;
  PaywallOffering? _offering;
  PaywallPlan _selectedPlan = PaywallPlan.yearly;
  bool _isPurchasing = false;

  SubscriptionState get subscriptionState => _subscriptionState;
  PaywallOffering? get offering => _offering;
  PaywallPlan get selectedPlan => _selectedPlan;
  bool get isPro => _subscriptionState.isPro;
  bool get isLoading => _subscriptionState.isLoading;
  bool get isPurchasing => _isPurchasing;

  PaywallPackage? get selectedPackage =>
      _offering?.packageForPlan(_selectedPlan);

  Future<void> initialize() async {
    _subscriptionState = _subscriptionState.copyWith(isLoading: true);
    notifyListeners();
    await _subscriptionService.initialize();
    final state = await _subscriptionService.getSubscriptionState();
    _offering = await _paywallProvider.loadOffering();
    await _setSubscriptionState(state);
  }

  Future<void> refreshSubscription() async {
    final state = await _subscriptionService.getSubscriptionState();
    await _setSubscriptionState(state);
  }

  Future<bool> ensureAccess(
    BuildContext context,
    PremiumFeature feature,
  ) async {
    if (_subscriptionState.isPro) {
      return true;
    }

    await refreshSubscription();
    if (!context.mounted) {
      return false;
    }
    if (_subscriptionState.isPro) {
      return true;
    }

    if (feature == PremiumFeature.cloudBackup) {
      if (!_paidFeatureUsageRepo.hasReachedFreeLimit) {
        return true;
      }
      await _disableCloudBackupIfNeeded(context: context);
      if (!context.mounted) {
        return false;
      }
      await _showPaywallAndRefresh(context);
      return false;
    }

    if (!_paidFeatureUsageRepo.hasReachedFreeLimit) {
      final usageCount = await _paidFeatureUsageRepo.incrementUsage();
      await _maybeRequestHalfLimitReview(usageCount);
      if (usageCount >= Config.paidFeatureFreeUsageLimit) {
        if (!context.mounted) {
          await _disableCloudBackupIfNeeded();
          return true;
        }
        await _disableCloudBackupIfNeeded(context: context);
      }
      return true;
    }

    await _disableCloudBackupIfNeeded(context: context);
    if (!context.mounted) {
      return false;
    }

    return _showPaywallAndRefresh(context);
  }

  Future<void> _maybeRequestHalfLimitReview(int usageCount) async {
    if (_paidFeatureUsageRepo.hasRequestedHalfLimitReview) {
      return;
    }

    final reviewStartCount = (Config.paidFeatureFreeUsageLimit / 2).ceil();
    final reviewStopCount = (Config.paidFeatureFreeUsageLimit * 0.9).ceil();
    if (usageCount < reviewStartCount || usageCount >= reviewStopCount) {
      return;
    }

    bool didRequestReview;
    try {
      didRequestReview = await _requestRateAppReview();
    } catch (_) {
      didRequestReview = false;
    }

    if (didRequestReview) {
      await _paidFeatureUsageRepo.markHalfLimitReviewRequested();
    }
  }

  void selectPlan(PaywallPlan plan) {
    if (_selectedPlan == plan) {
      return;
    }
    _selectedPlan = plan;
    notifyListeners();
  }

  Future<bool> purchaseSelectedPlan() async {
    final package = selectedPackage;
    if (package == null) {
      return false;
    }

    _isPurchasing = true;
    notifyListeners();
    try {
      final state = await _paywallProvider.purchase(package);
      await _setSubscriptionState(state);
      return state.isPro;
    } finally {
      _isPurchasing = false;
      notifyListeners();
    }
  }

  Future<bool> restorePurchases() async {
    _isPurchasing = true;
    notifyListeners();
    try {
      final state = await _paywallProvider.restorePurchases();
      await _setSubscriptionState(state);
      return state.isPro;
    } finally {
      _isPurchasing = false;
      notifyListeners();
    }
  }

  void _handleSubscriptionStateChanged(SubscriptionState state) {
    _setSubscriptionState(state);
  }

  Future<void> _setSubscriptionState(SubscriptionState state) async {
    _subscriptionState = state.copyWith(isLoading: false);
    if (!_subscriptionState.isPro &&
        _paidFeatureUsageRepo.hasReachedFreeLimit) {
      await _disableCloudBackupIfNeeded();
    }
    notifyListeners();
  }

  Future<bool> _showPaywallAndRefresh(BuildContext context) async {
    final didBecomePro = await _showPaywall(context);
    if (didBecomePro) {
      return true;
    }
    await refreshSubscription();
    return _subscriptionState.isPro;
  }

  Future<void> _disableCloudBackupIfNeeded({BuildContext? context}) async {
    final backupState = _backupSettingsRepo.getState();
    if (!backupState.enabled) {
      return;
    }

    if (context != null && context.mounted) {
      try {
        await context
            .read<CloudBackupProvider>()
            .disableCloudBackupForUsageLimit();
        return;
      } on ProviderNotFoundException {
        // Some tests and entry points do not mount the backup provider.
      }
    }

    try {
      await _backupService.disconnect();
    } catch (_) {}
    await _backupScheduler.cancelDailyBackup();
    await _backupSettingsRepo.clear();
  }
}
