import 'dart:io';

import 'package:idea_vault/data/managers/local/ideas_database.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<IdeasDatabaseManager> createTestIdeasDatabaseManager() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }

  final tempDirectory =
      await Directory.systemTemp.createTemp('idea_vault_test_db_');
  return IdeasDatabaseManager(
    databasePath: path.join(
      tempDirectory.path,
      IdeasDatabaseManager.databaseName,
    ),
  );
}

Future<void> disposeTestIdeasDatabaseManager(
  IdeasDatabaseManager databaseManager,
) async {
  final databasePath = databaseManager.databasePath;
  await databaseManager.deleteDatabaseFile();

  if (databasePath == null) {
    return;
  }

  final directory = Directory(path.dirname(databasePath));
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
