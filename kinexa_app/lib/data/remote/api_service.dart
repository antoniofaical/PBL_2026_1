import '../models/run_model.dart';

abstract class ApiService {
  Future<bool> healthCheck();

  /// Catálogo de coletas (metadados). Use [limit] para as N mais recentes.
  Future<List<RunModel>> fetchRuns({int? limit, int skip = 0});

  Future<Map<String, dynamic>> uploadRun(RunModel run);
  Future<void> deleteRun(String runId);
}
