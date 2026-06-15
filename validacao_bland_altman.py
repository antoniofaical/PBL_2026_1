"""
validacao_bland_altman.py — Validação IMU vs. marcadores de vídeo (v2)
=======================================================================

Valida as métricas do IMU (cadência e GCT) contra marcadores de vídeo Kinovea
(60 Hz) usando análise de Bland-Altman.

Pipeline:
  1. Carrega par (marcador .txt Kinovea + IMU .csv)
  2. Sincroniza via heel stomps (picos isolados de alta aceleração no IMU)
  3. Detecta IC/TC em cada sinal dentro da janela comum
  4. Calcula cadência e GCT por stride
  5. Gera gráficos Bland-Altman + tabela de resumo

Atualização v2 (2026-06) — FIX CRÍTICO:
  - GYRO_SENS corrigido de 32.8 → 16.4 LSB/(°/s)
    correspondente a GYRO_CONFIG = 0x18 (±2000°/s) no firmware v2
  - Threshold de saturação atualizado (0.5% em vez de 1.0%)

Uso:
    python validacao_bland_altman.py

Dependências: numpy, scipy, matplotlib
Dados IMU:    baixados do GitHub automaticamente (com cache local)
Dados marcador: arquivos .txt na mesma pasta (ou MARKER_DIR)
"""

import os
import urllib.request
import urllib.parse

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from scipy.signal import butter, filtfilt, find_peaks

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURAÇÃO
# ─────────────────────────────────────────────────────────────────────────────

MARKER_DIR   = "./"
IMU_BASE_URL = ("https://raw.githubusercontent.com/"
                "antoniofaical/PBL_2026_1/main/data/sessions/")

# Tabela de pares confirmados (marcador_arquivo, imu_arquivo, vel_kmh, confiança)
PARES = [
    ("A_10_kmh_MOV_A_.txt",                       "bruno_10kmh_1.csv", 10, "FORTE"),
    ("B_10_kmh_MOV_B_.txt",                       "bruno_10kmh_2.csv", 10, "FORTE"),
    ("A_12_kmh_MOV_.txt",                         "bruno_12kmh_1.csv", 12, "MODERADO"),
    ("B_12_kmh_MOV.txt",                          "bruno_12kmh_2.csv", 12, "MODERADO"),
    ("A_14_kmh_MOV_Perda_da_Bolinha__8s_.txt",    "bruno_14kmh_2.csv", 14, "PARCIAL"),
    ("B_14_kmh_MOV.txt",                          "bruno_14kmh_1.csv", 14, "FORTE"),
    ("PBL_Otávio.txt",                            "otavio_6kmh_1.csv",  6, "FORTE"),
]

# ── Sensibilidade IMU ─────────────────────────────────────────────────────────
# GYRO_CONFIG = 0x18  → ±2000 °/s → 16.4 LSB/(°/s)   ← firmware v2 (fix)
# GYRO_CONFIG = 0x10  → ±1000 °/s → 32.8 LSB/(°/s)   ← firmware v1 (depreciado)
GYRO_SENS  = 16.4    # LSB/(°/s)  *** ATUALIZADO v2 ***
ACCEL_SENS = 4096.0  # LSB/g — ACCEL_CONFIG = 0x10 (±8 g) — não alterado

FS_IMU    = 500.0   # Hz
FS_MARKER =  60.0   # Hz

# Limites de aceitabilidade (Falbriard et al., 2018)
LOA_GCT_LIMIT     = 15.0   # ms
LOA_CADENCE_LIMIT =  3.0   # spm

# ─────────────────────────────────────────────────────────────────────────────
# 1. LEITURA DE DADOS
# ─────────────────────────────────────────────────────────────────────────────

def load_marker(path):
    """
    Lê arquivo de marcadores exportado pelo Kinovea (60 Hz).
    Retorna dict: t, met_x, met_y, cal_x, cal_y
    """
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    lines = content.split("\n")
    sep   = "\t" if "\t" in lines[1] else ";"
    rows  = []
    for line in lines[3:]:
        line = line.strip()
        if not line or not line[0].isdigit():
            continue
        parts = line.split(sep)
        try:
            vals = [float(p.replace(",", ".").strip()) for p in parts[:5] if p.strip()]
            if len(vals) == 5:
                rows.append(vals)
        except ValueError:
            pass

    arr = np.array(rows)
    return {
        "t":     arr[:, 0],
        "met_x": arr[:, 1],
        "met_y": arr[:, 2],
        "cal_x": arr[:, 3],
        "cal_y": arr[:, 4],
    }


def load_imu(filename, cache_dir="./imu_cache"):
    """
    Baixa (e cacheia) o CSV do IMU do GitHub.
    Retorna dict: t_s, ax, ay, az, amag, gy_dps

    Usa GYRO_SENS = 16.4 LSB/(°/s) (±2000°/s, firmware v2).
    """
    os.makedirs(cache_dir, exist_ok=True)
    local = os.path.join(cache_dir, filename)

    if not os.path.exists(local):
        url = IMU_BASE_URL + urllib.parse.quote(filename)
        print(f"  Baixando {filename} ...")
        urllib.request.urlretrieve(url, local)

    t_ms_l, ax_l, ay_l, az_l, gy_l = [], [], [], [], []
    with open(local, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("#") or line.startswith("sample"):
                continue
            parts = line.strip().split(",")
            if len(parts) < 8:
                continue
            try:
                t_ms_l.append(int(parts[1]))
                ax_l.append(int(parts[2]))
                ay_l.append(int(parts[3]))
                az_l.append(int(parts[4]))
                gy_l.append(int(parts[6]))   # gyro Y = Ωp (pitch axis)
            except (ValueError, IndexError):
                pass

    t_ms  = np.array(t_ms_l,  dtype=np.int64)
    t_s   = (t_ms - t_ms[0]) / 1000.0
    ax_g  = np.array(ax_l, dtype=float) / ACCEL_SENS
    ay_g  = np.array(ay_l, dtype=float) / ACCEL_SENS
    az_g  = np.array(az_l, dtype=float) / ACCEL_SENS
    amag  = np.sqrt(ax_g**2 + ay_g**2 + az_g**2)
    gy_dps = np.array(gy_l, dtype=float) / GYRO_SENS   # ±2000°/s

    # Diagnóstico de saturação (apenas informativo — não deve ocorrer com ±2000°/s)
    sat_pct = 100.0 * np.sum(np.abs(np.array(gy_l)) >= 32760) / len(gy_l)
    if sat_pct > 0.5:
        print(f"  ⚠  SATURAÇÃO {sat_pct:.1f}% detectada em {filename} — "
              f"verifique GYRO_CONFIG no firmware")

    return {
        "t_s":    t_s,
        "ax":     ax_g,
        "ay":     ay_g,
        "az":     az_g,
        "amag":   amag,
        "gy_dps": gy_dps,
    }


# ─────────────────────────────────────────────────────────────────────────────
# 2. SINCRONIZAÇÃO VIA HEEL STOMP
# ─────────────────────────────────────────────────────────────────────────────

def find_stomp_imu(imu, search_window_s=20.0, min_amag=4.0):
    """
    Detecta o primeiro stomp de sincronização no IMU (pico isolado de |a|).
    Retorna o tempo (s) do primeiro stomp.
    """
    t   = imu["t_s"]
    mag = imu["amag"]

    mask = t < search_window_s
    t_w  = t[mask]
    m_w  = mag[mask]

    min_dist = int(0.2 * FS_IMU)
    peaks, _ = find_peaks(m_w, height=min_amag, distance=min_dist, prominence=2.0)

    if len(peaks) == 0:
        raise RuntimeError("Nenhum stomp detectado no IMU — verifique min_amag.")

    # Primeiro stomp de um cluster de ≥2 stomps separados por <2s
    for i, p in enumerate(peaks):
        if i + 1 < len(peaks):
            if t_w[peaks[i + 1]] - t_w[p] < 2.0:
                return float(t_w[p])

    return float(t_w[peaks[0]])


def find_stomp_marker(marker, search_window_s=5.0):
    """
    Detecta o stomp nos marcadores como pico de cal_y nos primeiros segundos.
    Retorna o tempo (s) do stomp no marcador.
    """
    t    = marker["t"]
    caly = marker["cal_y"]
    mask = t < search_window_s
    t_w  = t[mask]
    c_w  = caly[mask]

    min_dist = int(0.15 * FS_MARKER)
    peaks, _ = find_peaks(c_w, distance=min_dist, prominence=0.02)

    if len(peaks) == 0:
        print("  AVISO: stomp não detectado no marcador — usando t=0.")
        return 0.0

    return float(t_w[peaks[0]])


# ─────────────────────────────────────────────────────────────────────────────
# 3. DETECÇÃO DE IC/TC NOS MARCADORES
# ─────────────────────────────────────────────────────────────────────────────

def detect_events_marker(marker, t_start=0.0, t_end=None):
    """
    Detecta IC (mínimo local de cal_y) e TC (máximo local de met_y após IC).
    Retorna lista de dicts: {ic_t, tc_t, gct_ms, stride_t_ms}
    """
    t    = marker["t"]
    caly = marker["cal_y"]
    mety = marker["met_y"]

    if t_end is None:
        t_end = t[-1]

    b, a   = butter(4, 6.0 / (FS_MARKER / 2), "low")
    caly_f = filtfilt(b, a, caly)
    mety_f = filtfilt(b, a, mety)

    min_dist = int(0.35 * FS_MARKER)
    ic_peaks, _ = find_peaks(-caly_f, distance=min_dist, prominence=0.015)
    ic_in_window = ic_peaks[(t[ic_peaks] >= t_start) & (t[ic_peaks] <= t_end)]

    strides = []
    for i in range(len(ic_in_window) - 1):
        idx0 = ic_in_window[i]
        idx1 = ic_in_window[i + 1]

        ic_t        = float(t[idx0])
        stride_t_ms = (t[idx1] - t[idx0]) * 1000.0
        half        = (idx0 + idx1) // 2
        seg         = mety_f[idx0:half]
        seg_t       = t[idx0:half]

        if len(seg) < 4:
            continue

        tc_peaks, _ = find_peaks(seg, prominence=0.008)
        if len(tc_peaks) == 0:
            continue

        tc_t   = float(seg_t[tc_peaks[0]])
        gct_ms = (tc_t - ic_t) * 1000.0
        duty   = gct_ms / stride_t_ms

        if not (0.20 <= duty <= 0.60):
            continue
        if not (80 <= gct_ms <= 500):
            continue

        strides.append({
            "ic_t":        ic_t,
            "tc_t":        tc_t,
            "gct_ms":      gct_ms,
            "stride_t_ms": stride_t_ms,
        })

    return strides


# ─────────────────────────────────────────────────────────────────────────────
# 4. DETECÇÃO DE IC/TC NO IMU (Falbriard et al., 2018)
# ─────────────────────────────────────────────────────────────────────────────

def detect_events_imu(imu, t_start=0.0, t_end=None):
    """
    Método Falbriard: dois filtros Butterworth sobre Ωp (gyro Y = pitch).

    fc = 5 Hz  → detecção do pico de mid-swing
    fc = 30 Hz → localização de IC (k1) e TC (t1)

    IC = mínimo local de Ωp(30Hz) após cada mid-swing
    TC = primeiro mínimo local de Ωp(30Hz) na fase de apoio

    Retorna lista de dicts: {ic_t, tc_t, gct_ms, stride_t_ms}
    """
    t  = imu["t_s"]
    gy = imu["gy_dps"]

    if t_end is None:
        t_end = t[-1]

    b30, a30 = butter(2, 30.0 / (FS_IMU / 2), "low")
    gy30     = filtfilt(b30, a30, gy)

    mask   = (t >= t_start) & (t <= t_end)
    t_w    = t[mask]
    gy30_w = gy30[mask]

    if len(t_w) < 100:
        return []

    min_dist_ic = int(0.30 * FS_IMU)
    ic_peaks, _ = find_peaks(-gy30_w, distance=min_dist_ic,
                              height=-50, prominence=30)

    strides = []
    for i in range(len(ic_peaks) - 1):
        p0 = ic_peaks[i]
        p1 = ic_peaks[i + 1]

        ic_t        = float(t_w[p0])
        stride_t_s  = float(t_w[p1] - t_w[p0])
        stride_t_ms = stride_t_s * 1000.0

        if not (0.15 <= stride_t_s <= 0.90):
            continue

        span_end   = p0 + int(0.60 * stride_t_s * FS_IMU)
        span_end   = min(span_end, p1)
        span_start = p0 + 10

        if span_end <= span_start + 5:
            continue

        seg   = gy30_w[span_start:span_end]
        seg_t = t_w[span_start:span_end]

        tc_peaks, _ = find_peaks(-seg, prominence=15)
        if len(tc_peaks) == 0:
            continue

        best_tc = tc_peaks[np.argmin(seg[tc_peaks])]
        tc_t    = float(seg_t[best_tc])
        gct_ms  = (tc_t - ic_t) * 1000.0
        duty    = gct_ms / stride_t_ms

        if not (0.20 <= duty <= 0.65):
            continue
        if not (80 <= gct_ms <= 500):
            continue

        strides.append({
            "ic_t":        ic_t,
            "tc_t":        tc_t,
            "gct_ms":      gct_ms,
            "stride_t_ms": stride_t_ms,
        })

    return strides


# ─────────────────────────────────────────────────────────────────────────────
# 5. CORRESPONDÊNCIA STRIDE A STRIDE
# ─────────────────────────────────────────────────────────────────────────────

def match_strides(strides_ref, strides_imu, tol_s=0.080):
    """
    Para cada stride de referência encontra o IMU mais próximo por IC.
    Aceita se |ΔIC| ≤ tol_s.
    """
    matched_ref = []
    matched_imu = []

    imu_ic = np.array([s["ic_t"] for s in strides_imu])

    for ref in strides_ref:
        if len(imu_ic) == 0:
            continue
        diffs = np.abs(imu_ic - ref["ic_t"])
        best  = int(np.argmin(diffs))
        if diffs[best] <= tol_s:
            matched_ref.append(ref)
            matched_imu.append(strides_imu[best])

    return matched_ref, matched_imu


# ─────────────────────────────────────────────────────────────────────────────
# 6. BLAND-ALTMAN
# ─────────────────────────────────────────────────────────────────────────────

def bland_altman_stats(ref_vals, imu_vals):
    """
    Estatísticas de Bland-Altman.
    diff = IMU − referência  (positivo = IMU superestima)
    """
    ref  = np.array(ref_vals,  dtype=float)
    imu  = np.array(imu_vals,  dtype=float)
    diff = imu - ref
    mean = (imu + ref) / 2.0

    bias      = float(np.mean(diff))
    sd        = float(np.std(diff, ddof=1))
    loa_upper = bias + 1.96 * sd
    loa_lower = bias - 1.96 * sd
    corr      = float(np.corrcoef(mean, diff)[0, 1]) if len(diff) > 3 else float("nan")

    return {
        "n":         len(diff),
        "bias":      bias,
        "sd":        sd,
        "loa_upper": loa_upper,
        "loa_lower": loa_lower,
        "r_prop":    corr,
        "diff":      diff,
        "mean":      mean,
    }


# ─────────────────────────────────────────────────────────────────────────────
# 7. VISUALIZAÇÃO
# ─────────────────────────────────────────────────────────────────────────────

def plot_bland_altman(stats_gct, stats_cad, pair_labels,
                      outpath="bland_altman.png"):
    fig = plt.figure(figsize=(14, 6))
    gs  = gridspec.GridSpec(1, 2, figure=fig, wspace=0.35)

    colors = plt.cm.tab10(np.linspace(0, 1, len(stats_gct)))

    # ── GCT ──
    ax1 = fig.add_subplot(gs[0])
    all_means = np.concatenate([s["mean"] for s in stats_gct])
    all_diffs = np.concatenate([s["diff"] for s in stats_gct])
    overall   = bland_altman_stats(
        all_means - all_diffs / 2,
        all_means + all_diffs / 2,
    )
    for s, lbl, c in zip(stats_gct, pair_labels, colors):
        ax1.scatter(s["mean"], s["diff"], color=c, alpha=0.65, s=30,
                    label=lbl.replace(".txt", "").replace("_MOV", ""))

    ax1.axhline(overall["bias"],      color="black", lw=1.8, ls="-",
                label=f"Bias = {overall['bias']:.1f} ms")
    ax1.axhline(overall["loa_upper"], color="black", lw=1.2, ls="--",
                label=f"+1.96·SD = {overall['loa_upper']:.1f} ms")
    ax1.axhline(overall["loa_lower"], color="black", lw=1.2, ls="--",
                label=f"−1.96·SD = {overall['loa_lower']:.1f} ms")
    ax1.axhline(+LOA_GCT_LIMIT, color="red", lw=0.8, ls=":", alpha=0.5)
    ax1.axhline(-LOA_GCT_LIMIT, color="red", lw=0.8, ls=":", alpha=0.5,
                label=f"Limite Falbriard (±{LOA_GCT_LIMIT} ms)")

    ax1.set_xlabel("Média (IMU + marcador) / 2  [ms]",     fontsize=10)
    ax1.set_ylabel("Diferença  IMU − marcador  [ms]",      fontsize=10)
    ax1.set_title("Bland-Altman — GCT",                    fontsize=11, fontweight="bold")
    ax1.legend(fontsize=7.5, loc="upper right", framealpha=0.8)
    ax1.set_ylim(-80, 80)
    ax1.axhline(0, color="gray", lw=0.6, ls="-", alpha=0.4)
    ax1.text(0.02, 0.97, f"n = {overall['n']} strides",
             transform=ax1.transAxes, fontsize=8, va="top")

    # ── Cadência ──
    ax2 = fig.add_subplot(gs[1])
    cad_ref  = np.array([s["cad_ref"]  for s in stats_cad])
    cad_imu  = np.array([s["cad_imu"]  for s in stats_cad])
    cad_diff = cad_imu - cad_ref
    cad_mean = (cad_imu + cad_ref) / 2.0

    cad_bias  = float(np.mean(cad_diff))
    cad_sd    = float(np.std(cad_diff, ddof=1))
    cad_loa_u = cad_bias + 1.96 * cad_sd
    cad_loa_l = cad_bias - 1.96 * cad_sd

    for i, (lbl, c) in enumerate(zip(pair_labels, colors)):
        ax2.scatter(cad_mean[i], cad_diff[i], color=c, s=80,
                    label=lbl.replace(".txt", "").replace("_MOV", ""), zorder=3)

    ax2.axhline(cad_bias,  color="black", lw=1.8, ls="-",
                label=f"Bias = {cad_bias:.2f} spm")
    ax2.axhline(cad_loa_u, color="black", lw=1.2, ls="--",
                label=f"+1.96·SD = {cad_loa_u:.2f} spm")
    ax2.axhline(cad_loa_l, color="black", lw=1.2, ls="--",
                label=f"−1.96·SD = {cad_loa_l:.2f} spm")
    ax2.axhline(+LOA_CADENCE_LIMIT, color="red", lw=0.8, ls=":", alpha=0.5)
    ax2.axhline(-LOA_CADENCE_LIMIT, color="red", lw=0.8, ls=":", alpha=0.5,
                label=f"Limite ±{LOA_CADENCE_LIMIT} spm")

    ax2.set_xlabel("Média (IMU + marcador) / 2  [spm]",    fontsize=10)
    ax2.set_ylabel("Diferença  IMU − marcador  [spm]",     fontsize=10)
    ax2.set_title("Bland-Altman — Cadência",               fontsize=11, fontweight="bold")
    ax2.legend(fontsize=7.5, loc="upper right", framealpha=0.8)
    ax2.set_ylim(-10, 10)
    ax2.axhline(0, color="gray", lw=0.6, ls="-", alpha=0.4)
    ax2.text(0.02, 0.97, f"n = {len(cad_diff)} sessões",
             transform=ax2.transAxes, fontsize=8, va="top")

    plt.suptitle(
        "Validação IMU vs Marcadores de Vídeo (Bruno T47 + Otávio, esteira)",
        fontsize=12, fontweight="bold", y=1.01,
    )
    fig.savefig(outpath, dpi=150, bbox_inches="tight")
    print(f"\n  Figura salva em: {outpath}")
    plt.close(fig)


def print_summary_table(stats_gct, stats_cad, pair_labels):
    print("\n" + "═" * 90)
    print(f"{'Par':<30} {'km/h':>5}  {'n':>4}  "
          f"{'Bias GCT':>10}  {'LoA GCT':>16}  {'Bias cad':>10}")
    print("─" * 90)
    for sg, sc, lbl in zip(stats_gct, stats_cad, pair_labels):
        name    = (lbl.replace("_MOV_A_", "").replace("_MOV_B_", "")
                      .replace("_MOV", "").replace(".txt", ""))
        loa_str = f"[{sg['loa_lower']:+.1f}, {sg['loa_upper']:+.1f}]"
        print(f"{name:<30} {sc['speed']:>5}  {sg['n']:>4}  "
              f"{sg['bias']:>+8.1f}ms  {loa_str:>16}  "
              f"{sc['cad_diff']:>+8.2f}spm")
    print("═" * 90)

    all_diffs = np.concatenate([s["diff"] for s in stats_gct])
    pb  = float(np.mean(all_diffs))
    psd = float(np.std(all_diffs, ddof=1))
    pl  = 1.96 * psd
    print(f"\n  POOLED GCT  — bias={pb:+.1f} ms | SD={psd:.1f} ms | "
          f"LoA=[{pb-pl:+.1f}, {pb+pl:+.1f}] ms")

    cd  = np.array([s["cad_diff"] for s in stats_cad])
    cb  = float(np.mean(cd))
    csd = float(np.std(cd, ddof=1))
    cl  = 1.96 * csd
    print(f"  CADÊNCIA    — bias={cb:+.2f} spm | SD={csd:.2f} spm | "
          f"LoA=[{cb-cl:+.2f}, {cb+cl:+.2f}] spm")

    ok_gct = abs(pb) + pl  <= LOA_GCT_LIMIT
    ok_cad = abs(cb) + cl  <= LOA_CADENCE_LIMIT
    print(f"\n  Critério GCT (±{LOA_GCT_LIMIT}ms):    "
          f"{'✓ APROVADO' if ok_gct else '✗ REPROVADO'}")
    print(f"  Critério cad (±{LOA_CADENCE_LIMIT}spm): "
          f"{'✓ APROVADO' if ok_cad else '✗ REPROVADO'}")


# ─────────────────────────────────────────────────────────────────────────────
# 8. PIPELINE POR PAR
# ─────────────────────────────────────────────────────────────────────────────

def process_pair(marker_file, imu_file, speed_kmh, confianca,
                 marker_dir=MARKER_DIR):
    print(f"\n{'─'*60}")
    print(f"  {marker_file}  ↔  {imu_file}  [{speed_kmh} km/h | {confianca}]")

    marker_path = os.path.join(marker_dir, marker_file)
    if not os.path.exists(marker_path):
        print(f"  SKIP: marcador não encontrado em {marker_path}")
        return None, None

    marker = load_marker(marker_path)
    imu    = load_imu(imu_file)

    try:
        t_stomp_imu    = find_stomp_imu(imu)
        t_stomp_marker = find_stomp_marker(marker)
        offset = t_stomp_imu - t_stomp_marker
        print(f"  Stomp IMU: {t_stomp_imu:.3f}s | "
              f"Stomp marcador: {t_stomp_marker:.3f}s | "
              f"offset = {offset:.3f}s")
    except RuntimeError as e:
        print(f"  AVISO sincronização: {e} — usando offset=0")
        offset = 0.0
        t_stomp_marker = 0.0

    t_marker_end   = float(marker["t"][-1])
    t_imu_start    = float(marker["t"][0]) + offset
    t_imu_end      = t_marker_end + offset
    t_run_marker   = t_stomp_marker + 2.0
    t_run_imu      = t_imu_start + max(0, t_run_marker - float(marker["t"][0]))

    strides_marker = detect_events_marker(marker, t_start=t_run_marker,
                                          t_end=t_marker_end)
    strides_imu    = detect_events_imu(imu, t_start=t_run_imu,
                                       t_end=t_imu_end)

    print(f"  Strides: marcador={len(strides_marker)} | IMU={len(strides_imu)}")

    if len(strides_marker) < 3 or len(strides_imu) < 3:
        print("  SKIP: poucos strides detectados.")
        return None, None

    for s in strides_imu:
        s["ic_t"] -= offset
        s["tc_t"] -= offset

    matched_ref, matched_imu = match_strides(strides_marker, strides_imu)
    print(f"  Pares stride a stride: {len(matched_ref)}")

    if len(matched_ref) < 3:
        print("  SKIP: poucos pares encontrados.")
        return None, None

    gct_ref   = [s["gct_ms"]      for s in matched_ref]
    gct_imu   = [s["gct_ms"]      for s in matched_imu]
    stats_gct = bland_altman_stats(gct_ref, gct_imu)
    stats_gct["speed"] = speed_kmh

    cad_ref = 120_000.0 / np.median([s["stride_t_ms"] for s in matched_ref])
    cad_imu = 120_000.0 / np.median([s["stride_t_ms"] for s in matched_imu])
    stats_cad = {
        "cad_ref":  float(cad_ref),
        "cad_imu":  float(cad_imu),
        "cad_diff": float(cad_imu - cad_ref),
        "speed":    speed_kmh,
    }

    print(f"  Cadência → marcador:{cad_ref:.1f}spm | IMU:{cad_imu:.1f}spm | "
          f"Δ={cad_imu-cad_ref:+.1f}")
    print(f"  GCT      → bias:{stats_gct['bias']:+.1f}ms | "
          f"SD:{stats_gct['sd']:.1f}ms | "
          f"LoA:[{stats_gct['loa_lower']:+.1f}, {stats_gct['loa_upper']:+.1f}]ms")

    return stats_gct, stats_cad


# ─────────────────────────────────────────────────────────────────────────────
# 9. MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  VALIDAÇÃO IMU — BLAND-ALTMAN  (GYRO_SENS=16.4, ±2000°/s)")
    print("  Bruno (T47) + Otávio — Esteira — SESI 2026")
    print("=" * 60)

    all_stats_gct, all_stats_cad, valid_labels = [], [], []

    for marker_file, imu_file, speed, conf in PARES:
        sg, sc = process_pair(marker_file, imu_file, speed, conf)
        if sg is not None:
            all_stats_gct.append(sg)
            all_stats_cad.append(sc)
            valid_labels.append(marker_file)

    if not all_stats_gct:
        print("\nNenhum par processado com sucesso.")
        print(f"Verifique se os .txt dos marcadores estão em: {MARKER_DIR}")
        return

    print_summary_table(all_stats_gct, all_stats_cad, valid_labels)
    plot_bland_altman(all_stats_gct, all_stats_cad, valid_labels)
    print("\nConcluído.")


if __name__ == "__main__":
    main()
