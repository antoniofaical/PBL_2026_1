"""
ler_dados.py
============
Le arquivos de aquisição do MPU6050 em dois formatos:

1) .bin original gravado pelo firmware no LittleFS
2) .csv gerado por receive_ble.py ou receive_serial.py

Schema CSV esperado:
    sample_index,t_ms,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,
    calib_gx_bias_lsb,calib_gy_bias_lsb,calib_gz_bias_lsb,
    calib_g_T_x_lsb,calib_g_T_y_lsb,calib_g_T_z_lsb,calib_valid,
    source_path,source_size_bytes,received_at

CONFIGURAÇÃO DO MPU6050 NO FIRMWARE:
    Acelerômetro: ±8 g       -> 4096 LSB/g
    Giroscópio:  ±1000 °/s   -> 32.8 LSB/(°/s)
    Taxa-alvo: 500 Hz

USO:
    python ler_dados.py last_run.csv
    python ler_dados.py last_run.csv --csv-si
    python ler_dados.py corridas/run_001.bin
    python ler_dados.py corridas/run_001.bin --csv-si

REQUISITOS:
    pip install numpy matplotlib
"""

from __future__ import annotations

import argparse
import csv
import struct
import sys
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np

from pbl_data.format import (
    ACCEL_SENSITIVITY_LSB_PER_G,
    CSV_REQUIRED_COLUMNS,
    GYRO_SENSITIVITY_LSB_PER_DPS,
    HEADER_FMT,
    HEADER_SIZE,
    SAMPLE_RATE_HZ,
    SAMPLE_SIZE,
)

SAMPLE_DTYPE = np.dtype([
    ("t_ms", "<u4"),
    ("ax", "<i2"), ("ay", "<i2"), ("az", "<i2"),
    ("gx", "<i2"), ("gy", "<i2"), ("gz", "<i2"),
])

CSV_REQUIRED_COLUMNS = set(CSV_REQUIRED_COLUMNS)


def _parse_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    return text in {"1", "true", "t", "yes", "y", "sim", "s"}


def carregar_bin(caminho: str | Path) -> tuple[dict[str, Any], np.ndarray]:
    """
    Lê o .bin original e devolve (calib, samples).

    samples usa campos padronizados:
        t_ms, ax, ay, az, gx, gy, gz
    """
    caminho = Path(caminho)
    if not caminho.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {caminho}")

    with caminho.open("rb") as f:
        header_bytes = f.read(HEADER_SIZE)
        if len(header_bytes) < HEADER_SIZE:
            raise ValueError("Arquivo curto demais — não contém cabeçalho completo.")

        gx_b, gy_b, gz_b, gx_t, gy_t, gz_t, valid_raw = struct.unpack(HEADER_FMT, header_bytes)
        calib = {
            "gyro_bias_lsb": np.array([gx_b, gy_b, gz_b], dtype=np.float64),
            "gravity_T_lsb": np.array([gx_t, gy_t, gz_t], dtype=np.float64),
            "valid": (valid_raw & 0xFF) != 0,
            "source_format": "bin",
            "source_path": str(caminho),
        }

        rest = f.read()

    n_samples = len(rest) // SAMPLE_SIZE
    if n_samples == 0:
        raise ValueError("Arquivo sem amostras.")

    remainder = len(rest) % SAMPLE_SIZE
    if remainder:
        print(
            f"AVISO: {remainder} byte(s) extra no fim do .bin serão ignorados.",
            file=sys.stderr,
        )

    rest = rest[:n_samples * SAMPLE_SIZE]
    samples = np.frombuffer(rest, dtype=SAMPLE_DTYPE).copy()
    return calib, samples


def carregar_csv_schema_serial(caminho: str | Path) -> tuple[dict[str, Any], np.ndarray]:
    """
    Lê o CSV gerado pelo receptor serial e devolve (calib, samples).

    O CSV tem colunas *_raw; internamente elas são remapeadas para os nomes
    usados pelo pipeline antigo: ax, ay, az, gx, gy, gz.
    """
    caminho = Path(caminho)
    if not caminho.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {caminho}")

    with caminho.open("r", newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            raise ValueError("CSV vazio ou sem cabeçalho.")

        columns = set(reader.fieldnames)
        missing = sorted(CSV_REQUIRED_COLUMNS - columns)
        if missing:
            raise ValueError(
                "CSV não corresponde ao schema serial esperado. "
                f"Colunas ausentes: {', '.join(missing)}"
            )

        rows = list(reader)

    if not rows:
        raise ValueError("CSV sem amostras.")

    first = rows[0]
    calib = {
        "gyro_bias_lsb": np.array([
            float(first["calib_gx_bias_lsb"]),
            float(first["calib_gy_bias_lsb"]),
            float(first["calib_gz_bias_lsb"]),
        ], dtype=np.float64),
        "gravity_T_lsb": np.array([
            float(first["calib_g_T_x_lsb"]),
            float(first["calib_g_T_y_lsb"]),
            float(first["calib_g_T_z_lsb"]),
        ], dtype=np.float64),
        "valid": _parse_bool(first["calib_valid"]),
        "source_format": "csv_serial",
        "source_path": first.get("source_path", str(caminho)) or str(caminho),
        "source_size_bytes": first.get("source_size_bytes", ""),
        "received_at": first.get("received_at", ""),
    }

    samples = np.zeros(len(rows), dtype=SAMPLE_DTYPE)
    for i, row in enumerate(rows):
        samples["t_ms"][i] = int(float(row["t_ms"]))
        samples["ax"][i] = int(float(row["ax_raw"]))
        samples["ay"][i] = int(float(row["ay_raw"]))
        samples["az"][i] = int(float(row["az_raw"]))
        samples["gx"][i] = int(float(row["gx_raw"]))
        samples["gy"][i] = int(float(row["gy_raw"]))
        samples["gz"][i] = int(float(row["gz_raw"]))

    return calib, samples


def carregar_aquisicao(caminho: str | Path) -> tuple[dict[str, Any], np.ndarray]:
    """Carrega automaticamente .csv serial ou .bin original."""
    caminho = Path(caminho)
    suffix = caminho.suffix.lower()

    if suffix == ".csv":
        return carregar_csv_schema_serial(caminho)
    if suffix == ".bin":
        return carregar_bin(caminho)

    raise ValueError(
        f"Extensão não suportada: {suffix or '(sem extensão)'}. "
        "Use .csv ou .bin."
    )


def converter_para_si(samples: np.ndarray, calib: dict[str, Any]) -> dict[str, np.ndarray]:
    """
    Converte amostras brutas para unidades físicas.

    Retorna:
        t: tempo em segundos desde o início
        ax, ay, az: aceleração em m/s²
        gx, gy, gz: velocidade angular em °/s com bias subtraído
        *_raw: sinais brutos originais
    """
    if len(samples) == 0:
        raise ValueError("Não há amostras para converter.")

    t = (samples["t_ms"].astype(np.float64) - float(samples["t_ms"][0])) / 1000.0

    g_to_ms2 = 9.80665
    ax = samples["ax"].astype(np.float64) / ACCEL_SENSITIVITY_LSB_PER_G * g_to_ms2
    ay = samples["ay"].astype(np.float64) / ACCEL_SENSITIVITY_LSB_PER_G * g_to_ms2
    az = samples["az"].astype(np.float64) / ACCEL_SENSITIVITY_LSB_PER_G * g_to_ms2

    gyro_bias = np.asarray(calib["gyro_bias_lsb"], dtype=np.float64)
    gx = (samples["gx"].astype(np.float64) - gyro_bias[0]) / GYRO_SENSITIVITY_LSB_PER_DPS
    gy = (samples["gy"].astype(np.float64) - gyro_bias[1]) / GYRO_SENSITIVITY_LSB_PER_DPS
    gz = (samples["gz"].astype(np.float64) - gyro_bias[2]) / GYRO_SENSITIVITY_LSB_PER_DPS

    return {
        "t": t,
        "ax": ax, "ay": ay, "az": az,
        "gx": gx, "gy": gy, "gz": gz,
        "t_ms": samples["t_ms"].astype(np.uint32),
        "ax_raw": samples["ax"].astype(np.int16),
        "ay_raw": samples["ay"].astype(np.int16),
        "az_raw": samples["az"].astype(np.int16),
        "gx_raw": samples["gx"].astype(np.int16),
        "gy_raw": samples["gy"].astype(np.int16),
        "gz_raw": samples["gz"].astype(np.int16),
    }


def diagnostico(calib: dict[str, Any], samples: np.ndarray) -> None:
    """Imprime relatório básico de saúde da aquisição."""
    print("=" * 60)
    print("RELATÓRIO DO ARQUIVO")
    print("=" * 60)
    print(f"Formato               : {calib.get('source_format', 'desconhecido')}")
    print(f"Origem                : {calib.get('source_path', '')}")
    if calib.get("received_at"):
        print(f"Recebido em           : {calib['received_at']}")
    print(f"Amostras totais       : {len(samples)}")

    duracao_s = (float(samples["t_ms"][-1]) - float(samples["t_ms"][0])) / 1000.0
    print(f"Duração               : {duracao_s:.2f} s")
    if duracao_s > 0 and len(samples) > 1:
        taxa = (len(samples) - 1) / duracao_s
        print(f"Taxa de amostragem    : {taxa:.1f} Hz (alvo: {SAMPLE_RATE_HZ:.0f} Hz)")

    print()
    print("CALIBRAÇÃO:")
    print(f"  válida              : {calib['valid']}")
    print(f"  gyro bias (LSB)     : {calib['gyro_bias_lsb']}")
    print(f"  gravidade g_T (LSB) : {calib['gravity_T_lsb']}")

    norma = np.linalg.norm(calib["gravity_T_lsb"])
    print(f"  ‖g_T‖ medida        : {norma:.1f} LSB")
    print("  esperado em ±8 g    : 4096 LSB ± 10%")
    if not (3600 < norma < 4600):
        print("  ⚠ ATENÇÃO: norma fora da faixa — checar calibração/orientação")

    eixos = ["X", "Y", "Z"]
    idx_vert = int(np.argmax(np.abs(calib["gravity_T_lsb"])))
    sinal = "+" if calib["gravity_T_lsb"][idx_vert] > 0 else "-"
    print(f"Eixo vertical do chip : {sinal}{eixos[idx_vert]}")
    print("=" * 60)


def plotar(dados: dict[str, np.ndarray], titulo: str = "Sinais"):
    """Plot básico dos 6 sinais convertidos."""
    fig, axes = plt.subplots(3, 2, figsize=(12, 7), sharex=True)
    t = dados["t"]

    axes[0, 0].plot(t, dados["ax"])
    axes[0, 0].set_ylabel("ax (m/s²)")
    axes[0, 0].grid(alpha=0.3)

    axes[1, 0].plot(t, dados["ay"])
    axes[1, 0].set_ylabel("ay (m/s²)")
    axes[1, 0].grid(alpha=0.3)

    axes[2, 0].plot(t, dados["az"])
    axes[2, 0].set_ylabel("az (m/s²)")
    axes[2, 0].set_xlabel("tempo (s)")
    axes[2, 0].grid(alpha=0.3)

    axes[0, 1].plot(t, dados["gx"])
    axes[0, 1].set_ylabel("gx (°/s)")
    axes[0, 1].grid(alpha=0.3)

    axes[1, 1].plot(t, dados["gy"])
    axes[1, 1].set_ylabel("gy (°/s) — PITCH/Ωp")
    axes[1, 1].grid(alpha=0.3)

    axes[2, 1].plot(t, dados["gz"])
    axes[2, 1].set_ylabel("gz (°/s)")
    axes[2, 1].set_xlabel("tempo (s)")
    axes[2, 1].grid(alpha=0.3)

    fig.suptitle(titulo)
    fig.tight_layout()
    return fig


def exportar_csv_si(dados: dict[str, np.ndarray], caminho_saida: str | Path) -> None:
    """Exporta sinais convertidos para um CSV de análise."""
    caminho_saida = Path(caminho_saida)
    with caminho_saida.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "t_s", "t_ms",
            "ax_ms2", "ay_ms2", "az_ms2",
            "gx_dps", "gy_dps", "gz_dps",
            "ax_raw", "ay_raw", "az_raw", "gx_raw", "gy_raw", "gz_raw",
        ])
        for i in range(len(dados["t"])):
            writer.writerow([
                dados["t"][i], dados["t_ms"][i],
                dados["ax"][i], dados["ay"][i], dados["az"][i],
                dados["gx"][i], dados["gy"][i], dados["gz"][i],
                dados["ax_raw"][i], dados["ay_raw"][i], dados["az_raw"][i],
                dados["gx_raw"][i], dados["gy_raw"][i], dados["gz_raw"][i],
            ])
    print(f"CSV SI salvo em: {caminho_saida}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Lê aquisição .csv serial ou .bin e plota/converte os sinais.")
    parser.add_argument("arquivo", help="Arquivo .csv gerado pelo receptor serial ou .bin original")
    parser.add_argument("--csv-si", action="store_true", help="Exporta CSV com sinais convertidos para unidades físicas")
    parser.add_argument("--no-plot", action="store_true", help="Não abre janela de plot")
    args = parser.parse_args()

    caminho = Path(args.arquivo)
    calib, samples = carregar_aquisicao(caminho)
    diagnostico(calib, samples)
    dados = converter_para_si(samples, calib)

    if args.csv_si:
        out_path = caminho.with_name(caminho.stem + "_si.csv")
        exportar_csv_si(dados, out_path)

    if not args.no_plot:
        plotar(dados, titulo=f"Arquivo: {caminho.name}")
        plt.show()


if __name__ == "__main__":
    main()
