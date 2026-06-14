from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
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
