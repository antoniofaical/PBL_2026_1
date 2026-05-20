#!/usr/bin/env python3
"""
Receptor USB serial (Etapa 10) — fallback quando BLE nao estiver em uso.

Aguarda o firmware enviar /last_run.bin pela UART apos gravacao.
"""

from __future__ import annotations

import argparse
import datetime as dt
import sys
from pathlib import Path

try:
    import serial
except ImportError:
    print("ERRO: pip install pyserial", file=sys.stderr)
    raise

from pbl_data import parse_payload_to_rows, write_csv
from pbl_data.format import XFER_BEGIN_MARKER

BEGIN_MARKER = XFER_BEGIN_MARKER.encode("ascii")


def read_until_marker(ser: serial.Serial, marker: bytes) -> bytes:
    buf = bytearray()
    while True:
        b = ser.read(1)
        if not b:
            raise TimeoutError(f"Timeout esperando marcador: {marker!r}")
        buf += b
        if marker in buf:
            return bytes(buf)
        if len(buf) > 8192:
            buf = buf[-len(marker):]


def read_line_ascii(ser: serial.Serial) -> str:
    line = ser.readline()
    if not line:
        raise TimeoutError("Timeout lendo linha ASCII do cabecalho")
    return line.decode("ascii", errors="replace").strip()


def receive_binary_from_esp32(
    port: str, baud: int, timeout: float,
) -> tuple[bytes, dict[str, str]]:
    with serial.Serial(port=port, baudrate=baud, timeout=timeout) as ser:
        print(f"Aguardando pacote em {port} @ {baud} baud...")
        read_until_marker(ser, BEGIN_MARKER)

        metadata: dict[str, str] = {}
        size: int | None = None

        while True:
            line = read_line_ascii(ser)
            if line.startswith("PATH:"):
                metadata["path"] = line.split(":", 1)[1]
            elif line.startswith("SIZE:"):
                size = int(line.split(":", 1)[1])
                metadata["size"] = str(size)
            elif line == "DATA_BEGIN":
                break

        if size is None:
            raise ValueError("Cabecalho recebido sem SIZE:<bytes>")

        print(f"Recebendo {size} bytes...")
        payload = ser.read(size)
        if len(payload) != size:
            raise IOError(
                f"Pacote incompleto: esperado {size} bytes, recebido {len(payload)} bytes"
            )

        for _ in range(4):
            line = ser.readline()
            if not line:
                break
            decoded = line.decode("ascii", errors="replace").strip()
            if decoded == "XFER: OK":
                break

    return payload, metadata


def main() -> None:
    parser = argparse.ArgumentParser(description="Recebe dados do ESP32 via USB serial.")
    parser.add_argument("--port", default="COM10", help="Porta serial (padrao: COM10)")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--out", type=Path, default=None, help="CSV de saida")
    args = parser.parse_args()

    out_path = args.out or Path(
        f"data/sessions/serial_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)

    payload, metadata = receive_binary_from_esp32(args.port, args.baud, args.timeout)
    calib, rows = parse_payload_to_rows(payload)
    write_csv(out_path, calib, rows, metadata)

    print(f"CSV salvo em: {out_path.resolve()}")
    print(f"Amostras: {len(rows)}  |  Calibracao valida: {calib['calib_valid']}")


if __name__ == "__main__":
    main()
