import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../core/constants/enums.dart';
import '../../data/models/device_model.dart';
import '../logs/debug_log_service.dart';
import 'ble_constants.dart';
import 'ble_exception.dart';
import 'ble_permissions.dart';
import 'ble_protocol.dart';
import 'ble_run_payload.dart';
import 'ble_run_receiver.dart';
import 'ble_service.dart';

/// BLE real (ESP32 Kinexa) — scan, connect, validate, calibrate, record, download.
class RealBleService implements BleService {
  RealBleService(this._logs);

  final DebugLogService _logs;
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  DeviceModel? _device;
  String? _connectedBleId;

  final Map<String, String> _bleIdByDeviceId = {};

  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<List<int>>? _dataSub;

  QualifiedCharacteristic? _statusChar;
  QualifiedCharacteristic? _dataChar;
  QualifiedCharacteristic? _controlChar;

  final List<String> _statusLog = [];
  final _statusNotifyController = StreamController<String>.broadcast();

  KinexaRunReceiver? _activeReceiver;
  var _ackInFlight = false;
  var _ackPending = false;
  Future<BleDownloadResult>? _ongoingDownload;

  void _log(String message) => _logs.add('[BLE] $message');

  @override
  DeviceModel? get connectedDevice => _device;

  @override
  void registerBleConnectionId(String deviceId, String bleConnectionId) {
    _bleIdByDeviceId[deviceId] = bleConnectionId;
    _log('registered BLE id for $deviceId → $bleConnectionId');
  }

  String _resolveBleId(String deviceId) =>
      _bleIdByDeviceId[deviceId] ?? deviceId;

  @override
  Stream<List<DeviceModel>> scanDevices() async* {
    final granted = await BlePermissions.ensureBlePermissions(_log);
    if (!granted) {
      yield [];
      return;
    }

    _log('scan started');
    final found = <String, DeviceModel>{};

    yield [];

    try {
      final scanStream = _ble.scanForDevices(
        withServices: [KinexaBleUuids.service],
        scanMode: ScanMode.lowLatency,
      );

      await for (final discovered in scanStream.timeout(
        KinexaBleConfig.scanTimeout,
        onTimeout: (sink) => sink.close(),
      )) {
        final name = discovered.name.trim();
        if (name.isEmpty ||
            !name.toUpperCase().startsWith(KinexaBleConfig.deviceNamePrefix)) {
          continue;
        }

        _bleIdByDeviceId[name] = discovered.id;
        found[name] = DeviceModel(
          deviceId: name,
          mac: discovered.id,
          rssi: discovered.rssi,
          state: DeviceState.disconnected,
        );

        _log(
          'device found: $name, id=${discovered.id}, rssi=${discovered.rssi}',
        );
        yield found.values.toList()
          ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
      }
    } on TimeoutException {
      _log('scan timeout');
    } catch (e) {
      _log('error: scan $e');
    }

    yield found.values.toList()
      ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
  }

  @override
  Future<DeviceModel> connect(String deviceId) async {
    if (_device?.deviceId == deviceId &&
        _connectedBleId != null &&
        _controlChar != null) {
      _log('already connected to $deviceId — reusing session');
      return _device!;
    }

    _log('connecting to $deviceId');
    final bleId = _resolveBleId(deviceId);

    await _disconnectInternal();

    _device = DeviceModel(
      deviceId: deviceId,
      mac: bleId,
      state: DeviceState.connecting,
    );

    final connectedCompleter = Completer<void>();

    _connectionSub = _ble
        .connectToDevice(
          id: bleId,
          connectionTimeout: KinexaBleConfig.connectTimeout,
        )
        .listen(
      (update) {
        switch (update.connectionState) {
          case DeviceConnectionState.connected:
            _log('connected');
            if (!connectedCompleter.isCompleted) {
              connectedCompleter.complete();
            }
          case DeviceConnectionState.disconnected:
            _log('disconnected');
            if (_device != null) {
              _device = _device!.copyWith(state: DeviceState.disconnected);
            }
          default:
            break;
        }
      },
      onError: (Object e) {
        _log('error: connection $e');
        if (!connectedCompleter.isCompleted) {
          connectedCompleter.completeError(BleException('Falha na conexão: $e'));
        }
      },
    );

    try {
      await connectedCompleter.future.timeout(KinexaBleConfig.connectTimeout);
    } catch (e) {
      await _disconnectInternal();
      throw BleException('Timeout ao conectar em $deviceId');
    }

    _connectedBleId = bleId;

    try {
      await _discoverAndBindCharacteristics(bleId);
      await _subscribeNotifications(bleId);
      await Future<void>.delayed(KinexaBleConfig.notifySetupDelay);
      await _requestMtu(bleId);
      await _drainStatusNotifications(const Duration(milliseconds: 400));
      await _sniffStatusCharacteristic(const Duration(milliseconds: 600));

      // Firmware NOTIFY STATE:* em onConnect (pode chegar antes do subscribe).
      var snapshot = _snapshotFromLog();
      if (!KinexaBleProtocol.hasStateLine(snapshot.lines)) {
        _log('aguardando NOTIFY espontâneo de estado...');
        await _drainStatusNotifications(const Duration(seconds: 2));
        snapshot = _snapshotFromLog();
      }

      if (!KinexaBleProtocol.hasStateLine(snapshot.lines)) {
        _log('NOTIFY espontâneo ausente — pedindo STATUS uma vez');
        snapshot = await _queryStatus();
      }

      _device = _device!.copyWith(
        deviceId: snapshot.deviceId ?? deviceId,
        firmwareVersion: snapshot.firmwareVersion,
        state: snapshot.state,
        mac: bleId,
      );
      _log('connect complete STATE:${snapshot.state.name}');
      return _device!;
    } catch (e) {
      await _disconnectInternal();
      if (e is BleException) rethrow;
      throw BleException('Falha ao preparar BLE: $e');
    }
  }

  @override
  Future<DeviceModel> validate(DeviceModel device) async {
    _ensureConnected();
    _log('validate started');

    try {
      final mark = _statusWatermark;
      await _sendCommand(KinexaBleConfig.cmdPing);
      final pong = await _waitForResponseLine(
        'PONG',
        afterWatermark: mark,
        timeout: KinexaBleConfig.commandTimeout,
        sniff: true,
      );
      if (!pong) {
        throw BleException('Sensor não respondeu ao PING');
      }
      _log('PING OK');

      if (_statusChar == null || _controlChar == null || _dataChar == null) {
        throw BleException('Serviços BLE Kinexa incompletos');
      }
      _log('services discovered');

      final snapshot = _snapshotFromLog();
      _log(
        'validate snapshot state=${snapshot.state.name} '
        'fw=${snapshot.firmwareVersion} calib=${snapshot.calibrated}',
      );

      if (!KinexaBleProtocol.isFirmwareCompatible(snapshot.firmwareVersion)) {
        throw BleException(
          'Firmware incompatível: ${snapshot.firmwareVersion}',
        );
      }
      _log('firmware compatible');

      if (snapshot.state == DeviceState.error) {
        throw BleException('Sensor em estado de erro');
      }
      _log('sensor operational');

      _device = device.copyWith(
        deviceId: snapshot.deviceId ?? device.deviceId,
        firmwareVersion: snapshot.firmwareVersion,
        state: snapshot.state,
        mac: _connectedBleId,
        rssi: device.rssi,
        mtu: _device?.mtu,
      );
      return _device!;
    } catch (e) {
      if (e is BleException) rethrow;
      throw BleException('Falha na validação: $e');
    }
  }

  @override
  Future<void> calibrate() async {
    _ensureConnected();
    _log('CALIBRATE');

    final current = _device?.state;
    if (current == DeviceState.recording ||
        current == DeviceState.transferring) {
      throw BleException('Sensor ocupado — não é possível calibrar agora.');
    }

    _device = _device!.copyWith(state: DeviceState.calibrating);

    final mark = _statusWatermark;
    await _sendCommand(KinexaBleConfig.cmdCalibrate);

    final calibOk = await _waitForResponseLine(
      'CALIB:OK',
      afterWatermark: mark,
      timeout: KinexaBleConfig.calibrateTimeout,
      sniff: true,
    );
    if (!calibOk) {
      final recent = _linesSince(mark);
      if (recent.contains('CALIB:FAIL')) {
        throw BleException(
          'Calibração falhou — mantenha o sensor parado e tente novamente.',
        );
      }
      final err = _firstErrorLineIn(recent);
      throw BleException(
        err ?? 'Timeout na calibração — mantenha o sensor parado e tente novamente.',
      );
    }

    final ready = await _waitForResponseLine(
      'STATE:READY',
      afterWatermark: mark,
      timeout: KinexaBleConfig.commandResponseTimeout,
      sniff: true,
    );
    if (!ready) {
      throw BleException('Sensor não entrou em READY após calibração.');
    }

    _device = _device!.copyWith(state: DeviceState.ready);
    _log('CALIB:OK STATE:READY');
  }

  @override
  Future<void> startRecording() async {
    _ensureConnected();
    _log('START');

    if (_device?.state != DeviceState.ready) {
      final snapshot = await _queryStatus();
      if (snapshot.state != DeviceState.ready || !snapshot.calibrated) {
        if (snapshot.state == DeviceState.needsCalibration ||
            !snapshot.calibrated) {
          throw BleException(
            'Sensor não calibrado — calibre antes de iniciar a coleta.',
          );
        }
        throw BleException(
          'Sensor não está pronto (estado: ${snapshot.state.name}).',
        );
      }
      _device = _device!.copyWith(state: DeviceState.ready);
    }

    final mark = _statusWatermark;
    await _sendCommand(KinexaBleConfig.cmdStart);

    final recording = await _confirmRecordingStarted(afterWatermark: mark);
    if (!recording) {
      final err = _firstErrorLineIn(_linesSince(mark));
      throw BleException(err ?? 'Falha ao iniciar gravação no sensor.');
    }

    _device = _device!.copyWith(state: DeviceState.recording);
    _log('REC:STARTED STATE:RECORDING');
  }

  /// Firmware responde START com NOTIFY `REC:STARTED` + `STATE:RECORDING`
  /// (sem ACK). Android pode atrasar NOTIFYs — sniff READ + log acumulado.
  Future<bool> _confirmRecordingStarted({required int afterWatermark}) async {
    bool detected(List<String> lines) =>
        lines.any((l) => l == 'REC:STARTED') ||
        lines.any((l) => l == 'STATE:RECORDING') ||
        _snapshotFromLog().state == DeviceState.recording;

    if (detected(_linesSince(afterWatermark))) return true;

    final deadline = DateTime.now().add(KinexaBleConfig.recordingStartTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (detected(_linesSince(afterWatermark))) return true;
      await Future.wait([
        _sniffStatusCharacteristic(const Duration(milliseconds: 80)),
        _drainStatusNotifications(const Duration(milliseconds: 80)),
      ]);
    }

    return detected(_linesSince(afterWatermark)) ||
        _snapshotFromLog().state == DeviceState.recording;
  }

  @override
  Future<BleDownloadResult> stopAndDownload({
    KinexaXferProgressCallback? onProgress,
  }) async {
    _ensureConnected();
    _log('STOP + download');

    return _downloadWithCommand(
      KinexaBleConfig.cmdStop,
      onProgress: onProgress,
    );
  }

  @override
  Future<BleDownloadResult> retryDownload({
    KinexaXferProgressCallback? onProgress,
  }) async {
    _ensureConnected();
    _log('XFER retry (sem STOP)');

    return _downloadWithCommand(
      KinexaBleConfig.cmdXfer,
      onProgress: onProgress,
    );
  }

  Future<BleDownloadResult> _downloadWithCommand(
    String command, {
    KinexaXferProgressCallback? onProgress,
  }) {
    if (_ongoingDownload != null) {
      _log('download em andamento — aguardando resultado');
      return _ongoingDownload!;
    }

    final future = _runDownload(command: command, onProgress: onProgress);
    _ongoingDownload = future;
    return future.whenComplete(() => _ongoingDownload = null);
  }

  Future<BleDownloadResult> _runDownload({
    required String command,
    KinexaXferProgressCallback? onProgress,
  }) async {
    KinexaRunReceiver? receiver;
    try {
      receiver = KinexaRunReceiver(
        onLog: _log,
        onRequestAck: _requestXferAck,
        onProgress: onProgress,
      );
      _activeReceiver = receiver;

      await _sendCommand(command);
      _device = _device?.copyWith(state: DeviceState.transferring);

      final xfer = await receiver.waitForResult(KinexaBleConfig.xferTimeout);
      _log('payload recebido: ${xfer.payload.length} bytes, ok=${xfer.ok}');

      if (!xfer.ok || xfer.payload.isEmpty) {
        throw BleException('Transferência BLE incompleta ou vazia.');
      }

      final parsed = KinexaRunPayloadParser.parse(
        xfer.payload,
        sourcePath: xfer.sourcePath,
      );
      if (parsed.samples.isEmpty) {
        throw BleException('Nenhuma amostra IMU recebida do sensor.');
      }

      final csv = KinexaRunPayloadParser.toCsv(parsed);
      _device = _device?.copyWith(state: DeviceState.ready);
      _log('XFER:OK samples=${parsed.samples.length} packets=${xfer.packetCount}');

      return BleDownloadResult(
        csvContent: csv,
        sampleCount: parsed.samples.length,
        packetCount: xfer.packetCount,
        durationMs: KinexaRunPayloadParser.durationMs(parsed),
      );
    } catch (e, st) {
      _log('download error: $e');
      if (e is! BleException) {
        _log('download stack: $st');
      }
      if (_device != null && _device!.state == DeviceState.transferring) {
        _device = _device!.copyWith(state: DeviceState.ready);
      }
      if (e is BleException) rethrow;
      throw BleException('Falha no download BLE: $e');
    } finally {
      if (_activeReceiver == receiver) {
        _activeReceiver = null;
      }
      receiver?.dispose();
    }
  }

  @override
  Future<DeviceModel> getStatus() async {
    if (_device == null || _connectedBleId == null) {
      return DeviceModel(deviceId: '—', state: DeviceState.disconnected);
    }

    try {
      final snapshot = await _queryStatus();
      _device = _device!.copyWith(
        state: snapshot.state,
        firmwareVersion: snapshot.firmwareVersion,
        deviceId: snapshot.deviceId ?? _device!.deviceId,
      );
      return _device!;
    } catch (_) {
      return _device!;
    }
  }

  Future<void> _discoverAndBindCharacteristics(String bleId) async {
    await _ble.discoverAllServices(bleId);
    final services = await _ble.getDiscoveredServices(bleId);

    Service? kinexaService;
    for (final service in services) {
      if (service.id == KinexaBleUuids.service) {
        kinexaService = service;
        break;
      }
    }

    if (kinexaService == null) {
      throw BleException('Serviço Kinexa não encontrado');
    }

    Uuid? findChar(Uuid id) {
      for (final c in kinexaService!.characteristics) {
        if (c.id == id) return c.id;
      }
      return null;
    }

    final statusId = findChar(KinexaBleUuids.status);
    final dataId = findChar(KinexaBleUuids.data);
    final controlId = findChar(KinexaBleUuids.control);

    if (statusId == null || dataId == null || controlId == null) {
      throw BleException('Characteristics Kinexa ausentes no GATT');
    }

    _statusChar = QualifiedCharacteristic(
      deviceId: bleId,
      serviceId: KinexaBleUuids.service,
      characteristicId: statusId,
    );
    _dataChar = QualifiedCharacteristic(
      deviceId: bleId,
      serviceId: KinexaBleUuids.service,
      characteristicId: dataId,
    );
    _controlChar = QualifiedCharacteristic(
      deviceId: bleId,
      serviceId: KinexaBleUuids.service,
      characteristicId: controlId,
    );

    _log('characteristic found: ${KinexaBleUuids.status}');
    _log('characteristic found: ${KinexaBleUuids.data}');
    _log('characteristic found: ${KinexaBleUuids.control}');
  }

  Future<void> _subscribeNotifications(String bleId) async {
    final status = _statusChar;
    final data = _dataChar;
    if (status == null || data == null) {
      throw BleException('Characteristics não configuradas');
    }

    await _statusSub?.cancel();
    await _dataSub?.cancel();

    _statusSub = _ble.subscribeToCharacteristic(status).listen(
      (raw) => _handleStatusNotify(raw),
      onError: (Object e) => _log('error: status notify $e'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));

    _dataSub = _ble.subscribeToCharacteristic(data).listen(
      (raw) => _handleDataNotify(raw),
      onError: (Object e) => _log('error: data notify $e'),
    );
  }

  void _handleStatusNotify(List<int> raw) {
    final text = utf8.decode(raw, allowMalformed: true);
    for (final line in KinexaBleProtocol.splitStatusPayload(text)) {
      _appendStatusLine(line);
      _activeReceiver?.onStatus(line);
      if (line.length <= 80) {
        _log('status notify: $line');
      }
    }
  }

  void _appendStatusLine(String line) {
    _statusLog.add(line);
    if (!_statusNotifyController.isClosed) {
      _statusNotifyController.add(line);
    }
  }

  int get _statusWatermark => _statusLog.length;

  List<String> _linesSince(int watermark) {
    if (watermark >= _statusLog.length) return const [];
    return List<String>.of(_statusLog.sublist(watermark));
  }

  void _handleDataNotify(List<int> raw) {
    _activeReceiver?.onData(raw);
    if (_activeReceiver != null) {
      _log('chunk received: ${raw.length} bytes');
    }
  }

  Future<void> _requestMtu(String bleId) async {
    try {
      final mtu = await _ble.requestMtu(deviceId: bleId, mtu: 512);
      _device = _device?.copyWith(mtu: mtu);
      _log('MTU negotiated: $mtu');
    } catch (e) {
      _log('MTU request failed (using default): $e');
    }
  }

  Future<void> _sendCommand(String command) async {
    final control = _controlChar;
    if (control == null) throw BleException('Control characteristic ausente');

    _log('command sent: $command');
    try {
      await _ble.writeCharacteristicWithoutResponse(
        control,
        value: utf8.encode(command),
      );
    } catch (_) {
      await _ble.writeCharacteristicWithResponse(
        control,
        value: utf8.encode(command),
      );
    }
  }

  KinexaStatusSnapshot _snapshotFromLog() =>
      KinexaBleProtocol.snapshotFromLog(List<String>.of(_statusLog));

  /// Aguarda NOTIFYs chegarem (Android pode agrupar/atrasar).
  Future<void> _drainStatusNotifications(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    var lastCount = _statusLog.length;
    var idlePasses = 0;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final count = _statusLog.length;
      if (count == lastCount) {
        idlePasses++;
        if (idlePasses >= KinexaBleConfig.statusDrainIdlePasses) return;
      } else {
        idlePasses = 0;
        lastCount = count;
      }
    }
  }

  /// Resposta do comando STATUS — acumula NOTIFYs + leituras GATT no log.
  Future<KinexaStatusSnapshot> _queryStatus() async {
    await _sendCommand(KinexaBleConfig.cmdStatus);
    await _collectStatusAfterCommand();

    var snapshot = _snapshotFromLog();
    if (!KinexaBleProtocol.hasStateLine(snapshot.lines)) {
      _log('STATUS incompleto — reenviando uma vez');
      await _sendCommand(KinexaBleConfig.cmdStatus);
      await _collectStatusAfterCommand(
        drainTimeout: const Duration(seconds: 2),
      );
      snapshot = _snapshotFromLog();
    }

    if (!KinexaBleProtocol.hasStateLine(snapshot.lines)) {
      throw BleException(
        'Sensor não respondeu STATUS (log: $_statusLog)',
      );
    }

    _log(
      'STATUS parsed: state=${snapshot.state.name} '
      'calib=${snapshot.calibrated} logLines=${_statusLog.length}',
    );
    return snapshot;
  }

  /// NOTIFYs + READ da char Status (Android pode perder NOTIFYs rápidos).
  Future<void> _collectStatusAfterCommand({
    Duration drainTimeout = KinexaBleConfig.statusNotifyTimeout,
  }) async {
    await Future.wait([
      _sniffStatusCharacteristic(drainTimeout),
      _drainStatusNotifications(drainTimeout),
    ]);
    await Future<void>.delayed(KinexaBleConfig.statusBurstSettleDelay);
  }

  Future<void> _sniffStatusCharacteristic(Duration window) async {
    final status = _statusChar;
    if (status == null) return;

    final deadline = DateTime.now().add(window);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final raw = await _ble.readCharacteristic(status);
        if (raw.isNotEmpty) {
          for (final line in KinexaBleProtocol.splitStatusPayload(
            utf8.decode(raw, allowMalformed: true),
          )) {
            _appendStatusLine(line);
          }
        }
      } catch (_) {
        // ignora falha pontual de READ
      }
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
  }

  Future<List<String>> _awaitStatusLinesAfter({
    required int afterWatermark,
    required bool Function(List<String> lines) isComplete,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var idlePasses = 0;
    var lastCount = _statusLog.length;

    while (DateTime.now().isBefore(deadline)) {
      final lines = _linesSince(afterWatermark);
      if (isComplete(lines)) {
        await _drainStatusNotifications(KinexaBleConfig.statusBurstSettleDelay);
        return _linesSince(afterWatermark);
      }

      final count = _statusLog.length;
      if (count == lastCount) {
        idlePasses++;
      } else {
        idlePasses = 0;
        lastCount = count;
      }

      if (idlePasses >= 2) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } else {
        try {
          await _statusNotifyController.stream
              .first
              .timeout(const Duration(milliseconds: 100));
        } on TimeoutException {
          // continua
        }
      }
    }

    return _linesSince(afterWatermark);
  }

  Future<bool> _waitForResponseLine(
    String prefix, {
    required int afterWatermark,
    required Duration timeout,
    bool sniff = false,
  }) async {
    bool matches(List<String> lines) =>
        lines.any((line) => _statusLineMatches(line, prefix));

    if (matches(_linesSince(afterWatermark))) return true;

    if (sniff) {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (matches(_linesSince(afterWatermark))) return true;
        if (prefix == 'STATE:RECORDING' &&
            _snapshotFromLog().state == DeviceState.recording) {
          return true;
        }
        await Future.wait([
          _sniffStatusCharacteristic(const Duration(milliseconds: 80)),
          _drainStatusNotifications(const Duration(milliseconds: 80)),
        ]);
      }
      return matches(_linesSince(afterWatermark));
    }

    final lines = await _awaitStatusLinesAfter(
      afterWatermark: afterWatermark,
      isComplete: matches,
      timeout: timeout,
    );
    return matches(lines);
  }

  bool _statusLineMatches(String line, String prefix) {
    if (prefix.startsWith('STATE:')) {
      return line == prefix;
    }
    return line == prefix;
  }

  String? _firstErrorLineIn(List<String> lines) {
    for (final line in lines) {
      if (line.startsWith('ERROR:') ||
          line.startsWith('ERR:') ||
          line.startsWith('ERRO:')) {
        return _humanizeError(line);
      }
    }
    return null;
  }

  String _humanizeError(String line) {
    return switch (line) {
      'ERROR:INVALID_STATE' => 'Comando inválido para o estado atual do sensor.',
      'ERROR:NOT_CALIBRATED' => 'Sensor não calibrado — calibre antes de gravar.',
      'ERROR:NOT_RECORDING' => 'Sensor não está gravando.',
      'ERROR:NO_FILE' => 'Nenhuma coleta salva no sensor para reenviar.',
      'ERROR:FILE_OPEN' => 'Falha ao abrir arquivo no sensor.',
      'ERROR:NO_BLE' => 'Conexão BLE perdida.',
      'ERROR:UNKNOWN_COMMAND' => 'Comando desconhecido pelo firmware.',
      _ => line,
    };
  }

  void _requestXferAck() {
    unawaited(_sendXferAck());
  }

  Future<void> _sendXferAck() async {
    if (_ackInFlight) {
      _ackPending = true;
      return;
    }
    _ackInFlight = true;
    do {
      _ackPending = false;
      final control = _controlChar;
      if (control == null) break;

      // Igual receive_ble.py: write sem response para não bloquear no burst de NOTIFYs.
      try {
        await _ble.writeCharacteristicWithoutResponse(
          control,
          value: [KinexaBleConfig.xferAckByte],
        );
        _log('ACK sent');
      } catch (e) {
        try {
          await _ble.writeCharacteristicWithResponse(
            control,
            value: [KinexaBleConfig.xferAckByte],
          );
          _log('ACK sent (with response)');
        } catch (e2) {
          _log('error: ACK $e2');
        }
      }
    } while (_ackPending);
    _ackInFlight = false;
  }

  void _ensureConnected() {
    if (_device == null || _connectedBleId == null || _controlChar == null) {
      throw BleException('Nenhum sensor conectado');
    }
  }

  @override
  Future<void> disconnect() async {
    _log('disconnect requested');
    await _disconnectInternal();
    _device = null;
  }

  Future<void> _disconnectInternal() async {
    if (_ongoingDownload != null) {
      _log('disconnect adiado — download em andamento');
      return;
    }
    _activeReceiver?.dispose();
    _activeReceiver = null;
    await _statusSub?.cancel();
    await _dataSub?.cancel();
    await _connectionSub?.cancel();
    _statusSub = null;
    _dataSub = null;
    _connectionSub = null;
    _statusChar = null;
    _dataChar = null;
    _controlChar = null;
    _connectedBleId = null;
    _statusLog.clear();
  }
}
