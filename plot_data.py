import os
import glob

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

from scipy.signal import butter, filtfilt


# =========================
# CONFIGURAÇÕES
# =========================

PASTA_DADOS = ".\data\sessions"          # pasta onde estão os CSVs
PASTA_SAIDA = "plots"      # pasta de saída dos gráficos

FREQ_CORTE_HZ = 6          # frequência de corte do Butterworth
ORDEM_FILTRO = 4           # ordem do filtro

COLUNA_TEMPO = "t_ms"

COLUNAS_SINAIS = [
    "ax_raw",
    "ay_raw",
    "az_raw",
    "gx_raw",
    "gy_raw",
    "gz_raw",
]

os.makedirs(PASTA_SAIDA, exist_ok=True)


# =========================
# FUNÇÕES
# =========================

def estimar_fs_por_t_ms(t_ms):
    """
    Estima a frequência de amostragem a partir da coluna t_ms.
    Assume que t_ms está em milissegundos.
    """
    t_ms = np.asarray(t_ms, dtype=float)

    dt_ms = np.diff(t_ms)
    dt_ms = dt_ms[dt_ms > 0]

    if len(dt_ms) == 0:
        raise ValueError(
            "Não foi possível estimar a frequência de amostragem.")

    dt_s = np.median(dt_ms) / 1000.0
    fs = 1.0 / dt_s

    return fs


def filtro_butterworth_6hz(sinal, fs):
    """
    Aplica filtro Butterworth passa-baixa de 6 Hz.
    Não aplica nenhum outro tratamento.
    """
    nyquist = fs / 2.0
    freq_normalizada = FREQ_CORTE_HZ / nyquist

    if freq_normalizada >= 1:
        raise ValueError(
            f"Frequência de corte inválida: {FREQ_CORTE_HZ} Hz. "
            f"Nyquist = {nyquist:.2f} Hz."
        )

    b, a = butter(
        N=ORDEM_FILTRO,
        Wn=freq_normalizada,
        btype="low"
    )

    sinal_filtrado = filtfilt(b, a, sinal)

    return sinal_filtrado


def validar_schema(df, nome_arquivo):
    """
    Confere se o CSV possui as colunas necessárias.
    """
    colunas_necessarias = [COLUNA_TEMPO] + COLUNAS_SINAIS
    faltantes = [col for col in colunas_necessarias if col not in df.columns]

    if faltantes:
        raise ValueError(
            f"{nome_arquivo}: colunas ausentes no CSV: {faltantes}"
        )


def plotar_arquivo(caminho_csv):
    nome_arquivo = os.path.basename(caminho_csv)
    nome_base = os.path.splitext(nome_arquivo)[0]

    df = pd.read_csv(caminho_csv)

    validar_schema(df, nome_arquivo)

    t_ms = df[COLUNA_TEMPO].to_numpy(dtype=float)

    # Tempo relativo em segundos, apenas para facilitar leitura do gráfico.
    # Não altera os dados do sinal.
    t_s = (t_ms - t_ms[0]) / 1000.0

    fs = estimar_fs_por_t_ms(t_ms)

    print(f"\nArquivo: {nome_arquivo}")
    print(f"Amostras: {len(df)}")
    print(f"fs estimada: {fs:.2f} Hz")
    print(f"Duração: {t_s[-1]:.2f} s")

    # -------------------------
    # Plot acelerômetro
    # -------------------------

    plt.figure(figsize=(14, 6))

    for coluna in ["ax_raw", "ay_raw", "az_raw"]:
        sinal = df[coluna].to_numpy(dtype=float)
        sinal_filtrado = filtro_butterworth_6hz(sinal, fs)

        plt.plot(t_s, sinal_filtrado, label=coluna)

    plt.title(f"{nome_base} - Acelerômetro raw filtrado Butterworth 6 Hz")
    plt.xlabel("Tempo (s)")
    plt.ylabel("Aceleração raw (LSB)")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()

    caminho_saida = os.path.join(
        PASTA_SAIDA,
        f"{nome_base}_acelerometro_butterworth_6hz.png"
    )

    plt.savefig(caminho_saida, dpi=300)
    plt.close()

    # -------------------------
    # Plot giroscópio
    # -------------------------

    plt.figure(figsize=(14, 6))

    for coluna in ["gx_raw", "gy_raw", "gz_raw"]:
        sinal = df[coluna].to_numpy(dtype=float)
        sinal_filtrado = filtro_butterworth_6hz(sinal, fs)

        plt.plot(t_s, sinal_filtrado, label=coluna)

    plt.title(f"{nome_base} - Giroscópio raw filtrado Butterworth 6 Hz")
    plt.xlabel("Tempo (s)")
    plt.ylabel("Giroscópio raw (LSB)")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()

    caminho_saida = os.path.join(
        PASTA_SAIDA,
        f"{nome_base}_giroscopio_butterworth_6hz.png"
    )

    plt.savefig(caminho_saida, dpi=300)
    plt.close()


# =========================
# EXECUÇÃO
# =========================

arquivos_csv = sorted(glob.glob(os.path.join(PASTA_DADOS, "*.csv")))

print(f"Total de CSVs encontrados: {len(arquivos_csv)}")

for caminho_csv in arquivos_csv:
    try:
        plotar_arquivo(caminho_csv)
    except Exception as erro:
        print(f"[ERRO] {os.path.basename(caminho_csv)}: {erro}")

print("\nFinalizado.")
print(f"Gráficos salvos em: {PASTA_SAIDA}")
