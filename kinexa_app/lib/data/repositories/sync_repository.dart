import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/enums.dart';
import '../local/settings_dao.dart';
import '../remote/api_service.dart';
import 'run_repository.dart';

class SyncAllResult {
  const SyncAllResult({
    required this.skipped,
    required this.online,
    required this.uploaded,
    this.pruned = 0,
    this.error,
  });

  final bool skipped;
  final bool online;
  final int uploaded;
  final int pruned;
  final Object? error;

  bool get success => !skipped && online && error == null;
}

class SyncRepository {
  SyncRepository(this._api, this._runRepo, this._settings);

  final ApiService _api;
  final RunRepository _runRepo;
  final SettingsDao _settings;

  bool _isSyncing = false;
  final Set<String> _uploadingRunIds = {};

  Future<bool> isServerOnline() async {
    try {
      return await _api.healthCheck();
    } catch (_) {
      return false;
    }
  }

  /// Sincronização completa: health → reconciliar com servidor → upload pendentes.
  Future<SyncAllResult> syncAll() async {
    if (_isSyncing) {
      if (kDebugMode) {
        debugPrint('[Kinexa Sync] syncAll ignorado — já em andamento');
      }
      return const SyncAllResult(
        skipped: true,
        online: false,
        uploaded: 0,
      );
    }

    _isSyncing = true;
    try {
      final online = await isServerOnline();
      if (!online) {
        return const SyncAllResult(
          skipped: false,
          online: false,
          uploaded: 0,
        );
      }

      final pruned = await pullRemoteRuns();
      final uploaded = await _uploadPendingRuns();
      return SyncAllResult(
        skipped: false,
        online: true,
        uploaded: uploaded,
        pruned: pruned,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Kinexa Sync] syncAll falhou: $e\n$st');
      }
      return SyncAllResult(
        skipped: false,
        online: true,
        uploaded: 0,
        error: e,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Baixa runs do servidor (fonte de verdade) e remove cópias locais órfãs.
  /// Retorna quantas coletas locais sincronizadas foram removidas.
  Future<int> pullRemoteRuns() async {
    final remoteRuns = await _api.fetchRuns();
    final remoteIds = remoteRuns.map((r) => r.runId).toSet();

    var pruned = 0;
    final localRuns = await _runRepo.getLocalRuns();
    for (final local in localRuns) {
      if (remoteIds.contains(local.runId)) continue;

      final isGhost = local.syncStatus == SyncStatus.synced ||
          local.syncStatus == SyncStatus.syncing;
      if (isGhost) {
        await _runRepo.deleteLocalRun(local.runId);
        pruned++;
        if (kDebugMode) {
          debugPrint('[Kinexa Sync] removida cópia local órfã: ${local.runId}');
        }
      }
    }

    for (final summary in remoteRuns) {
      try {
        final detail = await _api.fetchRunDetail(summary.runId);
        String? csv;
        try {
          csv = await _api.fetchRunCsv(summary.runId);
        } catch (_) {}
        await _runRepo.saveLocal(
          detail.copyWith(csvContent: csv, syncStatus: SyncStatus.synced),
        );
      } catch (_) {
        await _runRepo.saveLocal(
          summary.copyWith(syncStatus: SyncStatus.synced),
        );
      }
    }

    await _settings.set(
      AppConstants.lastSyncKey,
      DateTime.now().toIso8601String(),
    );
    return pruned;
  }

  Future<int> syncPendingUploads() async {
    if (_isSyncing) return 0;
    if (!await isServerOnline()) return 0;
    return _uploadPendingRuns();
  }

  Future<int> _uploadPendingRuns() async {
    final pending = await _runRepo.getPendingRuns();
    var ok = 0;
    for (final run in pending) {
      if (_uploadingRunIds.contains(run.runId)) continue;
      _uploadingRunIds.add(run.runId);
      try {
        if (await _runRepo.uploadRun(run)) ok++;
      } finally {
        _uploadingRunIds.remove(run.runId);
      }
    }
    if (ok > 0) {
      await _settings.set(
        AppConstants.lastSyncKey,
        DateTime.now().toIso8601String(),
      );
    }
    return ok;
  }

  Future<void> clearLocalCache() async {
    await _runRepo.clearLocalRuns();
    await _settings.delete(AppConstants.lastSyncKey);
  }

  Future<String?> lastSync() => _settings.get(AppConstants.lastSyncKey);
}
