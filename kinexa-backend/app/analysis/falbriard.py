"""
Pipeline Falbriard et al. (2018) — port de analisar_sesi.py v4.

Método: giroscópio de pitch (Ωp = gyro.y) no dorso do pé.
Dois filtros Butterworth: 5 Hz (mid-swing) e 30 Hz (IC/TC).
"""

from __future__ import annotations

from typing import Any

import numpy as np
from scipy.signal import butter, filtfilt, find_peaks

from app.analysis.constants import (
    FALBRIARD_FC_IC_TC_HZ,
    FALBRIARD_FC_MIDSWING_HZ,
    FALBRIARD_PEAK_HEIGHT_DPS,
    FALBRIARD_PEAK_MIN_DISTANCE_HZ,
)


def butter_lowpass(
    signal: np.ndarray,
    fc_hz: float,
    fs_hz: float,
    order: int = 2,
) -> np.ndarray:
    """Butterworth passa-baixa zero-phase — butter_lp() em analisar_sesi.py."""
    signal = np.asarray(signal, dtype=np.float64)
    if len(signal) < 3 * (order + 1):
        return signal.copy()
    fc_hz = min(fc_hz, 0.45 * fs_hz)
    b, a = butter(order, fc_hz / (fs_hz / 2.0), btype="low")
    return filtfilt(b, a, signal)


def trim_stable_window(
    peaks: np.ndarray,
    fs_hz: float,
    min_stride_s: float = 0.20,
    min_steps: int = 5,
) -> np.ndarray:
    """Isola janela estável via IQR dos intervalos entre mid-swings."""
    if len(peaks) < min_steps + 1:
        return np.array([], dtype=int)

    dts = np.diff(peaks.astype(float)) / fs_hz
    q25, q75 = np.percentile(dts, 25), np.percentile(dts, 75)
    iqr = q75 - q25
    margin = 1.5 * iqr
    auto_max = min(2.5, q75 + margin)
    auto_min = max(min_stride_s, q25 - margin)

    valid = (dts >= auto_min) & (dts <= auto_max)
    best_start, best_len, cur_start, cur_len = 0, 0, 0, 0
    for i, ok in enumerate(valid):
        if ok:
            if cur_len == 0:
                cur_start = i
            cur_len += 1
            if cur_len > best_len:
                best_len, best_start = cur_len, cur_start
        else:
            cur_len = 0

    if best_len < min_steps:
        return np.array([], dtype=int)
    return peaks[best_start : best_start + best_len + 1]


def detect_ic_tc(
    omega_p_ict: np.ndarray,
    mid_swing_peaks: np.ndarray,
    margin: int = 5,
) -> tuple[np.ndarray, np.ndarray]:
    """IC e TC = mínimos de Ωp filtrado a 30 Hz entre mid-swings."""
    ic_list: list[int] = []
    tc_list: list[int] = []

    for i in range(len(mid_swing_peaks) - 1):
        p1 = int(mid_swing_peaks[i])
        p2 = int(mid_swing_peaks[i + 1])
        mid = (p1 + p2) // 2
        if p1 + margin < mid:
            ic_list.append(p1 + int(np.argmin(omega_p_ict[p1:mid])))
        if mid + margin < p2:
            tc_list.append(mid + int(np.argmin(omega_p_ict[mid:p2])))

    return np.array(ic_list, dtype=int), np.array(tc_list, dtype=int)


def compute_falbriard_metrics(
    ic: np.ndarray,
    tc: np.ndarray,
    fs_hz: float,
    *,
    is_walking: bool = False,
) -> dict[str, Any] | None:
    """
    Cadência, GCT e FLT — calcular_metricas() em analisar_sesi.py.

    cadência = 2 × 60 / T_stride [spm]
    GCT = T_TC − T_IC [ms]
    FLT = step_time − GCT [ms] (apenas corrida)
    """
    if len(ic) < 3:
        return None

    dt_stride = np.diff(ic.astype(float)) / fs_hz
    dt_stride = dt_stride[(dt_stride > 0.30) & (dt_stride < 2.50)]
    if len(dt_stride) == 0:
        return None

    cad_list = 2.0 * 60.0 / dt_stride

    gcts: list[float] = []
    for ic_idx in ic:
        tcs_after = tc[tc > ic_idx]
        if len(tcs_after):
            gct_ms = (tcs_after[0] - ic_idx) / fs_hz * 1000.0
            if 40 < gct_ms < 1500:
                gcts.append(gct_ms)
    gcts_arr = np.array(gcts, dtype=float)

    stride_ms = float(np.median(dt_stride)) * 1000.0
    step_ms = stride_ms / 2.0
    gct_mean = float(np.mean(gcts_arr)) if len(gcts_arr) else None

    flt_est = None
    flt_list: list[float] = []
    if gct_mean is not None and not is_walking:
        for ic_idx in ic:
            tcs_after = tc[tc > ic_idx]
            if not len(tcs_after):
                continue
            gct_ms = (tcs_after[0] - ic_idx) / fs_hz * 1000.0
            if not (40 < gct_ms < 1500):
                continue
            ics_after = ic[ic > ic_idx]
            if len(ics_after):
                stride_ms = (ics_after[0] - ic_idx) / fs_hz * 1000.0
            else:
                stride_ms = float(np.median(dt_stride)) * 1000.0
            step_ms = stride_ms / 2.0
            flt_ms = step_ms - gct_ms
            if 0 < flt_ms < 400:
                flt_list.append(flt_ms)
        if flt_list:
            flt_est = float(np.mean(flt_list))

    return {
        "cadence_spm": round(float(np.mean(cad_list)), 1),
        "cadence_std_spm": round(float(np.std(cad_list)), 1),
        "cadence_values": [round(float(v), 1) for v in cad_list],
        "gct_mean_ms": round(gct_mean, 0) if gct_mean is not None else None,
        "gct_std_ms": round(float(np.std(gcts_arr)), 0) if len(gcts_arr) else None,
        "gct_values": [round(float(v), 0) for v in gcts_arr],
        "flight_time_ms": round(flt_est, 0) if flt_est is not None else None,
        "flight_time_std_ms": round(float(np.std(flt_list)), 0) if flt_list else None,
        "stride_ms": round(stride_ms, 0),
        "step_ms": round(step_ms, 0),
        "steps_detected": int(len(ic)),
        "method": "falbriard_2018",
    }


def run_falbriard_pipeline(
    omega_p: np.ndarray,
    fs_hz: float,
    *,
    is_walking: bool = False,
) -> dict[str, Any]:
    """Executa detecção completa Falbriard sobre Ωp (gyro.y em °/s)."""
    gp_mid = butter_lowpass(omega_p, FALBRIARD_FC_MIDSWING_HZ, fs_hz)
    gp_ict = butter_lowpass(omega_p, FALBRIARD_FC_IC_TC_HZ, fs_hz)

    distance = max(1, int(fs_hz / FALBRIARD_PEAK_MIN_DISTANCE_HZ))
    peaks_raw, peak_props = find_peaks(
        gp_mid,
        distance=distance,
        height=FALBRIARD_PEAK_HEIGHT_DPS,
    )
    peaks_trim = trim_stable_window(peaks_raw, fs_hz)

    if len(peaks_trim) >= 3:
        ic_idx, tc_idx = detect_ic_tc(gp_ict, peaks_trim)
        metrics = compute_falbriard_metrics(ic_idx, tc_idx, fs_hz, is_walking=is_walking)
        status = "ok" if metrics else "no_metrics"
    else:
        ic_idx = tc_idx = np.array([], dtype=int)
        metrics = None
        status = "insufficient_peaks"

    n_ic = len(ic_idx)
    confidence = min(0.95, 0.4 + 0.05 * n_ic) if n_ic >= 2 else 0.2

    return {
        "status": status,
        "confidence": round(confidence, 2),
        "axis": "gy",
        "mid_swing_peaks_raw": peaks_raw,
        "mid_swing_peaks": peaks_trim,
        "peak_props": peak_props,
        "ic_indices": ic_idx,
        "tc_indices": tc_idx,
        "metrics": metrics,
        "filtered": {
            "mid_swing_hz": FALBRIARD_FC_MIDSWING_HZ,
            "ic_tc_hz": FALBRIARD_FC_IC_TC_HZ,
            "omega_p_mid": gp_mid,
            "omega_p_ict": gp_ict,
        },
    }
