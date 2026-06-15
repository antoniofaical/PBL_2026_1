/*
 * PBL_IMU.ino — Firmware ESP32-C3 Super Mini + MPU6050
 * =====================================================
 *
 * Projeto: PBL 2026 — Grupo 7 — FICSAE / SESI
 * Supervisor: Profa. Dra. Maria Isabel Veras Orselli
 *
 * Função: Coleta de dados inerciais (acelerômetro + giroscópio) a 500 Hz
 *         para estimativa de parâmetros temporais de corrida (método Falbriard)
 *         em atletas paralímpicos T11 e T46/T47.
 *
 * Hardware:
 *   - ESP32-C3 Super Mini
 *   - MPU6050 (I2C: SDA=GPIO6, SCL=GPIO7)
 *   - LED RGB (R=GPIO3, G=GPIO4, B=GPIO5) — anodo comum, lógica invertida
 *   - Botão tátil (GPIO2, INPUT_PULLUP)
 *   - LittleFS (armazenamento interno, ~1MB)
 *   - Li-Po + TP4056 + MT3608 boost 5V
 *
 * Máquina de estados (7 estados, indicados pelo LED):
 *   IDLE        → Vermelho piscando    → aguarda botão para calibrar
 *   CALIB_WAIT  → Amarelo piscando     → posicione o sensor; solte para calibrar
 *   CALIBRATING → Amarelo fixo         → coletando 500 amostras estáticas
 *   READY       → Verde piscando       → aguarda botão para iniciar gravação
 *   RECORDING   → Verde fixo           → gravando em LittleFS
 *   DUMP_WAIT   → Azul piscando        → aguarda botão para transmitir via Serial
 *   DUMPING     → Azul fixo            → transmitindo dados (não interromper)
 *
 * Configuração do MPU6050 (v2 — atualizado 2026-06):
 *   GYRO_CONFIG  = 0x18  → ±2000 °/s (CORRIGIDO de 0x10 = ±1000 °/s)
 *   ACCEL_CONFIG = 0x10  → ±8 g
 *   DLPF         = 0x01  → Banda ~188 Hz (necessário para 500 Hz)
 *   Taxa          500 Hz (SMPLRT_DIV = 1, com DLPF=0x01 → Gyro ODR = 1kHz)
 *
 * Saída Serial (DUMPING):
 *   Cabeçalho:
 *     #GYRO_RANGE 2000
 *     #ACCEL_RANGE 8
 *     #SAMPLE_RATE 500
 *     #CALIB <ax_off> <ay_off> <az_off>
 *     #GYRO_BIAS <gx_bias> <gy_bias> <gz_bias>
 *   Dados (CSV):
 *     sample_num,t_ms,ax,ay,az,gx,gy,gz
 *
 * Atualização v2 (2026-06):
 *   - GYRO_CONFIG corrigido para 0x18 (±2000°/s) — evita saturação em sprints
 *   - Cabeçalho serial inclui #GYRO_RANGE e #ACCEL_RANGE para parse automático
 *   - LittleFS: até ~1.3M amostras @ 500Hz ≈ ~43 min de gravação contínua
 */

#include <Arduino.h>
#include <Wire.h>
#include <LittleFS.h>

// ── Pinos ─────────────────────────────────────────────────────────────────────
#define PIN_SDA   6
#define PIN_SCL   7
#define PIN_LED_R 3    // LED RGB — anodo comum (HIGH = apagado)
#define PIN_LED_G 4
#define PIN_LED_B 5
#define PIN_BTN   2    // INPUT_PULLUP (LOW = pressionado)

// ── MPU6050 ───────────────────────────────────────────────────────────────────
#define MPU_ADDR  0x68

// Registradores
#define REG_SMPLRT_DIV   0x19
#define REG_CONFIG       0x1A   // DLPF
#define REG_GYRO_CONFIG  0x1B
#define REG_ACCEL_CONFIG 0x1C
#define REG_INT_ENABLE   0x38
#define REG_ACCEL_XOUT_H 0x3B
#define REG_PWR_MGMT_1   0x6B

// Configuração de faixas
// v2: GYRO_CONFIG = 0x18 → ±2000°/s | Sens: 16.4 LSB/(°/s)
// v1: GYRO_CONFIG = 0x10 → ±1000°/s | Sens: 32.8 LSB/(°/s)  ← DEPRECIADO
#define GYRO_CONFIG_VALUE   0x18   // ±2000 °/s   *** ATUALIZADO v2 ***
#define ACCEL_CONFIG_VALUE  0x10   // ±8 g
#define GYRO_RANGE_DPS      2000
#define ACCEL_RANGE_G       8

// Taxa de amostragem: 500 Hz
// Com DLPF=0x01 (Gyro ODR=1kHz): SMPLRT_DIV = (1000/500) - 1 = 1
#define SMPLRT_DIV_VALUE    1
#define SAMPLE_RATE_HZ      500

// ── LittleFS ──────────────────────────────────────────────────────────────────
#define DATA_FILE "/imu_data.bin"

// Estrutura de amostra binária (16 bytes por amostra)
struct __attribute__((packed)) ImuSample {
  uint32_t t_ms;   // timestamp em ms desde início da gravação
  int16_t  ax;
  int16_t  ay;
  int16_t  az;
  int16_t  gx;
  int16_t  gy;     // Ωp (pitch angular velocity — Falbriard)
  int16_t  gz;
};

// Calibração estática (calculada na fase CALIBRATING)
struct CalibData {
  float ax_off, ay_off, az_off;
  float gx_bias, gy_bias, gz_bias;
  bool  valid;
};

// ── Estado da máquina ─────────────────────────────────────────────────────────
enum State {
  IDLE,
  CALIB_WAIT,
  CALIBRATING,
  READY,
  RECORDING,
  DUMP_WAIT,
  DUMPING
};

State      gState          = IDLE;
CalibData  gCalib          = {0, 0, 0, 0, 0, 0, false};
uint32_t   gRecordStart    = 0;
uint32_t   gSampleCount    = 0;
uint32_t   gLastSampleTime = 0;
bool       gBtnWasPressed  = false;

// Período de amostragem em µs
#define SAMPLE_PERIOD_US (1000000UL / SAMPLE_RATE_HZ)   // 2000 µs = 500 Hz

// ── Utilitários I2C ───────────────────────────────────────────────────────────

void mpuWrite(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

uint8_t mpuRead8(uint8_t reg) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 1);
  return Wire.read();
}

void mpuReadAll(int16_t& ax, int16_t& ay, int16_t& az,
                int16_t& gx, int16_t& gy, int16_t& gz) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(REG_ACCEL_XOUT_H);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14);

  ax = (Wire.read() << 8) | Wire.read();
  ay = (Wire.read() << 8) | Wire.read();
  az = (Wire.read() << 8) | Wire.read();
  (void)Wire.read(); (void)Wire.read();  // temperatura (ignorada)
  gx = (Wire.read() << 8) | Wire.read();
  gy = (Wire.read() << 8) | Wire.read();
  gz = (Wire.read() << 8) | Wire.read();
}

// ── Inicialização do MPU6050 ──────────────────────────────────────────────────

void mpuInit() {
  // Wake up (sai de sleep)
  mpuWrite(REG_PWR_MGMT_1, 0x00);
  delay(100);

  // Clock source: PLL com giroscópio X (mais estável)
  mpuWrite(REG_PWR_MGMT_1, 0x01);
  delay(10);

  // DLPF = 0x01 → Accel BW ~184Hz / Gyro ODR 1kHz (necessário para 500Hz)
  mpuWrite(REG_CONFIG, 0x01);

  // Taxa de amostragem: SMPLRT_DIV = 1 → 1kHz / (1+1) = 500 Hz
  mpuWrite(REG_SMPLRT_DIV, SMPLRT_DIV_VALUE);

  // Giroscópio: ±2000 °/s (GYRO_CONFIG = 0x18)
  // *** FIX v2: era 0x10 (±1000°/s) → saturava em sprints > ~950°/s ***
  mpuWrite(REG_GYRO_CONFIG, GYRO_CONFIG_VALUE);

  // Acelerômetro: ±8 g (ACCEL_CONFIG = 0x10)
  mpuWrite(REG_ACCEL_CONFIG, ACCEL_CONFIG_VALUE);

  // Desabilitar interrupção (polling simples)
  mpuWrite(REG_INT_ENABLE, 0x00);

  delay(20);
}

// ── Calibração estática ───────────────────────────────────────────────────────

void runCalibration() {
  /*
   * Calibração Parte 1 (Falbriard, seção 2.2):
   *   - Sensor em repouso plano → mede offsets de acelerômetro e bias de giroscópio
   *   - Coleta N_CAL amostras, descarta as primeiras (warm-up)
   *   - az_off é corrigido para compensar a gravidade (alvo: 4096 LSB @ ±8g)
   *
   * Nota: esta calibração só precisa ser repetida se o sensor for
   *       fisicamente deslocado entre sessões.
   */
  const int N_CAL   = 500;
  const int DISCARD = 50;

  long ax_sum=0, ay_sum=0, az_sum=0;
  long gx_sum=0, gy_sum=0, gz_sum=0;
  int count = 0;

  int16_t ax, ay, az, gx, gy, gz;

  for (int i = 0; i < N_CAL + DISCARD; i++) {
    mpuReadAll(ax, ay, az, gx, gy, gz);
    if (i >= DISCARD) {
      ax_sum += ax; ay_sum += ay; az_sum += az;
      gx_sum += gx; gy_sum += gy; gz_sum += gz;
      count++;
    }
    delayMicroseconds(SAMPLE_PERIOD_US);
  }

  gCalib.ax_off   = (float)ax_sum / count;
  gCalib.ay_off   = (float)ay_sum / count;
  // az_off: offset menos a contribuição da gravidade
  // Com ±8g e sensor apontando para cima: az esperado = +4096 LSB
  gCalib.az_off   = (float)az_sum / count - 4096.0f;
  gCalib.gx_bias  = (float)gx_sum / count;
  gCalib.gy_bias  = (float)gy_sum / count;
  gCalib.gz_bias  = (float)gz_sum / count;
  gCalib.valid    = true;
}

// ── Gravação ──────────────────────────────────────────────────────────────────

File gDataFile;

void startRecording() {
  LittleFS.remove(DATA_FILE);
  gDataFile   = LittleFS.open(DATA_FILE, "w");
  gRecordStart = millis();
  gSampleCount = 0;
  gLastSampleTime = micros();
}

void recordSample() {
  uint32_t now = micros();
  if ((now - gLastSampleTime) < SAMPLE_PERIOD_US) return;
  gLastSampleTime = now;

  int16_t ax, ay, az, gx, gy, gz;
  mpuReadAll(ax, ay, az, gx, gy, gz);

  ImuSample s;
  s.t_ms = millis() - gRecordStart;
  s.ax   = ax;  s.ay = ay;  s.az = az;
  s.gx   = gx;  s.gy = gy;  s.gz = gz;

  gDataFile.write((uint8_t*)&s, sizeof(ImuSample));
  gSampleCount++;
}

void stopRecording() {
  gDataFile.close();
}

// ── Transmissão Serial ────────────────────────────────────────────────────────

void dumpData() {
  /*
   * Transmite dados em formato CSV com cabeçalho de metadados.
   * O cabeçalho permite que ler_dados.py detecte automaticamente a sensibilidade.
   */
  File f = LittleFS.open(DATA_FILE, "r");
  if (!f) {
    Serial.println("#ERROR: arquivo não encontrado");
    return;
  }

  // Cabeçalho com configuração de hardware
  Serial.println("#PBL_IMU v2");
  Serial.print("#GYRO_RANGE ");   Serial.println(GYRO_RANGE_DPS);
  Serial.print("#ACCEL_RANGE ");  Serial.println(ACCEL_RANGE_G);
  Serial.print("#SAMPLE_RATE ");  Serial.println(SAMPLE_RATE_HZ);

  if (gCalib.valid) {
    Serial.print("#CALIB ");
    Serial.print(gCalib.ax_off, 2); Serial.print(" ");
    Serial.print(gCalib.ay_off, 2); Serial.print(" ");
    Serial.println(gCalib.az_off, 2);

    Serial.print("#GYRO_BIAS ");
    Serial.print(gCalib.gx_bias, 2); Serial.print(" ");
    Serial.print(gCalib.gy_bias, 2); Serial.print(" ");
    Serial.println(gCalib.gz_bias, 2);
  } else {
    Serial.println("#CALIB 0.00 0.00 0.00");
    Serial.println("#GYRO_BIAS 0.00 0.00 0.00");
  }

  Serial.print("#SAMPLES "); Serial.println(gSampleCount);
  Serial.println("sample_num,t_ms,ax,ay,az,gx,gy,gz");

  ImuSample s;
  uint32_t idx = 0;
  while (f.read((uint8_t*)&s, sizeof(ImuSample)) == sizeof(ImuSample)) {
    Serial.print(idx++); Serial.print(",");
    Serial.print(s.t_ms); Serial.print(",");
    Serial.print(s.ax);   Serial.print(",");
    Serial.print(s.ay);   Serial.print(",");
    Serial.print(s.az);   Serial.print(",");
    Serial.print(s.gx);   Serial.print(",");
    Serial.print(s.gy);   Serial.print(",");
    Serial.println(s.gz);
  }
  f.close();
  Serial.println("#END");
}

// ── LED RGB ───────────────────────────────────────────────────────────────────
// Anodo comum: LOW = LED aceso

void setLed(bool r, bool g, bool b) {
  digitalWrite(PIN_LED_R, r ? LOW : HIGH);
  digitalWrite(PIN_LED_G, g ? LOW : HIGH);
  digitalWrite(PIN_LED_B, b ? LOW : HIGH);
}

void ledOff()    { setLed(false, false, false); }
void ledRed()    { setLed(true,  false, false); }
void ledYellow() { setLed(true,  true,  false); }
void ledGreen()  { setLed(false, true,  false); }
void ledBlue()   { setLed(false, false, true);  }

// ── Botão (debounce simples) ──────────────────────────────────────────────────

bool btnPressed() {
  bool pressed = (digitalRead(PIN_BTN) == LOW);
  if (pressed && !gBtnWasPressed) {
    gBtnWasPressed = true;
    delay(30);  // debounce
    return true;
  }
  if (!pressed) gBtnWasPressed = false;
  return false;
}

// ── Setup ─────────────────────────────────────────────────────────────────────

void setup() {
  Serial.begin(921600);
  delay(500);

  // Pinos
  pinMode(PIN_LED_R, OUTPUT);
  pinMode(PIN_LED_G, OUTPUT);
  pinMode(PIN_LED_B, OUTPUT);
  pinMode(PIN_BTN,   INPUT_PULLUP);
  ledOff();

  // I2C
  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(400000);  // 400kHz Fast Mode

  // MPU6050
  mpuInit();
  Serial.print("MPU6050: GYRO_CONFIG=0x");
  Serial.print(mpuRead8(REG_GYRO_CONFIG), HEX);
  Serial.print("  (esperado 0x");
  Serial.print(GYRO_CONFIG_VALUE, HEX);
  Serial.println(")");

  // LittleFS
  if (!LittleFS.begin(true)) {
    Serial.println("ERRO: LittleFS falhou");
    while (true) { ledRed(); delay(200); ledOff(); delay(200); }
  }

  Serial.println("PBL_IMU v2 pronto — pressione o botão para calibrar");
  gState = IDLE;
}

// ── Loop ──────────────────────────────────────────────────────────────────────

uint32_t gBlinkTimer = 0;
bool     gBlinkOn    = false;
#define  BLINK_MS 400

void updateBlink() {
  if (millis() - gBlinkTimer > BLINK_MS) {
    gBlinkTimer = millis();
    gBlinkOn = !gBlinkOn;
  }
}

void loop() {
  updateBlink();
  bool btn = btnPressed();

  switch (gState) {

    // ── IDLE: vermelho piscando ──────────────────────────────────────────────
    case IDLE:
      if (gBlinkOn) ledRed(); else ledOff();
      if (btn) {
        gState = CALIB_WAIT;
        Serial.println("Estado: CALIB_WAIT — posicione sensor e solte para calibrar");
      }
      break;

    // ── CALIB_WAIT: amarelo piscando ─────────────────────────────────────────
    case CALIB_WAIT:
      if (gBlinkOn) ledYellow(); else ledOff();
      // Transição por borda de soltar (sensor já posicionado)
      if (digitalRead(PIN_BTN) == HIGH && gBtnWasPressed) {
        gState = CALIBRATING;
        ledYellow();  // fixo durante calibração
        Serial.println("Estado: CALIBRATING...");
        runCalibration();
        Serial.println("Calibração concluída.");
        gState = READY;
        Serial.println("Estado: READY — pressione para gravar");
      }
      break;

    // ── CALIBRATING: tratado em CALIB_WAIT por ser síncrono ─────────────────
    case CALIBRATING:
      break;

    // ── READY: verde piscando ─────────────────────────────────────────────────
    case READY:
      if (gBlinkOn) ledGreen(); else ledOff();
      if (btn) {
        gState = RECORDING;
        ledGreen();  // fixo durante gravação
        startRecording();
        Serial.println("Estado: RECORDING — pressione para parar");
      }
      break;

    // ── RECORDING: verde fixo ─────────────────────────────────────────────────
    case RECORDING:
      ledGreen();
      recordSample();
      if (btn) {
        stopRecording();
        gState = DUMP_WAIT;
        Serial.print("Estado: DUMP_WAIT — amostras gravadas: ");
        Serial.println(gSampleCount);
        Serial.println("Pressione para transmitir via Serial");
      }
      break;

    // ── DUMP_WAIT: azul piscando ──────────────────────────────────────────────
    case DUMP_WAIT:
      if (gBlinkOn) ledBlue(); else ledOff();
      if (btn) {
        gState = DUMPING;
        ledBlue();  // fixo durante transmissão
        Serial.println("Estado: DUMPING — não interrompa a transmissão");
        dumpData();
        gState = READY;
        Serial.println("Transmissão concluída. Estado: READY");
      }
      break;

    // ── DUMPING: tratado em DUMP_WAIT por ser síncrono ───────────────────────
    case DUMPING:
      break;
  }
}
