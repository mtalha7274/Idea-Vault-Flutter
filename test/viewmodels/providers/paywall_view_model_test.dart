import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:idea_vault/config/config.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_scheduler.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/core/services/premium/paywall_provider.dart';
import 'package:idea_vault/core/services/premium/subscription_service.dart';
import 'package:idea_vault/data/repositories/local/cloud_backup_settings.dart';
import 'package:idea_vault/data/repositories/local/paid_feature_usage.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/models/backup/cloud_backup_state.dart';
import 'package:idea_vault/models/premium/paywall_offering.dart';
import 'package:idea_vault/models/premium/premium_feature.dart';
import 'package:idea_vault/models/premium/subscription_state.dart';
import 'package:idea_vault/viewmodels/providers/premium/paywall_view_model.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:provider/provider.dart';

import '../../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('PaywallViewModel access policy', () {
    late MemoryLocalStorageManager storage;
    late PaidFeatureUsageRepo usageRepo;
    late CloudBackupSettingsRepo backupSettingsRepo;
    late _FakeSubscriptionService subscriptionService;
    late _FakeCloudBackupService cloudBackupService;
    late _FakeCloudBackupScheduler cloudBackupScheduler;
    late PaywallViewModel viewModel;
    late int paywallShowCount;

    setUp(() {
      storage = MemoryLocalStorageManager();
      usageRepo = PaidFeatureUsageRepo(storage);
      backupSettingsRepo = CloudBackupSettingsRepo(storage);
      subscriptionService = _FakeSubscriptionService();
      cloudBackupService = _FakeCloudBackupService();
      cloudBackupScheduler = _FakeCloudBackupScheduler();
      paywallShowCount = 0;
      viewModel = PaywallViewModel(
        subscriptionService,
        LocalPaywallProvider(subscriptionService),
        usageRepo,
        backupSettingsRepo,
        cloudBackupService,
        cloudBackupScheduler,
        showPaywall: (_) async {
          paywallShowCount += 1;
          return false;
        },
      );
    });

    testWidgets('allows the first 30 counted feature uses', (tester) async {
      final context = await _pumpPolicyTestApp(tester, viewModel, storage);

      for (var i = 0; i < Config.paidFeatureFreeUsageLimit; i += 1) {
        final hasAccess = await viewModel.ensureAccess(
          context,
          PremiumFeature.aiOrganize,
        );
        expect(hasAccess, isTrue);
      }

      expect(usageRepo.usageCount, Config.paidFeatureFreeUsageLimit);
    });

    testWidgets('gates the 31st counted feature use behind the paywall',
        (tester) async {
      for (var i = 0; i < Config.paidFeatureFreeUsageLimit; i += 1) {
        await usageRepo.incrementUsage();
      }
      final context = await _pumpPolicyTestApp(tester, viewModel, storage);

      final hasAccess = await viewModel.ensureAccess(
        context,
        PremiumFeature.aiOrganize,
      );

      expect(hasAccess, isFalse);
      expect(paywallShowCount, 1);
      expect(usageRepo.usageCount, Config.paidFeatureFreeUsageLimit);
    });

    testWidgets('does not consume usage for pro users', (tester) async {
      subscriptionService.state = const SubscriptionState.initial().copyWith(
        isPro: true,
      );
      final context = await _pumpPolicyTestApp(tester, viewModel, storage);

      final hasAccess = await viewModel.ensureAccess(
        context,
        PremiumFeature.exportPdf,
      );

      expect(hasAccess, isTrue);
      expect(usageRepo.usageCount, 0);
    });

    testWidgets('allows cloud backup while under the free limit',
        (tester) async {
      final context = await _pumpPolicyTestApp(tester, viewModel, storage);

      final hasAccess = await viewModel.ensureAccess(
        context,
        PremiumFeature.cloudBackup,
      );

      expect(hasAccess, isTrue);
      expect(usageRepo.usageCount, 0);
    });

    testWidgets('turns cloud backup off on the 30th counted use',
        (tester) async {
      for (var i = 1; i < Config.paidFeatureFreeUsageLimit; i += 1) {
        await usageRepo.incrementUsage();
      }
      await backupSettingsRepo.saveState(
        const CloudBackupState.initial().copyWith(
          enabled: true,
          autoBackupEnabled: true,
          email: 'writer@example.com',
        ),
      );
      final context = await _pumpPolicyTestApp(tester, viewModel, storage);

      final hasAccess = await viewModel.ensureAccess(
        context,
        PremiumFeature.imageTextExtraction,
      );

      expect(hasAccess, isTrue);
      expect(usageRepo.usageCount, Config.paidFeatureFreeUsageLimit);
      expect(backupSettingsRepo.getState().enabled, isFalse);
      expect(cloudBackupService.disconnectCount, 1);
      expect(cloudBackupScheduler.cancelCount, 1);
    });
  });
}

Future<BuildContext> _pumpPolicyTestApp(
  WidgetTester tester,
  PaywallViewModel viewModel,
  MemoryLocalStorageManager storage,
) async {
  late BuildContext capturedContext;
  final themeProvider = ThemeProvider(ThemeRepo(storage));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PaywallViewModel>.value(value: viewModel),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: MaterialApp(
        theme: themeProvider.baseTheme.themeData,
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return capturedContext;
}

class _FakeSubscriptionService implements SubscriptionService {
  SubscriptionState state = const SubscriptionState.initial();

  @override
  void addListener(SubscriptionStateListener listener) {}

  @override
  Future<PaywallOffering?> getOffering() async => null;

  @override
  Future<SubscriptionState> getSubscriptionState() async => state;

  @override
  Future<void> initialize() async {}

  @override
  Future<SubscriptionState> purchasePackage(PaywallPackage package) async {
    state = state.copyWith(isPro: true);
    return state;
  }

  @override
  Future<SubscriptionState> restorePurchases() async {
    state = state.copyWith(isPro: true);
    return state;
  }
}

class _FakeCloudBackupService extends CloudBackupService {
  int disconnectCount = 0;

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
  }
}

class _FakeCloudBackupScheduler extends CloudBackupScheduler {
  int cancelCount = 0;

  @override
  Future<void> cancelDailyBackup() async {
    cancelCount += 1;
  }

  @override
  Future<void> scheduleDailyBackup() async {}
}
