"""Calibração MPU6050 — extração do CSV e persistência no Run."""

from __future__ import annotations

from io import StringIO
from typing import Any

import numpy as np
import pandas as pd

from app.analysis.preprocessing import extract_calibration, load_csv
from app.models import Run

# Origem dos dados de calibração (firmware → app → backend)
CALIB_SOURCE_CSV = "csv"
CALIB_SOURCE_APP = "app"
CALIB_SOURCE_FIRMWARE = "firmware"
CALIB_SOURCE_MANUAL = "manual"


def gravity_norm_lsb(gravity_T_lsb: tuple[float, float, float] | None) -> float | None:
    if gravity_T_lsb is None:
        return None
    arr = np.asarray(gravity_T_lsb, dtype=np.float64)
    if arr.size != 3:
        return None
    return float(np.linalg.norm(arr))


def calibration_from_csv_content(csv_content: str) -> dict[str, Any] | None:
    """Extrai calibração do CSV; None se schema app (sem colunas de calib)."""
    df = load_csv(content=csv_content)
    calib = extract_calibration(df)
    if calib.get("source_format") != "csv_serial":
        return None
    bias = calib["gyro_bias_lsb"]
    grav = calib["gravity_T_lsb"]
    return {
        "calib_gx_bias_lsb": float(bias[0]),
        "calib_gy_bias_lsb": float(bias[1]),
        "calib_gz_bias_lsb": float(bias[2]),
        "calib_g_T_x_lsb": float(grav[0]),
        "calib_g_T_y_lsb": float(grav[1]),
        "calib_g_T_z_lsb": float(grav[2]),
        "calib_valid": bool(calib.get("valid", False)),
        "calib_source": CALIB_SOURCE_CSV,
    }


def calibration_from_csv_path(path: str) -> dict[str, Any] | None:
    from pathlib import Path

    content = Path(path).read_text(encoding="utf-8")
    return calibration_from_csv_content(content)


def apply_calibration_to_run(run: Run, calib: dict[str, Any] | None) -> None:
    """Aplica dict de calibração ao modelo Run (ou limpa se None)."""
    if calib is None:
        run.calib_gx_bias_lsb = None
        run.calib_gy_bias_lsb = None
        run.calib_gz_bias_lsb = None
        run.calib_g_T_x_lsb = None
        run.calib_g_T_y_lsb = None
        run.calib_g_T_z_lsb = None
        run.calib_valid = None
        run.calib_source = None
        return

    run.calib_gx_bias_lsb = calib.get("calib_gx_bias_lsb")
    run.calib_gy_bias_lsb = calib.get("calib_gy_bias_lsb")
    run.calib_gz_bias_lsb = calib.get("calib_gz_bias_lsb")
    run.calib_g_T_x_lsb = calib.get("calib_g_T_x_lsb")
    run.calib_g_T_y_lsb = calib.get("calib_g_T_y_lsb")
    run.calib_g_T_z_lsb = calib.get("calib_g_T_z_lsb")
    run.calib_valid = calib.get("calib_valid")
    run.calib_source = calib.get("calib_source", CALIB_SOURCE_CSV)


def run_has_calibration(run: Run) -> bool:
    return run.calib_gx_bias_lsb is not None and run.calib_valid is not None


def run_calibration_summary(run: Run) -> dict[str, Any]:
    """Resumo para templates/API."""
    grav = None
    if run.calib_g_T_x_lsb is not None:
        grav = (run.calib_g_T_x_lsb, run.calib_g_T_y_lsb, run.calib_g_T_z_lsb)
    return {
        "gyro_bias_lsb": (
            [run.calib_gx_bias_lsb, run.calib_gy_bias_lsb, run.calib_gz_bias_lsb]
            if run.calib_gx_bias_lsb is not None
            else None
        ),
        "gravity_T_lsb": list(grav) if grav else None,
        "gravity_norm_lsb": gravity_norm_lsb(grav),
        "valid": run.calib_valid,
        "source": run.calib_source,
        "present": run_has_calibration(run),
    }
