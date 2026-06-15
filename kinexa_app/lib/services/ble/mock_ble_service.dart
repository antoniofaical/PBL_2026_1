import 'dart:async';
import 'dart:math';

import '../../core/constants/enums.dart';
import '../../data/models/device_model.dart';
import '../logs/debug_log_service.dart';
import 'ble_exception.dart';
import 'ble_run_payload.dart';
import 'ble_run_receiver.dart';
import 'ble_service.dart';

/// Simulação BLE — substituir por RealBleService no futuro.
class MockBleService implements BleService {
  MockBleService(this._logs);

  final DebugLogService _logs;
  DeviceModel? _device;

  @override
  DeviceModel? get connectedDevice => _device;

  @override
  Stream<List<DeviceModel>> scanDevices() async* {
    _logs.add('BLE: SCAN iniciado');
    yield [];
    await Future.delayed(const Duration(milliseconds: 800));
    yield [
      DeviceModel(deviceId: 'KINEXA_01', rssi: -48, mac: 'AA:BB:CC:01:01:01'),
      DeviceModel(deviceId: 'KINEXA_02', rssi: -72, mac: 'AA:BB:CC:02:02:02'),
    ];
    _logs.add('BLE: 2 devices encontrados');
  }

  @override
  void registerBleConnectionId(String deviceId, String bleConnectionId) {}

  @override
  Future<DeviceModel> connect(String deviceId) async {
    if (_device?.deviceId == deviceId &&
        (_device!.state == DeviceState.ready ||
            _device!.state == DeviceState.recording ||
            _device!.state == DeviceState.transferring)) {
      _logs.add('BLE: reconnect $deviceId STATE:${_device!.state.name}');
      return _device!;
    }

    _logs.add('BLE: CONNECT $deviceId');
    await Future.delayed(const Duration(milliseconds: 600));
    _device = DeviceModel(
      deviceId: deviceId,
      rssi: -50,
      mac: 'AA:BB:CC:01:01:01',
      mtu: 512,
      state: DeviceState.needsCalibration,
    );
    _logs.add('BLE: conectado STATE:NEEDS_CALIBRATION');
    return _device!;
  }

  @override
  Future<DeviceModel> validate(DeviceModel device) async {
    _logs.add('BLE: validate ${device.deviceId}');
    for (final step in [
      'Preparing',
      'Connecting',
      'ServicesFound',
      'FirmwareCompatible',
      'SensorOperational',
    ]) {
      await Future.delayed(const Duration(milliseconds: 400));
      _logs.add('BLE: $step OK');
    }

    final status = await getStatus();
    _device = device.copyWith(
      state: status.state,
      firmwareVersion: status.firmwareVersion,
      mtu: status.mtu,
      rssi: status.rssi,
      mac: status.mac,
    );
    _logs.add('BLE: validate OK STATE:${_device!.state.name}');
    return _device!;
  }

  @override
  Future<void> calibrate() async {
    _logs.add('BLE: CALIBRATE');
    _device = _device?.copyWith(state: DeviceState.calibrating);
    await Future.delayed(const Duration(seconds: 2));
    _device = _device?.copyWith(state: DeviceState.ready);
    _logs.add('BLE: CALIB:OK STATE:READY');
  }

  @override
  Future<void> startRecording() async {
    _logs.add('BLE: START');
    if (_device?.state == DeviceState.needsCalibration) {
      throw BleException(
        'Sensor não calibrado — calibre antes de iniciar a coleta.',
      );
    }
    await Future.delayed(const Duration(milliseconds: 300));
    _device = _device?.copyWith(state: DeviceState.recording);
    _logs.add('BLE: REC:STARTED STATE:RECORDING');
  }

  @override
  Future<BleDownloadResult> stopAndDownload({
    KinexaXferProgressCallback? onProgress,
  }) async {
    return _mockDownload(onProgress: onProgress, logStop: true);
  }

  @override
  Future<BleDownloadResult> retryDownload({
    KinexaXferProgressCallback? onProgress,
  }) async {
    return _mockDownload(onProgress: onProgress, logStop: false);
  }

  Future<BleDownloadResult> _mockDownload({
    KinexaXferProgressCallback? onProgress,
    required bool logStop,
  }) async {
    if (logStop) _logs.add('BLE: STOP');
    _logs.add('BLE: XFER start');
    _device = _device?.copyWith(state: DeviceState.transferring);
    await Future.delayed(const Duration(milliseconds: 500));

    final rng = Random(42);
    const sampleCount = 2500;
    const packetCount = 12;
    const bytesTotal = 143276;
    for (var p = 1; p <= packetCount; p++) {
      onProgress?.call(
        bytesReceived: (bytesTotal * p / packetCount).round(),
        bytesTotal: bytesTotal,
        packetCount: p,
      );
      await Future.delayed(const Duration(milliseconds: 120));
    }

    const mockCalib = KinexaCalibData(
      gxBias: -111.6,
      gyBias: 37.06,
      gzBias: -56.99,
      gTx: 2582.65,
      gTy: 1355.45,
      gTz: 2718.38,
      valid: true,
    );
    final samples = <KinexaImuSample>[];
    for (var i = 0; i < sampleCount; i++) {
      samples.add(
        KinexaImuSample(
          tMs: i * 2,
          ax: 1960 + rng.nextInt(80),
          ay: -500 + rng.nextInt(40),
          az: 3400 + rng.nextInt(60),
          gx: -360 + rng.nextInt(20),
          gy: -370 + rng.nextInt(15),
          gz: -40 + rng.nextInt(10),
        ),
      );
    }
    final parsed = KinexaParsedRun(
      calib: mockCalib,
      samples: samples,
      sourcePath: '/mock_last_run.bin',
    );
    final csv = KinexaRunPayloadParser.toCsv(parsed);
    await Future.delayed(const Duration(milliseconds: 400));
    _logs.add('BLE: XFER:OK');
    _device = _device?.copyWith(state: DeviceState.ready);

    return BleDownloadResult(
      csvContent: csv,
      sampleCount: sampleCount,
      packetCount: packetCount,
      durationMs: sampleCount * 2,
      calibration: mockCalib.toCalibrationModel(),
    );
  }

  @override
  Future<DeviceModel> getStatus() async {
    return _device ?? DeviceModel(deviceId: '—', state: DeviceState.disconnected);
  }

  @override
  Future<void> disconnect() async {
    _logs.add('BLE: disconnect');
    _device = null;
  }
}
