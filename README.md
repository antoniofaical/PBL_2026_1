# PBL 2026.1 — Aquisição de corrida (MPU6050 + ESP32-C3)

Sistema de aquisição de sinais inerciais para análise de marcha/corrida (método Falbriard), com **gravação no device** e **transferência wireless via BLE**.

**Versão atual:** Etapa 11 — aquisição wireless funcional (BLE + pipeline Python de análise).

## Hardware

| Item | Detalhe |
|------|---------|
| MCU | ESP32-C3 Super Mini |
| Sensor | MPU6050 (I2C `0x68`, 400 kHz) |
| Botão | GPIO 0 (pull-up, LOW = pressionado) |
| LED RGB | R=GPIO 7, G=GPIO 6, B=GPIO 5 (PWM, cátodo comum) |
| Taxa | 500 Hz, ±8 g, ±1000 °/s |

## Fluxo no device

1. Ligar → LED **azul** (IDLE), BLE advertising `PBL-Run-C3`
2. Conectar `receive_ble.py` no PC → mensagem *Device conectado. Esperando....*
3. **Botão** → calibração (~3 s, LED **rosa**) → LED **verde** (pronto)
4. **Botão** → gravação (LED **amarelo**)
5. **Botão** → fim da gravação + upload BLE (LED **roxo**) → CSV salvo no PC

## Estrutura do repositório

```
PBL_2026_1/
├── firmware_device/
│   └── firmware_device.ino    # Firmware Etapa 11 (Arduino IDE)
├── pbl_data/                  # Formato binário/CSV compartilhado
├── receive_ble.py             # Receptor BLE principal (wireless)
├── receive_serial.py          # Receptor USB serial (fallback)
├── ler_dados.py               # Leitura, diagnóstico e plots
├── detectar_eventos.py        # IC, TC, cadência, GCT
├── data/sessions/             # CSVs gerados (gitignored)
├── requirements.txt
└── LICENSE
```

## Instalação (Python)

```bash
pip install -r requirements.txt
```

## Uso rápido

### 1. Firmware

1. Abrir `firmware_device/firmware_device.ino` no Arduino IDE
2. Placa: **ESP32C3 Dev Module**
3. Instalar biblioteca **NimBLE-Arduino** (h2zero)
4. Upload

### 2. Receptor BLE (principal)

```bash
python receive_ble.py
# ou (atalho): python test_ble.py
```

Os CSVs vao para **`data/sessions/run_001.csv`**, nao mais `ble_sessions/`.

Opções:

```bash
python receive_ble.py --address 8C:D0:B2:A8:55:40
python receive_ble.py --out-dir data/sessions
python receive_ble.py --also-save-bin
```

Cada corrida salva `data/sessions/run_001.csv`, `run_002.csv`, …

### 3. Análise offline

```bash
python ler_dados.py data/sessions/run_001.csv
python detectar_eventos.py data/sessions/run_001.csv --export-events
```

### 4. USB serial (opcional / debug)

Com firmware que ainda envie pela UART após gravar:

```bash
python receive_serial.py --port COM10
```

## Formato dos dados

| Bloco | Tamanho | Conteúdo |
|-------|---------|----------|
| Cabeçalho | 28 B | Calibração (bias giro + gravidade) |
| Amostra | 16 B | `t_ms` + 6× int16 raw (ax…gz) |

CSV exportado: colunas `*_raw`, metadados de calibração e `received_at`.

## BLE (GATT)

| UUID | Função |
|------|--------|
| Serviço `4fafc201-…` | PBL Run |
| `beb5483e-…` Status | NOTIFY — mensagens ASCII |
| `0000ff02-…` Data | NOTIFY — payload binário |
| `0000ff03-…` Control | WRITE — ACK `0x01` por chunk |

## Roadmap

| Etapa | Status |
|-------|--------|
| 10 | Serial + máquina de estados |
| **11** | **BLE + LED PWM (atual)** |
| 12 | Upload WiFi rápido → API |
| 13 | Dashboard web |

## Licença

MIT — ver [LICENSE](LICENSE).
