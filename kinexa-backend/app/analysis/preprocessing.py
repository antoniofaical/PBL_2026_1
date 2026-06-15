"""Carregamento de CSV e conversão para unidades SI — baseado em ler_dados.py."""

from __future__ import annotations

from io import StringIO
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from app.analysis.constants import (
    ACCEL_SENSITIVITY_LSB_PER_G,
    FULL_CSV_COLUMNS,
    G_TO_MS2,
    GYRO_SENSITIVITY_LSB_PER_DPS,
    MIN_CSV_COLUMNS,
    SAMPLE_RATE_HZ,
)


def _parse_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    return text in {"1", "true", "t", "yes", "y", "sim", "s"}


def load_csv(path: str | Path | None = None, content: str | None = None) -> pd.DataFrame:
    """Carrega CSV de coleta (schema app ou schema serial completo)."""
    if content is not None:
        df = pd.read_csv(StringIO(content))
    elif path is not None:
        df = pd.read_csv(path)
    else:
        raise ValueError("Informe path ou content.")

    columns = set(df.columns)
    missing = sorted(MIN_CSV_COLUMNS - columns)
    if missing:
        raise ValueError(f"Colunas ausentes no CSV: {', '.join(missing)}")

    return df


def extract_calibration(df: pd.DataFrame) -> dict[str, Any]:
    """Extrai calibração do CSV ou usa defaults quando ausente (upload do app)."""
    has_full = FULL_CSV_COLUMNS.issubset(set(df.columns))
    if has_full and len(df) > 0:
        row = df.iloc[0]
        return {
            "gyro_bias_lsb": np.array([
                float(row["calib_gx_bias_lsb"]),
                float(row["calib_gy_bias_lsb"]),
                float(row["calib_gz_bias_lsb"]),
            ], dtype=np.float64),
            "gravity_T_lsb": np.array([
                float(row["calib_g_T_x_lsb"]),
                float(row["calib_g_T_y_lsb"]),
                float(row["calib_g_T_z_lsb"]),
            ], dtype=np.float64),
            "valid": _parse_bool(row["calib_valid"]),
            "source_format": "csv_serial",
        }

    return {
        "gyro_bias_lsb": np.zeros(3, dtype=np.float64),
        "gravity_T_lsb": np.array([0.0, 0.0, ACCEL_SENSITIVITY_LSB_PER_G], dtype=np.float64),
        "valid": False,
        "source_format": "csv_app",
    }


def convert_to_si(df: pd.DataFrame, calib: dict[str, Any]) -> dict[str, np.ndarray]:
    """Converte amostras brutas para unidades físicas — equivalente a converter_para_si()."""
    t_ms = df["t_ms"].to_numpy(dtype=np.float64)
    t = (t_ms - t_ms[0]) / 1000.0

    ax = df["ax_raw"].to_numpy(dtype=np.float64) / ACCEL_SENSITIVITY_LSB_PER_G * G_TO_MS2
    ay = df["ay_raw"].to_numpy(dtype=np.float64) / ACCEL_SENSITIVITY_LSB_PER_G * G_TO_MS2
    az = df["az_raw"].to_numpy(dtype=np.float64) / ACCEL_SENSITIVITY_LSB_PER_G * G_TO_MS2

    bias = np.asarray(calib["gyro_bias_lsb"], dtype=np.float64)
    gx = (df["gx_raw"].to_numpy(dtype=np.float64) - bias[0]) / GYRO_SENSITIVITY_LSB_PER_DPS
    gy = (df["gy_raw"].to_numpy(dtype=np.float64) - bias[1]) / GYRO_SENSITIVITY_LSB_PER_DPS
    gz = (df["gz_raw"].to_numpy(dtype=np.float64) - bias[2]) / GYRO_SENSITIVITY_LSB_PER_DPS

    accel_mag = np.sqrt(ax * ax + ay * ay + az * az)
    gyro_mag = np.sqrt(gx * gx + gy * gy + gz * gz)

    return {
        "t": t,
        "t_ms": t_ms.astype(np.uint32),
        "ax": ax, "ay": ay, "az": az,
        "gx": gx, "gy": gy, "gz": gz,
        "accel_mag": accel_mag,
        "gyro_mag": gyro_mag,
        "ax_raw": df["ax_raw"].to_numpy(dtype=np.int16),
        "ay_raw": df["ay_raw"].to_numpy(dtype=np.int16),
        "az_raw": df["az_raw"].to_numpy(dtype=np.int16),
        "gx_raw": df["gx_raw"].to_numpy(dtype=np.int16),
        "gy_raw": df["gy_raw"].to_numpy(dtype=np.int16),
        "gz_raw": df["gz_raw"].to_numpy(dtype=np.int16),
    }


def estimate_fs_hz(signals: dict[str, np.ndarray], fallback: float = SAMPLE_RATE_HZ) -> float:
    """Estima fs a partir de t_ms/t — reaproveitado de detectar_eventos.estimar_fs_hz()."""
    t = np.asarray(signals["t"], dtype=np.float64)
    if len(t) < 3:
        return fallback
    dt = np.diff(t)
    dt = dt[dt > 0]
    if len(dt) == 0:
        return fallback
    fs = 1.0 / float(np.median(dt))
    if not np.isfinite(fs) or fs <= 0:
        return fallback
    return fs
