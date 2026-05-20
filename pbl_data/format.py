"""Constantes e structs do arquivo /last_run.bin (sincronizar com firmware)."""

from __future__ import annotations

import struct

# MPU6050 no firmware: ±8 g, ±1000 °/s, 500 Hz
ACCEL_SENSITIVITY_LSB_PER_G = 4096.0
GYRO_SENSITIVITY_LSB_PER_DPS = 32.8
SAMPLE_RATE_HZ = 500.0

# Cabeçalho LittleFS: 6 floats + bool + padding = 28 bytes
CALIB_STRUCT = struct.Struct("<6f?3x")
# Amostra: t_ms + 6 int16 = 16 bytes
SAMPLE_FMT = "<Ihhhhhh"
SAMPLE_STRUCT = struct.Struct(SAMPLE_FMT)

CALIB_SIZE = CALIB_STRUCT.size
SAMPLE_SIZE = SAMPLE_STRUCT.size

# Leitura .bin alternativa (ler_dados) — equivalente ao cabeçalho acima
HEADER_FMT = "<ffffffI"
HEADER_SIZE = struct.calcsize(HEADER_FMT)

CSV_REQUIRED_COLUMNS = frozenset({
    "t_ms",
    "ax_raw", "ay_raw", "az_raw",
    "gx_raw", "gy_raw", "gz_raw",
    "calib_gx_bias_lsb", "calib_gy_bias_lsb", "calib_gz_bias_lsb",
    "calib_g_T_x_lsb", "calib_g_T_y_lsb", "calib_g_T_z_lsb",
    "calib_valid",
})

# Protocolo de transferência (serial / BLE status + data)
XFER_BEGIN_MARKER = "===BEGIN_LAST_RUN_BIN==="
XFER_END_MARKER = "===END_LAST_RUN_BIN==="
XFER_OK_LINE = "XFER: OK"
