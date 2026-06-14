import 'dart:async';
import 'dart:typed_data';

import 'ble_constants.dart';
import 'ble_exception.dart';

class KinexaXferResult {
  const KinexaXferResult({
    required this.payload,
    required this.sourcePath,
    required this.packetCount,
    required this.ok,
  });

  final Uint8List payload;
  final String sourcePath;
  final int packetCount;
  final bool ok;
}

typedef KinexaXferProgressCallback = void Function({
  required int bytesReceived,
  int? bytesTotal,
  required int packetCount,
});

/// Receptor da transferência BLE — espelha `receive_ble.BleRunReceiver`.
class KinexaRunReceiver {
  KinexaRunReceiver({
    required void Function(String message) onLog,
    required void Function() onRequestAck,
    KinexaXferProgressCallback? onProgress,
  })  : _onLog = onLog,
        _onRequestAck = onRequestAck,
        _onProgress = onProgress,
        _payload = BytesBuilder(copy: false);

  final void Function(String message) _onLog;
  final void Function() _onRequestAck;
  final KinexaXferProgressCallback? _onProgress;

  final _done = Completer<KinexaXferResult>();
  BytesBuilder _payload;

  int? _expectedSize;
  String _sourcePath = '';
  bool _receivingBinary = false;
  bool _activeXfer = false;
  int _bytesSinceAck = 0;
  int _packetCount = 0;
  bool _finalizing = false;
  int _finalizeGeneration = 0;
  Timer? _drainTimer;

  Future<KinexaXferResult> waitForResult(Duration timeout) {
    return _done.future.timeout(
      timeout,
      onTimeout: () => throw BleException('Timeout na transferência BLE'),
    );
  }

  void onStatus(String text) {
    if (text.isEmpty) return;

    if (!_activeXfer &&
        (text == KinexaBleConfig.xferDataEnd ||
            text == KinexaBleConfig.xferEndMarker ||
            text == KinexaBleConfig.xferOkLine)) {
      return;
    }

    if (text == KinexaBleConfig.xferStartLine) {
      _onLog('xfer start');
      return;
    }

    if (text == KinexaBleConfig.xferBeginMarker) {
      _beginNewTransfer();
      return;
    }

    if (text.startsWith('PATH:')) {
      _sourcePath = text.substring(5).trim();
      return;
    }

    if (text.startsWith('SIZE:')) {
      _expectedSize = int.tryParse(text.substring(5).trim());
      _onLog('xfer size: $_expectedSize bytes');
      _emitProgress();
      return;
    }

    if (text == KinexaBleConfig.xferDataBegin) {
      _receivingBinary = true;
      _resetPayload();
      _bytesSinceAck = 0;
      _packetCount = 0;
      _onRequestAck();
      return;
    }

    if (text == KinexaBleConfig.xferDataEnd ||
        text == KinexaBleConfig.xferEndMarker ||
        text == KinexaBleConfig.xferOkLine ||
        text == 'XFER:OK') {
      _scheduleFinalize();
      return;
    }

    if (text.startsWith('XFER:FAIL') ||
        text.startsWith('XFER:ABORTED') ||
        text.startsWith('ERRO:') ||
        text.startsWith('ERR:') ||
        text.startsWith('ERROR:')) {
      _fail(text);
    }
  }

  void onData(List<int> chunk) {
    if (chunk.isEmpty || _expectedSize == null) return;
    if (_receivingBinary || _payload.length < _expectedSize!) {
      _acceptData(chunk);
    }
  }

  void _acceptData(List<int> chunk) {
    final expected = _expectedSize;
    if (expected == null) return;
    if (_payload.length >= expected) return;

    _packetCount++;
    final remaining = expected - _payload.length;
    if (chunk.length <= remaining) {
      _payload.add(chunk);
    } else {
      _payload.add(chunk.sublist(0, remaining));
    }

    _maybeRequestAck(chunk.length);
    _emitProgress();
  }

  void _resetPayload() {
    _payload = BytesBuilder(copy: false);
  }

  void _beginNewTransfer() {
    _cancelDrain();
    _expectedSize = null;
    _sourcePath = '';
    _resetPayload();
    _receivingBinary = false;
    _activeXfer = true;
    _bytesSinceAck = 0;
    _packetCount = 0;
    _finalizing = false;
    _finalizeGeneration++;
    _onLog('xfer begin');
  }

  void _maybeRequestAck(int nbytes) {
    final expected = _expectedSize;
    if (expected == null) return;

    _bytesSinceAck += nbytes;
    final complete = _payload.length >= expected;
    if (complete || _bytesSinceAck >= KinexaBleConfig.xferBytesPerAck) {
      _bytesSinceAck = 0;
      _onRequestAck();
    }
  }

  void _emitProgress() {
    final onProgress = _onProgress;
    if (onProgress == null) return;
    onProgress(
      bytesReceived: _payload.length,
      bytesTotal: _expectedSize,
      packetCount: _packetCount,
    );
  }

  void _scheduleFinalize() {
    if (!_activeXfer) return;
    if (_expectedSize == null && _payload.isEmpty) return;
    if (_finalizing) return;
    if (_drainTimer != null) return;

    final generation = _finalizeGeneration;
    _finalizing = true;
    final deadline = DateTime.now().add(KinexaBleConfig.xferDrainAfterFooter);

    _drainTimer = Timer.periodic(
      KinexaBleConfig.xferDrainPollInterval,
      (timer) {
        if (generation != _finalizeGeneration || !_activeXfer) {
          timer.cancel();
          _drainTimer = null;
          _finalizing = false;
          return;
        }

        final expected = _expectedSize;
        if (expected != null && _payload.length >= expected) {
          timer.cancel();
          _drainTimer = null;
          _finalize(generation);
          return;
        }

        if (DateTime.now().isAfter(deadline)) {
          timer.cancel();
          _drainTimer = null;
          _finalize(generation);
        }
      },
    );
  }

  void _cancelDrain() {
    _drainTimer?.cancel();
    _drainTimer = null;
  }

  void _finalize(int generation) {
    if (_done.isCompleted || generation != _finalizeGeneration) return;

    _receivingBinary = false;
    _finalizing = false;

    final expected = _expectedSize ?? 0;
    final got = _payload.length;
    final complete = expected > 0 && got == expected;
    _activeXfer = false;

    if (!complete) {
      _done.completeError(
        BleException('Transferência incompleta: $got/$expected bytes'),
      );
      _onLog('xfer incomplete ($got/$expected bytes)');
      return;
    }

    _done.complete(
      KinexaXferResult(
        payload: Uint8List.fromList(_payload.toBytes()),
        sourcePath: _sourcePath.isEmpty ? '/last_run.bin' : _sourcePath,
        packetCount: _packetCount,
        ok: true,
      ),
    );
    _onLog('xfer complete ($got bytes, $_packetCount chunks)');
  }

  void _fail(String reason) {
    if (_done.isCompleted) return;
    _cancelDrain();
    _activeXfer = false;
    _receivingBinary = false;
    _finalizing = false;
    _done.completeError(BleException(reason));
  }

  void dispose() {
    _cancelDrain();
    if (!_done.isCompleted) {
      _done.completeError(BleException('Transferência cancelada'));
    }
  }
}
