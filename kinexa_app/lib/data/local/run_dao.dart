import 'package:sqflite/sqflite.dart';

import '../../core/constants/enums.dart';
import '../models/event_model.dart';
import '../models/run_model.dart';
import 'local_database.dart';
import 'run_csv_storage.dart';

class RunDao {
  RunDao(this._db);

  final LocalDatabase _db;

  /// Colunas listadas — sem `csv_content` (evita CursorWindow overflow).
  static const _listColumns = [
    'run_id',
    'device_id',
    'datetime',
    'athlete',
    'activity',
    'environment',
    'notes',
    'csv_path',
    'sample_count',
    'created_at',
    'sync_status',
  ];

  static bool _needsCsvFile(RunModel run) =>
      run.syncStatus == SyncStatus.localOnly ||
      run.syncStatus == SyncStatus.syncFailed ||
      run.syncStatus == SyncStatus.syncing;

  Future<void> upsertRun(RunModel run) async {
    final db = await _db.database;
    final csv = run.csvContent;

    if (_needsCsvFile(run) && csv != null && csv.isNotEmpty) {
      await RunCsvStorage.write(run.runId, csv);
    } else {
      await RunCsvStorage.delete(run.runId);
    }

    final map = run.toMap();
    map['csv_content'] = null;

    await db.insert('runs', map, conflictAlgorithm: ConflictAlgorithm.replace);
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
    final rows = await db.query(
      'runs',
      columns: _listColumns,
      where: 'run_id = ?',
      whereArgs: [runId],
    );
    if (rows.isEmpty) return null;
    final events = await _eventsForRun(db, runId);
    var run = RunModel.fromMap(rows.first, events: events);

    if (_needsCsvFile(run) &&
        (run.csvContent == null || run.csvContent!.isEmpty)) {
      final csv = await RunCsvStorage.read(runId);
      if (csv != null) {
        run = run.copyWith(csvContent: csv);
      }
    }
    return run;
  }

  Future<List<RunModel>> getAllRuns() async {
    final db = await _db.database;
    final rows = await db.query(
      'runs',
      columns: _listColumns,
      orderBy: 'created_at DESC',
    );
    final runs = <RunModel>[];
    for (final row in rows) {
      final runId = row['run_id'] as String;
      final events = await _eventsForRun(db, runId);
      runs.add(RunModel.fromMap(row, events: events));
    }
    return runs;
  }

  Future<List<RunModel>> getPendingRuns() async {
    final summaries = (await getAllRuns()).where(
      (r) =>
          r.syncStatus == SyncStatus.localOnly ||
          r.syncStatus == SyncStatus.syncFailed,
    );
    final pending = <RunModel>[];
    for (final summary in summaries) {
      final full = await getRun(summary.runId);
      if (full != null) pending.add(full);
    }
    return pending;
  }

  Future<void> deleteRun(String runId) async {
    final db = await _db.database;
    await db.delete('events', where: 'run_id = ?', whereArgs: [runId]);
    await db.delete('runs', where: 'run_id = ?', whereArgs: [runId]);
    await RunCsvStorage.delete(runId);
  }

  Future<void> deleteAllRuns() async {
    final db = await _db.database;
    await db.delete('events');
    await db.delete('runs');
    await RunCsvStorage.deleteAll();
  }

  Future<int> countDistinctAthletes() async {
    final db = await _db.database;
    final result =
        await db.rawQuery('SELECT COUNT(DISTINCT athlete) as c FROM runs');
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
