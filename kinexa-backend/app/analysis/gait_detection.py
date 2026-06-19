"""Detecção exploratória de eventos de marcha — baseado em detectar_eventos.py."""

from __future__ import annotations

import numpy as np
from scipy.signal import butter, filtfilt, find_peaks

from app.analysis.constants import SAMPLE_RATE_HZ

# Mapeamento interno → nomes da especificação
EVENT_TYPE_MAP = {
    "mid_swing": "mid_swing",
    "IC": "initial_contact",
    "TC": "toe_off",
}


def lowpass_filter(
    signal: np.ndarray,
    fc_hz: float = 30.0,
    fs_hz: float = SAMPLE_RATE_HZ,
    order: int = 2,
) -> np.ndarray:
    """Butterworth passa-baixa de fase zero — filtrar_passa_baixa()."""
    signal = np.asarray(signal, dtype=np.float64)
    if len(signal) < 3 * (order + 1):
        return signal.copy()

    nyq = fs_hz / 2.0
    if fc_hz >= nyq:
        fc_hz = 0.45 * fs_hz

    b, a = butter(order, fc_hz / nyq, btype="low")
    return filtfilt(b, a, signal)


def detect_mid_swing_peaks(
    omega_p: np.ndarray,
    fs_hz: float = SAMPLE_RATE_HZ,
    max_step_freq_hz: float = 4.0,
    min_height: float = 150.0,
) -> tuple[np.ndarray, dict]:
    """Detecta picos de mid-swing como máximos de Ωp — detectar_ciclos()."""
    dist_min = max(1, int(fs_hz / max_step_freq_hz))
    return find_peaks(omega_p, distance=dist_min, height=min_height)


def detect_ic_tc(
    omega_p: np.ndarray,
    mid_swing_peaks: np.ndarray,
    margin_samples: int = 5,
) -> tuple[np.ndarray, np.ndarray]:
    """IC e TC por mínimos de Ωp entre mid-swings — detectar_ic_tc()."""
    indices_ic: list[int] = []
    indices_tc: list[int] = []

    for i in range(len(mid_swing_peaks) - 1):
        p1 = int(mid_swing_peaks[i])
        p2 = int(mid_swing_peaks[i + 1])
        mid = (p1 + p2) // 2

        if p1 + margin_samples < mid:
            ic = p1 + int(np.argmin(omega_p[p1:mid]))
            indices_ic.append(ic)

        if mid + margin_samples < p2:
            tc = mid + int(np.argmin(omega_p[mid:p2]))
            indices_tc.append(tc)

    return np.array(indices_ic, dtype=int), np.array(indices_tc, dtype=int)


def _event_confidence(height: float, min_height: float) -> float:
    if min_height <= 0:
        return 0.5
    ratio = min(1.0, height / (min_height * 2))
    return round(max(0.3, ratio), 2)


def build_auto_events(
    signals: dict[str, np.ndarray],
    mid_swing_peaks: np.ndarray,
    peak_props: dict,
    ic_indices: np.ndarray,
    tc_indices: np.ndarray,
    axis: str = "gy",
    min_height: float = 150.0,
) -> list[dict]:
    """Monta lista serializável de eventos automáticos."""
    t_ms = signals["t_ms"]
    events: list[dict] = []

    heights = peak_props.get("peak_heights", np.array([]))

    for i, idx in enumerate(mid_swing_peaks):
        conf = _event_confidence(float(heights[i]) if i < len(heights) else min_height, min_height)
        events.append({
            "type": "mid_swing",
            "t_ms": int(t_ms[idx]),
            "confidence": conf,
            "source": "auto",
            "axis": axis,
        })

    for idx in ic_indices:
        events.append({
            "type": "initial_contact",
            "t_ms": int(t_ms[idx]),
            "confidence": 0.65,
            "source": "auto",
            "axis": axis,
            "note": "Falbriard et al. (2018) — mínimo de Ωp entre mid-swings",
        })

    for idx in tc_indices:
        events.append({
            "type": "toe_off",
            "t_ms": int(t_ms[idx]),
            "confidence": 0.60,
            "source": "auto",
            "axis": axis,
            "note": "Falbriard et al. (2018) — mínimo de Ωp entre mid-swings",
        })

    events.sort(key=lambda e: e["t_ms"])
    return events


def detect_gait_events(
    signals: dict[str, np.ndarray],
    fs_hz: float,
    axis: str = "gy",
    fc_hz: float = 30.0,
    min_peak_height: float = 150.0,
    max_step_freq_hz: float = 4.0,
) -> dict:
    """
    Pipeline completo de detecção.
    Retorna eventos, índices e metadados de confiança.
    """
    omega_raw = signals[axis]
    omega_filt = lowpass_filter(omega_raw, fc_hz=fc_hz, fs_hz=fs_hz)

    peaks, props = detect_mid_swing_peaks(
        omega_filt,
        fs_hz=fs_hz,
        max_step_freq_hz=max_step_freq_hz,
        min_height=min_peak_height,
    )

    if len(peaks) < 2:
        return {
            "events": [],
            "ic_indices": np.array([], dtype=int),
            "tc_indices": np.array([], dtype=int),
            "mid_swing_peaks": peaks,
            "confidence": 0.0,
            "axis": axis,
            "detection_status": "insufficient_peaks",
        }

    ic_idx, tc_idx = detect_ic_tc(omega_filt, peaks)
    events = build_auto_events(signals, peaks, props, ic_idx, tc_idx, axis, min_peak_height)

    n_ic = len(ic_idx)
    confidence = min(0.95, 0.4 + 0.05 * n_ic) if n_ic >= 2 else 0.25

    return {
        "events": events,
        "ic_indices": ic_idx,
        "tc_indices": tc_idx,
        "mid_swing_peaks": peaks,
        "confidence": round(confidence, 2),
        "axis": axis,
        "detection_status": "ok" if n_ic >= 2 else "low_confidence",
        "filtered_gy": omega_filt,
    }
