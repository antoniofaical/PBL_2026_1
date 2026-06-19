import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent

DATABASE_URL: str = os.getenv(
    "DATABASE_URL",
    "postgresql://user:password@localhost:5432/kinexa",
)
SECRET_KEY: str = os.getenv(
    "SECRET_KEY",
    "kinexa-dev-secret-change-in-production",
)
SESSION_MAX_AGE: int = int(os.getenv("SESSION_MAX_AGE", str(60 * 60 * 24 * 7)))
UPLOAD_DIR: Path = Path(os.getenv("UPLOAD_DIR", "uploads"))
if not UPLOAD_DIR.is_absolute():
    UPLOAD_DIR = BASE_DIR / UPLOAD_DIR

ACTIVITY_LABELS: dict[int, str] = {
    1: "Marcha",
    2: "Corrida",
    3: "Salto Vertical",
    4: "Salto em Distância",
}

ENVIRONMENT_LABELS: dict[int, str] = {
    1: "Esteira",
    2: "Pista Externa",
}
