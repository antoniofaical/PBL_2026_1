/**
 * ============================================================================
 * Etapa 10 — Máquina de estados integrada
 * Placa: ESP32-C3 Super Mini (Arduino-ESP32 core, board "ESP32C3 Dev Module")
 *
 * Pipeline:
 *   BOOT -> IDLE (azul) -> [btn] -> CALIB (rosa) -> READY (verde)
 *        -> [btn] -> REC (amarelo) -> [btn] -> SAVE (roxo)
 *        -> stream serial ok (verde 1s) | fail (vermelho 1s) -> IDLE
 *
 * Mapeamento de pinos (confirmado contra o esquemático do C3 Super Mini):
 *   GPIO 4 -> botão (com pull-up interno, baixo = pressionado)
 *   GPIO 5 -> LED R   (anodo, série 330R, cátodo comum no GND)
 *   GPIO 6 -> LED G
 *   GPIO 7 -> LED B
 *   GPIO 8 -> I2C SDA -> MPU6050 (AD0 no GND -> 0x68)
 *   GPIO 9 -> I2C SCL -> MPU6050
 *
 * Config do MPU para corrida:
 *   ACCEL_FS = ±8g (RECOMENDADO para validar andando; subir para ±16g em corrida)
 *   GYRO_FS  = ±1000°/s (RECOMENDADO para validar andando; subir para ±2000 em corrida)
 *   DLPF     = 44 Hz (compatível com filtro Butterworth de 30 Hz que o Falbriard aplica depois)
 *   SMPLRT_DIV = 1 -> taxa de saída = 1000/(1+1) = 500 Hz
 *
 * Gravação:
 *   - Buffer circular de 200 amostras em RAM (~3.2 KB)
 *   - Flush para LittleFS em blocos quando o buffer estiver meio cheio
 *   - Formato binário: int32 millis + 6 int16 raw = 16 B por amostra
 *   - Calibração (Parte 1) salva no início do arquivo como cabeçalho
 *
 * TODOs marcados no código:
 *   SAVE_XFER: stream serial do arquivo salvo em LittleFS
 *   [TODO_INT] Migrar de polling com micros() para INT pin do MPU
 * ============================================================================
 */

#include <Arduino.h>
#include <Wire.h>
#include <LittleFS.h>

// ---------- Pinos ----------
static constexpr uint8_t PIN_BUTTON = 0;
static constexpr uint8_t PIN_LED_R  = 7;
static constexpr uint8_t PIN_LED_G  = 6;
static constexpr uint8_t PIN_LED_B  = 5;
static constexpr uint8_t PIN_SDA    = 8;
static constexpr uint8_t PIN_SCL    = 9;

// ---------- MPU6050 registradores ----------
static constexpr uint8_t MPU_ADDR     = 0x68;
static constexpr uint8_t REG_PWR_MGMT_1   = 0x6B;
static constexpr uint8_t REG_SMPLRT_DIV   = 0x19;
static constexpr uint8_t REG_CONFIG       = 0x1A;
static constexpr uint8_t REG_GYRO_CONFIG  = 0x1B;
static constexpr uint8_t REG_ACCEL_CONFIG = 0x1C;
static constexpr uint8_t REG_ACCEL_XOUT_H = 0x3B;

// ---------- Parâmetros de aquisição ----------
static constexpr uint32_t SAMPLE_PERIOD_US = 2000;  // 500 Hz
static constexpr uint16_t CALIB_SAMPLES    = 1500;  // 3 s a 500 Hz
static constexpr uint16_t BUFFER_SIZE      = 200;

// ---------- Estados ----------
enum State : uint8_t {
  S_IDLE,        // azul
  S_CALIB,       // rosa
  S_READY,       // verde
  S_RECORDING,   // amarelo
  S_SAVE_XFER,   // roxo
  S_FLASH_OK,    // verde curto
  S_FLASH_FAIL   // vermelho curto
};

static State state = S_IDLE;

// ---------- Estrutura de amostra ----------
struct Sample {
  uint32_t t_ms;
  int16_t  ax, ay, az;
  int16_t  gx, gy, gz;
} __attribute__((packed));  // 16 B, alinhamento garantido

// ---------- Buffers ----------
static Sample buf[BUFFER_SIZE];
static volatile uint16_t buf_w = 0;  // índice de escrita

// ---------- Calibração estática ----------
struct CalibData {
  float gx_bias, gy_bias, gz_bias;   // bias do giroscópio em LSB
  float g_T[3];                       // vetor gravidade no frame técnico (em LSB)
  bool  valid;
} calib = {0, 0, 0, {0, 0, 0}, false};

// ---------- Arquivo ----------
static File rec_file;
static const char* REC_PATH = "/last_run.bin";

// ============================================================
// Helpers I2C
// ============================================================
static void mpuWrite(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission(true);
}

static bool mpuReadBurst(int16_t& ax, int16_t& ay, int16_t& az,
                         int16_t& gx, int16_t& gy, int16_t& gz) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(REG_ACCEL_XOUT_H);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(MPU_ADDR, (uint8_t)14, (uint8_t)true) != 14) return false;

  auto rd16 = []() -> int16_t {
    uint8_t hi = Wire.read();
    uint8_t lo = Wire.read();
    return (int16_t)((uint16_t)hi << 8 | lo);
  };
  ax = rd16(); ay = rd16(); az = rd16();
  rd16();  // temp -- descarta
  gx = rd16(); gy = rd16(); gz = rd16();
  return true;
}

// ============================================================
// LED RGB (cátodo comum, HIGH = aceso)
// ============================================================
static void setLed(bool r, bool g, bool b) {
  digitalWrite(PIN_LED_R, r ? HIGH : LOW);
  digitalWrite(PIN_LED_G, g ? HIGH : LOW);
  digitalWrite(PIN_LED_B, b ? HIGH : LOW);
}

static void ledForState(State s) {
  switch (s) {
    case S_IDLE:       setLed(0,0,1); break;   // azul
    case S_CALIB:      setLed(1,0,1); break;   // rosa (R+B)
    case S_READY:      setLed(0,1,0); break;   // verde
    case S_RECORDING:  setLed(1,1,0); break;   // amarelo (R+G)
    case S_SAVE_XFER:  setLed(1,0,1); break;   // roxo -- igual ao rosa em ON/OFF
                                               // (para distinguir: ver TODO PWM)
    case S_FLASH_OK:   setLed(0,1,0); break;
    case S_FLASH_FAIL: setLed(1,0,0); break;
  }
}

// ============================================================
// MPU init com config completa para corrida
// ============================================================
static bool mpuInit() {
  // Acorda o chip
  mpuWrite(REG_PWR_MGMT_1, 0x01);  // clock: PLL com gyro X (melhor que interno)
  delay(50);

  // Sample rate divider: 1kHz / (1+1) = 500 Hz
  mpuWrite(REG_SMPLRT_DIV, 1);

  // DLPF: 44 Hz (acel) / 42 Hz (gyro). Bits FS_SEL não são tocados aqui.
  mpuWrite(REG_CONFIG, 0x03);

  // Gyro range: ±1000 °/s (FS_SEL = 2 -> bits 4:3 = 10 -> 0x10)
  // Para corrida real, subir para ±2000 °/s -> 0x18
  mpuWrite(REG_GYRO_CONFIG, 0x10);

  // Accel range: ±8 g (AFS_SEL = 2 -> bits 4:3 = 10 -> 0x10)
  // Para corrida real, subir para ±16 g -> 0x18
  mpuWrite(REG_ACCEL_CONFIG, 0x10);

  // Sanity check via WHO_AM_I
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x75);
  if (Wire.endTransmission(false) != 0) return false;
  Wire.requestFrom(MPU_ADDR, (uint8_t)1, (uint8_t)true);
  return (Wire.available() && Wire.read() == 0x68);
}

// ============================================================
// Calibração estática (Parte 1 do Falbriard)
// Roda CALIB_SAMPLES amostras com o usuário parado em pé.
// Calcula: bias do giroscópio + vetor gravidade no frame técnico.
// ============================================================
static bool runStaticCalibration() {
  Serial.println(F("CALIB: starting -- keep foot still, standing upright"));
  double sax=0, say=0, saz=0, sgx=0, sgy=0, sgz=0;
  uint16_t got = 0;
  uint32_t t_next = micros();

  while (got < CALIB_SAMPLES) {
    if ((int32_t)(micros() - t_next) >= 0) {
      t_next += SAMPLE_PERIOD_US;
      int16_t ax, ay, az, gx, gy, gz;
      if (mpuReadBurst(ax, ay, az, gx, gy, gz)) {
        sax += ax; say += ay; saz += az;
        sgx += gx; sgy += gy; sgz += gz;
        got++;
      }
    }
  }

  calib.gx_bias = (float)(sgx / CALIB_SAMPLES);
  calib.gy_bias = (float)(sgy / CALIB_SAMPLES);
  calib.gz_bias = (float)(sgz / CALIB_SAMPLES);
  calib.g_T[0]  = (float)(sax / CALIB_SAMPLES);
  calib.g_T[1]  = (float)(say / CALIB_SAMPLES);
  calib.g_T[2]  = (float)(saz / CALIB_SAMPLES);

  // Sanity: ‖g_T‖ deve dar próximo de 4096 LSB (1g em ±8g -> 32768/8 = 4096)
  float gnorm = sqrt(calib.g_T[0]*calib.g_T[0] +
                     calib.g_T[1]*calib.g_T[1] +
                     calib.g_T[2]*calib.g_T[2]);

  Serial.printf("CALIB: gyro_bias = (%.1f, %.1f, %.1f) LSB\n",
                calib.gx_bias, calib.gy_bias, calib.gz_bias);
  Serial.printf("CALIB: g_T       = (%.1f, %.1f, %.1f) LSB, |g|=%.1f\n",
                calib.g_T[0], calib.g_T[1], calib.g_T[2], gnorm);

  // 4096 ± 25% é a janela aceitável (margem para alinhamento imperfeito + ruído)
  if (gnorm < 3000 || gnorm > 5000) {
    Serial.println(F("CALIB: FAIL -- gravity norm out of range. Foot not still or sensor saturated?"));
    calib.valid = false;
    return false;
  }
  calib.valid = true;
  Serial.println(F("CALIB: OK"));
  return true;
}

// ============================================================
// Aquisição: lê uma amostra e guarda no buffer
// ============================================================
static void acquireOne(uint32_t now_ms) {
  int16_t ax, ay, az, gx, gy, gz;
  if (!mpuReadBurst(ax, ay, az, gx, gy, gz)) return;

  buf[buf_w].t_ms = now_ms;
  buf[buf_w].ax = ax; buf[buf_w].ay = ay; buf[buf_w].az = az;
  buf[buf_w].gx = gx; buf[buf_w].gy = gy; buf[buf_w].gz = gz;
  buf_w++;

  // Flush quando meio cheio (para reduzir jitter de I/O)
  if (buf_w >= BUFFER_SIZE / 2) {
    if (rec_file) rec_file.write((const uint8_t*)buf, buf_w * sizeof(Sample));
    buf_w = 0;
  }
}

// ============================================================
// Botão: detecção de transição com debouncing simples
// ============================================================
static bool buttonPressed() {
  static int last_raw = HIGH;
  static uint32_t t_last = 0;
  int raw = digitalRead(PIN_BUTTON);
  uint32_t now = millis();
  if (raw == LOW && last_raw == HIGH && (now - t_last) > 80) {
    t_last = now;
    last_raw = raw;
    return true;
  }
  if (raw == HIGH) last_raw = HIGH;
  return false;
}

// ============================================================
// Início e fim de gravação
// ============================================================
static bool startRecording() {
  if (rec_file) rec_file.close();
  rec_file = LittleFS.open(REC_PATH, "w");
  if (!rec_file) return false;
  // Cabeçalho com calibração (28 bytes)
  rec_file.write((const uint8_t*)&calib, sizeof(calib));
  buf_w = 0;
  return true;
}

static void stopRecording() {
  if (buf_w > 0 && rec_file) {
    rec_file.write((const uint8_t*)buf, buf_w * sizeof(Sample));
    buf_w = 0;
  }
  if (rec_file) {
    rec_file.flush();
    rec_file.close();
  }
}

static bool streamSavedFileSerial(const char* path) {
  File f = LittleFS.open(path, "r");
  if (!f) {
    Serial.println(F("XFER: FAIL -- could not open saved file"));
    return false;
  }

  const size_t file_size = f.size();

  // Protocolo serial:
  // 1) Linhas ASCII até DATA_BEGIN
  // 2) Exatamente SIZE bytes binários
  // 3) Footer ASCII após os bytes binários
  //
  // O script Python deve procurar DATA_BEGIN, ler SIZE bytes, e então ignorar/validar o footer.
  Serial.println();
  Serial.println(F("===BEGIN_LAST_RUN_BIN==="));
  Serial.print(F("PATH:"));
  Serial.println(path);
  Serial.print(F("SIZE:"));
  Serial.println(file_size);
  Serial.println(F("DATA_BEGIN"));
  Serial.flush();

  static uint8_t xfer_buf[64];

  while (f.available()) {
    size_t n = f.read(xfer_buf, sizeof(xfer_buf));
    if (n == 0) break;

    size_t written = Serial.write(xfer_buf, n);
    if (written != n) {
      f.close();
      Serial.println();
      Serial.println(F("===END_LAST_RUN_BIN_FAIL==="));
      Serial.println(F("XFER: FAIL -- Serial.write incomplete"));
      return false;
    }

    // Mantém o watchdog/USB stack respirando em transmissões mais longas.
    delay(1);
  }

  Serial.flush();
  f.close();

  Serial.println();
  Serial.println(F("DATA_END"));
  Serial.println(F("===END_LAST_RUN_BIN==="));
  Serial.println(F("XFER: OK"));
  return true;
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(1500);
  Serial.println(F("\n=== Etapa 10: State Machine ==="));

  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_LED_R, OUTPUT);
  pinMode(PIN_LED_G, OUTPUT);
  pinMode(PIN_LED_B, OUTPUT);
  setLed(0,0,0);

  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(400000);  // I2C fast mode

  if (!mpuInit()) {
    Serial.println(F("FATAL: MPU6050 not responding"));
    while (1) { setLed(1,0,0); delay(200); setLed(0,0,0); delay(200); }
  }

  if (!LittleFS.begin(true)) {
    Serial.println(F("FATAL: LittleFS mount failed"));
    while (1) { setLed(1,0,0); delay(100); setLed(0,0,1); delay(100); }
  }

  state = S_IDLE;
  ledForState(state);
  Serial.println(F("Ready. Press button to calibrate."));
}

// ============================================================
// LOOP — máquina de estados
// ============================================================
void loop() {
  static uint32_t t_next_sample = 0;
  static uint32_t t_state_entered = 0;

  switch (state) {

    case S_IDLE:
      if (buttonPressed()) {
        Serial.println(F("STATE: IDLE -> CALIB"));
        state = S_CALIB;
        ledForState(state);
        t_state_entered = millis();
      }
      break;

    case S_CALIB:
      Serial.println(F("STATE: CALIB running"));
      if (runStaticCalibration()) {
        Serial.println(F("STATE: CALIB -> READY"));
        state = S_READY;
      } else {
        Serial.println(F("STATE: CALIB -> FLASH_FAIL"));
        state = S_FLASH_FAIL;
        t_state_entered = millis();
      }
      ledForState(state);
      break;

    case S_READY:
      if (buttonPressed()) {
        Serial.println(F("STATE: READY -> RECORDING"));
        if (startRecording()) {
          Serial.println(F("REC: file opened"));
          state = S_RECORDING;
          t_next_sample = micros();
        } else {
          Serial.println(F("REC: failed to open file"));
          state = S_FLASH_FAIL;
          t_state_entered = millis();
        }
        ledForState(state);
      }
      break;

    case S_RECORDING: {
      uint32_t now_us = micros();
      if ((int32_t)(now_us - t_next_sample) >= 0) {
        t_next_sample += SAMPLE_PERIOD_US;
        acquireOne(millis());
      }

      if (buttonPressed()) {
        Serial.println(F("STATE: RECORDING -> SAVE_XFER"));
        stopRecording();
        Serial.println(F("REC: file closed, starting serial transfer"));
        state = S_SAVE_XFER;
        ledForState(state);
        t_state_entered = millis();
      }
      break;
    }

    case S_SAVE_XFER: {
      Serial.println(F("STATE: SAVE_XFER running"));
      bool ok = streamSavedFileSerial(REC_PATH);

      Serial.println(ok ? F("STATE: SAVE_XFER -> FLASH_OK") : F("STATE: SAVE_XFER -> FLASH_FAIL"));
      state = ok ? S_FLASH_OK : S_FLASH_FAIL;
      ledForState(state);
      t_state_entered = millis();
      break;
    }

    case S_FLASH_OK:
    case S_FLASH_FAIL:
      if (millis() - t_state_entered > 1000) {
        state = S_IDLE;
        ledForState(state);
      }
      break;
  }
}

/*
 * VALIDAÇÃO BÁSICA:
 *   1. Compile e suba. LED azul ao boot.
 *   2. Botão 1: rosa por ~3s, depois verde. Veja no Serial os bias e g_T.
 *      Coloque o sensor parado e horizontal -- g_T deve ter um eixo
 *      próximo a ±4096 LSB (em ±8g) e os outros próximos de 0.
 *   3. Botão 2: amarelo. Movimente. Botão 3: roxo por 2s, depois verde 1s,
 *      depois azul.
 *   4. Durante SAVE_XFER, o ESP envia /last_run.bin pela Serial.
 *      No PC, capture a porta COM10 com um script Python lendo até DATA_BEGIN,
 *      depois lendo exatamente SIZE bytes binários.
 *
 * NÚMEROS DE REFERÊNCIA QUE VOCÊ DEVE VER (com a placa em uma mesa horizontal,
 * MPU plano com a face de cima virada para cima):
 *   gyro_bias ≈ (-50 ± 20, +30 ± 20, -10 ± 20) LSB (vai variar por unidade)
 *   g_T       ≈ (~0, ~0, +4096) LSB   <- se a Z do MPU estiver para cima
 *
 * Se g_T saturar (algum eixo > 32000), o range do acelerômetro está pequeno
 * demais (config ±8g está em vigor; pode descer para ±16g se for o caso).
 */
