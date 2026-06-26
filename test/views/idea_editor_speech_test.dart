import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_scheduler.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/core/services/note_lock_auth_service.dart';
import 'package:idea_vault/core/services/note_lock_biometric_service.dart';
import 'package:idea_vault/core/services/premium/paywall_provider.dart';
import 'package:idea_vault/core/services/premium/subscription_service.dart';
import 'package:idea_vault/data/repositories/local/cloud_backup_settings.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/data/repositories/local/paid_feature_usage.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/data/repositories/remote/idea_organization_repository.dart';
import 'package:idea_vault/injection_container.dart';
import 'package:idea_vault/models/backup/cloud_backup_account.dart';
import 'package:idea_vault/models/premium/paywall_offering.dart';
import 'package:idea_vault/models/premium/subscription_state.dart';
import 'package:idea_vault/main.dart' show navigatorKey;
import 'package:idea_vault/viewmodels/providers/ideas_provider.dart';
import 'package:idea_vault/viewmodels/providers/premium/paywall_view_model.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/views/idea_editor.dart';
import 'package:idea_vault/widgets/speech_to_text_mic_fab.dart';
import 'package:provider/provider.dart';

import '../helpers/in_memory_ideas_repo.dart';
import '../helpers/memory_local_storage.dart';

const _speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('IdeaEditor speech-to-text', () {
    late MemoryLocalStorageManager storage;
    late IdeasProvider ideasProvider;
    late ThemeProvider themeProvider;
    late PaywallViewModel paywallViewModel;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      if (!sl.isRegistered<IdeaOrganizationRepository>()) {
        sl.registerSingleton<IdeaOrganizationRepository>(
          _FakeIdeaOrganizationRepository(),
        );
      }

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_speechChannel, (call) async {
        switch (call.method) {
          case 'initialize':
            return true;
          case 'listen':
            return true;
          case 'has_permission':
            return true;
          case 'stop':
          case 'cancel':
            return null;
          default:
            return null;
        }
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_permissionChannel, (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
            return 1;
          case 'requestPermissions':
            final permissions = (call.arguments as List).cast<int>();
            return {for (final permission in permissions) permission: 1};
          default:
            return null;
        }
      });
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_speechChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_permissionChannel, null);
    });

    setUp(() async {
      storage = MemoryLocalStorageManager();
      themeProvider = ThemeProvider(ThemeRepo(storage));
      ideasProvider = IdeasProvider(
        InMemoryIdeasRepo(),
        IdeaEditorStateRepo(storage),
      );
      await ideasProvider.ensureLoaded();

      final paidFeatureUsageRepo = PaidFeatureUsageRepo(storage);
      final subscriptionService = _FakeSubscriptionService(
        state: const SubscriptionState.initial().copyWith(isPro: true),
      );
      paywallViewModel = PaywallViewModel(
        subscriptionService,
        LocalPaywallProvider(subscriptionService),
        paidFeatureUsageRepo,
        CloudBackupSettingsRepo(storage),
        _FakeCloudBackupService(),
        _FakeCloudBackupScheduler(),
        showPaywall: (_) async => false,
        requestRateAppReview: () async => false,
      );

      final noteLockAuthService = NoteLockAuthService();
      final noteLockBiometricService = NoteLockBiometricService();
      if (sl.isRegistered<NoteLockAuthService>()) {
        await sl.unregister<NoteLockAuthService>();
      }
      if (sl.isRegistered<NoteLockBiometricService>()) {
        await sl.unregister<NoteLockBiometricService>();
      }
      sl.registerSingleton<NoteLockAuthService>(noteLockAuthService);
      sl.registerSingleton<NoteLockBiometricService>(noteLockBiometricService);
    });

    tearDown(() async {
      if (sl.isRegistered<NoteLockAuthService>()) {
        await sl.unregister<NoteLockAuthService>();
      }
      if (sl.isRegistered<NoteLockBiometricService>()) {
        await sl.unregister<NoteLockBiometricService>();
      }
    });

    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<IdeasProvider>.value(value: ideasProvider),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
            ChangeNotifierProvider<PaywallViewModel>.value(
              value: paywallViewModel,
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: themeProvider.baseTheme.themeData,
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  viewInsets: EdgeInsets.zero,
                ),
                child: child!,
              );
            },
            home: const IdeaEditorScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> disposeEditor(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('prewarms speech engine after editor opens', (tester) async {
      await pumpEditor(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('idea-editor-mic-fab')), findsOneWidget);
      await disposeEditor(tester);
    });

    testWidgets('binds mic fab with idle speech state on editor open',
        (tester) async {
      await pumpEditor(tester);

      final micFab = tester.widget<SpeechToTextMicFab>(
        find.byType(SpeechToTextMicFab),
      );
      expect(micFab.isActivating, isFalse);
      expect(micFab.isListening, isFalse);

      await disposeEditor(tester);
    });
  });
}

class _FakeCloudBackupService extends CloudBackupService {
  @override
  Future<bool> backupExists() async => false;

  @override
  Future<CloudBackupAccount?> connect({bool forceAccountPicker = false}) async {
    return const CloudBackupAccount(
      email: 'writer@example.com',
      provider: 'test',
    );
  }

  @override
  Future<void> disconnect() async {}
}

class _FakeCloudBackupScheduler extends CloudBackupScheduler {
  @override
  Future<void> cancelDailyBackup() async {}

  @override
  Future<void> scheduleDailyBackup() async {}
}

class _FakeSubscriptionService implements SubscriptionService {
  _FakeSubscriptionService({required this.state});

  SubscriptionState state;

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

class _FakeIdeaOrganizationRepository implements IdeaOrganizationRepository {
  @override
  Future<String> organizeIdea(String sectionContent) async {
    return sectionContent;
  }
}
