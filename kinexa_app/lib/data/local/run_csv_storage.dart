import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// CSVs de coleta ficam em disco — nunca na coluna SQLite (limite CursorWindow ~2MB).
class RunCsvStorage {
  RunCsvStorage._();

  static Future<Directory> _runsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'run_csv'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> fileFor(String runId) async {
    final safe = runId.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return File(p.join((await _runsDir()).path, '$safe.csv'));
  }

  static Future<void> write(String runId, String csv) async {
    if (csv.isEmpty) return;
    await (await fileFor(runId)).writeAsString(csv);
  }

  static Future<String?> read(String runId) async {
    final file = await fileFor(runId);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<void> delete(String runId) async {
    final file = await fileFor(runId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> deleteAll() async {
    final dir = await _runsDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
