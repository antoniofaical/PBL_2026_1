import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// UUIDs e constantes extraídos de `firmware_device.ino`.
class KinexaBleUuids {
  static final service = Uuid.parse('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static final status = Uuid.parse('beb5483e-36e1-4688-b7f5-ea07361b26a8');
  static final data = Uuid.parse('0000ff02-0000-1000-8000-00805f9b34fb');
  static final control = Uuid.parse('0000ff03-0000-1000-8000-00805f9b34fb');
}

class KinexaBleConfig {
  static const deviceNamePrefix = 'KINEXA';
  static const defaultDeviceId = 'KINEXA_01';
  static const scanTimeout = Duration(seconds: 10);
  static const connectTimeout = Duration(seconds: 15);
  static const commandTimeout = Duration(seconds: 8);
  static const calibrateTimeout = Duration(seconds: 35);
  static const recordingStartTimeout = Duration(seconds: 2);
  static const commandResponseTimeout = Duration(seconds: 2);
  static const statusNotifyTimeout = Duration(seconds: 4);
  static const notifySetupDelay = Duration(milliseconds: 800);
  static const statusBurstSettleDelay = Duration(milliseconds: 350);
  static const statusDrainIdlePasses = 6;
  static const xferTimeout = Duration(minutes: 3);
  static const xferDrainAfterFooter = Duration(seconds: 20);
  static const xferDrainPollInterval = Duration(milliseconds: 20);
  static const xferAckByte = 0x01;
  static const xferChunkSize = 244;
  /// Alinhado com `XFER_BYTES_PER_ACK` no firmware (4 chunks).
  static const xferBytesPerAck = xferChunkSize * 4;

  /// Protocolo de transferência (Status NOTIFY) — ver `firmware_device.ino`.
  static const xferStartLine = 'XFER:START';
  static const xferBeginMarker = '===BEGIN_LAST_RUN_BIN===';
  static const xferEndMarker = '===END_LAST_RUN_BIN===';
  static const xferDataBegin = 'DATA_BEGIN';
  static const xferDataEnd = 'DATA_END';
  static const xferOkLine = 'XFER: OK';

  /// Comandos ASCII na characteristic Control (firmware).
  static const cmdStatus = 'STATUS';
  static const cmdPing = 'PING';
  static const cmdCalibrate = 'CALIBRATE';
  static const cmdStart = 'START';
  static const cmdStop = 'STOP';
  static const cmdXfer = 'XFER';
  static const cmdAbort = 'ABORT';
}
