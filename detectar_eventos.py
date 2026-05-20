"""
detectar_eventos.py
===================
Detecta eventos de marcha/corrida a partir de arquivos .csv do receptor serial
ou .bin original do firmware.

Entrada suportada:
    - .csv com schema gerado por receive_ble.py / receive_serial.py
    - .bin original gravado no LittleFS

Pipeline:
  1. Carrega aquisição com ler_dados.carregar_aquisicao()
  2. Converte sinais para unidades físicas
  3. Filtra Ωp com Butterworth passa-baixa
  4. Detecta mid-swing, IC e TC
  5. Calcula cadência e GCT

USO:
    python detectar_eventos.py last_run.csv
    python detectar_eventos.py last_run.csv --axis gy
    python detectar_eventos.py last_run.csv --no-plot

REQUISITOS:
    pip install numpy scipy matplotlib
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from scipy.signal import butter, filtfilt, find_peaks

from ler_dados import SAMPLE_RATE_HZ, carregar_aquisicao, converter_para_si


def estimar_fs_hz(dados: dict[str, np.ndarray], fallback: float = SAMPLE_RATE_HZ) -> float:
    """Estima fs a partir de t_ms/t; usa fallback se a estimativa não for confiável."""
    t = np.asarray(dados["t"], dtype=np.float64)
    if len(t) < 3:
        return fallback
    dt = np.diff(t)
    dt = dt[dt > 0]
    if len(dt) == 0:
        return fallback
    fs = 1.0 / float(np.median(dt))
    if not np.isfinite(fs) or fs <= 0:
        return fallback
    return fs


def filtrar_passa_baixa(sinal, fc_hz=30.0, fs_hz=SAMPLE_RATE_HZ, ordem=2):
    """Butterworth passa-baixa de fase zero."""
    sinal = np.asarray(sinal, dtype=np.float64)
    if len(sinal) < 3 * (ordem + 1):
        raise ValueError("Sinal curto demais para filtfilt.")

    nyq = fs_hz / 2.0
    if fc_hz >= nyq:
        fc_hz = 0.45 * fs_hz
        print(
            f"AVISO: fc ajustada para {fc_hz:.1f} Hz porque fs estimada é {fs_hz:.1f} Hz.")

    b, a = butter(ordem, fc_hz / nyq, btype="low")
    return filtfilt(b, a, sinal)


def detectar_ciclos(
    omega_p,
    fs_hz=SAMPLE_RATE_HZ,
    freq_passada_hz_max=4.0,
    altura_min=150.0,
):
    """Detecta picos de mid-swing como máximos de Ωp."""
    dist_min = max(1, int(fs_hz / freq_passada_hz_max))
    picos, props = find_peaks(omega_p, distance=dist_min, height=altura_min)
    return picos, props


def detectar_ic_tc(omega_p, picos_midswing, margem_amostras=5):
    """
    Em cada ciclo mid-swing→mid-swing:
      IC = mínimo de Ωp na primeira metade
      TC = mínimo de Ωp na segunda metade
    """
    indices_ic = []
    indices_tc = []

    for i in range(len(picos_midswing) - 1):
        p1 = int(picos_midswing[i])
        p2 = int(picos_midswing[i + 1])
        meio = (p1 + p2) // 2

        if p1 + margem_amostras < meio:
            ic = p1 + int(np.argmin(omega_p[p1:meio]))
            indices_ic.append(ic)

        if meio + margem_amostras < p2:
            tc = meio + int(np.argmin(omega_p[meio:p2]))
            indices_tc.append(tc)

    return np.array(indices_ic, dtype=int), np.array(indices_tc, dtype=int)


def calcular_metricas(indices_ic, indices_tc, fs_hz=SAMPLE_RATE_HZ):
    """Calcula cadência e Ground Contact Time."""
    if len(indices_ic) < 2:
        return None

    intervalos_ic = np.diff(indices_ic) / fs_hz
    intervalos_ic = intervalos_ic[intervalos_ic > 0]
    if len(intervalos_ic) == 0:
        return None

    cadencia_spm = 2 * 60.0 / intervalos_ic

    gct_ms = []
    for ic in indices_ic:
        tcs_depois = indices_tc[indices_tc > ic]
        if len(tcs_depois) > 0:
            gct_ms.append((tcs_depois[0] - ic) / fs_hz * 1000.0)

    return {
        "cadencia_spm_media": float(np.mean(cadencia_spm)),
        "cadencia_spm_std": float(np.std(cadencia_spm)),
        "cadencia_spm_lista": cadencia_spm,
        "gct_ms_media": float(np.mean(gct_ms)) if gct_ms else None,
        "gct_ms_std": float(np.std(gct_ms)) if gct_ms else None,
        "gct_ms_lista": np.array(gct_ms, dtype=float),
        "n_passos": int(len(indices_ic)),
    }


def plotar_eventos(dados, eixo_nome, omega_p_filt, picos, idx_ic, idx_tc, metricas):
    """Plot do Ωp filtrado com IC, TC e mid-swing."""
    fig, ax = plt.subplots(figsize=(13, 5))
    t = dados["t"]

    ax.plot(t, omega_p_filt, linewidth=0.8, label=f"{eixo_nome} filtrado")
    ax.scatter(t[picos], omega_p_filt[picos], s=60,
               marker="^", zorder=5, label="mid-swing")
    ax.scatter(t[idx_ic], omega_p_filt[idx_ic], s=60,
               marker="v", zorder=5, label="IC")
    ax.scatter(t[idx_tc], omega_p_filt[idx_tc], s=60,
               marker="v", zorder=5, label="TC")

    ax.axhline(0, linewidth=0.5)
    ax.set_xlabel("tempo (s)")
    ax.set_ylabel("Ωp (°/s)")

    if metricas:
        titulo = f"Detecção de eventos — {metricas['n_passos']} passos"
        titulo += f" — cadência {metricas['cadencia_spm_media']:.0f} ± {metricas['cadencia_spm_std']:.0f} spm"
        if metricas.get("gct_ms_media") is not None:
            titulo += f" — GCT {metricas['gct_ms_media']:.0f} ± {metricas['gct_ms_std']:.0f} ms"
    else:
        titulo = "Detecção de eventos — métricas indisponíveis"

    ax.set_title(titulo)
    ax.legend(loc="upper right")
    ax.grid(alpha=0.3)
    fig.tight_layout()
    return fig


def exportar_eventos_csv(caminho_saida: str | Path, dados, eixo_nome, picos, idx_ic, idx_tc, metricas) -> None:
    """Exporta eventos detectados para CSV longo."""
    caminho_saida = Path(caminho_saida)
    rows = []

    for idx in picos:
        rows.append((int(idx), float(dados["t"][idx]), "mid_swing", eixo_nome))
    for idx in idx_ic:
        rows.append((int(idx), float(dados["t"][idx]), "IC", eixo_nome))
    for idx in idx_tc:
        rows.append((int(idx), float(dados["t"][idx]), "TC", eixo_nome))

    rows.sort(key=lambda x: x[0])

    with caminho_saida.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["sample_index", "t_s", "event", "axis"])
        writer.writerows(rows)

    print(f"Eventos salvos em: {caminho_saida}")

    if metricas:
        metricas_path = caminho_saida.with_name(
            caminho_saida.stem + "_metricas.csv")
        with metricas_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["metrica", "valor"])
            writer.writerow(["n_passos", metricas["n_passos"]])
            writer.writerow(
                ["cadencia_spm_media", metricas["cadencia_spm_media"]])
            writer.writerow(["cadencia_spm_std", metricas["cadencia_spm_std"]])
            writer.writerow(["gct_ms_media", metricas["gct_ms_media"]])
            writer.writerow(["gct_ms_std", metricas["gct_ms_std"]])
        print(f"Métricas salvas em: {metricas_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Detecta eventos a partir de .csv serial ou .bin.")
    parser.add_argument(
        "arquivo", help="Arquivo .csv do receptor serial ou .bin original")
    parser.add_argument(
        "--axis", choices=["gx", "gy", "gz"], default="gy", help="Eixo usado como Ωp. Padrão: gy")
    parser.add_argument("--fc", type=float, default=30.0,
                        help="Frequência de corte do passa-baixa. Padrão: 30 Hz")
    parser.add_argument("--peak-height", type=float, default=150.0,
                        help="Altura mínima dos picos. Padrão: 150 °/s")
    parser.add_argument("--max-step-freq", type=float, default=4.0,
                        help="Frequência máxima de passada. Padrão: 4 Hz")
    parser.add_argument("--export-events", action="store_true",
                        help="Exporta eventos e métricas para CSV")
    parser.add_argument("--no-plot", action="store_true",
                        help="Não abre janela de plot")
    args = parser.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, OSError, ValueError):
            pass

    caminho = Path(args.arquivo)
    calib, samples = carregar_aquisicao(caminho)
    dados = converter_para_si(samples, calib)
    fs_hz = estimar_fs_hz(dados)

    omega_p_raw = dados[args.axis]
    omega_p_filt = filtrar_passa_baixa(omega_p_raw, fc_hz=args.fc, fs_hz=fs_hz)

    picos, _ = detectar_ciclos(
        omega_p_filt,
        fs_hz=fs_hz,
        freq_passada_hz_max=args.max_step_freq,
        altura_min=args.peak_height,
    )

    if len(picos) < 2:
        print("⚠ Não foram detectados picos suficientes de mid-swing.")
        print(f"  Arquivo: {caminho}")
        print(f"  Eixo testado: {args.axis}")
        print(f"  fs estimada: {fs_hz:.1f} Hz")
        print("  Tente: --axis gx ou --axis gz; ou reduza --peak-height, ex.: --peak-height 80")
        sys.exit(2)

    idx_ic, idx_tc = detectar_ic_tc(omega_p_filt, picos)
    metricas = calcular_metricas(idx_ic, idx_tc, fs_hz=fs_hz)

    print(f"\nArquivo: {caminho}")
    print(
        f"Formato carregado             : {calib.get('source_format', 'desconhecido')}")
    print(f"Eixo usado como Ωp            : {args.axis}")
    print(f"fs estimada                   : {fs_hz:.1f} Hz")
    print(f"Picos de mid-swing detectados : {len(picos)}")
    print(f"IC detectados                 : {len(idx_ic)}")
    print(f"TC detectados                 : {len(idx_tc)}")

    if metricas:
        print(
            f"\nCadência média : {metricas['cadencia_spm_media']:.1f} ± {metricas['cadencia_spm_std']:.1f} spm")
        if metricas["gct_ms_media"] is not None:
            print(
                f"GCT médio      : {metricas['gct_ms_media']:.0f} ± {metricas['gct_ms_std']:.0f} ms")
    else:
        print("\nMétricas indisponíveis: IC insuficientes ou intervalos inválidos.")

    if args.export_events:
        out_path = caminho.with_name(caminho.stem + "_eventos.csv")
        exportar_eventos_csv(out_path, dados, args.axis,
                             picos, idx_ic, idx_tc, metricas)

    if not args.no_plot:
        plotar_eventos(dados, args.axis, omega_p_filt,
                       picos, idx_ic, idx_tc, metricas)
        plt.show()


if __name__ == "__main__":
    main()
