"""Orquestra análise de runs e persistência."""

from __future__ import annotations

import json
from pathlib import Path

from sqlalchemy.orm import Session

from app.analysis.pipeline import ANALYSIS_VERSION, analyze_dataframe
from app.analysis.preprocessing import convert_to_si, estimate_fs_hz, extract_calibration, load_csv
from app.analysis.window import recording_bounds_ms, slice_dataframe_by_time, validate_window
from app.models import Event, Run, RunAnalysis


def _manual_events(run: Run) -> list[dict]:
    return [
        {
            "type": (e.description or "manual_marker").split()[0].lower(),
            "t_ms": e.timestamp_ms,
            "confidence": 1.0,
            "source": "manual",
            "description": e.description,
        }
        for e in sorted(run.events, key=lambda x: x.timestamp_ms)
    ]


def _filter_events_to_window(
    events: list[dict],
    start_ms: float | None,
    end_ms: float | None,
) -> list[dict]:
    if start_ms is None and end_ms is None:
        return events
    out: list[dict] = []
    for ev in events:
        t = ev["t_ms"]
        if start_ms is not None and t < start_ms:
            continue
        if end_ms is not None and t > end_ms:
            continue
        out.append(ev)
    return out


def analyze_run_file(
    csv_path: Path,
    manual_events: list[dict] | None = None,
    window_start_ms: float | None = None,
    window_end_ms: float | None = None,
    session_name: str = "",
    activity: int | None = None,
    athlete: str = "",
    notes: str = "",
) -> dict:
    """Executa pipeline analítico sobre CSV em disco (opcionalmente recortado)."""
    df = load_csv(path=csv_path)
    rec_start, rec_end = recording_bounds_ms(df)

    start_ms = window_start_ms
    end_ms = window_end_ms
    is_windowed = start_ms is not None or end_ms is not None

    if is_windowed:
        start_ms = start_ms if start_ms is not None else rec_start
        end_ms = end_ms if end_ms is not None else rec_end
        start_ms, end_ms = validate_window(start_ms, end_ms, rec_start, rec_end)
        df = slice_dataframe_by_time(df, start_ms, end_ms)
        if len(df) < 20:
            raise ValueError("Trecho selecionado contém poucas amostras para análise.")
    else:
        start_ms, end_ms = rec_start, rec_end

    name = session_name or csv_path.stem
    result = analyze_dataframe(
        df,
        session_name=name,
        activity=activity,
        athlete=athlete,
        notes=notes,
    )

    result["window"] = {
        "start_ms": start_ms,
        "end_ms": end_ms,
        "start_s": round((start_ms - rec_start) / 1000, 3),
        "end_s": round((end_ms - rec_start) / 1000, 3),
        "duration_s": round((end_ms - start_ms) / 1000, 3),
        "is_windowed": is_windowed,
    }

    manual = _filter_events_to_window(manual_events or [], window_start_ms, window_end_ms)
    auto = result.get("events", [])
    if is_windowed:
        auto = _filter_events_to_window(auto, window_start_ms, window_end_ms)
    if manual:
        merged = manual + auto
        merged.sort(key=lambda e: e["t_ms"])
        result["events"] = merged
        result["events_auto"] = auto
        result["events_manual"] = manual
        result["manual_event_count"] = len(manual)
    else:
        result["events"] = auto
        result["events_auto"] = auto
        result["events_manual"] = []

    return result


def analyze_run_window(
    csv_path: Path,
    manual_events: list[dict] | None,
    start_s: float,
    end_s: float,
    session_name: str = "",
    activity: int | None = None,
    athlete: str = "",
    notes: str = "",
) -> dict:
    """Analisa trecho [start_s, end_s] relativo ao início da coleta (t=0)."""
    df = load_csv(path=csv_path)
    rec_start, rec_end = recording_bounds_ms(df)
    start_ms = rec_start + start_s * 1000
    end_ms = rec_start + end_s * 1000
    return analyze_run_file(
        csv_path,
        manual_events=manual_events,
        window_start_ms=start_ms,
        window_end_ms=end_ms,
        session_name=session_name,
        activity=activity,
        athlete=athlete,
        notes=notes,
    )


def get_or_analyze(
    db: Session,
    run: Run,
    force: bool = False,
) -> tuple[RunAnalysis | None, dict]:
    """
    Retorna análise persistida ou calcula sob demanda.
    Se force=True, recalcula e persiste.
    """
    if not force:
        existing = (
            db.query(RunAnalysis)
            .filter(RunAnalysis.run_id == run.run_id)
            .order_by(RunAnalysis.created_at.desc())
            .first()
        )
        if (
            existing
            and existing.status == "completed"
            and existing.result_json
            and existing.analysis_version == ANALYSIS_VERSION
        ):
            return existing, json.loads(existing.result_json)

    csv_file = Path(run.csv_path)
    if not csv_file.is_file():
        raise FileNotFoundError("Arquivo CSV não encontrado")

    manual = _manual_events(run)
    try:
        result = analyze_run_file(
            csv_file,
            manual_events=manual,
            session_name=Path(run.csv_path).stem,
            activity=run.activity,
            athlete=run.athlete or "",
            notes=run.notes or "",
        )
        status = "completed"
    except Exception as exc:
        result = {"error": str(exc), "analysis_version": ANALYSIS_VERSION}
        status = "failed"

    analysis = RunAnalysis(
        run_id=run.run_id,
        analysis_version=ANALYSIS_VERSION,
        status=status,
        result_json=json.dumps(result, ensure_ascii=False),
    )

    if status == "completed":
        q = result.get("quality", {})
        cad = result.get("cadence") or {}
        gct = result.get("gct") or {}
        analysis.sample_count = q.get("sample_count")
        analysis.duration_ms = int(q.get("duration_s", 0) * 1000)
        analysis.mean_fs_hz = q.get("mean_fs_hz")
        analysis.gap_count = q.get("gap_count")
        analysis.saturation_count = q.get("saturation_count")
        analysis.cadence_spm = cad.get("cadence_spm")
        analysis.steps_detected = cad.get("steps_detected")
        analysis.mean_gct_ms = gct.get("mean_ms")
        analysis.std_gct_ms = gct.get("std_ms")
        flt = result.get("flight_time") or {}
        if flt.get("mean_ms") is not None:
            result.setdefault("flight_time", flt)

    db.add(analysis)
    db.commit()
    db.refresh(analysis)
    return analysis, result


def build_chart_data(csv_path: Path, max_points: int = 2500) -> dict:
    """Prepara séries temporais downsampled para Plotly.js."""
    df = load_csv(path=csv_path)
    calib = extract_calibration(df)
    signals = convert_to_si(df, calib)
    n = len(signals["t"])

    stride = max(1, n // max_points)
    idx = list(range(0, n, stride))

    def pick(key: str) -> list[float]:
        return [float(signals[key][i]) for i in idx]

    t = [float(signals["t"][i]) for i in idx]
    t_origin_ms = float(signals["t_ms"][0])

    return {
        "t": t,
        "t_origin_ms": t_origin_ms,
        "gyro": {"gx": pick("gx"), "gy": pick("gy"), "gz": pick("gz")},
        "sample_count": n,
        "stride": stride,
    }


def build_chart_data_for_run(csv_path: Path, detection_axis: str = "gy", max_points: int = 2500) -> dict:
    """Prepara séries de giroscópio para Plotly (pipeline analisa Ωp)."""
    data = build_chart_data(csv_path, max_points=max_points)
    data["detection_axis"] = detection_axis
    return data
