import '../../core/constants/enums.dart';

class KinexaStatusSnapshot {
  const KinexaStatusSnapshot({
    required this.state,
    this.firmwareVersion = '1.0.4',
    this.deviceId,
    this.calibrated = false,
    this.lines = const [],
  });

  final DeviceState state;
  final String firmwareVersion;
  final String? deviceId;
  final bool calibrated;
  final List<String> lines;
}

class KinexaBleProtocol {
  /// Quebra um payload BLE em linhas ASCII (firmware envia 1 linha por NOTIFY,
  /// mas a pilha Android pode agrupar várias).
  static List<String> splitStatusPayload(String payload) {
    return payload
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static KinexaStatusSnapshot parseStatusLines(List<String> lines) {
    DeviceState state = DeviceState.disconnected;
    var firmware = '1.0.4';
    String? deviceId;
    var calibrated = false;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('STATE:')) {
        state = parseStateTag(line.substring('STATE:'.length));
      } else if (line.startsWith('FW:')) {
        firmware = line.substring('FW:'.length).trim();
      } else if (line.startsWith('DEVICE:')) {
        deviceId = line.substring('DEVICE:'.length).trim();
      } else if (line == 'CALIB:OK') {
        calibrated = true;
      } else if (line == 'CALIB:INVALID') {
        calibrated = false;
      }
    }

    return KinexaStatusSnapshot(
      state: state,
      firmwareVersion: firmware,
      deviceId: deviceId,
      calibrated: calibrated,
      lines: lines,
    );
  }

  static DeviceState parseStateTag(String tag) {
    final normalized = tag.trim().split(RegExp(r'[\s\r\n]')).first.toUpperCase();
    switch (normalized) {
      case 'NEEDS_CALIBRATION':
        return DeviceState.needsCalibration;
      case 'CALIBRATING':
        return DeviceState.calibrating;
      case 'READY':
        return DeviceState.ready;
      case 'RECORDING':
        return DeviceState.recording;
      case 'TRANSFER':
        return DeviceState.transferring;
      case 'ERROR':
      case 'UNKNOWN':
        return DeviceState.error;
      default:
        return DeviceState.disconnected;
    }
  }

  static bool hasStateLine(Iterable<String> lines) =>
      lines.any((line) => line.trim().startsWith('STATE:'));

  /// Resposta do comando STATUS — basta ter linha STATE: (Android pode
  /// entregar os 4 NOTIFYs com atraso ou só o último; o log acumula tudo).
  static bool isStatusResponse(List<String> lines) => hasStateLine(lines);

  /// Monta snapshot a partir do log acumulado (último valor de cada campo).
  static KinexaStatusSnapshot snapshotFromLog(List<String> log) =>
      parseStatusLines(log);

  /// Aceita firmware 1.0.x e 2.0.x (PBL_IMU v2).
  static bool isFirmwareCompatible(String version) {
    final normalized = version.trim().toLowerCase().replaceFirst('v', '');
    final parts = normalized.split('.');
    if (parts.length < 2) return false;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    if (major == null || minor == null) return false;
    return (major == 1 || major == 2) && minor == 0;
  }
}
