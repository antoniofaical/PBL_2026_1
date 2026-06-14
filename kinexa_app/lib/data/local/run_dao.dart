import 'package:sqflite/sqflite.dart';

import '../../core/constants/enums.dart';
import '../models/event_model.dart';
import '../models/run_model.dart';
import 'local_database.dart';

class RunDao {
  RunDao(this._db);

  final LocalDatabase _db;

  Future<void> upsertRun(RunModel run) async {
    final db = await _db.database;
    await db.insert('runs', run.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete('events', where: 'run_id = ?', whereArgs: [run.runId]);
    for (final event in run.events) {
      await db.insert('events', {
        'run_id': run.runId,
        'timestamp_ms': event.timestampMs,
        'description': event.description,
      });
    }
  }

  Future<RunModel?> getRun(String runId) async {
    final db = await _db.database;
    final rows = await db.query('runs', where: 'run_id = ?', whereArgs: [runId]);
    if (rows.isEmpty) return null;
    final events = await _eventsForRun(db, runId);
    return RunModel.fromMap(rows.first, events: events);
  }

  Future<List<RunModel>> getAllRuns() async {
    final db = await _db.database;
    final rows = await db.query('runs', orderBy: 'created_at DESC');
    final runs = <RunModel>[];
    for (final row in rows) {
      final runId = row['run_id'] as String;
      final events = await _eventsForRun(db, runId);
      runs.add(RunModel.fromMap(row, events: events));
    }
    return runs;
  }

  Future<List<RunModel>> getPendingRuns() async {
    final all = await getAllRuns();
    return all
        .where((r) =>
            r.syncStatus == SyncStatus.localOnly ||
            r.syncStatus == SyncStatus.syncFailed)
        .toList();
  }

  Future<void> deleteRun(String runId) async {
    final db = await _db.database;
    await db.delete('events', where: 'run_id = ?', whereArgs: [runId]);
    await db.delete('runs', where: 'run_id = ?', whereArgs: [runId]);
  }

  Future<void> deleteAllRuns() async {
    final db = await _db.database;
    await db.delete('events');
    await db.delete('runs');
  }

  Future<int> countDistinctAthletes() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(DISTINCT athlete) as c FROM runs');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<EventModel>> _eventsForRun(dynamic db, String runId) async {
    final rows = await db.query(
      'events',
      where: 'run_id = ?',
      whereArgs: [runId],
      orderBy: 'timestamp_ms ASC',
    );
    return List<EventModel>.from(rows.map((r) => EventModel.fromMap(r)));
  }
}
