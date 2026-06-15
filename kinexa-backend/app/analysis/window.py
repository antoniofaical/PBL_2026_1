"""Recorte temporal de coletas para análise por trecho."""

from __future__ import annotations

import pandas as pd

MIN_WINDOW_MS = 3000


def slice_dataframe_by_time(
    df: pd.DataFrame,
    start_ms: float | None = None,
    end_ms: float | None = None,
) -> pd.DataFrame:
    """Retorna linhas com t_ms dentro de [start_ms, end_ms] (inclusivo)."""
    if start_ms is None and end_ms is None:
        return df

    mask = pd.Series(True, index=df.index)
    if start_ms is not None:
        mask &= df["t_ms"] >= start_ms
    if end_ms is not None:
        mask &= df["t_ms"] <= end_ms
    return df.loc[mask].reset_index(drop=True)


def recording_bounds_ms(df: pd.DataFrame) -> tuple[float, float]:
    """Limites absolutos da coleta em milissegundos."""
    t = df["t_ms"].to_numpy(dtype=float)
    return float(t[0]), float(t[-1])


def validate_window(
    start_ms: float,
    end_ms: float,
    rec_start_ms: float,
    rec_end_ms: float,
) -> tuple[float, float]:
    """Normaliza e valida janela contra os limites da coleta."""
    start = max(rec_start_ms, min(start_ms, rec_end_ms))
    end = max(rec_start_ms, min(end_ms, rec_end_ms))
    if end <= start:
        raise ValueError("Fim da janela deve ser posterior ao início.")
    if end - start < MIN_WINDOW_MS:
        raise ValueError(
            f"Janela mínima de {MIN_WINDOW_MS / 1000:.1f} s — selecione um trecho maior."
        )
    return start, end
