import '../../../models/premium/paywall_offering.dart';
import '../../../models/premium/subscription_state.dart';

typedef SubscriptionStateListener = void Function(SubscriptionState state);

abstract class SubscriptionService {
  Future<void> initialize();
  Future<SubscriptionState> getSubscriptionState();
  Future<PaywallOffering?> getOffering();
  Future<SubscriptionState> purchasePackage(PaywallPackage package);
  Future<SubscriptionState> restorePurchases();
  void addListener(SubscriptionStateListener listener);
}
