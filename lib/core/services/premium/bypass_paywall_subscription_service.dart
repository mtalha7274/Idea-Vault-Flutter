import '../../../config/config.dart';
import '../../../models/premium/paywall_offering.dart';
import '../../../models/premium/subscription_state.dart';
import 'subscription_service.dart';

class BypassPaywallSubscriptionService implements SubscriptionService {
  BypassPaywallSubscriptionService(this._inner);

  final SubscriptionService _inner;

  bool get _shouldGrantPro => Config.debug && Config.bypassPaywall;

  SubscriptionState _withBypassProIfNeeded(SubscriptionState state) {
    if (!_shouldGrantPro || state.isPro) {
      return state;
    }
    return state.copyWith(
      isPro: true,
      source: 'debug_bypass',
      clearExpiresAt: true,
      clearActiveProductId: true,
    );
  }

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<SubscriptionState> getSubscriptionState() async {
    final state = await _inner.getSubscriptionState();
    return _withBypassProIfNeeded(state);
  }

  @override
  Future<PaywallOffering?> getOffering() => _inner.getOffering();

  @override
  Future<SubscriptionState> purchasePackage(PaywallPackage package) async {
    final state = await _inner.purchasePackage(package);
    return _withBypassProIfNeeded(state);
  }

  @override
  Future<SubscriptionState> restorePurchases() async {
    final state = await _inner.restorePurchases();
    return _withBypassProIfNeeded(state);
  }

  @override
  void addListener(SubscriptionStateListener listener) {
    _inner.addListener((state) => listener(_withBypassProIfNeeded(state)));
  }
}
