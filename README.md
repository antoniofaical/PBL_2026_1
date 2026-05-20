# PBL 2026.1 — Aquisição de corrida (MPU6050 + ESP32-C3)

Sistema de aquisição de sinais inerciais para análise de marcha/corrida (método Falbriard), com **gravação no device** e **transferência wireless via BLE**.

**Versão atual:** Etapa 11 — aquisição wireless funcional (BLE + pipeline Python de análise). **Validada em bancada** (ver [Validação](#validação-mesa--bancada)).

## Hardware

| Item    | Detalhe                                          |
| ------- | ------------------------------------------------ |
| MCU     | ESP32-C3 Super Mini                              |
| Sensor  | MPU6050 (I2C `0x68`, 400 kHz)                    |
| Botão   | GPIO 0 (pull-up, LOW = pressionado)              |
| LED RGB | R=GPIO 7, G=GPIO 6, B=GPIO 5 (PWM, cátodo comum) |
| Taxa    | 500 Hz, ±8 g, ±1000 °/s                          |

## Fluxo no device

1. Ligar → LED **azul** (IDLE), BLE advertising `PBL-Run-C3`
2. Conectar `receive_ble.py` no PC → mensagem _Device conectado. Esperando...._
3. **Botão** → calibração (~3 s, LED **rosa**) → LED **verde** (pronto)
4. **Botão** → gravação (LED **amarelo**)
5. **Botão** → fim da gravação + upload BLE (LED **roxo**) → CSV salvo no PC

> Calibração e gravação exigem BLE conectado. Sem receptor ativo, o firmware não avança no fluxo.

## Estrutura do repositório

```
PBL_2026_1/
├── firmware_device/
│   └── firmware_device.ino    # Firmware Etapa 11 (Arduino IDE)
├── pbl_data/                    # Formato binário/CSV compartilhado
│   ├── format.py                # Structs, constantes MPU, protocolo XFER
│   ├── payload.py               # Parse do payload binário → linhas CSV
│   └── csv_io.py                # Escrita de CSV padronizado
├── receive_ble.py               # Receptor BLE principal (wireless)
├── receive_serial.py            # Receptor USB serial (fallback)
├── ler_dados.py                 # Leitura, diagnóstico e plots (.csv / .bin)
├── detectar_eventos.py          # IC, TC, cadência, GCT (método Falbriard)
├── data/sessions/               # CSVs gerados (gitignored)
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

Os CSVs vão para **`data/sessions/run_001.csv`**, `run_002.csv`.

Opções:

```bash
python receive_ble.py --address 8C:D0:B2:A8:55:40
python receive_ble.py --out-dir data/sessions
python receive_ble.py --also-save-bin
```

Cada sessão incrementa o contador `run_NNN`. A transferência usa ACK por bloco de bytes no characteristic **Control** (`0x01`), alinhado ao firmware para uploads estáveis no Windows.

### 3. Análise offline

```bash
python ler_dados.py data/sessions/run_001.csv
python ler_dados.py data/sessions/run_001.csv --no-plot
python detectar_eventos.py data/sessions/run_001.csv
python detectar_eventos.py data/sessions/run_001.csv --export-events --no-plot
```

### 4. USB serial (opcional / debug)

Com firmware que ainda envie pela UART após gravar:

```bash
python receive_serial.py --port COM10
```

## Formato dos dados

Constantes centralizadas em `pbl_data/format.py` (sincronizar com o firmware):

| Constante    | Valor                                                    |
| ------------ | -------------------------------------------------------- |
| Cabeçalho    | 28 B — `<6f?3x` (bias giro + gravidade + `calib_valid`)  |
| Amostra      | 16 B — `SAMPLE_FMT = "<Ihhhhhh"` (`t_ms` + 6× int16 raw) |
| Taxa nominal | 500 Hz                                                   |
| Acel         | 4096 LSB/g (±8 g)                                        |
| Giro         | 32,8 LSB/(°/s) (±1000 °/s)                               |

CSV exportado: colunas `*_raw`, metadados de calibração, `source_path`, `received_at`.

## BLE (GATT)

| UUID                                           | Função                                                      |
| ---------------------------------------------- | ----------------------------------------------------------- |
| Serviço `4fafc201-1fb5-459e-8fcc-c5c9c331914b` | PBL Run                                                     |
| `beb5483e-36e1-4688-b7f5-ea07361b26a8` Status  | NOTIFY — mensagens ASCII (`===BEGIN…===`, `XFER: OK`, etc.) |
| `0000ff02-0000-1000-8000-00805f9b34fb` Data    | NOTIFY — payload binário                                    |
| `0000ff03-0000-1000-8000-00805f9b34fb` Control | WRITE — ACK `0x01` (por bloco de bytes no upload)           |

Framing da transferência (serial/BLE): `===BEGIN_LAST_RUN_BIN===` → `PATH:` → `SIZE:` → `DATA_BEGIN` → bytes → `DATA_END` → `===END_LAST_RUN_BIN===` → `XFER: OK`.

## Validação (mesa / bancada)

Bateria executada **sem corrida/marcha com o sensor no corpo** — device na mesa, shake manual e rotações lentas. **Resultado: 14/14 OK** (maio/2026).

| #   | Teste                                                         | Resultado |
| --- | ------------------------------------------------------------- | --------- |
| 1   | Imports `pbl_data` (`SAMPLE_FMT`, `SAMPLE_SIZE`)              | OK        |
| 2   | `ler_dados.py` em CSV existente (`--no-plot`)                 | OK        |
| 3   | `detectar_eventos.py` em CSV existente (`--no-plot`)          | OK        |
| 4   | `--export-events` gera `*_eventos.csv`                        | OK        |
| 5   | Boot: LED azul + advertising `PBL-Run-C3`                     | OK        |
| 6   | Conexão `receive_ble.py` + mensagem de espera                 | OK        |
| 7   | Calibração estática (~3 s) → LED verde                        | OK        |
| 8   | Gravação parada: \|a\| ≈ 1 g, giro ~0 pós-bias                | OK        |
| 9   | Taxa: Δt_ms ≈ 2 ms (500 Hz)                                   | OK        |
| 10  | Shake na mesa (5–10 s): variação em ax/ay/az + upload         | OK        |
| 11  | Rotação lenta por eixo: picos coerentes em gx/gy/gz           | OK        |
| 12  | `detectar_eventos` no CSV do shake (`--axis` gx/gy/gz)        | OK        |
| 13  | Duas sessões seguidas (`run_001`, `run_002`, …) + `XFER: OK`  | OK        |
| 14  | `--also-save-bin`: `.bin` = 28 + N×16 B; leitura bate com CSV | OK        |

**Fora desta bateria (próxima etapa de validação):** teste de campo com corrida/marcha real e comparação com referência (vídeo, esteira ou segundo IMU).

### Smoke rápido (repetir antes de demo)

```bash
python -c "from pbl_data.format import SAMPLE_FMT, SAMPLE_SIZE; assert SAMPLE_FMT=='<Ihhhhhh' and SAMPLE_SIZE==16"
python ler_dados.py data/sessions/run_001.csv --no-plot
python detectar_eventos.py data/sessions/run_001.csv --no-plot
```

## Roadmap

| Etapa  | Status                                                    |
| ------ | --------------------------------------------------------- |
| 10     | Serial + máquina de estados                               |
| **11** | **BLE + LED PWM + pipeline Python (validado em bancada)** |
| 12     | Upload WiFi rápido → API                                  |
| 13     | Dashboard web                                             |

## Licença

MIT — ver [LICENSE](LICENSE).
