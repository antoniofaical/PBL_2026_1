"""
analisar_sesi.py — Pipeline de análise Falbriard nos dados do SESI (v4)
========================================================================

Método: Falbriard et al. (2018) — estimativa de parâmetros temporais de
corrida por giroscópio de pitch montado no dorso do pé.

Parâmetros estimados:
  - Cadência (spm)
  - Ground Contact Time — GCT (ms)
  - Flight Time — FLT (ms)  [apenas corrida]

Atualizações v4 (2026-06):
  - Compatível com GYRO_CONFIG = 0x18 (±2000 °/s) — fix de saturação
  - Sensibilidade lida automaticamente via ler_dados.py (sem hardcoding)
  - Aviso de saturação atualizado para ±2000 °/s
  - Import path relativo (não depende de /tmp/)

Uso:
    python analisar_sesi.py [--no-plot]
"""

import sys
import argparse
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from scipy.signal import butter, filtfilt, find_peaks

# ler_dados.py deve estar na mesma pasta ou no PYTHONPATH
from ler_dados import (
    carregar_aquisicao,
    converter_para_si,
    porcentagem_saturacao,
    estimar_fs,
    SAMPLE_RATE_HZ,
)

# ── Faixas de referência da literatura ───────────────────────────────────────

REFS = {
    "otavio_4kmh":       dict(cad=(100, 120), gct_ms=(580, 800), flt_ms=None,
                              label="Otávio 4 km/h  (caminhada)"),
    "otavio_6kmh":       dict(cad=(115, 135), gct_ms=(540, 680), flt_ms=None,
                              label="Otávio 6 km/h  (caminhada rápida)"),
    "bruno_10kmh":       dict(cad=(155, 180), gct_ms=(200, 295), flt_ms=(80, 160),
                              label="Bruno 10 km/h (corrida)"),
    "bruno_12kmh":       dict(cad=(160, 185), gct_ms=(180, 265), flt_ms=(90, 165),
                              label="Bruno 12 km/h (corrida)"),
    "bruno_14kmh":       dict(cad=(165, 192), gct_ms=(165, 245), flt_ms=(95, 170),
                              label="Bruno 14 km/h (corrida)"),
    "bruno_outside":     dict(cad=(230, 340), gct_ms=(80, 160),  flt_ms=(75, 160),
                              label="Bruno pista (sprint)"),
    "cristofer_outside": dict(cad=(150, 270), gct_ms=(80, 260),  flt_ms=(70, 180),
                              label="Cristofer pista (T11)"),
}


def _key(nome):
    for k in REFS:
        if k in nome:
            return k
    return None


def _status(val, faixa):
    if faixa is None or val is None:
        return "–"
    lo, hi = faixa
    if lo <= val <= hi:
        return "✓"
    return f"⚠ (esp.{lo}–{hi})"


# ── Filtros ───────────────────────────────────────────────────────────────────

def butter_lp(sinal, fc, fs=500.0, ordem=2):
    """Filtro Butterworth passa-baixa zero-phase."""
    fc = min(fc, 0.45 * fs)
    b, a = butter(ordem, fc / (fs / 2.0), btype="low")
    return filtfilt(b, a, sinal)


# ── Trimming adaptativo ───────────────────────────────────────────────────────

def trim_janela_auto(picos, fs, min_s=0.20, min_passos=5):
    """
    Isolamento automático da janela de corrida estável via IQR dos intervalos.
    Funciona para caminhada (stride ~1.1s) e sprint (stride ~0.35s) sem ajuste
    manual de parâmetros.
    """
    if len(picos) < min_passos + 1:
        return np.array([])
    dts = np.diff(picos.astype(float)) / fs

    q25, q75 = np.percentile(dts, 25), np.percentile(dts, 75)
    iqr = q75 - q25
    margin   = 1.5 * iqr
    auto_max = min(2.5, q75 + margin)
    auto_min = max(min_s, q25 - margin)

    valido = (dts >= auto_min) & (dts <= auto_max)
    best_s, best_l, cur_s, cur_l = 0, 0, 0, 0
    for i, v in enumerate(valido):
        if v:
            if cur_l == 0:
                cur_s = i
            cur_l += 1
            if cur_l > best_l:
                best_l, best_s = cur_l, cur_s
        else:
            cur_l = 0

    if best_l < min_passos:
        return np.array([])
    return picos[best_s: best_s + best_l + 1]


# ── Detecção de IC e TC (método Falbriard) ───────────────────────────────────

def detectar_ic_tc(gp_ict, picos, margem=5):
    """
    Detecta Initial Contact (IC) e Toe-off Contact (TC) a partir dos picos
    de mid-swing.

    IC = mínimo de Ωp (filtrado 30 Hz) no intervalo antes do meio-stride
    TC = mínimo de Ωp no intervalo após o meio-stride

    Baseado em Falbriard et al. (2018), Frontiers in Physiology.
    """
    ic, tc = [], []
    for i in range(len(picos) - 1):
        p1, p2 = int(picos[i]), int(picos[i + 1])
        meio = (p1 + p2) // 2
        if p1 + margem < meio:
            ic.append(p1 + int(np.argmin(gp_ict[p1:meio])))
        if meio + margem < p2:
            tc.append(meio + int(np.argmin(gp_ict[meio:p2])))
    return np.array(ic, dtype=int), np.array(tc, dtype=int)


# ── Cálculo de métricas ───────────────────────────────────────────────────────

def calcular_metricas(ic, tc, fs, is_walking=False):
    """
    Calcula cadência, GCT e FLT a partir dos instantes de IC e TC detectados.

    Fórmulas:
      cadência = 2 × 60 / T_stride          [spm]
      GCT      = T_TC − T_IC                [ms]
      FLT      = T_stride/2 − GCT           [ms]  (apenas corrida)

    Nota: FLT = step_time − GCT (não stride − 2×GCT, que seria swing time).
    """
    if len(ic) < 3:
        return None

    dt_stride = np.diff(ic.astype(float)) / fs
    dt_stride = dt_stride[(dt_stride > 0.30) & (dt_stride < 2.50)]
    if not len(dt_stride):
        return None

    cad = 2.0 * 60.0 / dt_stride   # spm

    gcts = []
    for ic_v in ic:
        tcs = tc[tc > ic_v]
        if len(tcs):
            g = (tcs[0] - ic_v) / fs * 1000.0
            if 40 < g < 1500:
                gcts.append(g)
    gcts = np.array(gcts)

    stride_ms = float(np.median(dt_stride)) * 1000.0
    step_ms   = stride_ms / 2.0
    gct_med   = float(np.mean(gcts)) if len(gcts) else None

    flt_est = None
    if gct_med is not None and not is_walking:
        flt_est = step_ms - gct_med
        if flt_est < 0 or flt_est > 400:
            flt_est = None

    return {
        "cad_media": float(np.mean(cad)),
        "cad_std":   float(np.std(cad)),
        "cad_lista": cad,
        "gct_media": gct_med,
        "gct_std":   float(np.std(gcts)) if len(gcts) else None,
        "gct_lista": gcts,
        "flt_est":   flt_est,
        "stride_ms": stride_ms,
        "step_ms":   step_ms,
        "n_passos":  int(len(ic)),
    }


# ── Plots ─────────────────────────────────────────────────────────────────────

def plot_sessao(nome, dados, gp_mid, gp_ict,
                picos_raw, picos_trim, ic, tc,
                metricas, ref, sat, gyro_range_dps, out_dir):
    t   = dados["t"]
    fig = plt.figure(figsize=(15, 10))

    titulo = f"{nome}   |   saturação gyro gy: {sat:.2f}%"
    # Com ±2000°/s, saturação só em situações extremas (>2000°/s — improvável)
    if sat > 0.5:
        titulo += f"  ⚠ saturação detectada em ±{gyro_range_dps}°/s"
    fig.suptitle(titulo, fontsize=11)

    gs  = gridspec.GridSpec(3, 2, figure=fig, hspace=0.50, wspace=0.35)
    ax1 = fig.add_subplot(gs[0, :])
    ax2 = fig.add_subplot(gs[1, :])
    ax3 = fig.add_subplot(gs[2, 0])
    ax4 = fig.add_subplot(gs[2, 1])

    # Sinal completo
    ax1.plot(t, gp_mid, lw=0.6, color="#888",    alpha=0.7,
             label="Ωp filtrado 5 Hz (mid-swing)")
    ax1.plot(t, gp_ict, lw=0.6, color="#4a86e8", alpha=0.5,
             label="Ωp filtrado 30 Hz (IC/TC)")
    if len(picos_raw):
        ax1.scatter(t[picos_raw], gp_mid[picos_raw], s=15, color="#ff7537",
                    zorder=3, alpha=0.5, label="mid-swing (todos)")
    if len(picos_trim):
        ax1.scatter(t[picos_trim], gp_mid[picos_trim], s=55, marker="^",
                    color="#16a766", zorder=5, label="mid-swing (janela útil)")
    ax1.axhline(0, lw=0.4, color="gray")
    ax1.set(ylabel="Ωp (°/s)", xlabel="tempo (s)",
            title="Sinal completo — detecção de mid-swing e isolamento da janela útil")
    ax1.legend(fontsize=8, loc="upper right")
    ax1.grid(alpha=0.2)

    # Janela trimada com IC/TC
    if len(picos_trim) and len(ic):
        i0 = max(0, int(picos_trim[0]) - 100)
        i1 = min(len(t) - 1, int(picos_trim[-1]) + 100)
        ax2.plot(t[i0:i1], gp_ict[i0:i1], lw=0.9, color="#4a86e8")
        ax2.scatter(t[picos_trim], gp_ict[picos_trim], s=55, marker="^",
                    color="#16a766", zorder=5, label="mid-swing")
        if len(ic):
            ax2.scatter(t[ic], gp_ict[ic], s=55, marker="v",
                        color="#e24b4a", zorder=5, label="IC (contato inicial)")
        if len(tc):
            ax2.scatter(t[tc], gp_ict[tc], s=55, marker="s",
                        color="#ff7537", zorder=5, label="TC (retirada do pé)")
        ax2.axhline(0, lw=0.4, color="gray")
        ax2.set(ylabel="Ωp (°/s)", xlabel="tempo (s)",
                title="Janela útil — IC, TC e mid-swing detectados")
        ax2.legend(fontsize=8, loc="upper right")
        ax2.grid(alpha=0.2)
    else:
        ax2.text(0.5, 0.5, "Janela não detectada", ha="center", va="center",
                 transform=ax2.transAxes)
        ax2.set_title("Janela útil")

    # Cadência por passada
    if metricas and len(metricas["cad_lista"]):
        ps = np.arange(1, len(metricas["cad_lista"]) + 1)
        ax3.plot(ps, metricas["cad_lista"], "o-", ms=5, lw=1, color="#3c78d8")
        ax3.axhline(metricas["cad_media"], ls="--", lw=1.5, color="#3c78d8",
                    label=f"média {metricas['cad_media']:.1f} spm")
        if ref and ref["cad"]:
            ax3.axhspan(*ref["cad"], alpha=0.15, color="#16a766",
                        label="faixa literatura")
        st = _status(metricas["cad_media"], ref["cad"] if ref else None)
        ax3.set(xlabel="passada #", ylabel="cadência (spm)",
                title=f"Cadência:  {metricas['cad_media']:.0f} ± "
                      f"{metricas['cad_std']:.0f} spm   {st}")
        ax3.legend(fontsize=8)
        ax3.grid(alpha=0.2)
    else:
        ax3.text(0.5, 0.5, "–", ha="center", va="center",
                 transform=ax3.transAxes)
        ax3.set_title("Cadência")

    # GCT + FLT
    if metricas and len(metricas["gct_lista"]):
        ps_g = np.arange(1, len(metricas["gct_lista"]) + 1)
        ax4.plot(ps_g, metricas["gct_lista"], "s-", ms=5, lw=1,
                 color="#e24b4a", label="GCT (IC→TC)")
        ax4.axhline(metricas["gct_media"], ls="--", lw=1.5, color="#e24b4a",
                    label=f"GCT médio {metricas['gct_media']:.0f} ms")
        if ref and ref["gct_ms"]:
            ax4.axhspan(*ref["gct_ms"], alpha=0.12, color="#e24b4a",
                        label="GCT literatura")
        if metricas.get("flt_est") is not None:
            ax4.axhline(metricas["flt_est"], ls=":", lw=1.8, color="#ff7537",
                        label=f"FLT estimado {metricas['flt_est']:.0f} ms")
            if ref and ref.get("flt_ms"):
                ax4.axhspan(*ref["flt_ms"], alpha=0.10, color="#ff7537",
                            label="FLT literatura")
        gct_st = _status(metricas["gct_media"], ref["gct_ms"] if ref else None)
        ax4.set(xlabel="passo #", ylabel="tempo (ms)",
                title=f"GCT: {metricas['gct_media']:.0f} ± "
                      f"{metricas['gct_std']:.0f} ms   {gct_st}")
        ax4.legend(fontsize=8)
        ax4.grid(alpha=0.2)
    else:
        ax4.text(0.5, 0.5, "–", ha="center", va="center",
                 transform=ax4.transAxes)
        ax4.set_title("GCT / Flight time estimado")

    out = out_dir / f"{nome}_validacao.png"
    fig.savefig(out, dpi=130, bbox_inches="tight")
    plt.close(fig)
    return out


# ── Pipeline principal ────────────────────────────────────────────────────────

def processar(csv_path, out_dir, plot=True):
    """Processa uma sessão completa e retorna dict de resultados."""
    nome  = Path(csv_path).stem
    calib, samples = carregar_aquisicao(csv_path)
    dados = converter_para_si(samples, calib)
    fs    = estimar_fs(samples)
    sat   = porcentagem_saturacao(samples, "gy")
    gyro_range = calib.get("gyro_range_dps", 2000)

    # Dois filtros Butterworth (regra dos dois filtros — Falbriard 2018)
    gp_mid = butter_lp(dados["gy"], fc=5.0,  fs=fs)   # detecção mid-swing
    gp_ict = butter_lp(dados["gy"], fc=30.0, fs=fs)   # localização IC/TC

    picos_raw, _ = find_peaks(gp_mid, distance=int(fs / 4.5), height=80.0)
    picos_trim   = trim_janela_auto(picos_raw, fs)

    is_walking = "4kmh" in nome or "6kmh" in nome

    if len(picos_trim) >= 3:
        ic, tc   = detectar_ic_tc(gp_ict, picos_trim)
        metricas = calcular_metricas(ic, tc, fs, is_walking=is_walking)
    else:
        ic = tc = np.array([], dtype=int)
        metricas = None

    ref      = REFS.get(_key(nome))
    out_path = None
    if plot:
        out_path = plot_sessao(nome, dados, gp_mid, gp_ict,
                               picos_raw, picos_trim, ic, tc,
                               metricas, ref, sat, gyro_range, out_dir)

    return dict(
        nome=nome, sat=sat, gyro_range=gyro_range,
        n_raw=len(picos_raw), n_trim=len(picos_trim),
        metricas=metricas, ref=ref,
        calib_ok=calib.get("valid", False),
        plot=out_path,
    )


def tabela(results):
    sep = "─" * 118
    print(sep)
    print(f"{'Sessão':<32} {'Sat%':>5}  {'n':>4}  "
          f"{'Cadência (spm)':>20}  {'GCT (ms)':>16}  {'FLT_est(ms)':>13}  Validação")
    print(sep)
    for r in results:
        m   = r["metricas"]
        ref = r["ref"]
        sat = r["sat"]
        if m is None:
            print(f"{r['nome']:<32} {sat:>5.2f}   —    "
                  f"{'—':>20}  {'—':>16}  {'—':>13}  sem janela")
            continue
        cad_s = f"{m['cad_media']:5.1f} ± {m['cad_std']:4.1f}"
        gct_s = (f"{m['gct_media']:5.0f} ± {m['gct_std']:4.0f}"
                 if m["gct_media"] else "—")
        flt_s = f"{m['flt_est']:5.0f}" if m["flt_est"] else "—"
        cad_ok = _status(m["cad_media"], ref["cad"] if ref else None)
        gct_ok = _status(m["gct_media"], ref["gct_ms"] if ref else None)
        flt_ok = _status(m["flt_est"],   ref.get("flt_ms") if ref else None)
        warn   = f"  ⚠ sat:{sat:.1f}%" if sat > 0.5 else ""
        print(f"{r['nome']:<32} {sat:>5.2f}  {m['n_passos']:>4}  "
              f"{cad_s:>20}  {gct_s:>16}  {flt_s:>13}  "
              f"cad:{cad_ok}  gct:{gct_ok}  flt:{flt_ok}{warn}")
    print(sep)


def main():
    parser = argparse.ArgumentParser(description="Pipeline Falbriard — dados SESI")
    parser.add_argument("--no-plot", action="store_true", help="Não gerar gráficos")
    parser.add_argument(
        "--data-dir",
        default=None,
        help="Pasta com os CSVs (default: ./data/sessions/)",
    )
    args = parser.parse_args()

    # Caminho relativo ao script — não depende de /tmp/
    script_dir = Path(__file__).parent
    data_dir   = Path(args.data_dir) if args.data_dir else script_dir / "data" / "sessions"
    out_dir    = script_dir / "output" / "plots"
    out_dir.mkdir(parents=True, exist_ok=True)

    sessoes = sorted([
        p for p in data_dir.glob("*.csv")
        if p.stem not in {"run_003", "run_006"}
    ])

    if not sessoes:
        print(f"Nenhum CSV encontrado em: {data_dir}")
        return

    print(f"\nProcessando {len(sessoes)} sessões...\n")
    results = []
    for p in sessoes:
        r = processar(p, out_dir, plot=not args.no_plot)
        results.append(r)
        m = r["metricas"]
        if m:
            flt_str = f"  FLT={m['flt_est']:.0f}ms" if m["flt_est"] else ""
            gct_str = f"GCT={m['gct_media']:.0f}ms" if m["gct_media"] else "GCT=—"
            info = f"cad={m['cad_media']:.0f}spm  {gct_str}{flt_str}"
        else:
            info = "sem janela"
        print(f"  {r['nome']:<32}  trim={r['n_trim']:3d}  "
              f"sat={r['sat']:.2f}%  range=±{r['gyro_range']}°/s  {info}")

    print()
    tabela(results)
    if not args.no_plot:
        print(f"\nPlots → {out_dir}\n")


if __name__ == "__main__":
    main()
