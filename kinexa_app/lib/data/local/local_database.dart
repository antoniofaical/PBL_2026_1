import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

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
      version: 1,
      onCreate: (db, version) async {
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
      },
    );
  }
}
