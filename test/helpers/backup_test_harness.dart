import 'dart:io';

import 'package:idea_vault/core/services/backup/cloud_backup_scheduler.dart';
import 'package:idea_vault/core/services/backup/cloud_backup_service.dart';
import 'package:idea_vault/core/services/backup/initial_cloud_auth_coordinator.dart';
import 'package:idea_vault/core/services/backup/restore_safety_copy_store.dart';
import 'package:idea_vault/data/repositories/local/app_install_state.dart';
import 'package:idea_vault/data/repositories/local/backup_device_identity.dart';
import 'package:idea_vault/data/repositories/local/cloud_backup_settings.dart';
import 'package:idea_vault/data/repositories/local/idea_editor_state.dart';
import 'package:idea_vault/models/backup/cloud_backup_entry.dart';
import 'package:idea_vault/models/backup/cloud_backup_snapshot.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/models/random_addition.dart';
import 'package:idea_vault/viewmodels/providers/backup/cloud_backup_provider.dart';

import 'fake_cloud_backup_store.dart';
import 'in_memory_local_vault_repo.dart';
import 'memory_local_storage.dart';

class FakeCloudBackupScheduler extends CloudBackupScheduler {
  int scheduleCount = 0;
  int cancelCount = 0;

  @override
  Future<void> scheduleDailyBackup() async {
    scheduleCount += 1;
  }

  @override
  Future<void> cancelDailyBackup() async {
    cancelCount += 1;
  }
}

Idea backupTestIdea(
  String id, {
  String? title,
  DateTime? updatedAt,
  String content = '',
  bool isLocked = false,
  String? sectionId,
}) {
  final time = updatedAt ?? DateTime.utc(2026, 1, 1);
  return Idea(
    id: id,
    title: title ?? 'Idea $id',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: time,
    isLocked: isLocked,
    lastOpenedSectionId: sectionId ?? 'section-$id',
    sections: [
      IdeaSection(
        id: sectionId ?? 'section-$id',
        name: 'Idea',
        content: content,
      ),
    ],
  );
}

RandomAddition backupTestNote(String id, {String? content}) {
  return RandomAddition(
    id: id,
    content: content ?? 'Note $id',
    createdAt: DateTime.utc(2026, 1, 2),
  );
}

String backupTestFileName(
  CloudBackupSnapshot snapshot, {
  required String deviceShortId,
}) {
  return CloudBackupEntry.buildFileName(
    formatVersion: snapshot.version,
    createdAt: snapshot.createdAt,
    deviceShortId: deviceShortId,
    ideaCount: snapshot.ideaCount,
    randomAdditionCount: snapshot.randomAdditionCount,
    deviceName: snapshot.deviceName,
  );
}

String putBackupFile(
  FakeCloudBackupStore store, {
  required List<Idea> ideas,
  List<RandomAddition> notes = const [],
  String deviceId = 'ffffffff00000000ffffffff00000000',
  String deviceName = 'Pixel 8',
  DateTime? createdAt,
  DateTime? modifiedAt,
}) {
  final snapshot = CloudBackupSnapshot.fromContent(
    ideas: ideas,
    randomAdditions: notes,
    deviceId: deviceId,
    deviceName: deviceName,
    appVersion: '1.0.0+1',
    createdAt: createdAt ?? DateTime.utc(2026, 11, 2, 9),
  );
  final name = backupTestFileName(
    snapshot,
    deviceShortId: deviceId.substring(0, 8),
  );
  store.putFile(name, snapshot.encode(), modifiedAt: modifiedAt);
  return name;
}

class BackupTestHarness {
  BackupTestHarness({
    this.isIOS = false,
    DateTime Function()? clock,
    Directory? safetyDirectory,
  })  : clock = clock ?? DateTime.now,
        storage = MemoryLocalStorageManager(),
        store = FakeCloudBackupStore(clock: clock),
        vault = InMemoryLocalVaultRepo(),
        scheduler = FakeCloudBackupScheduler(),
        _safetyDirectory = safetyDirectory {
    settingsRepo = CloudBackupSettingsRepo(storage);
    identityRepo = BackupDeviceIdentityRepo(storage);
    service = CloudBackupService(
      androidStore: store,
      iosStore: store,
      useICloud: isIOS,
    );
  }

  final bool isIOS;
  final DateTime Function() clock;
  final MemoryLocalStorageManager storage;
  final FakeCloudBackupStore store;
  final InMemoryLocalVaultRepo vault;
  final FakeCloudBackupScheduler scheduler;
  final Directory? _safetyDirectory;
  late final CloudBackupSettingsRepo settingsRepo;
  late final BackupDeviceIdentityRepo identityRepo;
  late final CloudBackupService service;

  Future<String> ensureIdentity({String name = 'Test Phone'}) async {
    final identity = await identityRepo.ensure(deviceName: name);
    return identity.shortId;
  }

  CloudBackupProvider buildProvider({RestoreSafetyCopyStore? safetyStore}) {
    final directory = _safetyDirectory;
    return CloudBackupProvider(
      settingsRepo,
      service,
      scheduler,
      InitialCloudAuthCoordinator(AppInstallStateRepo(storage)),
      localVaultRepo: vault,
      safetyCopyStore: safetyStore ??
          (directory == null
              ? null
              : RestoreSafetyCopyStore(
                  directory: () async => directory,
                  clock: clock,
                )),
      deviceIdentityRepo: identityRepo,
      editorStateRepo: IdeaEditorStateRepo(storage),
      isIOS: isIOS,
      clock: clock,
      deviceName: 'Test Phone',
      appVersion: '2.0.0+5',
      copyTitle: (title, fromBackup) =>
          fromBackup ? '$title (from backup)' : '$title (from this device)',
    );
  }
}
