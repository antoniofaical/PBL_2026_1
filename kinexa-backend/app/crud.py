import re
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.config import UPLOAD_DIR
from app.models import Event, Run
from app.schemas import EventCreate, RunUpdate, RunUpload

RUN_ID_PATTERN = re.compile(r"^[A-Za-z0-9_\-\.]+$")


def safe_csv_path(run_id: str) -> Path:
    if not RUN_ID_PATTERN.fullmatch(run_id):
        raise ValueError("run_id inválido para nome de arquivo")
    return UPLOAD_DIR / f"{run_id}.csv"


def count_csv_samples(csv_content: str) -> int:
    lines = csv_content.strip().splitlines()
    if not lines:
        return 0
    data_lines = [line for line in lines[1:] if line.strip()]
    return len(data_lines)


def get_run(db: Session, run_id: str) -> Run | None:
    return db.query(Run).filter(Run.run_id == run_id).first()


def get_runs(db: Session, skip: int = 0, limit: int | None = None) -> list[Run]:
    query = db.query(Run).order_by(Run.created_at.desc()).offset(skip)
    if limit is not None:
        query = query.limit(limit)
    return query.all()


def get_dashboard_stats(db: Session) -> dict:
    total_runs = db.query(func.count(Run.run_id)).scalar() or 0
    total_athletes = db.query(func.count(func.distinct(Run.athlete))).scalar() or 0
    total_events = db.query(func.count(Event.id)).scalar() or 0
    recent_runs = get_runs(db, limit=5)
    return {
        "total_runs": total_runs,
        "total_athletes": total_athletes,
        "total_events": total_events,
        "recent_runs": recent_runs,
    }


def create_run_from_upload(db: Session, payload: RunUpload) -> tuple[Run, int]:
    sample_count = count_csv_samples(payload.csv)
    csv_path = safe_csv_path(payload.run_id)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    csv_path.write_text(payload.csv, encoding="utf-8")

    run = Run(
        run_id=payload.run_id,
        device_id=payload.device_id,
        datetime=payload.datetime,
        athlete=payload.athlete,
        activity=payload.activity,
        environment=payload.environment,
        notes=payload.notes,
        csv_path=str(csv_path),
        sample_count=sample_count,
    )
    db.add(run)

    for event_data in payload.events:
        db.add(
            Event(
                run_id=payload.run_id,
                timestamp_ms=event_data.timestamp_ms,
                description=event_data.description,
            )
        )

    db.commit()
    db.refresh(run)
    return run, sample_count


def events_to_text(events: list[Event]) -> str:
    lines = []
    for event in sorted(events, key=lambda e: e.timestamp_ms):
        desc = event.description or ""
        lines.append(f"{event.timestamp_ms}|{desc}")
    return "\n".join(lines)


def parse_events_text(text: str) -> list[EventCreate]:
    events: list[EventCreate] = []
    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue
        if "|" in line:
            ts_str, desc = line.split("|", 1)
        else:
            parts = line.split(None, 1)
            if not parts:
                continue
            ts_str = parts[0]
            desc = parts[1] if len(parts) > 1 else ""
        try:
            timestamp_ms = int(ts_str.strip())
        except ValueError as exc:
            raise ValueError(
                f"Linha {lineno}: timestamp inválido ({ts_str!r})"
            ) from exc
        if timestamp_ms < 0:
            raise ValueError(f"Linha {lineno}: timestamp deve ser >= 0")
        events.append(
            EventCreate(
                timestamp_ms=timestamp_ms,
                description=desc.strip() or None,
            )
        )
    return events


def update_run(db: Session, run: Run, payload: RunUpdate) -> Run:
    run.device_id = payload.device_id
    run.datetime = payload.datetime
    run.athlete = payload.athlete
    run.activity = payload.activity
    run.environment = payload.environment
    run.notes = payload.notes

    db.query(Event).filter(Event.run_id == run.run_id).delete()
    for event_data in payload.events:
        db.add(
            Event(
                run_id=run.run_id,
                timestamp_ms=event_data.timestamp_ms,
                description=event_data.description,
            )
        )

    db.commit()
    db.refresh(run)
    return run


def create_simulated_run(db: Session) -> Run:
    """Coleta de exemplo para testes do dashboard (temporário)."""
    now = datetime.now(timezone.utc)
    run_id = f"sim_{now.strftime('%Y%m%d_%H%M%S')}"
    suffix = 0
    while get_run(db, run_id):
        suffix += 1
        run_id = f"sim_{now.strftime('%Y%m%d_%H%M%S')}_{suffix}"

    csv_rows = [
        "t_ms,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw",
        *(f"{i * 2},{1965 + i % 50},{-496 + i % 20},{3410 + i % 30},"
          f"{-363 + i % 10},{-367 + i % 8},{-41 + i % 5}"
          for i in range(120)),
    ]
    payload = RunUpload(
        run_id=run_id,
        device_id="ESP32-C3-DEMO",
        datetime=now.astimezone().replace(microsecond=0).isoformat(),
        athlete="Atleta Demo",
        activity=2,
        environment=1,
        notes="Coleta simulada (botão dev do dashboard)",
        events=[
            EventCreate(timestamp_ms=0, description="Início da gravação"),
            EventCreate(timestamp_ms=5000, description="Esteira 8 km/h"),
            EventCreate(timestamp_ms=15000, description="Fim do aquecimento"),
        ],
        csv="\n".join(csv_rows) + "\n",
    )
    run, _ = create_run_from_upload(db, payload)
    return run


def delete_run(db: Session, run: Run) -> None:
    csv_file = Path(run.csv_path)
    run_id = run.run_id
    db.delete(run)
    db.commit()
    if csv_file.is_file():
        csv_file.unlink()
