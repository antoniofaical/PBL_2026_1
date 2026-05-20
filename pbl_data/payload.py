"""Parse do payload binário gravado pelo ESP32."""

from __future__ import annotations

import sys

from pbl_data.format import CALIB_STRUCT, SAMPLE_STRUCT


def parse_payload_to_rows(payload: bytes) -> tuple[dict[str, object], list[dict[str, object]]]:
    if len(payload) < CALIB_STRUCT.size:
        raise ValueError(f"Payload muito pequeno para conter CalibData: {len(payload)} bytes")

    gx_bias, gy_bias, gz_bias, g_tx, g_ty, g_tz, calib_valid = CALIB_STRUCT.unpack_from(payload, 0)

    calib = {
        "calib_gx_bias_lsb": gx_bias,
        "calib_gy_bias_lsb": gy_bias,
        "calib_gz_bias_lsb": gz_bias,
        "calib_g_T_x_lsb": g_tx,
        "calib_g_T_y_lsb": g_ty,
        "calib_g_T_z_lsb": g_tz,
        "calib_valid": bool(calib_valid),
    }

    sample_bytes = payload[CALIB_STRUCT.size:]
    remainder = len(sample_bytes) % SAMPLE_STRUCT.size
    if remainder != 0:
        print(
            f"AVISO: {remainder} byte(s) sobrando apos dividir em amostras de "
            f"{SAMPLE_STRUCT.size} bytes. Esses bytes serao ignorados.",
            file=sys.stderr,
        )
        sample_bytes = sample_bytes[: len(sample_bytes) - remainder]

    rows: list[dict[str, object]] = []
    for idx, offset in enumerate(range(0, len(sample_bytes), SAMPLE_STRUCT.size)):
        t_ms, ax, ay, az, gx, gy, gz = SAMPLE_STRUCT.unpack_from(sample_bytes, offset)
        rows.append({
            "sample_index": idx,
            "t_ms": t_ms,
            "ax_raw": ax,
            "ay_raw": ay,
            "az_raw": az,
            "gx_raw": gx,
            "gy_raw": gy,
            "gz_raw": gz,
        })

    return calib, rows
