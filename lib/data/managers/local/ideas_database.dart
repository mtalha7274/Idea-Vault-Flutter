import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class IdeasDatabaseManager {
  IdeasDatabaseManager({
    this.databasePath,
  });

  static const String databaseName = 'idea_vault.db';
  static const int databaseVersion = 3;

  static const String ideasTable = 'ideas';
  static const String sectionsTable = 'idea_sections';
  static const String randomAdditionsTable = 'random_additions';

  final String? databasePath;
  Database? _database;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    final resolvedPath = databasePath ??
        path.join(
          await getDatabasesPath(),
          databaseName,
        );

    _database = await openDatabase(
      resolvedPath,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $ideasTable (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_opened_section_id TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE $sectionsTable (
            id TEXT PRIMARY KEY,
            idea_id TEXT NOT NULL,
            name TEXT NOT NULL,
            content TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            FOREIGN KEY (idea_id) REFERENCES $ideasTable(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_sections_idea_sort
          ON $sectionsTable (idea_id, sort_order)
        ''');

        await db.execute('''
          CREATE INDEX idx_ideas_updated_at
          ON $ideasTable (updated_at)
        ''');

        await _createRandomAdditionsTable(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await _createRandomAdditionsTable(db);
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE $ideasTable ADD COLUMN last_opened_section_id TEXT',
          );
        }
      },
    );

    return _database!;
  }

  Future<void> _createRandomAdditionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $randomAdditionsTable (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_random_additions_created_at
      ON $randomAdditionsTable (created_at)
    ''');
  }

  Future<void> close() async {
    if (_database == null) {
      return;
    }

    await _database!.close();
    _database = null;
  }

  Future<void> deleteDatabaseFile() async {
    final resolvedPath = databasePath ??
        path.join(
          await getDatabasesPath(),
          databaseName,
        );
    await close();
    await deleteDatabase(resolvedPath);
  }
}
