"""
ler_dados.py — Módulo de carregamento e conversão dos dados do IMU (ESP32-C3 + MPU6050)
========================================================================================

Formato de CSV gerado pelo firmware PBL_IMU:
  - Seção de cabeçalho (linhas iniciadas com '#'):
      # CALIB accel_x_offset accel_y_offset accel_z_offset
      # GYRO_BIAS gx_bias gy_bias gz_bias
      # GYRO_RANGE 2000          ← range configurado em °/s
      # ACCEL_RANGE 8            ← range configurado em g
      # SAMPLE_RATE 500          ← Hz
  - Dados (uma linha por amostra):
      sample_num, t_ms, ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw

Convenção de eixos (MPU6050 montado no dorso do pé, X → dedos, Y → mediolateral):
  - gyro.y = Ωp (velocidade angular de pitch) — eixo usado pelo método Falbriard

Sensibilidade padrão configurada no firmware:
  - GYRO_CONFIG = 0x18  → ±2000 °/s → 16.4 LSB/(°/s)
  - ACCEL_CONFIG = 0x10 → ±8 g       → 4096 LSB/g

Atualização v2 (2026-06):
  - GYRO_SENS corrigido de 32.8 → 16.4 LSB/(°/s) para GYRO_CONFIG = 0x18
  - Detecção automática do range a partir do cabeçalho '#GYRO_RANGE'
  - Backward-compat: se cabeçalho ausente, usa GYRO_SENS_DEFAULT
"""

import numpy as np
from pathlib import Path

# ── Constantes de hardware ────────────────────────────────────────────────────

SAMPLE_RATE_HZ = 500  # Hz — taxa de amostragem padrão do firmware

# Sensibilidades padrão (firmware com GYRO_CONFIG=0x18, ACCEL_CONFIG=0x10)
GYRO_SENS_DEFAULT  = 16.4    # LSB/(°/s) — ±2000 °/s
ACCEL_SENS_DEFAULT = 4096.0  # LSB/g     — ±8 g

# Tabela de sensibilidade vs. range (MPU6050 datasheet, Table 1 e 3)
_GYRO_SENS_TABLE  = {250: 131.0, 500: 65.5, 1000: 32.8, 2000: 16.4}
_ACCEL_SENS_TABLE = {2: 16384.0, 4: 8192.0, 8: 4096.0, 16: 2048.0}

# ── Funções públicas ──────────────────────────────────────────────────────────

def carregar_aquisicao(csv_path):
    """
    Carrega um arquivo CSV gerado pelo firmware PBL_IMU.

    Parâmetros
    ----------
    csv_path : str | Path

    Retorna
    -------
    calib : dict
        Informações de calibração e configuração extraídas do cabeçalho.
        Campos garantidos: valid (bool), gyro_sens (float), accel_sens (float),
        gyro_range_dps (int), accel_range_g (int), sample_rate (int),
        accel_offsets (ndarray[3]), gyro_bias (ndarray[3]).

    samples : dict
        Arrays raw (int16) de cada canal:
        t_ms, ax, ay, az, gx, gy, gz.
        Também expõe 'n_samples' (int).
    """
    path = Path(csv_path)
    calib = _parse_header(path)

    t_ms_l, ax_l, ay_l, az_l = [], [], [], []
    gx_l,   gy_l, gz_l       = [], [], []

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("sample"):
                continue
            parts = line.split(",")
            if len(parts) < 8:
                continue
            try:
                t_ms_l.append(int(parts[1]))
                ax_l.append(int(parts[2]))
                ay_l.append(int(parts[3]))
                az_l.append(int(parts[4]))
                gx_l.append(int(parts[5]))
                gy_l.append(int(parts[6]))   # Ωp — pitch angular velocity
                gz_l.append(int(parts[7]))
            except (ValueError, IndexError):
                continue

    samples = {
        "t_ms":     np.array(t_ms_l, dtype=np.int64),
        "ax":       np.array(ax_l,   dtype=np.int32),
        "ay":       np.array(ay_l,   dtype=np.int32),
        "az":       np.array(az_l,   dtype=np.int32),
        "gx":       np.array(gx_l,   dtype=np.int32),
        "gy":       np.array(gy_l,   dtype=np.int32),   # Ωp
        "gz":       np.array(gz_l,   dtype=np.int32),
        "n_samples": len(t_ms_l),
    }

    return calib, samples


def converter_para_si(samples, calib):
    """
    Converte samples raw (ADC counts) para unidades SI.

    Parâmetros
    ----------
    samples : dict  (retornado por carregar_aquisicao)
    calib   : dict  (retornado por carregar_aquisicao)

    Retorna
    -------
    dict com:
      t   (s)     — tempo a partir de zero
      ax, ay, az  (g)    — aceleração
      gx, gy, gz  (°/s) — velocidade angular  ← gy = Ωp (Falbriard)
      amag (g)    — magnitude da aceleração
    """
    gs  = calib["gyro_sens"]    # LSB/(°/s)
    as_ = calib["accel_sens"]   # LSB/g

    # Bias de giroscópio (subtraído antes da conversão)
    gb = calib.get("gyro_bias", np.zeros(3))

    t_ms = samples["t_ms"].astype(np.float64)
    t    = (t_ms - t_ms[0]) / 1000.0   # segundos a partir de zero

    ax_g  = (samples["ax"].astype(float) - calib["accel_offsets"][0]) / as_
    ay_g  = (samples["ay"].astype(float) - calib["accel_offsets"][1]) / as_
    az_g  = (samples["az"].astype(float) - calib["accel_offsets"][2]) / as_

    gx_dps = (samples["gx"].astype(float) - gb[0]) / gs
    gy_dps = (samples["gy"].astype(float) - gb[1]) / gs   # Ωp
    gz_dps = (samples["gz"].astype(float) - gb[2]) / gs

    amag = np.sqrt(ax_g**2 + ay_g**2 + az_g**2)

    return {
        "t":    t,
        "ax":   ax_g,
        "ay":   ay_g,
        "az":   az_g,
        "gx":   gx_dps,
        "gy":   gy_dps,   # ← este é o Ωp usado pelo Falbriard
        "gz":   gz_dps,
        "amag": amag,
    }


def porcentagem_saturacao(samples, eixo="gy"):
    """
    Calcula a porcentagem de amostras saturadas no eixo dado.
    Saturação = |valor| ≥ 32760 (≈ full-scale de 16 bits).
    Independente do range configurado — o ADC do MPU6050 é sempre 16 bits.
    """
    lim = 32760
    arr = samples[eixo].astype(np.int64)
    return 100.0 * float(np.sum(np.abs(arr) >= lim)) / len(arr)


def estimar_fs(samples):
    """Estima a taxa de amostragem real a partir dos timestamps."""
    t_ms = samples["t_ms"]
    dt = np.diff(t_ms.astype(np.float64))
    dt = dt[dt > 0]
    if not len(dt):
        return float(SAMPLE_RATE_HZ)
    fs = 1000.0 / float(np.median(dt))
    return fs if np.isfinite(fs) and fs > 0 else float(SAMPLE_RATE_HZ)


# ── Parsing interno ───────────────────────────────────────────────────────────

def _parse_header(path):
    """
    Lê o cabeçalho do CSV (linhas com '#') e extrai configuração de hardware.
    Se o cabeçalho estiver ausente ou incompleto, usa os defaults do firmware atual.
    """
    gyro_range    = 2000    # °/s — default do firmware v2 (GYRO_CONFIG=0x18)
    accel_range   = 8       # g   — ACCEL_CONFIG=0x10
    sample_rate   = SAMPLE_RATE_HZ
    accel_offsets = np.zeros(3, dtype=float)
    gyro_bias     = np.zeros(3, dtype=float)
    header_found  = False

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("#"):
                break
            header_found = True
            parts = line[1:].split()
            if not parts:
                continue
            tag = parts[0].upper()
            try:
                if tag == "CALIB" and len(parts) >= 4:
                    accel_offsets = np.array([float(parts[1]),
                                              float(parts[2]),
                                              float(parts[3])])
                elif tag == "GYRO_BIAS" and len(parts) >= 4:
                    gyro_bias = np.array([float(parts[1]),
                                          float(parts[2]),
                                          float(parts[3])])
                elif tag == "GYRO_RANGE" and len(parts) >= 2:
                    gyro_range = int(parts[1])
                elif tag == "ACCEL_RANGE" and len(parts) >= 2:
                    accel_range = int(parts[1])
                elif tag == "SAMPLE_RATE" and len(parts) >= 2:
                    sample_rate = int(parts[1])
            except (ValueError, IndexError):
                continue

    gyro_sens  = _GYRO_SENS_TABLE.get(gyro_range,  GYRO_SENS_DEFAULT)
    accel_sens = _ACCEL_SENS_TABLE.get(accel_range, ACCEL_SENS_DEFAULT)

    return {
        "valid":          header_found,
        "gyro_range_dps": gyro_range,
        "accel_range_g":  accel_range,
        "sample_rate":    sample_rate,
        "gyro_sens":      gyro_sens,     # LSB/(°/s)
        "accel_sens":     accel_sens,    # LSB/g
        "accel_offsets":  accel_offsets,
        "gyro_bias":      gyro_bias,
    }
