"""Constantes MPU6050 — sincronizadas com pbl_data/format.py e firmware."""

ACCEL_SENSITIVITY_LSB_PER_G = 4096.0
GYRO_SENSITIVITY_LSB_PER_DPS = 32.8
SAMPLE_RATE_HZ = 500.0
G_TO_MS2 = 9.80665

# Colunas mínimas presentes nos CSVs enviados pelo app Android
MIN_CSV_COLUMNS = frozenset({
    "t_ms",
    "ax_raw", "ay_raw", "az_raw",
    "gx_raw", "gy_raw", "gz_raw",
})

# Schema completo do receptor serial (ler_dados.py)
FULL_CSV_COLUMNS = MIN_CSV_COLUMNS | frozenset({
    "calib_gx_bias_lsb", "calib_gy_bias_lsb", "calib_gz_bias_lsb",
    "calib_g_T_x_lsb", "calib_g_T_y_lsb", "calib_g_T_z_lsb",
    "calib_valid",
})

# Saturação aproximada para ±8 g / ±1000 °/s
ACCEL_SAT_LSB = 32000
GYRO_SAT_LSB = 30000
