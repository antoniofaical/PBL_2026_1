"""Exportação CSV com schema unificado dos receptores."""

from __future__ import annotations

import csv
import datetime as dt
from pathlib import Path


def write_csv(
    csv_path: Path,
    calib: dict[str, object],
    rows: list[dict[str, object]],
    metadata: dict[str, str],
) -> None:
    fieldnames = [
        "sample_index", "t_ms",
        "ax_raw", "ay_raw", "az_raw", "gx_raw", "gy_raw", "gz_raw",
        "calib_gx_bias_lsb", "calib_gy_bias_lsb", "calib_gz_bias_lsb",
        "calib_g_T_x_lsb", "calib_g_T_y_lsb", "calib_g_T_z_lsb", "calib_valid",
        "source_path", "source_size_bytes", "received_at",
    ]

    received_at = dt.datetime.now().isoformat(timespec="seconds")

    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({
                **row,
                **calib,
                "source_path": metadata.get("path", ""),
                "source_size_bytes": metadata.get("size", ""),
                "received_at": received_at,
            })
