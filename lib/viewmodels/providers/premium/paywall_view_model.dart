import 'package:flutter/material.dart';

import '../../../config/router/app_router.dart';
import '../../../core/services/backup/cloud_backup_scheduler.dart';
import '../../../core/services/premium/paywall_provider.dart';
import '../../../core/services/premium/subscription_service.dart';
import '../../../data/repositories/local/cloud_backup_settings.dart';
import '../../../models/premium/paywall_offering.dart';
import '../../../models/premium/premium_feature.dart';
import '../../../models/premium/subscription_state.dart';

class PaywallViewModel with ChangeNotifier {
  PaywallViewModel(
    this._subscriptionService,
    this._paywallProvider,
    this._backupSettingsRepo,
    this._backupScheduler,
  ) : _subscriptionState = const SubscriptionState.initial() {
    _subscriptionService.addListener(_handleSubscriptionStateChanged);
  }

  final SubscriptionService _subscriptionService;
  final PaywallProvider _paywallProvider;
  final CloudBackupSettingsRepo _backupSettingsRepo;
  final CloudBackupScheduler _backupScheduler;

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
    if (_subscriptionState.isPro) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    await AppRouter.showPaywall(context);
    await refreshSubscription();
    return _subscriptionState.isPro;
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
    if (!_subscriptionState.isPro) {
      await _disableAutoBackupIfNeeded();
    }
    notifyListeners();
  }

  Future<void> _disableAutoBackupIfNeeded() async {
    final backupState = _backupSettingsRepo.getState();
    if (!backupState.enabled || !backupState.autoBackupEnabled) {
      return;
    }

    await _backupSettingsRepo.saveState(
      backupState.copyWith(autoBackupEnabled: false),
    );
    await _backupScheduler.cancelDailyBackup();
  }
}
