from contextlib import asynccontextmanager
from pathlib import Path
import json

from fastapi import Depends, FastAPI, Form, HTTPException, Query, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from starlette.middleware.sessions import SessionMiddleware

from app import crud
from app.auth import authenticate_user, get_user_by_username
from app.auth_middleware import AuthMiddleware, CurrentUser
from app.calibration import run_calibration_summary
from app.config import ACTIVITY_LABELS, ENVIRONMENT_LABELS, SECRET_KEY, SESSION_MAX_AGE, UPLOAD_DIR
from app.display_labels import (
    calibration_display_summary,
    detection_status_label,
    event_type_label,
    format_mean_std,
    sensor_gyro_info_from_csv,
)
from app.database import create_tables, get_db
from app.models import Run, User
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

AUTH_ERRORS = {
    "invalid": "Usuário ou senha incorretos.",
    "required": "Informe usuário e senha.",
    "session": "Sessão expirada. Entre novamente.",
}


def _template_context(request: Request, **extra):
    return {
        "request": request,
        "current_user": getattr(request.state, "user", None),
        "activity_labels": ACTIVITY_LABELS,
        "environment_labels": ENVIRONMENT_LABELS,
        **extra,
    }


def _require_run(db: Session, run_id: str, user: User) -> Run:
    run = crud.get_run(db, run_id, user.id)
    if not run:
        raise HTTPException(status_code=404, detail="Coleta não encontrada")
    return run


def _admin_user_id(db: Session) -> int:
    admin = get_user_by_username(db, "admin")
    if not admin:
        raise HTTPException(
            status_code=503,
            detail="Usuário admin não configurado. Reinicie o servidor.",
        )
    return admin.id


def _abbreviate_run_id(run_id: str, length: int = 12) -> str:
    if len(run_id) <= length:
        return run_id
    return f"{run_id[:length]}…"


templates.env.filters["abbreviate_run_id"] = _abbreviate_run_id
templates.env.filters["activity_label"] = lambda v: ACTIVITY_LABELS.get(v, str(v))
templates.env.filters["environment_label"] = lambda v: ENVIRONMENT_LABELS.get(v, str(v))

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
templates.env.filters["analysis_status_label"] = (
    lambda v: ANALYSIS_STATUS_LABELS.get(v, "Pendente") if v else "Pendente"
)
templates.env.filters["calib_source_label"] = (
    lambda v: CALIB_SOURCE_LABELS.get(v, v or "—") if v else "—"
)
templates.env.filters["event_type_label"] = event_type_label
templates.env.filters["detection_status_label"] = detection_status_label
templates.env.filters["format_mean_std"] = format_mean_std
templates.env.filters["calib_display"] = calibration_display_summary


@asynccontextmanager
async def lifespan(_app: FastAPI):
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    create_tables()
    yield


app = FastAPI(title="Kinexa Backend", version="1.0.0", lifespan=lifespan)
app.add_middleware(AuthMiddleware)
app.add_middleware(SessionMiddleware, secret_key=SECRET_KEY, max_age=SESSION_MAX_AGE)
app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")


# --- Auth ---


@app.get("/login", response_class=HTMLResponse)
def login_page(request: Request):
    user = getattr(request.state, "user", None)
    if user is not None:
        return RedirectResponse(url="/", status_code=303)

    error_code = request.query_params.get("error")
    error = AUTH_ERRORS.get(error_code) if error_code else None
    next_url = request.query_params.get("next", "/")

    return templates.TemplateResponse(
        request,
        "login.html",
        _template_context(request, error=error, next_url=next_url),
    )


@app.post("/login")
def login_submit(
    request: Request,
    username: str = Form(""),
    password: str = Form(""),
    next: str = Form("/"),
    db: Session = Depends(get_db),
):
    if not username.strip() or not password:
        return RedirectResponse(url="/login?error=required", status_code=303)

    user = authenticate_user(db, username, password)
    if not user:
        return RedirectResponse(url="/login?error=invalid", status_code=303)

    request.session["user_id"] = user.id

    next_url = next.strip() or "/"
    if not next_url.startswith("/") or next_url.startswith("//"):
        next_url = "/"

    return RedirectResponse(url=next_url, status_code=303)


@app.get("/logout")
def logout(request: Request):
    request.session.clear()
    return RedirectResponse(url="/login", status_code=303)


# --- API ---


@app.get("/api/health")
def health_check():
    """Probe público — sem auth. Usado pelo app móvel na splash."""
    return {"status": "ok", "service": "kinexa-backend"}


@app.post("/api/auth/login")
def api_login(
    request: Request,
    username: str = Form(""),
    password: str = Form(""),
    db: Session = Depends(get_db),
):
    if not username.strip() or not password:
        raise HTTPException(status_code=400, detail="Informe usuário e senha.")
    user = authenticate_user(db, username, password)
    if not user:
        raise HTTPException(status_code=401, detail="Usuário ou senha incorretos.")
    request.session["user_id"] = user.id
    return {"user_id": user.id, "username": user.username}


@app.get("/api/auth/me")
def api_auth_me(user: User = CurrentUser):
    return {"user_id": user.id, "username": user.username}


@app.post("/api/auth/logout")
def api_logout(request: Request):
    request.session.clear()
    return {"status": "ok"}


@app.post(
    "/api/runs/upload",
    response_model=UploadCreatedResponse | UploadExistsResponse,
)
def upload_run(
    payload: RunUpload,
    request: Request,
    db: Session = Depends(get_db),
):
    existing = crud.get_run_by_id(db, payload.run_id)
    if existing:
        return UploadExistsResponse(status="already_exists", run_id=payload.run_id)

    session_user = getattr(request.state, "user", None)
    user_id = session_user.id if session_user else _admin_user_id(db)

    try:
        run, sample_count = crud.create_run_from_upload(
            db, payload, user_id=user_id
        )
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
    user: User = CurrentUser,
):
    return crud.get_runs(db, user.id, skip=skip, limit=limit)


@app.get("/api/runs/{run_id}", response_model=RunDetail)
def get_run_detail(
    run_id: str,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    return _require_run(db, run_id, user)


@app.get("/api/runs/{run_id}/csv")
def download_csv(
    run_id: str,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)

    csv_file = Path(run.csv_path)
    if not csv_file.is_file():
        raise HTTPException(status_code=404, detail="Arquivo CSV não encontrado")

    return FileResponse(
        path=csv_file,
        media_type="text/csv",
        filename=f"{run_id}.csv",
    )


@app.put("/api/runs/{run_id}", response_model=RunDetail)
def update_run_api(
    run_id: str,
    payload: RunUpdate,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)
    return crud.update_run(db, run, payload)


@app.delete("/api/runs/{run_id}")
def delete_run(
    run_id: str,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)

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
    user: User = CurrentUser,
):
    """Reprocessa métricas e eventos apenas no trecho selecionado (não persiste)."""
    run = _require_run(db, run_id, user)
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
        return analyze_run_window(
            csv_file,
            manual_events=manual,
            start_s=start_s,
            end_s=end_s,
            session_name=Path(run.csv_path).stem,
            activity=run.activity,
            athlete=run.athlete or "",
            notes=run.notes or "",
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/api/runs/{run_id}/analysis")
def get_run_analysis(
    run_id: str,
    force: bool = Query(False),
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)
    try:
        _record, result = get_or_analyze(db, run, force=force)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return result


@app.get("/api/runs/{run_id}/charts")
def get_run_charts(
    run_id: str,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)
    csv_file = Path(run.csv_path)
    if not csv_file.is_file():
        raise HTTPException(status_code=404, detail="Arquivo CSV não encontrado")
    try:
        return build_chart_data_for_run(csv_file)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/api/runs/{run_id}/analysis/export")
def export_analysis_json(
    run_id: str,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)
    try:
        _record, result = get_or_analyze(db, run, force=False)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return JSONResponse(
        content=result,
        headers={"Content-Disposition": f'attachment; filename="{run_id}_analysis.json"'},
    )


@app.get("/api/runs/{run_id}/events/export")
def export_events_csv(
    run_id: str,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    """Exporta eventos manuais + automáticos em CSV."""
    import csv
    import io

    run = _require_run(db, run_id, user)
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


@app.get("/fundamentacao", response_class=HTMLResponse)
def fundamentacao_page(request: Request):
  return templates.TemplateResponse(
    request,
    "fundamentacao.html",
    _template_context(request),
  )


@app.get("/", response_class=HTMLResponse)
def dashboard(
    request: Request,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    stats = crud.get_dashboard_stats(db, user.id)
    seeded = request.query_params.get("seeded")
    return templates.TemplateResponse(
        request,
        "dashboard.html",
        _template_context(request, seeded=seeded, **stats),
    )


@app.post("/dev/seed-run")
def seed_demo_run(db: Session = Depends(get_db), user: User = CurrentUser):
    """Temporário: insere coleta simulada para testes locais (apenas usuário demo)."""
    if user.username != "demo":
        raise HTTPException(status_code=403, detail="Disponível apenas para o usuário demo.")
    run = crud.create_simulated_run(db, user.id)
    return RedirectResponse(url=f"/runs?seeded={run.run_id}", status_code=303)


@app.post("/dev/clear-runs")
def clear_demo_runs(db: Session = Depends(get_db), user: User = CurrentUser):
    """Remove todas as coletas do usuário demo (dev)."""
    if user.username != "demo":
        raise HTTPException(status_code=403, detail="Disponível apenas para o usuário demo.")
    removed = crud.delete_all_runs_for_user(db, user.id)
    return RedirectResponse(url=f"/runs?cleared={removed}", status_code=303)


@app.get("/runs", response_class=HTMLResponse)
def runs_page(
    request: Request,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    runs_enriched = crud.get_runs_with_analysis(db, user.id)
    deleted = request.query_params.get("deleted") == "1"
    seeded = request.query_params.get("seeded")
    cleared_raw = request.query_params.get("cleared")
    cleared = int(cleared_raw) if cleared_raw is not None and cleared_raw.isdigit() else None
    return templates.TemplateResponse(
        request,
        "runs.html",
        _template_context(
            request,
            runs_enriched=runs_enriched,
            deleted=deleted,
            seeded=seeded,
            cleared=cleared,
        ),
    )


@app.get("/runs/{run_id}", response_class=HTMLResponse)
def run_detail_page(
    run_id: str,
    request: Request,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)

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
    sensor_gyro = sensor_gyro_info_from_csv(csv_file) if csv_file.is_file() else None
    calib_summary = run_calibration_summary(run)

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
            calib=calib_summary,
            calib_disp=calibration_display_summary(
                calib_summary,
                gyro_range_dps=sensor_gyro["range_dps"] if sensor_gyro else 1000,
            ),
            sensor_gyro=sensor_gyro,
        ),
    )


@app.get("/runs/{run_id}/edit", response_class=HTMLResponse)
def run_edit_page(
    run_id: str,
    request: Request,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)

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
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)

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
def run_delete_web(
    run_id: str,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)

    try:
        crud.delete_run(db, run)
    except OSError as exc:
        raise HTTPException(
            status_code=500, detail=f"Falha ao remover CSV: {exc}"
        ) from exc

    return RedirectResponse(url="/runs?deleted=1", status_code=303)


@app.post("/runs/{run_id}/analyze")
def run_analyze_web(
    run_id: str,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)
    try:
        get_or_analyze(db, run, force=True)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return RedirectResponse(url=f"/runs/{run_id}/analysis?analyzed=1", status_code=303)


@app.get("/runs/{run_id}/analysis", response_class=HTMLResponse)
def run_analysis_page(
    run_id: str,
    request: Request,
    db: Session = Depends(get_db),
    user: User = CurrentUser,
):
    run = _require_run(db, run_id, user)

    csv_file = Path(run.csv_path)
    if not csv_file.is_file():
        raise HTTPException(status_code=404, detail="Arquivo CSV não encontrado")

    analyzed = request.query_params.get("analyzed") == "1"
    force = request.query_params.get("force") == "1"

    try:
        analysis_record, result = get_or_analyze(db, run, force=force)
        detection_axis = result.get("detection", {}).get("axis", "gy")
        sensor_gyro = sensor_gyro_info_from_csv(csv_file)
        chart_data = build_chart_data_for_run(csv_file, detection_axis=detection_axis)
        chart_data["gyro_range_dps"] = sensor_gyro["range_dps"]
    except (FileNotFoundError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    calib_summary = run_calibration_summary(run)

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
            calib=calib_summary,
            calib_disp=calibration_display_summary(
                calib_summary,
                gyro_range_dps=sensor_gyro["range_dps"],
            ),
            sensor_gyro=sensor_gyro,
            window_json=json.dumps(result.get("window", {})),
        ),
    )
