"""Pipeline analítico central — método Falbriard et al. (2018)."""

from __future__ import annotations

from typing import Any

import pandas as pd

from app.analysis.falbriard import run_falbriard_pipeline
from app.analysis.gait_detection import build_auto_events
from app.analysis.literature import FALBRIARD_CITATION, validate_against_literature
from app.analysis.preprocessing import (
    convert_to_si,
    estimate_fs_hz,
    extract_calibration,
    gyro_saturation_percent,
    resolve_gyro_range_dps,
)
from app.analysis.signal_quality import compute_signal_quality

ANALYSIS_VERSION = "2.0.0"


def _infer_walking(session_name: str = "", activity: int | None = None) -> bool:
    """Caminhada não estima FLT; corrida sim."""
    name = session_name.lower()
    if "4kmh" in name or "6kmh" in name or "caminh" in name:
        return True
    # Activity enum app: 0=salto, 1=caminhada, 2=corrida, etc. — ajustar se necessário
    if activity == 1:
        return True
    return False


def _metrics_to_cadence(metrics: dict[str, Any] | None) -> dict[str, Any] | None:
    if not metrics:
        return None
    return {
        "steps_detected": metrics["steps_detected"],
        "cadence_spm": metrics["cadence_spm"],
        "cadence_std_spm": metrics["cadence_std_spm"],
        "cadence_values": metrics.get("cadence_values", []),
        "confidence": 0.75,
        "method": metrics["method"],
        "note": "IC→IC, filtro 5 Hz mid-swing",
    }


def _metrics_to_gct(metrics: dict[str, Any] | None) -> dict[str, Any] | None:
    if not metrics or metrics.get("gct_mean_ms") is None:
        return None
    return {
        "mean_ms": metrics["gct_mean_ms"],
        "std_ms": metrics.get("gct_std_ms"),
        "values": metrics.get("gct_values", []),
        "confidence": 0.70,
        "status": "estimated",
        "method": metrics["method"],
        "note": "GCT = TC − IC (Ωp mínimo entre mid-swings, filtro 30 Hz)",
    }


def _metrics_to_flt(metrics: dict[str, Any] | None) -> dict[str, Any] | None:
    if not metrics or metrics.get("flight_time_ms") is None:
        return None
    return {
        "mean_ms": metrics["flight_time_ms"],
        "std_ms": metrics.get("flight_time_std_ms"),
        "method": metrics["method"],
        "note": "Tempo de voo = duração do passo − tempo de contato",
    }


def analyze_dataframe(
    df: pd.DataFrame,
    *,
    session_name: str = "",
    activity: int | None = None,
    athlete: str = "",
    notes: str = "",
) -> dict[str, Any]:
    """
    Pipeline Falbriard v4 — port de analisar_sesi.py + ler_dados.py.
    """
    calib = extract_calibration(df)
    signals = convert_to_si(df, calib)
    fs_hz = estimate_fs_hz(signals)
    quality = compute_signal_quality(signals, calib, fs_hz)
    quality["gyro_saturation_pct"] = gyro_saturation_percent(signals, "gy_raw")
    quality["gyro_range_dps"] = resolve_gyro_range_dps(calib)

    is_walking = _infer_walking(session_name, activity)
    falbriard = run_falbriard_pipeline(signals["gy"], fs_hz, is_walking=is_walking)

    ic_idx = falbriard["ic_indices"]
    tc_idx = falbriard["tc_indices"]
    peaks_trim = falbriard["mid_swing_peaks"]
    metrics = falbriard["metrics"]

    events = build_auto_events(
        signals,
        peaks_trim,
        falbriard["peak_props"],
        ic_idx,
        tc_idx,
        axis="gy",
        min_height=80.0,
    )

    cadence = _metrics_to_cadence(metrics)
    gct = _metrics_to_gct(metrics)
    flt = _metrics_to_flt(metrics)

    literature = validate_against_literature(
        session_name,
        athlete,
        notes,
        cadence_spm=cadence["cadence_spm"] if cadence else None,
        gct_ms=gct["mean_ms"] if gct else None,
        flt_ms=flt["mean_ms"] if flt else None,
    )

    return {
        "analysis_version": ANALYSIS_VERSION,
        "method": {
            "name": "falbriard_2018",
            "citation": FALBRIARD_CITATION,
            "axis": "gy",
            "axis_label": "Ωp (pitch angular velocity)",
            "filters_hz": {"mid_swing": 5.0, "ic_tc": 30.0},
            "is_walking": is_walking,
        },
        "quality": quality,
        "cadence": cadence,
        "gct": gct,
        "flight_time": flt,
        "literature_validation": literature,
        "events": events,
        "detection": {
            "axis": "gy",
            "status": falbriard["status"],
            "confidence": falbriard["confidence"],
            "mid_swing_count_raw": int(len(falbriard["mid_swing_peaks_raw"])),
            "mid_swing_count": int(len(peaks_trim)),
            "ic_count": int(len(ic_idx)),
            "tc_count": int(len(tc_idx)),
        },
        "signals_meta": {
            "fs_hz": fs_hz,
            "calib_valid": calib.get("valid", False),
            "source_format": calib.get("source_format", "unknown"),
            "gyro_range_dps": calib.get("gyro_range_dps"),
            "gyro_sens_lsb_per_dps": calib.get("gyro_sens"),
        },
        "metrics_raw": metrics,
    }
