from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

# Activity: 1=Marcha, 2=Corrida, 3=Salto Vertical, 4=Salto em Distância
# Environment: 1=Esteira, 2=Pista Externa

VALID_ACTIVITIES = {1, 2, 3, 4}
VALID_ENVIRONMENTS = {1, 2}


class RunCalibration(BaseModel):
    """Calibração registrada no device — futuro sync app/firmware."""
    calib_gx_bias_lsb: float | None = None
    calib_gy_bias_lsb: float | None = None
    calib_gz_bias_lsb: float | None = None
    calib_g_T_x_lsb: float | None = None
    calib_g_T_y_lsb: float | None = None
    calib_g_T_z_lsb: float | None = None
    calib_valid: bool | None = None
    calib_source: str | None = Field(
        default=None,
        description="csv | app | firmware | manual",
    )


class EventCreate(BaseModel):
    timestamp_ms: int = Field(..., ge=0)
    description: str | None = None


class RunUpload(BaseModel):
    run_id: str = Field(..., min_length=1, max_length=128)
    device_id: str = Field(..., min_length=1, max_length=128)
    datetime: str = Field(..., min_length=1)
    athlete: str = Field(..., min_length=1, max_length=256)
    activity: int
    environment: int
    notes: str | None = None
    calibration: RunCalibration | None = None
    events: list[EventCreate] = Field(default_factory=list)
    csv: str = Field(..., min_length=1)

    @field_validator("run_id")
    @classmethod
    def validate_run_id(cls, value: str) -> str:
        import re

        if not re.fullmatch(r"[A-Za-z0-9_\-\.]+", value):
            raise ValueError(
                "run_id deve conter apenas letras, números, _, - ou ."
            )
        return value

    @field_validator("activity")
    @classmethod
    def validate_activity(cls, value: int) -> int:
        if value not in VALID_ACTIVITIES:
            raise ValueError(f"activity deve ser um de {sorted(VALID_ACTIVITIES)}")
        return value

    @field_validator("environment")
    @classmethod
    def validate_environment(cls, value: int) -> int:
        if value not in VALID_ENVIRONMENTS:
            raise ValueError(f"environment deve ser um de {sorted(VALID_ENVIRONMENTS)}")
        return value


class EventRead(BaseModel):
    id: int
    timestamp_ms: int
    description: str | None

    model_config = {"from_attributes": True}


class RunRead(BaseModel):
    run_id: str
    device_id: str
    datetime: str
    athlete: str
    activity: int
    environment: int
    notes: str | None
    csv_path: str
    sample_count: int | None
    calib_gx_bias_lsb: float | None = None
    calib_gy_bias_lsb: float | None = None
    calib_gz_bias_lsb: float | None = None
    calib_g_T_x_lsb: float | None = None
    calib_g_T_y_lsb: float | None = None
    calib_g_T_z_lsb: float | None = None
    calib_valid: bool | None = None
    calib_source: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class RunDetail(RunRead):
    events: list[EventRead]


class RunUpdate(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    datetime: str = Field(..., min_length=1)
    athlete: str = Field(..., min_length=1, max_length=256)
    activity: int
    environment: int
    notes: str | None = None
    events: list[EventCreate] = Field(default_factory=list)

    @field_validator("activity")
    @classmethod
    def validate_activity(cls, value: int) -> int:
        if value not in VALID_ACTIVITIES:
            raise ValueError(f"activity deve ser um de {sorted(VALID_ACTIVITIES)}")
        return value

    @field_validator("environment")
    @classmethod
    def validate_environment(cls, value: int) -> int:
        if value not in VALID_ENVIRONMENTS:
            raise ValueError(f"environment deve ser um de {sorted(VALID_ENVIRONMENTS)}")
        return value


class UploadCreatedResponse(BaseModel):
    status: Literal["created"]
    run_id: str
    sample_count: int


class UploadExistsResponse(BaseModel):
    status: Literal["already_exists"]
    run_id: str
