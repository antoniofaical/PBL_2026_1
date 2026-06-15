import '../models/run_model.dart';

abstract class ApiService {
  Future<bool> healthCheck();
  Future<List<RunModel>> fetchRuns({int? limit, int skip = 0});
  Future<RunModel> fetchRunDetail(String runId);
  Future<String> fetchRunCsv(String runId);
  Future<Map<String, dynamic>> uploadRun(RunModel run);
  Future<void> deleteRun(String runId);
}
