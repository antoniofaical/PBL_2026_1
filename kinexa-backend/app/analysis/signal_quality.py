"""Métricas de qualidade do sinal IMU."""

from __future__ import annotations

from typing import Any

import numpy as np

from app.analysis.constants import ACCEL_SAT_LSB, GYRO_SAT_LSB, SAMPLE_RATE_HZ
from app.analysis.preprocessing import estimate_fs_hz


def _count_gaps(t_ms: np.ndarray, gap_factor: float = 3.0) -> int:
    if len(t_ms) < 2:
        return 0
    dt = np.diff(t_ms.astype(np.float64))
    dt = dt[dt > 0]
    if len(dt) == 0:
        return len(t_ms) - 1
    median_dt = float(np.median(dt))
    if median_dt <= 0:
        return 0
    return int(np.sum(dt > gap_factor * median_dt))


def _count_saturation(signals: dict[str, np.ndarray]) -> int:
    count = 0
    for key in ("ax_raw", "ay_raw", "az_raw"):
        arr = np.abs(signals[key])
        count += int(np.sum(arr >= ACCEL_SAT_LSB))
    for key in ("gx_raw", "gy_raw", "gz_raw"):
        arr = np.abs(signals[key])
        count += int(np.sum(arr >= GYRO_SAT_LSB))
    return count


def compute_signal_quality(
    signals: dict[str, np.ndarray],
    calib: dict[str, Any],
    fs_hz: float | None = None,
) -> dict[str, Any]:
    """Calcula indicadores de qualidade da coleta."""
    n = len(signals["t"])
    t_ms = signals["t_ms"]
    duration_s = float(signals["t"][-1]) if n > 1 else 0.0
    fs = fs_hz if fs_hz is not None else estimate_fs_hz(signals)

    gap_count = _count_gaps(t_ms)
    saturation_count = _count_saturation(signals)

    axes_present = all(k in signals for k in ("ax", "ay", "az", "gx", "gy", "gz"))

    status = "valid"
    reasons: list[str] = []

    if n < 100:
        status = "invalid"
        reasons.append("amostras insuficientes")
    elif duration_s < 2.0:
        status = "suspect"
        reasons.append("duração curta")
    elif gap_count > 0:
        status = "suspect"
        reasons.append("gaps temporais")
    elif saturation_count > n * 0.01:
        status = "suspect"
        reasons.append("possível saturação")
    elif not calib.get("valid", False):
        status = "suspect"
        reasons.append("calibração não confirmada no CSV")
    elif abs(fs - SAMPLE_RATE_HZ) > 50:
        status = "suspect"
        reasons.append("taxa de amostragem atípica")

    if not axes_present:
        status = "invalid"
        reasons.append("eixos ausentes")

    return {
        "sample_count": n,
        "duration_s": round(duration_s, 2),
        "mean_fs_hz": round(fs, 1),
        "gap_count": gap_count,
        "saturation_count": saturation_count,
        "axes_present": axes_present,
        "calib_valid": bool(calib.get("valid", False)),
        "quality_status": status,
        "quality_notes": reasons,
    }
