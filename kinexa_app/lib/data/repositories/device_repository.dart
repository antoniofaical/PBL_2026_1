import '../local/settings_dao.dart';
import '../models/device_model.dart';

class DeviceRepository {
  DeviceRepository(this._settings);

  final SettingsDao _settings;

  static const _key = 'default_device_id';
  static const _macKey = 'default_device_mac';
  static const _promptKey = 'ask_default_device';

  Future<DeviceModel?> getDefaultDevice() async {
    final id = await _settings.get(_key);
    if (id == null || id.isEmpty) return null;
    final mac = await _settings.get(_macKey);
    return DeviceModel(deviceId: id, mac: mac, rssi: -55);
  }

  Future<void> setDefaultDevice(DeviceModel device) async {
    await _settings.set(_key, device.deviceId);
    if (device.mac != null) {
      await _settings.set(_macKey, device.mac!);
    }
  }

  /// Pergunta "registrar como padrão?" até o usuário escolher SIM uma vez.
  Future<bool> shouldAskDefaultDevice() async {
    final value = await _settings.get(_promptKey);
    return value != 'false';
  }

  Future<void> markDefaultPromptDismissed() async {
    await _settings.set(_promptKey, 'false');
  }

  Future<void> clearDefaultDevice() async {
    await _settings.set(_key, '');
    await _settings.set(_promptKey, '');
  }
}
