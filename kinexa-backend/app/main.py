from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, Form, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app import crud
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
def list_runs(db: Session = Depends(get_db)):
    return crud.get_runs(db)


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
    runs = crud.get_runs(db)
    deleted = request.query_params.get("deleted") == "1"
    return templates.TemplateResponse(
        request,
        "runs.html",
        _template_context(request, runs=runs, deleted=deleted),
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

    return templates.TemplateResponse(
        request,
        "run_detail.html",
        _template_context(request, run=run, csv_preview=csv_preview, updated=updated),
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
