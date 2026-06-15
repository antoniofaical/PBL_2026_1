from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

# Activity enum (documentação):
#   1 = Marcha
#   2 = Corrida
#   3 = Salto Vertical
#   4 = Salto em Distância
#
# Environment enum:
#   1 = Esteira
#   2 = Pista Externa


class Run(Base):
    __tablename__ = "runs"

    run_id: Mapped[str] = mapped_column(String, primary_key=True)
    device_id: Mapped[str] = mapped_column(String, nullable=False)
    datetime: Mapped[str] = mapped_column(String, nullable=False)
    athlete: Mapped[str] = mapped_column(String, nullable=False)
    activity: Mapped[int] = mapped_column(Integer, nullable=False)
    environment: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    csv_path: Mapped[str] = mapped_column(String, nullable=False)
    sample_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    quality_status: Mapped[str | None] = mapped_column(String(16), nullable=True)

    # Calibração MPU6050 (sync app/firmware ou extraída do CSV)
    calib_gx_bias_lsb: Mapped[float | None] = mapped_column(Float, nullable=True)
    calib_gy_bias_lsb: Mapped[float | None] = mapped_column(Float, nullable=True)
    calib_gz_bias_lsb: Mapped[float | None] = mapped_column(Float, nullable=True)
    calib_g_T_x_lsb: Mapped[float | None] = mapped_column("calib_gt_x_lsb", Float, nullable=True)
    calib_g_T_y_lsb: Mapped[float | None] = mapped_column("calib_gt_y_lsb", Float, nullable=True)
    calib_g_T_z_lsb: Mapped[float | None] = mapped_column("calib_gt_z_lsb", Float, nullable=True)
    calib_valid: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    calib_source: Mapped[str | None] = mapped_column(String(16), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    events: Mapped[list["Event"]] = relationship(
        "Event",
        back_populates="run",
        cascade="all, delete-orphan",
        order_by="Event.timestamp_ms",
    )
    analyses: Mapped[list["RunAnalysis"]] = relationship(
        "RunAnalysis",
        back_populates="run",
        cascade="all, delete-orphan",
        order_by="RunAnalysis.created_at.desc()",
    )


class RunAnalysis(Base):
    __tablename__ = "run_analyses"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    run_id: Mapped[str] = mapped_column(
        String,
        ForeignKey("runs.run_id", ondelete="CASCADE"),
        nullable=False,
    )
    analysis_version: Mapped[str] = mapped_column(String(16), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    sample_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    mean_fs_hz: Mapped[float | None] = mapped_column(Float, nullable=True)
    gap_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    saturation_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cadence_spm: Mapped[float | None] = mapped_column(Float, nullable=True)
    steps_detected: Mapped[int | None] = mapped_column(Integer, nullable=True)
    mean_gct_ms: Mapped[float | None] = mapped_column(Float, nullable=True)
    std_gct_ms: Mapped[float | None] = mapped_column(Float, nullable=True)
    result_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    run: Mapped["Run"] = relationship("Run", back_populates="analyses")


class Event(Base):
    __tablename__ = "events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    run_id: Mapped[str] = mapped_column(
        String,
        ForeignKey("runs.run_id", ondelete="CASCADE"),
        nullable=False,
    )
    timestamp_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    run: Mapped["Run"] = relationship("Run", back_populates="events")
