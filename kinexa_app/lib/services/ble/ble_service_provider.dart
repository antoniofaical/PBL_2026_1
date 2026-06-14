import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logs/debug_log_service.dart';
import 'ble_service.dart';
import 'mock_ble_service.dart';
import 'real_ble_service.dart';

const useRealBle = bool.fromEnvironment(
  'KINEXA_USE_REAL_BLE',
  defaultValue: false,
);

final bleServiceProvider = Provider<BleService>((ref) {
  final logs = ref.read(debugLogProvider);
  if (useRealBle) {
    return RealBleService(logs);
  }
  return MockBleService(logs);
});

final debugLogProvider = Provider<DebugLogService>((ref) => DebugLogService());
