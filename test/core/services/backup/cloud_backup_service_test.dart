import 'package:flutter_test/flutter_test.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_store.dart';
import 'package:idea_vault/models/backup/cloud_backup_account.dart';
import 'package:idea_vault/models/backup/cloud_usage_metadata.dart';

void main() {
  group('CloudBackupService usage metadata', () {
    test('writes and restores usage metadata separately', () async {
      final store = _FakeCloudBackupStore();
      final service = CloudBackupService(androidStore: store, iosStore: store);
      final metadata = CloudUsageMetadata(
        version: CloudUsageMetadata.currentVersion,
        updatedAt: DateTime.utc(2026, 6, 25),
        usageCount: 7,
        freeUsageGrantLimit: 50,
        introSeen: true,
        halfLimitReviewRequested: false,
      );

      await service.backUpUsageMetadata(metadata, silentAuth: true);
      final restored = await service.restoreUsageMetadata(silentAuth: true);

      expect(store.usageMetadataContents, isNotNull);
      expect(restored?.usageCount, 7);
      expect(restored?.introSeen, isTrue);
      expect(store.lastUsageSilentAuth, isTrue);
    });
  });
}

class _FakeCloudBackupStore implements CloudBackupStore {
  String? usageMetadataContents;
  bool? lastUsageSilentAuth;

  @override
  Future<bool> backupExists() async => false;

  @override
  Future<CloudBackupAccount?> connect(
      {required bool forceAccountPicker}) async {
    return const CloudBackupAccount(
        email: 'test@example.com', provider: 'test');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<CloudBackupFile?> readBackup() async => null;

  @override
  Future<CloudBackupFile?> readUsageMetadata({bool silentAuth = false}) async {
    lastUsageSilentAuth = silentAuth;
    final contents = usageMetadataContents;
    if (contents == null) {
      return null;
    }
    return CloudBackupFile(contents: contents, sizeBytes: contents.length);
  }

  @override
  Future<int> writeBackup(String contents, {bool silentAuth = false}) async {
    return contents.length;
  }

  @override
  Future<int> writeUsageMetadata(
    String contents, {
    bool silentAuth = false,
  }) async {
    lastUsageSilentAuth = silentAuth;
    usageMetadataContents = contents;
    return contents.length;
  }
}
