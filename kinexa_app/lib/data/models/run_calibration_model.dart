/// Calibração MPU6050 — espelha `RunCalibration` do backend e colunas do CSV serial.
class RunCalibrationModel {
  const RunCalibrationModel({
    required this.gxBiasLsb,
    required this.gyBiasLsb,
    required this.gzBiasLsb,
    required this.gTxLsb,
    required this.gTyLsb,
    required this.gTzLsb,
    required this.valid,
    this.source = 'app',
  });

  final double gxBiasLsb;
  final double gyBiasLsb;
  final double gzBiasLsb;
  final double gTxLsb;
  final double gTyLsb;
  final double gTzLsb;
  final bool valid;
  final String source;

  factory RunCalibrationModel.fromApiJson(Map<String, dynamic> json) {
    return RunCalibrationModel(
      gxBiasLsb: (json['calib_gx_bias_lsb'] as num).toDouble(),
      gyBiasLsb: (json['calib_gy_bias_lsb'] as num).toDouble(),
      gzBiasLsb: (json['calib_gz_bias_lsb'] as num).toDouble(),
      gTxLsb: (json['calib_g_T_x_lsb'] as num).toDouble(),
      gTyLsb: (json['calib_g_T_y_lsb'] as num).toDouble(),
      gTzLsb: (json['calib_g_T_z_lsb'] as num).toDouble(),
      valid: json['calib_valid'] == true,
      source: (json['calib_source'] as String?) ?? 'csv',
    );
  }

  static RunCalibrationModel? tryFromApiJson(Map<String, dynamic> json) {
    const keys = [
      'calib_gx_bias_lsb',
      'calib_gy_bias_lsb',
      'calib_gz_bias_lsb',
      'calib_g_T_x_lsb',
      'calib_g_T_y_lsb',
      'calib_g_T_z_lsb',
    ];
    if (!keys.every((k) => json[k] != null)) return null;
    try {
      return RunCalibrationModel.fromApiJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Extrai calibração da primeira linha de dados de um CSV com schema completo.
  static RunCalibrationModel? tryFromCsv(String? csv) {
    if (csv == null || csv.trim().isEmpty) return null;
    final lines = csv.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return null;

    final headers = _splitCsvLine(lines.first);
    final values = _splitCsvLine(lines[1]);
    if (headers.length != values.length) return null;

    final idx = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      idx[headers[i].trim()] = i;
    }

    const required = [
      'calib_gx_bias_lsb',
      'calib_gy_bias_lsb',
      'calib_gz_bias_lsb',
      'calib_g_T_x_lsb',
      'calib_g_T_y_lsb',
      'calib_g_T_z_lsb',
      'calib_valid',
    ];
    if (!required.every(idx.containsKey)) return null;

    double? pickDouble(String key) =>
        double.tryParse(values[idx[key]!].trim());

    bool pickBool(String key) {
      final raw = values[idx[key]!].trim().toLowerCase();
      return raw == '1' || raw == 'true' || raw == 't' || raw == 'yes';
    }

    final gx = pickDouble('calib_gx_bias_lsb');
    final gy = pickDouble('calib_gy_bias_lsb');
    final gz = pickDouble('calib_gz_bias_lsb');
    final tx = pickDouble('calib_g_T_x_lsb');
    final ty = pickDouble('calib_g_T_y_lsb');
    final tz = pickDouble('calib_g_T_z_lsb');
    if (gx == null || gy == null || gz == null || tx == null || ty == null || tz == null) {
      return null;
    }

    return RunCalibrationModel(
      gxBiasLsb: gx,
      gyBiasLsb: gy,
      gzBiasLsb: gz,
      gTxLsb: tx,
      gTyLsb: ty,
      gTzLsb: tz,
      valid: pickBool('calib_valid'),
    );
  }

  Map<String, dynamic> toUploadJson() => {
        'calib_gx_bias_lsb': gxBiasLsb,
        'calib_gy_bias_lsb': gyBiasLsb,
        'calib_gz_bias_lsb': gzBiasLsb,
        'calib_g_T_x_lsb': gTxLsb,
        'calib_g_T_y_lsb': gTyLsb,
        'calib_g_T_z_lsb': gTzLsb,
        'calib_valid': valid,
        'calib_source': source,
      };

  List<String> csvValues() => [
        _fmt(gxBiasLsb),
        _fmt(gyBiasLsb),
        _fmt(gzBiasLsb),
        _fmt(gTxLsb),
        _fmt(gTyLsb),
        _fmt(gTzLsb),
        valid ? 'true' : 'false',
      ];

  static List<String> csvHeaderNames() => const [
        'calib_gx_bias_lsb',
        'calib_gy_bias_lsb',
        'calib_gz_bias_lsb',
        'calib_g_T_x_lsb',
        'calib_g_T_y_lsb',
        'calib_g_T_z_lsb',
        'calib_valid',
      ];

  static String _fmt(double v) {
    final text = v.toString();
    return text.contains('e') || text.contains('E') ? v.toStringAsFixed(8) : text;
  }

  static List<String> _splitCsvLine(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (ch == ',' && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
        continue;
      }
      buf.write(ch);
    }
    out.add(buf.toString());
    return out;
  }
}
