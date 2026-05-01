import 'package:flutter/material.dart';
import 'homepage.dart';
import 'paywall_screen.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const _paywallDelay = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showStartupPaywall();
    });
  }

  Future<void> _showStartupPaywall() async {
    await Future.delayed(_paywallDelay);
    if (!mounted) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const PaywallScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Homepage();
  }
}
