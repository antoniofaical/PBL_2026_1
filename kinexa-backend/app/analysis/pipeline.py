"""Pipeline analítico central — analyze_dataframe()."""

from __future__ import annotations

from typing import Any

import pandas as pd

from app.analysis.cadence import compute_cadence
from app.analysis.gait_detection import detect_gait_events
from app.analysis.gct import estimate_gct
from app.analysis.preprocessing import convert_to_si, estimate_fs_hz, extract_calibration
from app.analysis.signal_quality import compute_signal_quality

ANALYSIS_VERSION = "1.0.0"


def _try_axes(signals: dict, fs_hz: float) -> dict:
    """Tenta gy, gx, gz até obter detecção utilizável."""
    best: dict | None = None
    for axis in ("gy", "gx", "gz"):
        for min_h in (150.0, 80.0, 40.0):
            result = detect_gait_events(
                signals, fs_hz, axis=axis, min_peak_height=min_h,
            )
            if result["detection_status"] == "ok":
                return result
            if best is None or len(result.get("mid_swing_peaks", [])) > len(
                best.get("mid_swing_peaks", [])
            ):
                best = result
    return best or detect_gait_events(signals, fs_hz)


def analyze_dataframe(df: pd.DataFrame) -> dict[str, Any]:
    """
    Função analítica central — sem I/O nem renderização.
    Reaproveita lógica de ler_dados.py e detectar_eventos.py.
    """
    calib = extract_calibration(df)
    signals = convert_to_si(df, calib)
    fs_hz = estimate_fs_hz(signals)
    quality = compute_signal_quality(signals, calib, fs_hz)

    gait = _try_axes(signals, fs_hz)
    ic_idx = gait["ic_indices"]
    tc_idx = gait["tc_indices"]

    cadence = compute_cadence(ic_idx, fs_hz, quality["duration_s"])
    gct = estimate_gct(ic_idx, tc_idx, fs_hz)

    return {
        "analysis_version": ANALYSIS_VERSION,
        "quality": quality,
        "cadence": cadence,
        "gct": gct,
        "events": gait["events"],
        "detection": {
            "axis": gait.get("axis", "gy"),
            "status": gait.get("detection_status", "unknown"),
            "confidence": gait.get("confidence", 0.0),
            "mid_swing_count": int(len(gait.get("mid_swing_peaks", []))),
        },
        "signals_meta": {
            "fs_hz": fs_hz,
            "calib_valid": calib.get("valid", False),
            "source_format": calib.get("source_format", "unknown"),
        },
    }
