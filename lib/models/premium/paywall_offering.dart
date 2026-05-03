enum PaywallPlan {
  yearly,
  monthly,
}

class PaywallPackage {
  const PaywallPackage({
    required this.id,
    required this.productId,
    required this.priceLabel,
    this.trialLabel,
  });

  final String id;
  final String productId;
  final String priceLabel;
  final String? trialLabel;
}

class PaywallOffering {
  const PaywallOffering({
    required this.yearly,
    required this.monthly,
  });

  final PaywallPackage? yearly;
  final PaywallPackage? monthly;

  PaywallPackage? packageForPlan(PaywallPlan plan) {
    switch (plan) {
      case PaywallPlan.yearly:
        return yearly;
      case PaywallPlan.monthly:
        return monthly;
    }
  }
}
