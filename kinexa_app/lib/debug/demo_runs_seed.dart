import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/enums.dart';
import '../data/local/settings_dao.dart';
import '../data/models/run_model.dart';
import '../data/repositories/run_repository.dart';

/// Desative com `--dart-define=SKIP_DEMO_SEED=true` para validar empty state.
const _skipDemoSeed = bool.fromEnvironment('SKIP_DEMO_SEED');

/// Insere coletas de demonstração no SQLite local quando o banco está vazio.
/// Ativo apenas com banco vazio — útil para validar a Home populada contra o Figma.
Future<void> seedDemoRunsIfEmpty(
  RunRepository repo,
  SettingsDao settings,
) async {
  if (_skipDemoSeed) return;

  debugPrint('[demo_seed] seedDemoRunsIfEmpty()');

  final existing = await repo.getLocalRuns();
  if (existing.isNotEmpty) {
    debugPrint('[demo_seed] DB já tem ${existing.length} coletas — skip.');
    return;
  }

  debugPrint('[demo_seed] Inserindo 8 coletas de demonstração…');

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final runs = <RunModel>[
    RunModel(
      runId: 'demo-001',
      deviceId: 'demo-device',
      datetime: DateTime(today.year, today.month, today.day, 10, 45).toIso8601String(),
      athlete: 'João Silva',
      activity: Activity.marcha.value,
      environment: Environment.pistaExterna.value,
      createdAt: DateTime(today.year, today.month, today.day, 10, 45).toIso8601String(),
      syncStatus: SyncStatus.localOnly,
      sampleCount: 1200,
    ),
    RunModel(
      runId: 'demo-002',
      deviceId: 'demo-device',
      datetime: DateTime(yesterday.year, yesterday.month, yesterday.day, 16, 30)
          .toIso8601String(),
      athlete: 'Maria Oliveira',
      activity: Activity.marcha.value,
      environment: Environment.esteira.value,
      createdAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 16, 30)
          .toIso8601String(),
      syncStatus: SyncStatus.synced,
      sampleCount: 980,
    ),
    RunModel(
      runId: 'demo-003',
      deviceId: 'demo-device',
      datetime: DateTime(2026, 5, 30, 9, 15).toIso8601String(),
      athlete: 'José Santos',
      activity: Activity.corrida.value,
      environment: Environment.esteira.value,
      createdAt: DateTime(2026, 5, 30, 9, 15).toIso8601String(),
      syncStatus: SyncStatus.synced,
      sampleCount: 2100,
    ),
    RunModel(
      runId: 'demo-004',
      deviceId: 'demo-device',
      datetime: DateTime(2026, 5, 20, 14, 0).toIso8601String(),
      athlete: 'Ana Costa',
      activity: Activity.marcha.value,
      environment: Environment.esteira.value,
      createdAt: DateTime(2026, 5, 20, 14, 0).toIso8601String(),
      syncStatus: SyncStatus.synced,
      sampleCount: 850,
    ),
    RunModel(
      runId: 'demo-005',
      deviceId: 'demo-device',
      datetime: DateTime(2026, 5, 20, 11, 30).toIso8601String(),
      athlete: 'Francisco Oliveira',
      activity: Activity.marcha.value,
      environment: Environment.esteira.value,
      createdAt: DateTime(2026, 5, 20, 11, 30).toIso8601String(),
      syncStatus: SyncStatus.synced,
      sampleCount: 760,
    ),
    RunModel(
      runId: 'demo-006',
      deviceId: 'demo-device',
      datetime: DateTime(2026, 5, 20, 8, 0).toIso8601String(),
      athlete: 'João Santos',
      activity: Activity.marcha.value,
      environment: Environment.esteira.value,
      createdAt: DateTime(2026, 5, 20, 8, 0).toIso8601String(),
      syncStatus: SyncStatus.synced,
      sampleCount: 640,
    ),
    RunModel(
      runId: 'demo-007',
      deviceId: 'demo-device',
      datetime: DateTime(today.year, today.month, today.day, 8, 15).toIso8601String(),
      athlete: 'Carla Mendes',
      activity: Activity.saltoVertical.value,
      environment: Environment.esteira.value,
      createdAt: DateTime(today.year, today.month, today.day, 8, 15).toIso8601String(),
      syncStatus: SyncStatus.localOnly,
      sampleCount: 420,
    ),
    RunModel(
      runId: 'demo-008',
      deviceId: 'demo-device',
      datetime: DateTime(yesterday.year, yesterday.month, yesterday.day, 11, 0)
          .toIso8601String(),
      athlete: 'Pedro Lima',
      activity: Activity.saltoDistancia.value,
      environment: Environment.pistaExterna.value,
      createdAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 11, 0)
          .toIso8601String(),
      syncStatus: SyncStatus.synced,
      sampleCount: 310,
    ),
  ];

  for (final run in runs) {
    await repo.saveLocal(run);
  }

  await settings.set(
    AppConstants.lastSyncKey,
    DateTime(today.year, today.month, today.day, 14, 30).toIso8601String(),
  );
  debugPrint('[demo_seed] Seed concluído.');
}
