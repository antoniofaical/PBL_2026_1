"""Cálculo de cadência — baseado em detectar_eventos.calcular_metricas()."""

from __future__ import annotations

import numpy as np


def compute_cadence(
    ic_indices: np.ndarray,
    fs_hz: float,
    duration_s: float,
) -> dict | None:
    """
    Cadência a partir de intervalos entre IC consecutivos.
    Fórmula: cadence_spm = 2 * 60 / intervalo_ic (passos por minuto).
    """
    if len(ic_indices) < 2 or duration_s <= 0:
        return None

    intervals_s = np.diff(ic_indices) / fs_hz
    intervals_s = intervals_s[intervals_s > 0]
    if len(intervals_s) == 0:
        return None

    cadence_per_interval = 2 * 60.0 / intervals_s
    mean_spm = float(np.mean(cadence_per_interval))
    std_spm = float(np.std(cadence_per_interval))
    steps = int(len(ic_indices))

    # Confiança heurística: mais passos e menor variabilidade → maior confiança
    cv = std_spm / mean_spm if mean_spm > 0 else 1.0
    confidence = max(0.2, min(0.95, 0.5 + steps * 0.02 - cv * 0.3))

    return {
        "steps_detected": steps,
        "cadence_spm": round(mean_spm, 1),
        "cadence_std_spm": round(std_spm, 1),
        "confidence": round(confidence, 2),
        "method": "ic_intervals",
        "note": "estimado por IMU — detecção exploratória",
    }
