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
      unawaited(_scheduleStartupPaywall());
    });
  }

  Future<void> _waitForPaywallIdle(PaywallViewModel vm) async {
    if (!vm.isLoading) {
      return;
    }
    final completer = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (!vm.isLoading) {
        vm.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    };
    vm.addListener(listener);
    await completer.future;
  }

  Future<void> _scheduleStartupPaywall() async {
    if (!mounted) {
      return;
    }
    final paywallVm = context.read<PaywallViewModel>();
    await Future.wait<void>([
      Future<void>.delayed(const Duration(milliseconds: 1000)),
      _waitForPaywallIdle(paywallVm),
    ]);
    if (!mounted || _startupPaywallHandled) {
      return;
    }
    _startupPaywallHandled = true;
    if (!paywallVm.isPro) {
      unawaited(AppRouter.showPaywall(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Homepage();
  }
}
