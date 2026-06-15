import 'dart:typed_data';

import '../../data/models/run_calibration_model.dart';

/// Dados de calibração gravados no cabeçalho de `/last_run.bin`.
class KinexaCalibData {
  const KinexaCalibData({
    required this.gxBias,
    required this.gyBias,
    required this.gzBias,
    required this.gTx,
    required this.gTy,
    required this.gTz,
    required this.valid,
  });

  final double gxBias;
  final double gyBias;
  final double gzBias;
  final double gTx;
  final double gTy;
  final double gTz;
  final bool valid;

  RunCalibrationModel toCalibrationModel() => RunCalibrationModel(
        gxBiasLsb: gxBias,
        gyBiasLsb: gyBias,
        gzBiasLsb: gzBias,
        gTxLsb: gTx,
        gTyLsb: gTy,
        gTzLsb: gTz,
        valid: valid,
      );
}

class KinexaImuSample {
  const KinexaImuSample({
    required this.tMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  final int tMs;
  final int ax;
  final int ay;
  final int az;
  final int gx;
  final int gy;
  final int gz;
}

class KinexaParsedRun {
  const KinexaParsedRun({
    required this.calib,
    required this.samples,
    required this.sourcePath,
  });

  final KinexaCalibData calib;
  final List<KinexaImuSample> samples;
  final String sourcePath;
}

/// Parser do payload binário (`CalibData` + `Sample[]`) — espelha `pbl_data/format.py`.
class KinexaRunPayloadParser {
  KinexaRunPayloadParser._();

  static const calibSize = 28;
  static const sampleSize = 16;

  static KinexaParsedRun parse(
    Uint8List payload, {
    String sourcePath = '/last_run.bin',
  }) {
    if (payload.length < calibSize) {
      throw FormatException(
        'Payload muito pequeno (${payload.length} bytes)',
      );
    }

    final view = ByteData.sublistView(payload);
    final calib = KinexaCalibData(
      gxBias: view.getFloat32(0, Endian.little),
      gyBias: view.getFloat32(4, Endian.little),
      gzBias: view.getFloat32(8, Endian.little),
      gTx: view.getFloat32(12, Endian.little),
      gTy: view.getFloat32(16, Endian.little),
      gTz: view.getFloat32(20, Endian.little),
      valid: view.getUint8(24) != 0,
    );

    final sampleBytes = payload.length - calibSize;
    final fullSamples = sampleBytes ~/ sampleSize;
    final samples = <KinexaImuSample>[];

    for (var i = 0; i < fullSamples; i++) {
      final offset = calibSize + i * sampleSize;
      samples.add(
        KinexaImuSample(
          tMs: view.getUint32(offset, Endian.little),
          ax: view.getInt16(offset + 4, Endian.little),
          ay: view.getInt16(offset + 6, Endian.little),
          az: view.getInt16(offset + 8, Endian.little),
          gx: view.getInt16(offset + 10, Endian.little),
          gy: view.getInt16(offset + 12, Endian.little),
          gz: view.getInt16(offset + 14, Endian.little),
        ),
      );
    }

    return KinexaParsedRun(
      calib: calib,
      samples: samples,
      sourcePath: sourcePath,
    );
  }

  /// CSV com bias de giroscópio e vetor gravidade (LSB) — schema do receptor serial.
  static String toCsv(KinexaParsedRun run) {
    final calib = run.calib.toCalibrationModel();
    final calibCols = RunCalibrationModel.csvHeaderNames();
    final calibVals = calib.csvValues();

    final buffer = StringBuffer(
      't_ms,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,${calibCols.join(',')}\n',
    );
    for (final sample in run.samples) {
      buffer.write(
        '${sample.tMs},${sample.ax},${sample.ay},${sample.az},'
        '${sample.gx},${sample.gy},${sample.gz}',
      );
      for (final v in calibVals) {
        buffer.write(',$v');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  static int durationMs(KinexaParsedRun run) {
    if (run.samples.isEmpty) return 0;
    if (run.samples.length == 1) return run.samples.first.tMs;
    return run.samples.last.tMs - run.samples.first.tMs;
  }
}
