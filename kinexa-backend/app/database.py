from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import DATABASE_URL

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def create_tables() -> None:
    from app import models  # noqa: F401

    Base.metadata.create_all(bind=engine)
    _migrate_existing()


def _migrate_existing() -> None:
    """Ajustes incrementais em bancos já existentes (sem Alembic)."""
    from sqlalchemy import inspect, text

    insp = inspect(engine)
    if not insp.has_table("runs"):
        return

    run_cols = {c["name"].lower() for c in insp.get_columns("runs")}
    calib_cols = {
        "calib_gx_bias_lsb": "DOUBLE PRECISION",
        "calib_gy_bias_lsb": "DOUBLE PRECISION",
        "calib_gz_bias_lsb": "DOUBLE PRECISION",
        "calib_gt_x_lsb": "DOUBLE PRECISION",
        "calib_gt_y_lsb": "DOUBLE PRECISION",
        "calib_gt_z_lsb": "DOUBLE PRECISION",
        "calib_valid": "BOOLEAN",
        "calib_source": "VARCHAR(16)",
    }
    with engine.begin() as conn:
        if "quality_status" not in run_cols:
            conn.execute(text(
                "ALTER TABLE runs ADD COLUMN quality_status VARCHAR(16)"
            ))
        for col, sql_type in calib_cols.items():
            if col not in run_cols:
                conn.execute(text(
                    f"ALTER TABLE runs ADD COLUMN {col} {sql_type}"
                ))
