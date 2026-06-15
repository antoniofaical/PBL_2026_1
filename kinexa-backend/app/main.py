from contextlib import asynccontextmanager
from pathlib import Path
import json

from fastapi import Depends, FastAPI, Form, HTTPException, Query, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app import crud
from app.calibration import run_calibration_summary
from app.config import ACTIVITY_LABELS, ENVIRONMENT_LABELS, UPLOAD_DIR
from app.database import create_tables, get_db
from app.schemas import (
    RunDetail,
    RunRead,
    RunUpdate,
    RunUpload,
    UploadCreatedResponse,
    UploadExistsResponse,
)
from app.services.analysis_service import (
    analyze_run_window,
    build_chart_data_for_run,
    get_or_analyze,
)

BASE_DIR = Path(__file__).resolve().parent
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))


def _template_context(request: Request, **extra):
    return {
        "request": request,
        "activity_labels": ACTIVITY_LABELS,
        "environment_labels": ENVIRONMENT_LABELS,
        **extra,
    }


def _abbreviate_run_id(run_id: str, length: int = 12) -> str:
    if len(run_id) <= length:
        return run_id
    return f"{run_id[:length]}…"


templates.env.filters["abbreviate_run_id"] = _abbreviate_run_id
templates.env.filters["activity_label"] = lambda v: ACTIVITY_LABELS.get(v, str(v))
templates.env.filters["environment_label"] = lambda v: ENVIRONMENT_LABELS.get(v, str(v))

QUALITY_LABELS = {
    "valid": "Válida",
    "suspect": "Suspeita",
    "invalid": "Inválida",
}
ANALYSIS_STATUS_LABELS = {
    "completed": "Concluída",
    "failed": "Falha",
    "pending": "Pendente",
}
CALIB_SOURCE_LABELS = {
    "csv": "CSV / receptor BLE",
    "app": "App (sync)",
    "firmware": "Firmware",
    "manual": "Manual",
}
templates.env.filters["quality_label"] = lambda v: QUALITY_LABELS.get(v, "—") if v else "—"
templates.env.filters["analysis_status_label"] = (
    lambda v: ANALYSIS_STATUS_LABELS.get(v, "Pendente") if v else "Pendente"
)
templates.env.filters["calib_source_label"] = (
    lambda v: CALIB_SOURCE_LABELS.get(v, v or "—") if v else "—"
)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    create_tables()
    yield


app = FastAPI(title="Kinexa Backend", version="1.0.0", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")


# --- API ---


@app.get("/api/health")
def health_check():
    return {"status": "ok"}


@app.post(
    "/api/runs/upload",
    response_model=UploadCreatedResponse | UploadExistsResponse,
)
def upload_run(payload: RunUpload, db: Session = Depends(get_db)):
    existing = crud.get_run(db, payload.run_id)
    if existing:
        return UploadExistsResponse(status="already_exists", run_id=payload.run_id)

    try:
        run, sample_count = crud.create_run_from_upload(db, payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except OSError as exc:
        raise HTTPException(
            status_code=500, detail=f"Falha ao salvar CSV: {exc}"
        ) from exc

    return UploadCreatedResponse(
        status="created",
        run_id=run.run_id,
        sample_count=sample_count,
    )


@app.get("/api/runs", response_model=list[RunRead])
def list_runs(
    limit: int | None = Query(None, ge=1, le=500),
    skip: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    return crud.get_runs(db, skip=skip, limit=limit)


@app.get("/api/runs/{run_id}", response_model=RunDetail)
def get_run_detail(run_id: str, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    return run


@app.get("/api/runs/{run_id}/csv")
def download_csv(run_id: str, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")

    csv_file = Path(run.csv_path)
    if not csv_file.is_file():
        raise HTTPException(status_code=404, detail="Arquivo CSV não encontrado")

    return FileResponse(
        path=csv_file,
        media_type="text/csv",
        filename=f"{run_id}.csv",
    )


@app.put("/api/runs/{run_id}", response_model=RunDetail)
def update_run_api(run_id: str, payload: RunUpdate, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    return crud.update_run(db, run, payload)


@app.delete("/api/runs/{run_id}")
def delete_run(run_id: str, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")

    try:
        crud.delete_run(db, run)
    except OSError as exc:
        raise HTTPException(
            status_code=500, detail=f"Falha ao remover CSV: {exc}"
        ) from exc

    return {"status": "deleted", "run_id": run_id}


@app.get("/api/runs/{run_id}/analysis/window")
def get_run_analysis_window(
    run_id: str,
    start_s: float = Query(..., ge=0, description="Início do trecho (s, relativo ao início da coleta)"),
    end_s: float = Query(..., gt=0, description="Fim do trecho (s, relativo)"),
    db: Session = Depends(get_db),
):
    """Reprocessa métricas e eventos apenas no trecho selecionado (não persiste)."""
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    csv_file = Path(run.csv_path)
    if not csv_file.is_file():
        raise HTTPException(status_code=404, detail="Arquivo CSV não encontrado")

    manual = [
        {
            "type": (e.description or "manual_marker").split()[0].lower(),
            "t_ms": e.timestamp_ms,
            "confidence": 1.0,
            "source": "manual",
            "description": e.description,
        }
        for e in sorted(run.events, key=lambda x: x.timestamp_ms)
    ]
    try:
        return analyze_run_window(csv_file, manual_events=manual, start_s=start_s, end_s=end_s)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/api/runs/{run_id}/analysis")
def get_run_analysis(
    run_id: str,
    force: bool = Query(False),
    db: Session = Depends(get_db),
):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    try:
        _record, result = get_or_analyze(db, run, force=force)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return result


@app.get("/api/runs/{run_id}/charts")
def get_run_charts(run_id: str, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    csv_file = Path(run.csv_path)
    if not csv_file.is_file():
        raise HTTPException(status_code=404, detail="Arquivo CSV não encontrado")
    try:
        return build_chart_data_for_run(csv_file)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/api/runs/{run_id}/analysis/export")
def export_analysis_json(run_id: str, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    try:
        _record, result = get_or_analyze(db, run, force=False)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return JSONResponse(
        content=result,
        headers={"Content-Disposition": f'attachment; filename="{run_id}_analysis.json"'},
    )


@app.get("/api/runs/{run_id}/events/export")
def export_events_csv(run_id: str, db: Session = Depends(get_db)):
    """Exporta eventos manuais + automáticos em CSV."""
    import csv
    import io

    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    try:
        _record, result = get_or_analyze(db, run, force=False)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    events = result.get("events", [])
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(["type", "t_ms", "t_s", "confidence", "source", "description"])
    for ev in events:
        writer.writerow([
            ev.get("type", ""),
            ev.get("t_ms", ""),
            round(ev.get("t_ms", 0) / 1000, 3),
            ev.get("confidence", ""),
            ev.get("source", ""),
            ev.get("description", ev.get("note", "")),
        ])

    from fastapi.responses import Response
    return Response(
        content=buffer.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{run_id}_events.csv"'},
    )


# --- Admin site ---


@app.get("/", response_class=HTMLResponse)
def dashboard(request: Request, db: Session = Depends(get_db)):
    stats = crud.get_dashboard_stats(db)
    seeded = request.query_params.get("seeded")
    return templates.TemplateResponse(
        request,
        "dashboard.html",
        _template_context(request, seeded=seeded, **stats),
    )


@app.post("/dev/seed-run")
def seed_demo_run(db: Session = Depends(get_db)):
    """Temporário: insere coleta simulada para testes locais."""
    run = crud.create_simulated_run(db)
    return RedirectResponse(url=f"/?seeded={run.run_id}", status_code=303)


@app.get("/runs", response_class=HTMLResponse)
def runs_page(request: Request, db: Session = Depends(get_db)):
    runs_enriched = crud.get_runs_with_analysis(db)
    deleted = request.query_params.get("deleted") == "1"
    return templates.TemplateResponse(
        request,
        "runs.html",
        _template_context(request, runs_enriched=runs_enriched, deleted=deleted),
    )


@app.get("/runs/{run_id}", response_class=HTMLResponse)
def run_detail_page(run_id: str, request: Request, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")

    csv_preview: list[str] = []
    csv_file = Path(run.csv_path)
    if csv_file.is_file():
        try:
            lines = csv_file.read_text(encoding="utf-8").splitlines()
            csv_preview = lines[:11]
        except OSError:
            csv_preview = []

    updated = request.query_params.get("updated") == "1"
    analyzed = request.query_params.get("analyzed") == "1"
    latest_analysis = crud.get_latest_analysis(db, run_id)

    return templates.TemplateResponse(
        request,
        "run_detail.html",
        _template_context(
            request,
            run=run,
            csv_preview=csv_preview,
            updated=updated,
            analyzed=analyzed,
            latest_analysis=latest_analysis,
            calib=run_calibration_summary(run),
        ),
    )


@app.get("/runs/{run_id}/edit", response_class=HTMLResponse)
def run_edit_page(run_id: str, request: Request, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")

    return templates.TemplateResponse(
        request,
        "run_edit.html",
        _template_context(
            request,
            run=run,
            events_text=crud.events_to_text(run.events),
            error=None,
        ),
    )


@app.post("/runs/{run_id}/edit", response_class=HTMLResponse)
def run_edit_submit(
    run_id: str,
    request: Request,
    device_id: str = Form(...),
    datetime: str = Form(...),
    athlete: str = Form(...),
    activity: int = Form(...),
    environment: int = Form(...),
    notes: str = Form(""),
    events_text: str = Form(""),
    db: Session = Depends(get_db),
):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")

    form_ctx = {
        "run": run,
        "events_text": events_text,
        "form": {
            "device_id": device_id,
            "datetime": datetime,
            "athlete": athlete,
            "activity": activity,
            "environment": environment,
            "notes": notes,
        },
    }

    try:
        events = crud.parse_events_text(events_text)
        payload = RunUpdate(
            device_id=device_id.strip(),
            datetime=datetime.strip(),
            athlete=athlete.strip(),
            activity=activity,
            environment=environment,
            notes=notes.strip() or None,
            events=events,
        )
        crud.update_run(db, run, payload)
    except ValueError as exc:
        return templates.TemplateResponse(
            request,
            "run_edit.html",
            _template_context(request, error=str(exc), **form_ctx),
            status_code=400,
        )

    return RedirectResponse(url=f"/runs/{run_id}?updated=1", status_code=303)


@app.post("/runs/{run_id}/delete")
def run_delete_web(run_id: str, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")

    try:
        crud.delete_run(db, run)
    except OSError as exc:
        raise HTTPException(
            status_code=500, detail=f"Falha ao remover CSV: {exc}"
        ) from exc

    return RedirectResponse(url="/runs?deleted=1", status_code=303)


@app.post("/runs/{run_id}/analyze")
def run_analyze_web(run_id: str, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    try:
        get_or_analyze(db, run, force=True)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return RedirectResponse(url=f"/runs/{run_id}/analysis?analyzed=1", status_code=303)


@app.post("/runs/{run_id}/quality")
def run_quality_web(
    run_id: str,
    quality_status: str = Form(...),
    db: Session = Depends(get_db),
):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    try:
        crud.set_quality_status(db, run, quality_status)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    referer = request.headers.get("referer", f"/runs/{run_id}")
    if "/analysis" in referer:
        return RedirectResponse(url=f"/runs/{run_id}/analysis", status_code=303)
    return RedirectResponse(url=f"/runs/{run_id}?updated=1", status_code=303)


@app.get("/runs/{run_id}/analysis", response_class=HTMLResponse)
def run_analysis_page(run_id: str, request: Request, db: Session = Depends(get_db)):
    run = crud.get_run(db, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")

    csv_file = Path(run.csv_path)
    if not csv_file.is_file():
        raise HTTPException(status_code=404, detail="Arquivo CSV não encontrado")

    analyzed = request.query_params.get("analyzed") == "1"
    force = request.query_params.get("force") == "1"

    try:
        analysis_record, result = get_or_analyze(db, run, force=force)
        detection_axis = result.get("detection", {}).get("axis", "gy")
        chart_data = build_chart_data_for_run(csv_file, detection_axis=detection_axis)
    except (FileNotFoundError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return templates.TemplateResponse(
        request,
        "run_analysis.html",
        _template_context(
            request,
            run=run,
            analysis=result,
            analysis_record=analysis_record,
            chart_json=json.dumps(chart_data),
            events_json=json.dumps(result.get("events", [])),
            analyzed=analyzed,
            calib=run_calibration_summary(run),
            window_json=json.dumps(result.get("window", {})),
        ),
    )
