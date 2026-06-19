"""Carregamento de CSV e conversão para unidades SI — baseado em ler_dados.py v2."""

from __future__ import annotations

from io import StringIO
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from app.analysis.constants import (
    ACCEL_RANGE_G_DEFAULT,
    ACCEL_SENS_TABLE,
    ACCEL_SENSITIVITY_LSB_PER_G,
    ADC_SAT_LSB,
    FULL_CSV_COLUMNS,
    GYRO_RANGE_DPS_DEFAULT,
    GYRO_RANGE_DPS_LEGACY,
    GYRO_SENS_TABLE,
    GYRO_SENSITIVITY_LSB_PER_DPS,
    MIN_CSV_COLUMNS,
    SAMPLE_RATE_HZ,
)


def _parse_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    return text in {"1", "true", "t", "yes", "y", "sim", "s"}


def _parse_firmware_header(text: str) -> tuple[dict[str, Any], list[str]]:
    """Lê cabeçalho '# ...' do firmware PBL_IMU (ler_dados._parse_header)."""
    gyro_range = GYRO_RANGE_DPS_DEFAULT
    accel_range = ACCEL_RANGE_G_DEFAULT
    sample_rate = int(SAMPLE_RATE_HZ)
    accel_offsets = np.zeros(3, dtype=float)
    gyro_bias = np.zeros(3, dtype=float)
    header_found = False
    data_lines: list[str] = []

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            header_found = True
            parts = stripped[1:].split()
            if not parts:
                continue
            tag = parts[0].upper()
            try:
                if tag == "CALIB" and len(parts) >= 4:
                    accel_offsets = np.array([float(parts[1]), float(parts[2]), float(parts[3])])
                elif tag == "GYRO_BIAS" and len(parts) >= 4:
                    gyro_bias = np.array([float(parts[1]), float(parts[2]), float(parts[3])])
                elif tag == "GYRO_RANGE" and len(parts) >= 2:
                    gyro_range = int(parts[1])
                elif tag == "ACCEL_RANGE" and len(parts) >= 2:
                    accel_range = int(parts[1])
                elif tag == "SAMPLE_RATE" and len(parts) >= 2:
                    sample_rate = int(parts[1])
            except (ValueError, IndexError):
                continue
        elif stripped and not stripped.lower().startswith("sample"):
            data_lines.append(stripped)

    gyro_sens = GYRO_SENS_TABLE.get(gyro_range, GYRO_SENSITIVITY_LSB_PER_DPS)
    accel_sens = ACCEL_SENS_TABLE.get(accel_range, ACCEL_SENSITIVITY_LSB_PER_G)

    calib = {
        "valid": header_found,
        "gyro_range_dps": gyro_range,
        "accel_range_g": accel_range,
        "sample_rate": sample_rate,
        "gyro_sens": gyro_sens,
        "accel_sens": accel_sens,
        "accel_offsets": accel_offsets,
        "gyro_bias": gyro_bias,
        "source_format": "firmware_header",
    }
    return calib, data_lines


def _firmware_lines_to_dataframe(lines: list[str]) -> pd.DataFrame:
    """Converte linhas sample_num,t_ms,ax,...,gz do firmware em DataFrame."""
    rows: list[dict[str, int]] = []
    for line in lines:
        parts = line.split(",")
        if len(parts) < 8:
            continue
        try:
            rows.append({
                "sample_index": int(parts[0]),
                "t_ms": int(parts[1]),
                "ax_raw": int(parts[2]),
                "ay_raw": int(parts[3]),
                "az_raw": int(parts[4]),
                "gx_raw": int(parts[5]),
                "gy_raw": int(parts[6]),
                "gz_raw": int(parts[7]),
            })
        except (ValueError, IndexError):
            continue
    if not rows:
        raise ValueError("Nenhuma amostra válida no CSV com cabeçalho de firmware.")
    return pd.DataFrame(rows)


def load_csv(path: str | Path | None = None, content: str | None = None) -> pd.DataFrame:
    """Carrega CSV (schema app, schema serial com colunas, ou firmware com '#')."""
    raw_text: str | None = None
    if content is not None:
        raw_text = content
    elif path is not None:
        raw_text = Path(path).read_text(encoding="utf-8", errors="replace")
    else:
        raise ValueError("Informe path ou content.")

    if raw_text.lstrip().startswith("#"):
        calib, data_lines = _parse_firmware_header(raw_text)
        df = _firmware_lines_to_dataframe(data_lines)
        df.attrs["firmware_calib"] = calib
        return df

    df = pd.read_csv(StringIO(raw_text))
    columns = set(df.columns)
    missing = sorted(MIN_CSV_COLUMNS - columns)
    if missing:
        raise ValueError(f"Colunas ausentes no CSV: {', '.join(missing)}")
    return df


def extract_calibration(df: pd.DataFrame) -> dict[str, Any]:
    """Extrai calibração do CSV — app, colunas embutidas ou cabeçalho firmware."""
    fw_calib = df.attrs.get("firmware_calib")
    if fw_calib:
        return {
            "gyro_bias_lsb": np.asarray(fw_calib["gyro_bias"], dtype=np.float64),
            "gravity_T_lsb": np.zeros(3, dtype=np.float64),
            "accel_offsets_lsb": np.asarray(fw_calib["accel_offsets"], dtype=np.float64),
            "gyro_sens": float(fw_calib["gyro_sens"]),
            "accel_sens": float(fw_calib["accel_sens"]),
            "gyro_range_dps": int(fw_calib["gyro_range_dps"]),
            "accel_range_g": int(fw_calib["accel_range_g"]),
            "sample_rate": int(fw_calib["sample_rate"]),
            "valid": bool(fw_calib["valid"]),
            "source_format": "firmware_header",
        }

    has_full = FULL_CSV_COLUMNS.issubset(set(df.columns))
    if has_full and len(df) > 0:
        row = df.iloc[0]
        gyro_range = GYRO_RANGE_DPS_LEGACY
        accel_range = ACCEL_RANGE_G_DEFAULT
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
            "accel_offsets_lsb": np.zeros(3, dtype=np.float64),
            "gyro_sens": GYRO_SENS_TABLE.get(gyro_range, GYRO_SENSITIVITY_LSB_PER_DPS),
            "accel_sens": ACCEL_SENS_TABLE.get(accel_range, ACCEL_SENSITIVITY_LSB_PER_G),
            "gyro_range_dps": gyro_range,
            "accel_range_g": accel_range,
            "sample_rate": int(SAMPLE_RATE_HZ),
            "valid": _parse_bool(row["calib_valid"]),
            "source_format": "csv_app",
        }

    return {
        "gyro_bias_lsb": np.zeros(3, dtype=np.float64),
        "gravity_T_lsb": np.array([0.0, 0.0, ACCEL_SENSITIVITY_LSB_PER_G], dtype=np.float64),
        "accel_offsets_lsb": np.zeros(3, dtype=np.float64),
        "gyro_sens": GYRO_SENSITIVITY_LSB_PER_DPS,
        "accel_sens": ACCEL_SENSITIVITY_LSB_PER_G,
        "gyro_range_dps": GYRO_RANGE_DPS_DEFAULT,
        "accel_range_g": ACCEL_RANGE_G_DEFAULT,
        "sample_rate": int(SAMPLE_RATE_HZ),
        "valid": False,
        "source_format": "csv_app",
    }


def resolve_gyro_range_dps(calib: dict[str, Any] | None) -> int:
    """Faixa do giroscópio: cabeçalho firmware ou ±1000°/s legado (CSV app sem header)."""
    if not calib:
        return GYRO_RANGE_DPS_DEFAULT
    if calib.get("source_format") == "firmware_header":
        return int(calib.get("gyro_range_dps", GYRO_RANGE_DPS_DEFAULT))
    return int(calib.get("gyro_range_dps", GYRO_RANGE_DPS_LEGACY))


def convert_to_si(df: pd.DataFrame, calib: dict[str, Any]) -> dict[str, np.ndarray]:
    """Converte amostras brutas — gyro em °/s (Ωp = gy), accel em g."""
    gs = float(calib.get("gyro_sens", GYRO_SENSITIVITY_LSB_PER_DPS))
    as_ = float(calib.get("accel_sens", ACCEL_SENSITIVITY_LSB_PER_G))
    bias = np.asarray(calib["gyro_bias_lsb"], dtype=np.float64)
    accel_off = np.asarray(calib.get("accel_offsets_lsb", np.zeros(3)), dtype=np.float64)

    t_ms = df["t_ms"].to_numpy(dtype=np.float64)
    t = (t_ms - t_ms[0]) / 1000.0

    ax_g = (df["ax_raw"].to_numpy(dtype=np.float64) - accel_off[0]) / as_
    ay_g = (df["ay_raw"].to_numpy(dtype=np.float64) - accel_off[1]) / as_
    az_g = (df["az_raw"].to_numpy(dtype=np.float64) - accel_off[2]) / as_

    gx = (df["gx_raw"].to_numpy(dtype=np.float64) - bias[0]) / gs
    gy = (df["gy_raw"].to_numpy(dtype=np.float64) - bias[1]) / gs  # Ωp
    gz = (df["gz_raw"].to_numpy(dtype=np.float64) - bias[2]) / gs

    accel_mag = np.sqrt(ax_g * ax_g + ay_g * ay_g + az_g * az_g)
    gyro_mag = np.sqrt(gx * gx + gy * gy + gz * gz)

    return {
        "t": t,
        "t_ms": t_ms.astype(np.uint32),
        "ax": ax_g, "ay": ay_g, "az": az_g,
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


def gyro_saturation_percent(signals: dict[str, np.ndarray], axis: str = "gy_raw") -> float:
    """Porcentagem de amostras saturadas — ler_dados.porcentagem_saturacao()."""
    arr = np.abs(signals[axis].astype(np.int64))
    n = len(arr)
    if n == 0:
        return 0.0
    return round(100.0 * float(np.sum(arr >= ADC_SAT_LSB)) / n, 3)


def estimate_fs_hz(signals: dict[str, np.ndarray], fallback: float = SAMPLE_RATE_HZ) -> float:
    """Estima fs a partir de t_ms."""
    t_ms = signals["t_ms"].astype(np.float64)
    if len(t_ms) < 2:
        return fallback
    dt = np.diff(t_ms)
    dt = dt[dt > 0]
    if len(dt) == 0:
        return fallback
    fs = 1000.0 / float(np.median(dt))
    if not np.isfinite(fs) or fs <= 0:
        return fallback
    return fs
