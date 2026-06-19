"""Importa CSVs de data/sessions/ para o banco Kinexa."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from datetime import datetime
from pathlib import Path

# Permite executar: python scripts/import_sessions.py (a partir de kinexa-backend)
_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from app.auth import get_user_by_username
from app.crud import create_run_from_upload, get_run_by_id
from app.database import SessionLocal, create_tables
from app.schemas import RunUpload

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SESSIONS_DIR = REPO_ROOT / "data" / "sessions"

# activity: 2=Corrida | environment: 1=Esteira 2=Pista Externa
ACTIVITY_CORRIDA = 2
ENV_ESTEIRA = 1
ENV_PISTA = 2


def _capitalize_name(raw: str) -> str:
    return raw.strip().capitalize()


def parse_filename(stem: str) -> dict:
    """Extrai atleta, ambiente e dica de velocidade do nome do arquivo."""
    parts = stem.split("_")
    athlete = _capitalize_name(parts[0])

    if "outside" in parts:
        environment = ENV_PISTA
        speed_hint = "Pista externa"
    else:
        environment = ENV_ESTEIRA
        speed_hint = None
        for p in parts[1:]:
            m = re.match(r"(\d+)kmh", p, re.I)
            if m:
                speed_hint = f"Esteira ~{m.group(1)} km/h"
                break

    notes = "Importado de data/sessions — metadados incompletos, revisar manualmente."
    if speed_hint:
        notes = f"{notes} {speed_hint}."

    return {
        "athlete": athlete,
        "activity": ACTIVITY_CORRIDA,
        "environment": environment,
        "notes": notes,
    }


def read_csv_datetime(csv_path: Path) -> str | None:
    """Usa received_at da primeira linha, se existir."""
    with csv_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            received = (row.get("received_at") or "").strip()
            if received:
                return received
            break
    return None


def import_session(db, csv_path: Path, *, dry_run: bool = False, user_id: int) -> str:
    run_id = csv_path.stem
    existing = get_run_by_id(db, run_id)
    if existing:
        return f"SKIP  {run_id} (já existe)"

    meta = parse_filename(run_id)
    dt = read_csv_datetime(csv_path) or datetime.now().astimezone().replace(microsecond=0).isoformat()

    csv_content = csv_path.read_text(encoding="utf-8")

    payload = RunUpload(
        run_id=run_id,
        device_id="pendente",
        datetime=dt,
        athlete=meta["athlete"],
        activity=meta["activity"],
        environment=meta["environment"],
        notes=meta["notes"],
        events=[],
        csv=csv_content,
    )

    if dry_run:
        return f"DRY   {run_id} — {meta['athlete']} | env={meta['environment']} | {dt}"

    create_run_from_upload(db, payload, user_id=user_id)
    return f"OK    {run_id} — {meta['athlete']} ({meta['notes'][:50]}…)"


def main() -> None:
    parser = argparse.ArgumentParser(description="Importa coletas de data/sessions para o DB.")
    parser.add_argument(
        "files",
        nargs="*",
        help="CSV(s) específicos; se omitido, importa a lista padrão de sessions.",
    )
    parser.add_argument(
        "--sessions-dir",
        type=Path,
        default=DEFAULT_SESSIONS_DIR,
        help="Pasta com os CSVs (default: data/sessions)",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--backfill-calib",
        action="store_true",
        help="Extrai calibração do CSV de todas as runs já no banco",
    )
    args = parser.parse_args()

    if args.backfill_calib:
        create_tables()
        db = SessionLocal()
        try:
            from app.crud import backfill_all_calibrations

            n = backfill_all_calibrations(db)
            print(f"Calibração atualizada em {n} coleta(s).")
        finally:
            db.close()
        return

    if args.files:
        paths = [Path(f) for f in args.files]
    else:
        default_names = [
            "otavio_6kmh_1.csv",
            "bruno_10kmh_1.csv",
            "bruno_10kmh_2.csv",
            "bruno_12kmh_1.csv",
            "bruno_12kmh_2.csv",
            "bruno_14kmh_1.csv",
            "bruno_14kmh_2.csv",
            "bruno_14kmh_3.csv",
            "bruno_outside_1.csv",
            "cristofer_outside_1.csv",
            "cristofer_outside_2.csv",
            "otavio_4kmh_1.csv",
            "otavio_4kmh_2.csv",
        ]
        paths = [args.sessions_dir / n for n in default_names]

    create_tables()
    db = SessionLocal()
    try:
        admin = get_user_by_username(db, "admin")
        if not admin:
            print("ERRO  usuário admin não encontrado — execute create_tables() primeiro.")
            sys.exit(1)
        for path in paths:
            if not path.is_file():
                print(f"MISS  {path} — arquivo não encontrado")
                continue
            print(import_session(db, path, dry_run=args.dry_run, user_id=admin.id))
    finally:
        db.close()


if __name__ == "__main__":
    main()
