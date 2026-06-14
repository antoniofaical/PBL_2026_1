import '../../data/models/device_model.dart';
import 'ble_run_receiver.dart';

abstract class BleService {
  Stream<List<DeviceModel>> scanDevices();
  Future<DeviceModel> connect(String deviceId);
  Future<DeviceModel> validate(DeviceModel device);
  Future<void> calibrate();
  Future<void> startRecording();
  Future<BleDownloadResult> stopAndDownload({
    KinexaXferProgressCallback? onProgress,
  });
  Future<BleDownloadResult> retryDownload({
    KinexaXferProgressCallback? onProgress,
  });
  Future<DeviceModel> getStatus();
  DeviceModel? get connectedDevice;
  Future<void> disconnect();

  /// Mapeia `deviceId` lógico (ex.: KINEXA_01) para o id BLE da plataforma.
  void registerBleConnectionId(String deviceId, String bleConnectionId) {}
}
