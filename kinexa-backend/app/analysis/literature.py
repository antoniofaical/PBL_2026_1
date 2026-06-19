"""Faixas de referência e validação contra literatura — analisar_sesi.py REFS."""

from __future__ import annotations

from typing import Any

# Faixas coletadas nas sessões SESI / protocolo do projeto (comparativo interno)
LITERATURE_REFS: dict[str, dict[str, Any]] = {
    "otavio_4kmh": {
        "cad": (100, 120),
        "gct_ms": (580, 800),
        "flt_ms": None,
        "label": "Otávio 4 km/h (caminhada)",
    },
    "otavio_6kmh": {
        "cad": (115, 135),
        "gct_ms": (540, 680),
        "flt_ms": None,
        "label": "Otávio 6 km/h (caminhada rápida)",
    },
    "bruno_10kmh": {
        "cad": (155, 180),
        "gct_ms": (200, 295),
        "flt_ms": (80, 160),
        "label": "Bruno 10 km/h (corrida)",
    },
    "bruno_12kmh": {
        "cad": (160, 185),
        "gct_ms": (180, 265),
        "flt_ms": (90, 165),
        "label": "Bruno 12 km/h (corrida)",
    },
    "bruno_14kmh": {
        "cad": (165, 192),
        "gct_ms": (165, 245),
        "flt_ms": (95, 170),
        "label": "Bruno 14 km/h (corrida)",
    },
    "bruno_outside": {
        "cad": (230, 340),
        "gct_ms": (80, 160),
        "flt_ms": (75, 160),
        "label": "Bruno pista (sprint)",
    },
    "cristofer_outside": {
        "cad": (150, 270),
        "gct_ms": (80, 260),
        "flt_ms": (70, 180),
        "label": "Cristofer pista (T11)",
    },
}

FALBRIARD_CITATION = (
    "Falbriard M, Meyer F, Mariani B, Millet GP, Aminian K (2018). "
    "Accurate Estimation of Running Temporal Parameters Using Foot-Worn Inertial Sensors. "
    "Frontiers in Physiology 9:610. doi:10.3389/fphys.2018.00610"
)


def match_literature_key(name: str) -> str | None:
    """Associa nome de arquivo/sessão a uma chave de referência interna."""
    lowered = name.lower()
    for key in LITERATURE_REFS:
        if key in lowered:
            return key
    return None


def _in_range(value: float | None, band: tuple[float, float] | None) -> str:
    if band is None or value is None:
        return "na"
    lo, hi = band
    if lo <= value <= hi:
        return "ok"
    return "warn"


def validate_against_literature(
    *name_hints: str,
    cadence_spm: float | None = None,
    gct_ms: float | None = None,
    flt_ms: float | None = None,
) -> dict[str, Any] | None:
    """Compara métricas estimadas com faixas do protocolo SESI."""
    key = None
    for hint in name_hints:
        if hint:
            key = match_literature_key(hint)
            if key:
                break
    if key is None:
        return None

    ref = LITERATURE_REFS[key]
    cad_status = _in_range(cadence_spm, ref["cad"])
    gct_status = _in_range(gct_ms, ref["gct_ms"])
    flt_status = _in_range(flt_ms, ref.get("flt_ms"))

    return {
        "key": key,
        "label": ref["label"],
        "cadence": {"status": cad_status, "range_spm": ref["cad"]},
        "gct": {"status": gct_status, "range_ms": ref["gct_ms"]},
        "flight_time": {"status": flt_status, "range_ms": ref.get("flt_ms")},
        "overall": (
            "ok"
            if all(s in ("ok", "na") for s in (cad_status, gct_status, flt_status))
            else "warn"
        ),
    }
