import '../../../models/premium/paywall_offering.dart';
import '../../../models/premium/subscription_state.dart';
import 'subscription_service.dart';

abstract class PaywallProvider {
  Future<PaywallOffering?> loadOffering();
  Future<SubscriptionState> purchase(PaywallPackage package);
  Future<SubscriptionState> restorePurchases();
}

class LocalPaywallProvider implements PaywallProvider {
  const LocalPaywallProvider(this._subscriptionService);

  final SubscriptionService _subscriptionService;

  @override
  Future<PaywallOffering?> loadOffering() {
    return _subscriptionService.getOffering();
  }

  @override
  Future<SubscriptionState> purchase(PaywallPackage package) {
    return _subscriptionService.purchasePackage(package);
  }

  @override
  Future<SubscriptionState> restorePurchases() {
    return _subscriptionService.restorePurchases();
  }
}
