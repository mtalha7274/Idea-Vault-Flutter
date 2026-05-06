import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../viewmodels/providers/premium/paywall_view_model.dart';
import 'homepage.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool _startupPaywallHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final paywallVm = context.read<PaywallViewModel>();
      void tryShowStartupPaywall() {
        if (!mounted || _startupPaywallHandled) {
          return;
        }
        if (paywallVm.isLoading) {
          return;
        }
        _startupPaywallHandled = true;
        paywallVm.removeListener(tryShowStartupPaywall);
        if (!paywallVm.isPro) {
          unawaited(AppRouter.showPaywall(context));
        }
      }

      paywallVm.addListener(tryShowStartupPaywall);
      tryShowStartupPaywall();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Homepage();
  }
}
