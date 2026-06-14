import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

class SettingsDao {
  SettingsDao(this._db);

  final LocalDatabase _db;

  Future<String?> get(String key) async {
    final db = await _db.database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    final db = await _db.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String key) async {
    final db = await _db.database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
