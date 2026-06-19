"""Constantes MPU6050 — sincronizadas com ler_dados.py e firmware PBL_IMU."""

# Defaults do firmware (GYRO_CONFIG=0x18 → ±2000 °/s, ACCEL_CONFIG=0x10 → ±8 g)
GYRO_SENSITIVITY_LSB_PER_DPS = 16.4
ACCEL_SENSITIVITY_LSB_PER_G = 4096.0
GYRO_RANGE_DPS_DEFAULT = 2000
GYRO_RANGE_DPS_LEGACY = 1000  # coletas SESI sem cabeçalho #GYRO_RANGE no CSV
ACCEL_RANGE_G_DEFAULT = 8
SAMPLE_RATE_HZ = 500.0
G_TO_MS2 = 9.80665

# Tabelas datasheet MPU6050 (ler_dados.py)
GYRO_SENS_TABLE: dict[int, float] = {250: 131.0, 500: 65.5, 1000: 32.8, 2000: 16.4}
ACCEL_SENS_TABLE: dict[int, float] = {2: 16384.0, 4: 8192.0, 8: 4096.0, 16: 2048.0}

# Saturação ADC 16 bits (ler_dados.porcentagem_saturacao)
ADC_SAT_LSB = 32760

# Colunas mínimas presentes nos CSVs enviados pelo app Android
MIN_CSV_COLUMNS = frozenset({
    "t_ms",
    "ax_raw", "ay_raw", "az_raw",
    "gx_raw", "gy_raw", "gz_raw",
})

# Schema completo do receptor serial / app com calibração embutida
FULL_CSV_COLUMNS = MIN_CSV_COLUMNS | frozenset({
    "calib_gx_bias_lsb", "calib_gy_bias_lsb", "calib_gz_bias_lsb",
    "calib_g_T_x_lsb", "calib_g_T_y_lsb", "calib_g_T_z_lsb",
    "calib_valid",
})

# Falbriard et al. (2018) — filtros Butterworth 2ª ordem
FALBRIARD_FC_MIDSWING_HZ = 5.0
FALBRIARD_FC_IC_TC_HZ = 30.0
FALBRIARD_PEAK_HEIGHT_DPS = 80.0
FALBRIARD_PEAK_MIN_DISTANCE_HZ = 4.5
