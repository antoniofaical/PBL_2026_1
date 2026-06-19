import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'run_csv_storage.dart';

class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  static const int _version = 3;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'kinexa.db'),
      version: _version,
      onCreate: _createSchema,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Remove blobs grandes da tabela — CSV passa a ficar só em arquivo.
          await db.execute('UPDATE runs SET csv_content = NULL');
        }
        if (oldVersion < 3) {
          // Coletas remotas são metadata-only — CSV só para upload pendente.
          final rows = await db.query(
            'runs',
            columns: ['run_id', 'sync_status'],
          );
          for (final row in rows) {
            if (row['sync_status'] == 'synced') {
              await RunCsvStorage.delete(row['run_id'] as String);
            }
          }
        }
      },
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE runs (
        run_id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        datetime TEXT NOT NULL,
        athlete TEXT NOT NULL,
        activity INTEGER NOT NULL,
        environment INTEGER NOT NULL,
        notes TEXT,
        csv_path TEXT,
        csv_content TEXT,
        sample_count INTEGER,
        created_at TEXT,
        sync_status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id TEXT NOT NULL,
        timestamp_ms INTEGER NOT NULL,
        description TEXT,
        FOREIGN KEY(run_id) REFERENCES runs(run_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }
}
