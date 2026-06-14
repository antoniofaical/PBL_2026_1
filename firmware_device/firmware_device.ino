/**
 * ============================================================================
 * Kinexa firmware — ESP32-C3 + MPU6050 + BLE (app Android)
 * Placa: ESP32-C3 Super Mini (Arduino-ESP32 core, "ESP32C3 Dev Module")
 *
 * Dependência: biblioteca "NimBLE-Arduino" (h2zero) no Gerenciador de Bibliotecas.
 *
 * Máquina de estados (controle principal via BLE; botão = emergência):
 *
 *   BOOT -> S_NEEDS_CALIBRATION
 *        -> [app: CALIBRATE] -> S_CALIBRATING -> S_READY
 *        -> [app: START]      -> S_RECORDING
 *        -> [app: STOP]       -> S_TRANSFER -> S_READY
 *
 * Calibração é on demand: no boot o atleta pode não estar parado/posicionado.
 * Metadados, eventos e upload HTTP são responsabilidade do app Android.
 *
 * Pinagem (hardware real):
 *   GPIO 0 -> botão (INPUT_PULLUP, LOW = pressionado) — apenas emergência
 *   GPIO 7 -> LED R   (PWM, cátodo comum no GND)
 *   GPIO 6 -> LED G
 *   GPIO 5 -> LED B
 *   GPIO 8 -> I2C SDA (MPU6050 @ 0x68)
 *   GPIO 9 -> I2C SCL
 *
 * GATT:
 *   Serviço  4fafc201-1fb5-459e-8fcc-c5c9c331914b
 *   Status   beb5483e-36e1-4688-b7f5-ea07361b26a8  (READ + NOTIFY) — linhas ASCII
 *   Data     0000ff02-0000-1000-8000-00805f9b34fb  (NOTIFY) — payload binário
 *   Control  0000ff03-0000-1000-8000-00805f9b34fb  (WRITE) — ACK 0x01 ou comandos ASCII
 *
 * Comandos BLE (Control characteristic, ASCII):
 *   STATUS | PING | CALIBRATE | START | STOP | ABORT
 *
 * ACK de transferência: byte único 0x01 (não confundir com comandos ASCII).
 *
 * Protocolo de transferência binária (Status + Data):
 *   XFER:START / ===BEGIN_LAST_RUN_BIN=== / PATH / SIZE / DATA_BEGIN
 *   <bytes binários em chunks na characteristic Data>
 *   DATA_END / ===END_LAST_RUN_BIN=== / XFER: OK
 * ============================================================================
 */

#include <Arduino.h>
#include <Wire.h>
#include <LittleFS.h>
#include <cstdarg>
#include <cstring>
#include <NimBLEDevice.h>

// ---------------------------------------------------------------------------
// Identidade do device
// ---------------------------------------------------------------------------
static constexpr char DEVICE_ID[]  = "KINEXA_01";
static constexpr char FW_VERSION[] = "1.0.4";

// ---------------------------------------------------------------------------
// Pinos
// ---------------------------------------------------------------------------
static constexpr uint8_t PIN_BUTTON = 0;
static constexpr uint8_t PIN_LED_R  = 7;
static constexpr uint8_t PIN_LED_G  = 6;
static constexpr uint8_t PIN_LED_B  = 5;
static constexpr uint8_t PIN_SDA    = 8;
static constexpr uint8_t PIN_SCL    = 9;

// Botão de emergência (não controla fluxo normal)
static constexpr uint32_t BTN_EMERGENCY_MS     = 3000;
static constexpr uint32_t BTN_FORCE_RECALIB_MS = 8000;

// ---------------------------------------------------------------------------
// MPU6050
// ---------------------------------------------------------------------------
static constexpr uint8_t MPU_ADDR           = 0x68;
static constexpr uint8_t REG_PWR_MGMT_1     = 0x6B;
static constexpr uint8_t REG_SMPLRT_DIV     = 0x19;
static constexpr uint8_t REG_CONFIG         = 0x1A;
static constexpr uint8_t REG_GYRO_CONFIG    = 0x1B;
static constexpr uint8_t REG_ACCEL_CONFIG   = 0x1C;
static constexpr uint8_t REG_ACCEL_XOUT_H   = 0x3B;

// ---------------------------------------------------------------------------
// Aquisição
// ---------------------------------------------------------------------------
static constexpr uint32_t SAMPLE_PERIOD_US = 2000;   // 500 Hz
static constexpr uint16_t CALIB_SAMPLES   = 1500;   // ~3 s
static constexpr uint16_t BUFFER_SIZE     = 200;

// ---------------------------------------------------------------------------
// BLE UUIDs
// ---------------------------------------------------------------------------
static constexpr char SERVICE_UUID[]      = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
static constexpr char CHAR_STATUS_UUID[]  = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
static constexpr char CHAR_DATA_UUID[]    = "0000ff02-0000-1000-8000-00805f9b34fb";
static constexpr char CHAR_CONTROL_UUID[] = "0000ff03-0000-1000-8000-00805f9b34fb";

static constexpr size_t XFER_CHUNK_SIZE = 244;
static constexpr size_t XFER_BYTES_PER_ACK = XFER_CHUNK_SIZE * 4;
static constexpr uint32_t XFER_ACK_TIMEOUT_MS = 20000;
static constexpr uint32_t XFER_POST_DRAIN_MS = 400;
static constexpr uint32_t XFER_INTER_CHUNK_DELAY_MS = 3;
static constexpr uint32_t XFER_HDR_LINE_DELAY_MS = 30;
static constexpr uint32_t XFER_PRE_PAYLOAD_DELAY_MS = 80;

// ---------------------------------------------------------------------------
// Estados da FSM
// ---------------------------------------------------------------------------
enum State : uint8_t {
  S_NEEDS_CALIBRATION,
  S_CALIBRATING,
  S_READY,
  S_RECORDING,
  S_TRANSFER,
  S_ERROR,
};

enum XferPhase : uint8_t {
  XFER_OPEN_FILE,
  XFER_HDR_START,
  XFER_HDR_BEGIN,
  XFER_HDR_PATH,
  XFER_HDR_SIZE,
  XFER_HDR_DATA_BEGIN,
  XFER_SEND_PAYLOAD,
  XFER_POST_DRAIN,
  XFER_FTR_DATA_END,
  XFER_FTR_END_MARKER,
  XFER_FTR_OK,
  XFER_FINISH,
  XFER_WAIT,
};

// ---------------------------------------------------------------------------
// Tipos de dados
// ---------------------------------------------------------------------------
struct Sample {
  uint32_t t_ms;
  int16_t ax, ay, az;
  int16_t gx, gy, gz;
} __attribute__((packed));

struct CalibData {
  float gx_bias, gy_bias, gz_bias;
  float g_T[3];
  bool valid;
} calib = {0, 0, 0, {0, 0, 0}, false};

struct Rgb {
  uint8_t r, g, b;
};

struct CalibAccum {
  double sax = 0, say = 0, saz = 0;
  double sgx = 0, sgy = 0, sgz = 0;
  uint16_t got = 0;
  uint32_t t_next_us = 0;
};

// ---------------------------------------------------------------------------
// Estado global
// ---------------------------------------------------------------------------
static State state = S_NEEDS_CALIBRATION;

static Sample buf[BUFFER_SIZE];
static volatile uint16_t buf_w = 0;

static File rec_file;
static const char* REC_PATH = "/last_run.bin";

static uint32_t t_next_sample_us = 0;

// BLE
static NimBLEServer* bleServer = nullptr;
static NimBLECharacteristic* bleCharStatus = nullptr;
static NimBLECharacteristic* bleCharData = nullptr;
static NimBLECharacteristic* bleCharControl = nullptr;
static volatile bool bleConnected = false;
static volatile bool bleStatusSubscribed = false;
static volatile bool bleDataSubscribed = false;
static volatile bool bleAbortXfer = false;
static volatile bool bleXferAck = false;

static CalibAccum calibAccum;

static XferPhase xferPhase = XFER_OPEN_FILE;
static File xferFile;
static size_t xferTotalBytes = 0;
static size_t xferSentBytes = 0;
static uint8_t xferChunk[XFER_CHUNK_SIZE];
static bool xferAwaitingAck = false;
static uint32_t xferAckDeadlineMs = 0;
static uint32_t xferPostDrainUntilMs = 0;
static uint32_t xferWaitUntilMs = 0;
static XferPhase xferAfterWaitPhase = XFER_HDR_BEGIN;

// LED PWM + blink
static constexpr uint32_t LEDC_FREQ_HZ = 5000;
static constexpr uint8_t LEDC_RES_BITS = 8;
static uint32_t ledBlinkLastMs = 0;
static bool ledBlinkOn = false;

// ---------------------------------------------------------------------------
// Protótipos
// ---------------------------------------------------------------------------
static void logSerial(const char* msg);
static void logSerialf(const char* fmt, ...);

static void ledInit();
static void ledSetColor(const Rgb& c);
static Rgb ledBlinkOnColor(State s);
static void ledArmBlink(State s);
static void ledApplySolid(State s);
static void ledTick();

static void mpuWrite(uint8_t reg, uint8_t val);
static bool mpuReadBurst(int16_t& ax, int16_t& ay, int16_t& az,
                         int16_t& gx, int16_t& gy, int16_t& gz);
static bool mpuInit();
static bool mpuInitWithRetry(uint8_t attempts = 5);

static void bleInit();
static bool bleNotifyStatus(const char* msg);
static bool bleNotifyData(const uint8_t* data, size_t len);
static bool bleIsReadyForXfer();

static const char* stateTag(State s);
static void notifyStatus(const char* msg);
static void sendStatusResponse();
static void handleBleCommand(const char* raw);
static void normalizeCommand(char* cmd, size_t cap);

static void calibReset();
static bool calibTick();
static void calibFinalize();
static void startCalibration();

static void acquireOne(uint32_t now_ms);
static void buttonTick();
static bool startRecording();
static void stopRecording();
static void startRecordingCmd();
static void stopRecordingCmd();
static void handleAbort();
static void forceRecalibration();

static void xferReset();
static void xferFail();
static void xferTick();
static bool xferOpenFile();
static bool xferSendPayloadChunk();
static void startTransfer();

static void setState(State next);
static void onStateEnter(State entered, State previous);

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------
static void logSerial(const char* msg) {
  Serial.println(msg);
}

static void logSerialf(const char* fmt, ...) {
  char line[160];
  va_list args;
  va_start(args, fmt);
  vsnprintf(line, sizeof(line), fmt, args);
  va_end(args);
  Serial.println(line);
}

// ---------------------------------------------------------------------------
// LED RGB — PWM + pisca por estado
// ---------------------------------------------------------------------------
static const Rgb LED_OFF       = {0, 0, 0};
static const Rgb LED_BLUE      = {0, 0, 255};
static const Rgb LED_YELLOW    = {255, 255, 0};
static const Rgb LED_GREEN     = {0, 255, 0};
static const Rgb LED_RED       = {255, 0, 0};

static void ledInit() {
  ledcAttach(PIN_LED_R, LEDC_FREQ_HZ, LEDC_RES_BITS);
  ledcAttach(PIN_LED_G, LEDC_FREQ_HZ, LEDC_RES_BITS);
  ledcAttach(PIN_LED_B, LEDC_FREQ_HZ, LEDC_RES_BITS);
  ledSetColor(LED_OFF);
}

static void ledSetColor(const Rgb& c) {
  ledcWrite(PIN_LED_R, c.r);
  ledcWrite(PIN_LED_G, c.g);
  ledcWrite(PIN_LED_B, c.b);
}

static Rgb ledBlinkOnColor(State s) {
  switch (s) {
    case S_NEEDS_CALIBRATION:
    case S_CALIBRATING:
    case S_TRANSFER:
      return LED_BLUE;
    case S_ERROR:
      return LED_RED;
    default:
      return LED_OFF;
  }
}

static void ledArmBlink(State s) {
  ledBlinkLastMs = millis();
  ledBlinkOn = true;
  ledSetColor(ledBlinkOnColor(s));
}

static void ledApplySolid(State s) {
  switch (s) {
    case S_READY:      ledSetColor(LED_GREEN); break;
    case S_RECORDING:  ledSetColor(LED_YELLOW); break;
    default:           break;
  }
}

static void ledTick() {
  const uint32_t now = millis();
  uint32_t period = 0;

  switch (state) {
    case S_NEEDS_CALIBRATION:
      period = 800;
      break;
    case S_CALIBRATING:
      period = 200;
      break;
    case S_TRANSFER:
      period = 400;
      break;
    case S_ERROR:
      period = 300;
      break;
    case S_READY:
    case S_RECORDING:
      ledApplySolid(state);
      return;
    default:
      return;
  }

  if (now - ledBlinkLastMs >= period) {
    ledBlinkLastMs = now;
    ledBlinkOn = !ledBlinkOn;
    ledSetColor(ledBlinkOn ? ledBlinkOnColor(state) : LED_OFF);
  }
}

// ---------------------------------------------------------------------------
// MPU6050
// ---------------------------------------------------------------------------
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

  ax = rd16();
  ay = rd16();
  az = rd16();
  rd16();
  gx = rd16();
  gy = rd16();
  gz = rd16();
  return true;
}

static bool mpuInit() {
  mpuWrite(REG_PWR_MGMT_1, 0x01);
  delay(50);

  mpuWrite(REG_SMPLRT_DIV, 1);
  mpuWrite(REG_CONFIG, 0x03);
  mpuWrite(REG_GYRO_CONFIG, 0x10);
  mpuWrite(REG_ACCEL_CONFIG, 0x10);

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x75);
  if (Wire.endTransmission(false) != 0) return false;
  Wire.requestFrom(MPU_ADDR, (uint8_t)1, (uint8_t)true);
  return Wire.available() && Wire.read() == 0x68;
}

static bool mpuInitWithRetry(uint8_t attempts) {
  for (uint8_t i = 0; i < attempts; i++) {
    if (mpuInit()) return true;
    logSerialf("MPU: init retry %u/%u", (unsigned)(i + 1), (unsigned)attempts);
    delay(100);
  }
  return false;
}

// ---------------------------------------------------------------------------
// BLE — callbacks
// ---------------------------------------------------------------------------
class BleServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& connInfo) override {
    (void)server;
    (void)connInfo;
    bleConnected = true;
    bleAbortXfer = false;
    logSerial("BLE: connected");
    notifyStatus(stateTag(state));
  }

  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo, int reason) override {
    (void)connInfo;
    (void)reason;
    bleConnected = false;
    bleStatusSubscribed = false;
    bleDataSubscribed = false;
    logSerial("BLE: disconnected");

    if (state == S_TRANSFER) {
      bleAbortXfer = true;
    }

    NimBLEDevice::startAdvertising();
    server->startAdvertising();
  }
};

class BleControlCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo& connInfo) override {
    (void)connInfo;
    const std::string& value = chr->getValue();

    // ACK binário da transferência (1 byte 0x01)
    if (value.size() == 1 && (uint8_t)value[0] == 0x01) {
      bleXferAck = true;
      return;
    }

    if (value.empty()) return;

    char cmd[48];
    const size_t n = value.size() < sizeof(cmd) - 1 ? value.size() : sizeof(cmd) - 1;
    memcpy(cmd, value.data(), n);
    cmd[n] = '\0';
    handleBleCommand(cmd);
  }
};

class BleCharCallbacks : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic* chr, NimBLEConnInfo& connInfo, uint16_t subValue) override {
    (void)connInfo;
    const bool subscribed = subValue > 0;
    if (chr == bleCharStatus) {
      bleStatusSubscribed = subscribed;
      logSerial(subscribed ? "BLE: status subscribed" : "BLE: status unsubscribed");
    } else if (chr == bleCharData) {
      bleDataSubscribed = subscribed;
      logSerial(subscribed ? "BLE: data subscribed" : "BLE: data unsubscribed");
    }
  }
};

static BleServerCallbacks bleServerCb;
static BleCharCallbacks bleCharCb;
static BleControlCallbacks bleControlCb;

static bool bleNotifyStatus(const char* msg) {
  if (!bleConnected || bleCharStatus == nullptr) return false;
  const size_t len = strlen(msg);
  bleCharStatus->setValue((uint8_t*)msg, len);
  return bleCharStatus->notify();
}

static bool bleNotifyData(const uint8_t* data, size_t len) {
  if (!bleConnected || bleCharData == nullptr || len == 0) return false;
  bleCharData->setValue(const_cast<uint8_t*>(data), len);
  return bleCharData->notify();
}

static bool bleIsReadyForXfer() {
  return bleConnected && bleStatusSubscribed && bleDataSubscribed;
}

static void bleInit() {
  NimBLEDevice::init(DEVICE_ID);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  bleServer = NimBLEDevice::createServer();
  bleServer->setCallbacks(&bleServerCb);

  NimBLEService* service = bleServer->createService(SERVICE_UUID);

  bleCharStatus = service->createCharacteristic(
      CHAR_STATUS_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  bleCharStatus->setCallbacks(&bleCharCb);
  bleCharStatus->setValue("boot");

  bleCharData = service->createCharacteristic(
      CHAR_DATA_UUID,
      NIMBLE_PROPERTY::NOTIFY);
  bleCharData->setCallbacks(&bleCharCb);

  bleCharControl = service->createCharacteristic(
      CHAR_CONTROL_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  bleCharControl->setCallbacks(&bleControlCb);

  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->setName(DEVICE_ID);
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->enableScanResponse(true);
  advertising->start();

  logSerialf("BLE: advertising as %s", DEVICE_ID);
}

// ---------------------------------------------------------------------------
// Protocolo BLE — comandos e status
// ---------------------------------------------------------------------------
static const char* stateTag(State s) {
  switch (s) {
    case S_NEEDS_CALIBRATION: return "STATE:NEEDS_CALIBRATION";
    case S_CALIBRATING:       return "STATE:CALIBRATING";
    case S_READY:             return "STATE:READY";
    case S_RECORDING:         return "STATE:RECORDING";
    case S_TRANSFER:          return "STATE:TRANSFER";
    case S_ERROR:             return "STATE:ERROR";
    default:                  return "STATE:UNKNOWN";
  }
}

static void notifyStatus(const char* msg) {
  logSerialf("NOTIFY: %s", msg);
  bleNotifyStatus(msg);
}

static void sendStatusResponse() {
  notifyStatus(stateTag(state));

  char line[40];
  snprintf(line, sizeof(line), "FW:%s", FW_VERSION);
  notifyStatus(line);

  snprintf(line, sizeof(line), "DEVICE:%s", DEVICE_ID);
  notifyStatus(line);

  notifyStatus(calib.valid ? "CALIB:OK" : "CALIB:INVALID");
}

static void normalizeCommand(char* cmd, size_t cap) {
  if (cap == 0) return;

  size_t start = 0;
  while (cmd[start] && (cmd[start] == ' ' || cmd[start] == '\t' ||
                         cmd[start] == '\r' || cmd[start] == '\n')) {
    start++;
  }

  size_t i = 0;
  for (size_t j = start; cmd[j] && i < cap - 1; j++) {
    char c = cmd[j];
    if (c == '\r' || c == '\n') break;
    if (c >= 'a' && c <= 'z') c = (char)(c - 'a' + 'A');
    cmd[i++] = c;
  }
  cmd[i] = '\0';

  while (i > 0 && (cmd[i - 1] == ' ' || cmd[i - 1] == '\t')) {
    cmd[--i] = '\0';
  }
}

static void handleBleCommand(const char* raw) {
  char cmd[48];
  strncpy(cmd, raw, sizeof(cmd) - 1);
  cmd[sizeof(cmd) - 1] = '\0';
  normalizeCommand(cmd, sizeof(cmd));

  if (cmd[0] == '\0') return;

  logSerialf("BLE CMD: %s", cmd);

  if (strcmp(cmd, "STATUS") == 0) {
    sendStatusResponse();
    return;
  }

  if (strcmp(cmd, "PING") == 0) {
    notifyStatus("PONG");
    return;
  }

  if (strcmp(cmd, "CALIBRATE") == 0) {
    startCalibration();
    return;
  }

  if (strcmp(cmd, "START") == 0) {
    startRecordingCmd();
    return;
  }

  if (strcmp(cmd, "STOP") == 0) {
    stopRecordingCmd();
    return;
  }

  if (strcmp(cmd, "XFER") == 0) {
    if (state == S_TRANSFER) {
      notifyStatus("XFER:ALREADY");
      return;
    }
    if (state != S_READY) {
      notifyStatus("ERROR:INVALID_STATE");
      return;
    }
    if (!LittleFS.exists(REC_PATH)) {
      notifyStatus("ERROR:NO_FILE");
      return;
    }
    xferReset();
    startTransfer();
    return;
  }

  if (strcmp(cmd, "ABORT") == 0) {
    handleAbort();
    return;
  }

  notifyStatus("ERROR:UNKNOWN_COMMAND");
}

// ---------------------------------------------------------------------------
// Calibração estática — não bloqueante, on demand via app
// ---------------------------------------------------------------------------
static void calibReset() {
  calibAccum = CalibAccum{};
  calibAccum.t_next_us = micros();
}

static bool calibTick() {
  if (calibAccum.got >= CALIB_SAMPLES) return true;

  const int32_t dt = (int32_t)(micros() - calibAccum.t_next_us);
  if (dt < 0) return false;

  calibAccum.t_next_us += SAMPLE_PERIOD_US;

  int16_t ax, ay, az, gx, gy, gz;
  if (!mpuReadBurst(ax, ay, az, gx, gy, gz)) return false;

  calibAccum.sax += ax;
  calibAccum.say += ay;
  calibAccum.saz += az;
  calibAccum.sgx += gx;
  calibAccum.sgy += gy;
  calibAccum.sgz += gz;
  calibAccum.got++;
  return calibAccum.got >= CALIB_SAMPLES;
}

static void calibFinalize() {
  const float n = (float)CALIB_SAMPLES;
  calib.gx_bias = (float)(calibAccum.sgx / n);
  calib.gy_bias = (float)(calibAccum.sgy / n);
  calib.gz_bias = (float)(calibAccum.sgz / n);
  calib.g_T[0] = (float)(calibAccum.sax / n);
  calib.g_T[1] = (float)(calibAccum.say / n);
  calib.g_T[2] = (float)(calibAccum.saz / n);

  const float gnorm = sqrtf(
      calib.g_T[0] * calib.g_T[0] +
      calib.g_T[1] * calib.g_T[1] +
      calib.g_T[2] * calib.g_T[2]);

  logSerialf("CALIB: gyro_bias = (%.1f, %.1f, %.1f)", calib.gx_bias, calib.gy_bias, calib.gz_bias);
  logSerialf("CALIB: |g_T| = %.1f LSB", gnorm);

  if (gnorm < 3000.0f || gnorm > 5000.0f) {
    calib.valid = false;
    logSerial("CALIB: FAIL — gravity norm out of range");
    return;
  }

  calib.valid = true;
  logSerial("CALIB: OK");
}

static void startCalibration() {
  if (state == S_RECORDING || state == S_TRANSFER) {
    notifyStatus("ERROR:INVALID_STATE");
    return;
  }

  calib.valid = false;
  logSerial("CALIB: start requested by app");
  setState(S_CALIBRATING);
}

// ---------------------------------------------------------------------------
// Gravação
// ---------------------------------------------------------------------------
static void acquireOne(uint32_t now_ms) {
  int16_t ax, ay, az, gx, gy, gz;
  if (!mpuReadBurst(ax, ay, az, gx, gy, gz)) return;

  buf[buf_w].t_ms = now_ms;
  buf[buf_w].ax = ax;
  buf[buf_w].ay = ay;
  buf[buf_w].az = az;
  buf[buf_w].gx = gx;
  buf[buf_w].gy = gy;
  buf[buf_w].gz = gz;
  buf_w++;

  if (buf_w >= BUFFER_SIZE / 2) {
    if (rec_file) {
      rec_file.write((const uint8_t*)buf, buf_w * sizeof(Sample));
    }
    buf_w = 0;
    delay(0);
  }
}

static bool startRecording() {
  if (rec_file) rec_file.close();
  rec_file = LittleFS.open(REC_PATH, "w");
  if (!rec_file) return false;
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
  logSerial("REC: file closed");
}

static void startRecordingCmd() {
  if (state != S_READY) {
    notifyStatus("ERROR:INVALID_STATE");
    return;
  }
  if (!calib.valid) {
    notifyStatus("ERROR:NOT_CALIBRATED");
    return;
  }
  if (!bleConnected) {
    notifyStatus("ERROR:NO_BLE");
    return;
  }

  if (startRecording()) {
    t_next_sample_us = micros();
    logSerial("REC: started");
    notifyStatus("REC:STARTED");
    setState(S_RECORDING);
  } else {
    logSerial("REC: failed to open file");
    notifyStatus("ERROR:FILE_OPEN");
    setState(S_ERROR);
  }
}

static void stopRecordingCmd() {
  if (state != S_RECORDING) {
    notifyStatus("ERROR:NOT_RECORDING");
    return;
  }

  stopRecording();
  logSerial("REC: stopped by app");
  notifyStatus("REC:STOPPED");
  startTransfer();
}

static void handleAbort() {
  if (state == S_RECORDING) {
    stopRecording();
    logSerial("REC: aborted");
    notifyStatus("REC:ABORTED");
    if (calib.valid) {
      setState(S_READY);
    } else {
      setState(S_NEEDS_CALIBRATION);
    }
    return;
  }

  if (state == S_TRANSFER) {
    bleAbortXfer = true;
    xferReset();
    logSerial("XFER: aborted by app");
    notifyStatus("XFER:ABORTED");
    if (calib.valid) {
      setState(S_READY);
    } else {
      setState(S_NEEDS_CALIBRATION);
    }
    return;
  }

  sendStatusResponse();
}

static void forceRecalibration() {
  logSerial("BUTTON: force recalibration");

  if (state == S_RECORDING) {
    stopRecording();
    notifyStatus("REC:ABORTED");
  } else if (state == S_TRANSFER) {
    bleAbortXfer = true;
    xferReset();
    notifyStatus("XFER:ABORTED");
  }

  calib.valid = false;
  notifyStatus("BUTTON:FORCE_RECALIBRATION");
  setState(S_NEEDS_CALIBRATION);
}

// ---------------------------------------------------------------------------
// Botão físico — apenas emergência
// ---------------------------------------------------------------------------
static void buttonTick() {
  static bool was_pressed = false;
  static uint32_t press_start_ms = 0;
  static bool fired_emergency = false;
  static bool fired_force_recal = false;

  const bool pressed = digitalRead(PIN_BUTTON) == LOW;
  const uint32_t now = millis();

  if (pressed && !was_pressed) {
    press_start_ms = now;
    fired_emergency = false;
    fired_force_recal = false;
  }

  if (pressed) {
    const uint32_t held = now - press_start_ms;

    if (!fired_emergency && held >= BTN_EMERGENCY_MS && state == S_RECORDING) {
      fired_emergency = true;
      logSerial("BUTTON: emergency stop");
      notifyStatus("BUTTON:EMERGENCY_STOP");
      stopRecording();
      notifyStatus("REC:ABORTED");
      if (calib.valid) {
        setState(S_READY);
      } else {
        setState(S_NEEDS_CALIBRATION);
      }
    }

    if (!fired_force_recal && held >= BTN_FORCE_RECALIB_MS) {
      fired_force_recal = true;
      forceRecalibration();
    }
  } else if (was_pressed) {
    // Pressão curta: não altera estado (apenas log opcional)
    const uint32_t held = now - press_start_ms;
    if (held < BTN_EMERGENCY_MS) {
      logSerialf("BUTTON: short press ignored (%u ms)", (unsigned)held);
    }
  }

  was_pressed = pressed;
}

// ---------------------------------------------------------------------------
// Transferência BLE — não bloqueante
// ---------------------------------------------------------------------------
static void xferReset() {
  if (xferFile) xferFile.close();
  xferPhase = XFER_OPEN_FILE;
  xferTotalBytes = 0;
  xferSentBytes = 0;
  xferAwaitingAck = false;
  xferAckDeadlineMs = 0;
  xferPostDrainUntilMs = 0;
  bleXferAck = false;
  bleAbortXfer = false;
}

static int xferAckState() {
  if (!xferAwaitingAck) return 1;
  if (bleXferAck) {
    bleXferAck = false;
    xferAwaitingAck = false;
    return 1;
  }
  if (millis() > xferAckDeadlineMs) return -1;
  return 0;
}

static bool xferSendBurstAndWaitAck() {
  size_t sent = 0;
  while (xferSentBytes < xferTotalBytes && sent < XFER_BYTES_PER_ACK) {
    const size_t before = xferSentBytes;
    if (!xferSendPayloadChunk()) return false;
    sent += (xferSentBytes - before);
    if (xferSentBytes < xferTotalBytes) {
      delay(XFER_INTER_CHUNK_DELAY_MS);
    }
  }
  if (sent == 0 && xferSentBytes >= xferTotalBytes) {
    return true;
  }
  xferAwaitingAck = true;
  xferAckDeadlineMs = millis() + XFER_ACK_TIMEOUT_MS;
  return true;
}

static void xferFail() {
  if (xferFile) xferFile.close();
  logSerial("XFER: FAIL");
  notifyStatus("XFER:FAIL");
  if (calib.valid) {
    setState(S_READY);
  } else {
    setState(S_ERROR);
  }
}

static bool xferOpenFile() {
  xferFile = LittleFS.open(REC_PATH, "r");
  if (!xferFile) {
    logSerial("XFER: FAIL — cannot open file");
    return false;
  }
  xferTotalBytes = xferFile.size();
  xferSentBytes = 0;
  logSerialf("XFER: file size %u bytes", (unsigned)xferTotalBytes);
  return true;
}

static bool xferSendPayloadChunk() {
  if (!xferFile || xferSentBytes >= xferTotalBytes) return true;

  const size_t remaining = xferTotalBytes - xferSentBytes;
  const size_t to_read = remaining < XFER_CHUNK_SIZE ? remaining : XFER_CHUNK_SIZE;
  const size_t n = xferFile.read(xferChunk, to_read);
  if (n == 0) return false;

  if (!bleNotifyData(xferChunk, n)) return false;

  xferSentBytes += n;
  return true;
}

static void startTransfer() {
  logSerial("XFER: starting");
  setState(S_TRANSFER);
}

static void xferScheduleWait(uint32_t ms, XferPhase next) {
  xferWaitUntilMs = millis() + ms;
  xferAfterWaitPhase = next;
  xferPhase = XFER_WAIT;
}

static void xferTick() {
  if (bleAbortXfer || !bleConnected) {
    logSerial("XFER: aborted — BLE disconnected or ABORT");
    xferFail();
    return;
  }

  switch (xferPhase) {

    case XFER_OPEN_FILE:
      if (!bleIsReadyForXfer()) return;
      if (!xferOpenFile()) {
        xferFail();
        return;
      }
      xferPhase = XFER_HDR_START;
      break;

    case XFER_WAIT:
      if (millis() < xferWaitUntilMs) return;
      xferPhase = xferAfterWaitPhase;
      break;

    case XFER_HDR_START:
      if (!bleNotifyStatus("XFER:START")) return;
      xferScheduleWait(XFER_HDR_LINE_DELAY_MS, XFER_HDR_BEGIN);
      break;

    case XFER_HDR_BEGIN:
      if (!bleNotifyStatus("===BEGIN_LAST_RUN_BIN===")) return;
      xferScheduleWait(XFER_HDR_LINE_DELAY_MS, XFER_HDR_PATH);
      break;

    case XFER_HDR_PATH: {
      char line[48];
      snprintf(line, sizeof(line), "PATH:%s", REC_PATH);
      if (!bleNotifyStatus(line)) return;
      xferScheduleWait(XFER_HDR_LINE_DELAY_MS, XFER_HDR_SIZE);
      break;
    }

    case XFER_HDR_SIZE: {
      char line[32];
      snprintf(line, sizeof(line), "SIZE:%u", (unsigned)xferTotalBytes);
      if (!bleNotifyStatus(line)) return;
      xferScheduleWait(XFER_HDR_LINE_DELAY_MS, XFER_HDR_DATA_BEGIN);
      break;
    }

    case XFER_HDR_DATA_BEGIN:
      if (!bleNotifyStatus("DATA_BEGIN")) return;
      bleXferAck = false;
      xferAwaitingAck = false;
      xferScheduleWait(XFER_PRE_PAYLOAD_DELAY_MS, XFER_SEND_PAYLOAD);
      break;

    case XFER_SEND_PAYLOAD: {
      const int ack = xferAckState();
      if (ack == 0) return;
      if (ack < 0) {
        logSerial("XFER: FAIL — ACK timeout");
        xferFail();
        return;
      }
      if (xferSentBytes >= xferTotalBytes) {
        xferPhase = XFER_POST_DRAIN;
        xferPostDrainUntilMs = millis() + XFER_POST_DRAIN_MS;
        break;
      }
      if (!xferSendBurstAndWaitAck()) {
        xferFail();
        return;
      }
      break;
    }

    case XFER_POST_DRAIN: {
      const int ack = xferAckState();
      if (ack == 0) return;
      if (ack < 0) {
        logSerial("XFER: FAIL — ACK timeout (drain)");
        xferFail();
        return;
      }
      if (millis() < xferPostDrainUntilMs) return;
      xferPhase = XFER_FTR_DATA_END;
      break;
    }

    case XFER_FTR_DATA_END:
      if (xferFile) {
        xferFile.close();
      }
      if (!bleNotifyStatus("DATA_END")) return;
      xferPhase = XFER_FTR_END_MARKER;
      break;

    case XFER_FTR_END_MARKER:
      if (!bleNotifyStatus("===END_LAST_RUN_BIN===")) return;
      xferPhase = XFER_FTR_OK;
      break;

    case XFER_FTR_OK:
      // Mantém "XFER: OK" para compatibilidade com receive_ble.py
      if (!bleNotifyStatus("XFER: OK")) return;
      xferPhase = XFER_FINISH;
      break;

    case XFER_FINISH:
      logSerial("XFER: OK — transfer complete");
      notifyStatus("XFER:OK");
      setState(S_READY);
      break;
  }
}

// ---------------------------------------------------------------------------
// FSM — transições
// ---------------------------------------------------------------------------
static void onStateEnter(State entered, State /*previous*/) {
  notifyStatus(stateTag(entered));

  switch (entered) {
    case S_NEEDS_CALIBRATION:
      calib.valid = false;
      ledArmBlink(S_NEEDS_CALIBRATION);
      break;

    case S_CALIBRATING:
      calibReset();
      ledArmBlink(S_CALIBRATING);
      break;

    case S_READY:
      ledApplySolid(S_READY);
      break;

    case S_RECORDING:
      ledApplySolid(S_RECORDING);
      break;

    case S_TRANSFER:
      xferReset();
      ledArmBlink(S_TRANSFER);
      break;

    case S_ERROR:
      ledArmBlink(S_ERROR);
      break;
  }
}

static void setState(State next) {
  const State prev = state;
  if (prev == next) return;

  state = next;
  logSerialf("STATE: %s -> %s", stateTag(prev), stateTag(next));
  onStateEnter(next, prev);
}

// ---------------------------------------------------------------------------
// setup / loop
// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println(F("\n=== Kinexa firmware ==="));
  logSerialf("BOOT: FW %s device %s", FW_VERSION, DEVICE_ID);

  pinMode(PIN_BUTTON, INPUT_PULLUP);
  ledInit();

  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(400000);

  bleInit();

  if (!mpuInitWithRetry()) {
    logSerial("ERR: MPU6050 not responding — verifique I2C (SDA=GPIO8, SCL=GPIO9)");
    notifyStatus("ERR:MPU");
    setState(S_ERROR);
    return;
  }
  logSerial("BOOT: MPU6050 OK");

  if (!LittleFS.begin(true)) {
    logSerial("ERR: LittleFS mount failed");
    notifyStatus("ERR:FS");
    setState(S_ERROR);
    return;
  }
  logSerial("BOOT: LittleFS OK");

  calib.valid = false;
  // state já inicia como S_NEEDS_CALIBRATION — forçar entrada para acionar LED/BLE
  state = S_ERROR;
  setState(S_NEEDS_CALIBRATION);
  logSerial("BOOT: waiting for CALIBRATE from app");
}

void loop() {
  ledTick();
  buttonTick();

  switch (state) {

    case S_NEEDS_CALIBRATION:
    case S_READY:
    case S_ERROR:
      delay(1);
      break;

    case S_CALIBRATING:
      if (calibTick()) {
        calibFinalize();
        if (calib.valid) {
          notifyStatus("CALIB:OK");
          setState(S_READY);
        } else {
          notifyStatus("CALIB:FAIL");
          setState(S_NEEDS_CALIBRATION);
        }
      }
      delay(0);
      break;

    case S_RECORDING: {
      const uint32_t now_us = micros();
      if ((int32_t)(now_us - t_next_sample_us) >= 0) {
        t_next_sample_us += SAMPLE_PERIOD_US;
        acquireOne(millis());
      }
      delay(0);
      break;
    }

    case S_TRANSFER:
      xferTick();
      break;
  }
}
