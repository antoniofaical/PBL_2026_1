"""Estimativa de Ground Contact Time — baseado em detectar_eventos.calcular_metricas()."""

from __future__ import annotations

import numpy as np


def estimate_gct(
    ic_indices: np.ndarray,
    tc_indices: np.ndarray,
    fs_hz: float,
    min_confidence: float = 0.5,
) -> dict | None:
    """
    GCT = tempo entre initial_contact e toe_off (estimativa exploratória).
    Retorna None se não houver pares confiáveis.
    """
    if len(ic_indices) == 0 or len(tc_indices) == 0:
        return None

    gct_values: list[float] = []
    for ic in ic_indices:
        tcs_after = tc_indices[tc_indices > ic]
        if len(tcs_after) > 0:
            gct_ms = (tcs_after[0] - ic) / fs_hz * 1000.0
            if 50 < gct_ms < 600:
                gct_values.append(gct_ms)

    if len(gct_values) < 2:
        return None

    arr = np.array(gct_values, dtype=float)
    mean_ms = float(np.mean(arr))
    std_ms = float(np.std(arr))

    cv = std_ms / mean_ms if mean_ms > 0 else 1.0
    confidence = max(0.2, min(0.85, 0.45 + len(gct_values) * 0.03 - cv * 0.4))

    if confidence < min_confidence:
        return {
            "mean_ms": round(mean_ms, 0),
            "std_ms": round(std_ms, 0),
            "values": [round(v, 0) for v in gct_values],
            "confidence": round(confidence, 2),
            "status": "low_confidence",
            "note": "estimativa exploratória — requer validação",
        }

    return {
        "mean_ms": round(mean_ms, 0),
        "std_ms": round(std_ms, 0),
        "values": [round(v, 0) for v in gct_values],
        "confidence": round(confidence, 2),
        "status": "estimated",
        "note": "estimado por IMU — detecção exploratória",
    }
