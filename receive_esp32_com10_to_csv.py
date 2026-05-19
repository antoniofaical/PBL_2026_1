"""
Recebe o arquivo /last_run.bin streamado pelo ESP32 via Serial (COM10)
e converte para CSV.

Protocolo esperado do firmware:
===BEGIN_LAST_RUN_BIN===
PATH:/last_run.bin
SIZE:<N>
DATA_BEGIN
<N bytes binarios>
DATA_END
===END_LAST_RUN_BIN===
XFER: OK

Formato binario esperado:
- CalibData: 28 bytes = 6 floats little-endian + 1 bool + 3 bytes padding
- Sample: 16 bytes = uint32 t_ms + 6 int16 raw
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import struct
import sys
from pathlib import Path

try:
    import serial
except ImportError:
    print("ERRO: pyserial nao esta instalado. Instale com: pip install pyserial", file=sys.stderr)
    raise


BEGIN_MARKER = b"===BEGIN_LAST_RUN_BIN==="
DATA_BEGIN_MARKER = b"DATA_BEGIN\n"

CALIB_STRUCT = struct.Struct("<6f?3x")      # 28 bytes: gx, gy, gz, gTx, gTy, gTz, valid, padding
SAMPLE_STRUCT = struct.Struct("<Ihhhhhh")   # 16 bytes: t_ms, ax, ay, az, gx, gy, gz


def read_until_marker(ser: serial.Serial, marker: bytes) -> bytes:
    """Le da serial ate encontrar marker. Retorna tudo que veio antes + marker."""
    buf = bytearray()
    while True:
        b = ser.read(1)
        if not b:
            raise TimeoutError(f"Timeout esperando marcador: {marker!r}")
        buf += b
        if marker in buf:
            return bytes(buf)
        # Evita crescimento indefinido se houver muito log antes do pacote.
        if len(buf) > 8192:
            buf = buf[-len(marker):]


def read_line_ascii(ser: serial.Serial) -> str:
    line = ser.readline()
    if not line:
        raise TimeoutError("Timeout lendo linha ASCII do cabecalho")
    return line.decode("ascii", errors="replace").strip()


def receive_binary_from_esp32(port: str, baud: int, timeout: float) -> tuple[bytes, dict[str, str]]:
    """Recebe exatamente SIZE bytes binarios enviados pelo firmware."""
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
                size_text = line.split(":", 1)[1]
                size = int(size_text)
                metadata["size"] = size_text

            elif line == "DATA_BEGIN":
                break

        if size is None:
            raise ValueError("Cabecalho recebido sem SIZE:<bytes>")

        print(f"Recebendo {size} bytes...")
        payload = ser.read(size)
        if len(payload) != size:
            raise IOError(f"Pacote incompleto: esperado {size} bytes, recebido {len(payload)} bytes")

        # Lê algumas linhas finais apenas para limpar/validar o footer. Não depende dele para delimitar o binario.
        footer_lines = []
        for _ in range(4):
            line = ser.readline()
            if not line:
                break
            decoded = line.decode("ascii", errors="replace").strip()
            if decoded:
                footer_lines.append(decoded)
            if decoded == "XFER: OK":
                break
        metadata["footer"] = " | ".join(footer_lines)

    return payload, metadata


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
            f"AVISO: {remainder} byte(s) sobrando apos dividir em amostras de {SAMPLE_STRUCT.size} bytes. "
            "Esses bytes serao ignorados.",
            file=sys.stderr,
        )
        sample_bytes = sample_bytes[:len(sample_bytes) - remainder]

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


def write_csv(csv_path: Path, calib: dict[str, object], rows: list[dict[str, object]], metadata: dict[str, str]) -> None:
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


def default_output_path() -> Path:
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    return Path(f"last_run_{stamp}.csv")


def main() -> None:
    parser = argparse.ArgumentParser(description="Recebe dados do ESP32 via COM10 e salva em CSV.")
    parser.add_argument("--port", default="COM10", help="Porta serial. Padrao: COM10")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate. Padrao: 115200")
    parser.add_argument("--timeout", type=float, default=10.0, help="Timeout de leitura em segundos. Padrao: 10")
    parser.add_argument("--out", type=Path, default=None, help="Arquivo CSV de saida")
    args = parser.parse_args()

    out_path = args.out or default_output_path()

    payload, metadata = receive_binary_from_esp32(args.port, args.baud, args.timeout)
    calib, rows = parse_payload_to_rows(payload)
    write_csv(out_path, calib, rows, metadata)

    print(f"CSV salvo em: {out_path.resolve()}")
    print(f"Amostras exportadas: {len(rows)}")
    print(f"Calibracao valida: {calib['calib_valid']}")


if __name__ == "__main__":
    main()
