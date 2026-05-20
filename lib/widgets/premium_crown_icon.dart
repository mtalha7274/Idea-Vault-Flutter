import 'package:flutter/material.dart';

import '../core/constants/app_assets.dart';

class PremiumCrownIcon extends StatelessWidget {
  const PremiumCrownIcon({
    super.key,
    this.size = 24,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.crown,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
