import '../../core/constants/enums.dart';
import 'run_calibration_model.dart';

class DeviceModel {
  DeviceModel({
    required this.deviceId,
    this.firmwareVersion = '1.0.3',
    this.rssi,
    this.mac,
    this.mtu = 512,
    this.state = DeviceState.disconnected,
  });

  final String deviceId;
  final String firmwareVersion;
  final int? rssi;
  final String? mac;
  final int? mtu;
  final DeviceState state;

  DeviceModel copyWith({
    String? deviceId,
    String? firmwareVersion,
    int? rssi,
    String? mac,
    int? mtu,
    DeviceState? state,
  }) =>
      DeviceModel(
        deviceId: deviceId ?? this.deviceId,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
        rssi: rssi ?? this.rssi,
        mac: mac ?? this.mac,
        mtu: mtu ?? this.mtu,
        state: state ?? this.state,
      );
}

class BleDownloadResult {
  BleDownloadResult({
    required this.csvContent,
    required this.sampleCount,
    required this.packetCount,
    required this.durationMs,
    this.calibration,
  });

  final String csvContent;
  final int sampleCount;
  final int packetCount;
  final int durationMs;
  final RunCalibrationModel? calibration;
}

@Deprecated('Use BleDownloadResult')
typedef MockDownloadResult = BleDownloadResult;
