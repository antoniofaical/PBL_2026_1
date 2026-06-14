import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/local/local_database.dart';
import 'data/local/run_dao.dart';
import 'data/local/settings_dao.dart';
import 'data/models/device_model.dart';
import 'data/models/event_model.dart';
import 'data/models/run_model.dart';
import 'data/remote/api_service.dart';
import 'data/remote/http_api_service.dart';
import 'data/repositories/device_repository.dart';
import 'data/repositories/run_repository.dart';
import 'data/repositories/sync_repository.dart';
export 'services/ble/ble_service_provider.dart';

final apiServiceProvider = Provider<ApiService>((ref) => HttpApiService());

final runDaoProvider = Provider<RunDao>(
  (ref) => RunDao(LocalDatabase.instance),
);

final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => SettingsDao(LocalDatabase.instance),
);

final runRepositoryProvider = Provider<RunRepository>(
  (ref) => RunRepository(ref.read(runDaoProvider), ref.read(apiServiceProvider)),
);

final syncRepositoryProvider = Provider<SyncRepository>(
  (ref) => SyncRepository(
    ref.read(apiServiceProvider),
    ref.read(runRepositoryProvider),
    ref.read(settingsDaoProvider),
  ),
);

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => DeviceRepository(ref.read(settingsDaoProvider)),
);

final serverOnlineProvider = StateProvider<bool>((ref) => false);

final offlineModeProvider = StateProvider<bool>((ref) => false);

final homeRefreshProvider = StateProvider<int>((ref) => 0);

/// Define para onde o fluxo de calibração deve ir ao concluir.
enum SensorFlowMode {
  newCollection,
  changeSensor,
  testSensor,
  calibrateSensor,
}

final sensorFlowModeProvider = StateProvider<SensorFlowMode>(
  (ref) => SensorFlowMode.newCollection,
);

void bumpHomeRefresh(WidgetRef ref) {
  ref.read(homeRefreshProvider.notifier).state++;
}

/// Sessão ativa de nova coleta (metadados + device + eventos).
class CollectionSession {
  CollectionSession({
    this.device,
    this.athlete = '',
    this.activity = 2,
    this.environment = 1,
    this.notes = '',
    this.events = const [],
    this.startedAt,
    this.isCalibrated = false,
  });

  final DeviceModel? device;
  final String athlete;
  final int activity;
  final int environment;
  final String notes;
  final List<EventModel> events;
  final DateTime? startedAt;
  final bool isCalibrated;

  CollectionSession copyWith({
    DeviceModel? device,
    String? athlete,
    int? activity,
    int? environment,
    String? notes,
    List<EventModel>? events,
    DateTime? startedAt,
    bool? isCalibrated,
  }) =>
      CollectionSession(
        device: device ?? this.device,
        athlete: athlete ?? this.athlete,
        activity: activity ?? this.activity,
        environment: environment ?? this.environment,
        notes: notes ?? this.notes,
        events: events ?? this.events,
        startedAt: startedAt ?? this.startedAt,
        isCalibrated: isCalibrated ?? this.isCalibrated,
      );
}

class CollectionSessionNotifier extends StateNotifier<CollectionSession> {
  CollectionSessionNotifier() : super(CollectionSession());

  void reset() => state = CollectionSession();

  void setDevice(DeviceModel device) =>
      state = state.copyWith(device: device, isCalibrated: false);

  void setMetadata({
    required String athlete,
    required int activity,
    required int environment,
    String? notes,
  }) =>
      state = state.copyWith(
        athlete: athlete,
        activity: activity,
        environment: environment,
        notes: notes ?? '',
      );

  void markCalibrated() => state = state.copyWith(isCalibrated: true);

  void startTimer() => state = state.copyWith(startedAt: DateTime.now());

  void addEvent(EventModel event) =>
      state = state.copyWith(events: [...state.events, event]);

  int get elapsedMs {
    if (state.startedAt == null) return 0;
    return DateTime.now().difference(state.startedAt!).inMilliseconds;
  }
}

final collectionSessionProvider =
    StateNotifierProvider<CollectionSessionNotifier, CollectionSession>(
  (ref) => CollectionSessionNotifier(),
);

/// Resultado da transferência para a TransferScreen.
class TransferResult {
  TransferResult({
    required this.run,
    required this.uploadSuccess,
  });

  final RunModel run;
  final bool uploadSuccess;
}

final transferResultProvider = StateProvider<TransferResult?>((ref) => null);
