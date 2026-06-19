import '../../core/constants/enums.dart';
import '../local/run_dao.dart';
import '../models/run_model.dart';
import '../remote/api_service.dart';

class RunRepository {
  RunRepository(this._dao, this._api);

  final RunDao _dao;
  final ApiService _api;

  Future<List<RunModel>> getLocalRuns() => _dao.getAllRuns();

  Future<RunModel?> getRun(String runId) => _dao.getRun(runId);

  Future<int> countAthletes() => _dao.countDistinctAthletes();

  Future<List<RunModel>> getPendingRuns() => _dao.getPendingRuns();

  Future<void> saveLocal(RunModel run) => _dao.upsertRun(run);

  Future<void> deleteLocalRun(String runId) => _dao.deleteRun(runId);

  Future<void> clearLocalRuns() => _dao.deleteAllRuns();

  Future<bool> uploadRun(RunModel run) async {
    final updated = run.copyWith(syncStatus: SyncStatus.syncing);
    await _dao.upsertRun(updated);
    try {
      final result = await _api.uploadRun(run);
      final status = result['status'] as String?;
      if (status == 'created' ||
          status == 'already_exists' ||
          status == 'ok') {
        await _dao.upsertRun(
          run.copyWith(
            syncStatus: SyncStatus.synced,
            clearCsvContent: true,
            sampleCount: result['sample_count'] as int? ?? run.sampleCount,
          ),
        );
        return true;
      }
      await _dao.upsertRun(run.copyWith(syncStatus: SyncStatus.syncFailed));
      return false;
    } catch (_) {
      await _dao.upsertRun(run.copyWith(syncStatus: SyncStatus.syncFailed));
      return false;
    }
  }

  Future<void> deleteRun(String runId) async {
    try {
      await _api.deleteRun(runId);
    } catch (_) {
      // remove local mesmo se remoto falhar
    }
    await deleteLocalRun(runId);
  }
}
