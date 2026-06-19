"""Rótulos e formatação para templates do dashboard."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from app.analysis.constants import GYRO_RANGE_DPS_DEFAULT, GYRO_SENS_TABLE
from app.analysis.preprocessing import resolve_gyro_range_dps

ACCEL_SENS_DEFAULT = 4096.0
G_MS2 = 9.80665

EVENT_TYPE_LABELS = {
    "initial_contact": "Contato inicial",
    "toe_off": "Retirada do pé",
    "mid_swing": "Meio do balanço",
    "manual": "Marcação manual",
    "manual_marker": "Marcação manual",
}

DETECTION_STATUS_LABELS = {
    "ok": "OK",
    "no_metrics": "Sem métricas",
    "insufficient_peaks": "Poucos ciclos",
    "low_confidence": "Baixa confiança",
}


def event_type_label(value: str | None) -> str:
    if not value:
        return "—"
    return EVENT_TYPE_LABELS.get(value, value.replace("_", " "))


def detection_status_label(value: str | None) -> str:
    if not value:
        return "—"
    return DETECTION_STATUS_LABELS.get(value, value)


def format_mean_std(mean, std=None, *, unit: str = "", decimals: int = 0) -> str:
    """Formata média ± desvio padrão para exibição."""
    if mean is None:
        return "—"
    if decimals <= 0:
        m = f"{int(round(float(mean)))}"
        if std is not None and float(std) > 0:
            return f"{m} ± {int(round(float(std)))}{unit}"
        return f"{m}{unit}"
    m = f"{float(mean):.{decimals}f}"
    if std is not None and float(std) > 0:
        return f"{m} ± {float(std):.{decimals}f}{unit}"
    return f"{m}{unit}"


def sensor_gyro_info(calib: dict[str, Any] | None) -> dict[str, Any]:
    """Resumo da faixa dinâmica do giroscópio para exibição."""
    range_dps = resolve_gyro_range_dps(calib)
    is_legacy = calib is None or calib.get("source_format") != "firmware_header"
    return {
        "range_dps": range_dps,
        "range_label": f"±{range_dps} °/s",
        "is_legacy": is_legacy,
        "note": (
            "Coletas anteriores ao firmware com faixa ampliada (±2000 °/s)."
            if is_legacy
            else "Faixa registrada no cabeçalho do CSV (firmware atual)."
        ),
    }


def sensor_gyro_info_from_csv(csv_path: str | Path) -> dict[str, Any]:
    from app.analysis.preprocessing import extract_calibration, load_csv

    df = load_csv(path=csv_path)
    return sensor_gyro_info(extract_calibration(df))


def calibration_display_summary(calib: dict, *, gyro_range_dps: int = 1000) -> dict:
    """Converte calibração de LSB para unidades físicas legíveis."""
    bias_lsb = calib.get("gyro_bias_lsb")
    grav_lsb = calib.get("gravity_T_lsb")
    out: dict = {"present": bool(calib.get("present"))}
    gyro_sens = GYRO_SENS_TABLE.get(gyro_range_dps, 16.4)

    if bias_lsb and len(bias_lsb) == 3:
        out["gyro_bias_dps"] = [round(float(b) / gyro_sens, 2) for b in bias_lsb]
    if grav_lsb and len(grav_lsb) == 3:
        ax = float(grav_lsb[0]) / ACCEL_SENS_DEFAULT
        ay = float(grav_lsb[1]) / ACCEL_SENS_DEFAULT
        az = float(grav_lsb[2]) / ACCEL_SENS_DEFAULT
        out["gravity_g"] = [round(ax, 3), round(ay, 3), round(az, 3)]
        out["gravity_ms2"] = [round(v * G_MS2, 2) for v in (ax, ay, az)]
        out["gravity_norm_g"] = round((ax * ax + ay * ay + az * az) ** 0.5, 3)
    return out
