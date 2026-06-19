import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/enums.dart';
import '../local/settings_dao.dart';
import '../models/run_model.dart';
import '../remote/api_service.dart';
import 'auth_repository.dart';
import 'run_repository.dart';

class SyncAllResult {
  const SyncAllResult({
    required this.skipped,
    required this.online,
    required this.uploaded,
    this.pruned = 0,
    this.error,
    this.authRequired = false,
    this.message,
  });

  final bool skipped;
  final bool online;
  final int uploaded;
  final int pruned;
  final Object? error;
  final bool authRequired;
  final String? message;

  bool get success => online && error == null && !authRequired;
}

class SyncRepository {
  SyncRepository(this._api, this._runRepo, this._settings, this._auth);

  final ApiService _api;
  final RunRepository _runRepo;
  final SettingsDao _settings;
  final AuthRepository _auth;

  bool _isSyncing = false;
  final Set<String> _uploadingRunIds = {};
  Future<SyncAllResult>? _activeSync;

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[Kinexa Sync] $message');
    }
  }

  Future<bool> isServerOnline() async {
    try {
      return await _api.healthCheck();
    } catch (_) {
      return false;
    }
  }

  /// Sincronização completa: health → sessão → pull → upload.
  Future<SyncAllResult> syncAll({bool skipHealthCheck = false}) {
    if (_activeSync != null) {
      _log('syncAll aguardando sync em andamento');
      return _activeSync!;
    }

    final future = _syncAllImpl(skipHealthCheck: skipHealthCheck).whenComplete(() {
      _activeSync = null;
    });
    _activeSync = future;
    return future;
  }

  Future<SyncAllResult> _syncAllImpl({bool skipHealthCheck = false}) async {
    _isSyncing = true;
    try {
      if (!skipHealthCheck) {
        final online = await isServerOnline();
        if (!online) {
          return const SyncAllResult(
            skipped: false,
            online: false,
            uploaded: 0,
            message: 'Health check falhou antes do sync.',
          );
        }
      }

      final session = await _auth.restoreSession();
      if (session == null) {
        _log('syncAll abortado — sessão ausente');
        return const SyncAllResult(
          skipped: false,
          online: true,
          uploaded: 0,
          authRequired: true,
        );
      }

      final pull = await pullRemoteRuns();
      final uploaded = await _uploadPendingRuns();
      return SyncAllResult(
        skipped: false,
        online: true,
        uploaded: uploaded,
        pruned: pull.pruned,
        message: pull.warning,
      );
    } catch (e, st) {
      _log('syncAll falhou: $e\n$st');
      if (e is DioException) {
        if (e.type == DioExceptionType.cancel) {
          return const SyncAllResult(
            skipped: false,
            online: true,
            uploaded: 0,
            authRequired: true,
          );
        }
        if (e.response?.statusCode == 401) {
          return const SyncAllResult(
            skipped: false,
            online: true,
            uploaded: 0,
            authRequired: true,
          );
        }
      }
      return SyncAllResult(
        skipped: false,
        online: true,
        uploaded: 0,
        error: e,
        message: e.toString(),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Após `fetchRuns` OK, falhas locais não abortam o sync.
  Future<({int pruned, String? warning})> pullRemoteRuns() async {
    final limit = AppConstants.syncRemotePullLimit; // metadata-only
    final remoteRuns = await _api.fetchRuns(limit: limit);

    _log('pull remoto OK (metadata-only): ${remoteRuns.length} runs (limit=$limit)');

    var pruned = 0;
    String? warning;

    final remoteIds = remoteRuns.map((r) => r.runId).toSet();

    try {
      for (final summary in remoteRuns) {
        try {
          // Preserve eventos locais se este payload de metadados vier sem `events`.
          final existing = await _runRepo.getRun(summary.runId);
          final eventsToKeep = summary.events.isNotEmpty
              ? summary.events
              : (existing?.events ?? const []);

          await _saveLocalSafe(
            summary.copyWith(
              syncStatus: SyncStatus.synced,
              clearCsvContent: true,
              events: eventsToKeep,
            ),
            onWarning: (w) => warning ??= w,
          );
        } catch (e) {
          final msg = 'Salvar metadados ${summary.runId}: $e';
          warning ??= msg;
          _log(msg);
        }
      }

      final localRuns = await _runRepo.getLocalRuns();
      for (final local in localRuns) {
        if (local.syncStatus == SyncStatus.synced &&
            !remoteIds.contains(local.runId)) {
          try {
            await _runRepo.deleteLocalRun(local.runId);
            pruned++;
          } catch (e) {
            final msg = 'Remover cópia local ${local.runId}: $e';
            warning ??= msg;
            _log(msg);
          }
        }
      }

      try {
        await _settings.set(
          AppConstants.lastSyncKey,
          DateTime.now().toIso8601String(),
        );
      } catch (e) {
        final msg = 'Não foi possível gravar last_sync: $e';
        warning ??= msg;
        _log(msg);
      }
    } catch (e, st) {
      warning ??= 'Persistência local: $e';
      _log('$warning\n$st');
    }

    return (pruned: pruned, warning: warning);
  }

  Future<bool> _saveLocalSafe(
    RunModel run, {
    void Function(String message)? onWarning,
  }) async {
    try {
      await _runRepo.saveLocal(run);
      return true;
    } catch (e) {
      final msg = 'saveLocal ${run.runId}: $e';
      onWarning?.call(msg);
      _log(msg);
      return false;
    }
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
      try {
        await _settings.set(
          AppConstants.lastSyncKey,
          DateTime.now().toIso8601String(),
        );
      } catch (_) {}
    }
    return ok;
  }

  Future<void> clearLocalCache() async {
    await _runRepo.clearLocalRuns();
    await _settings.delete(AppConstants.lastSyncKey);
  }

  Future<String?> lastSync() => _settings.get(AppConstants.lastSyncKey);
}
