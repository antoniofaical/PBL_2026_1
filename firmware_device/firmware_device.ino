/**
 * ============================================================================
 * Etapa 11 — Máquina de estados + BLE (NimBLE) + LED RGB PWM
 * Placa: ESP32-C3 Super Mini (Arduino-ESP32 core, "ESP32C3 Dev Module")
 *
 * Dependência: biblioteca "NimBLE-Arduino" (h2zero) no Gerenciador de Bibliotecas.
 *
 * Pipeline:
 *   BOOT -> BLE advertising -> IDLE (azul)
 *        -> [central conecta] notify: "Device conectado. Esperando...."
 *        -> [btn] -> CALIB (rosa)  notify: "Calibrando..."
 *        -> READY (verde)          notify: "Device Calibrado! Pronto para gravar..."
 *        -> [btn] -> RECORDING (amarelo) notify: "GRAVANDO..."
 *        -> [btn] -> SAVE_XFER (roxo)      notify: "Gravação finalizada! Transmitindo..."
 *        -> xfer BLE -> FLASH_OK (verde 1s) -> IDLE
 *
 * Pinagem (hardware real):
 *   GPIO 0 -> botão (INPUT_PULLUP, LOW = pressionado)
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
 *   Control  0000ff03-0000-1000-8000-00805f9b34fb  (WRITE) — ACK 0x01 por chunk recebido
 *
 * Protocolo de transferência (igual à etapa 10 serial, via Status + Data):
 *   ===BEGIN_LAST_RUN_BIN=== / PATH / SIZE / DATA_BEGIN
 *   <SIZE bytes binários em chunks na characteristic Data>
 *   DATA_END / ===END_LAST_RUN_BIN=== / XFER: OK
 * ============================================================================
 */

#include <Arduino.h>
#include <Wire.h>
#include <LittleFS.h>
#include <cstdarg>
#include <NimBLEDevice.h>

// ---------------------------------------------------------------------------
// Pinos
// ---------------------------------------------------------------------------
static constexpr uint8_t PIN_BUTTON = 0;
static constexpr uint8_t PIN_LED_R  = 7;
static constexpr uint8_t PIN_LED_G  = 6;
static constexpr uint8_t PIN_LED_B  = 5;
static constexpr uint8_t PIN_SDA    = 8;
static constexpr uint8_t PIN_SCL    = 9;

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
static constexpr uint16_t CALIB_SAMPLES      = 1500;   // ~3 s
static constexpr uint16_t BUFFER_SIZE        = 200;

// ---------------------------------------------------------------------------
// BLE UUIDs
// ---------------------------------------------------------------------------
static constexpr char BLE_DEVICE_NAME[] = "PBL-Run-C3";
static constexpr char SERVICE_UUID[]    = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
static constexpr char CHAR_STATUS_UUID[]  = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
static constexpr char CHAR_DATA_UUID[]    = "0000ff02-0000-1000-8000-00805f9b34fb";
static constexpr char CHAR_CONTROL_UUID[] = "0000ff03-0000-1000-8000-00805f9b34fb";

static constexpr size_t XFER_CHUNK_SIZE = 120;
static constexpr uint32_t XFER_CHUNK_INTERVAL_MS = 12;
static constexpr uint32_t XFER_ACK_TIMEOUT_MS = 8000;
static constexpr uint32_t XFER_POST_DRAIN_MS = 1500;

// ---------------------------------------------------------------------------
// Estados da FSM
// ---------------------------------------------------------------------------
enum State : uint8_t {
  S_IDLE,
  S_CALIB,
  S_READY,
  S_RECORDING,
  S_SAVE_XFER,
  S_FLASH_OK,
  S_FLASH_FAIL,
};

enum XferPhase : uint8_t {
  XFER_OPEN_FILE,
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
static State state = S_IDLE;

static Sample buf[BUFFER_SIZE];
static volatile uint16_t buf_w = 0;

static File rec_file;
static const char* REC_PATH = "/last_run.bin";

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

// Calibração não bloqueante
static CalibAccum calibAccum;

// Transferência não bloqueante
static XferPhase xferPhase = XFER_OPEN_FILE;
static File xferFile;
static size_t xferTotalBytes = 0;
static size_t xferSentBytes = 0;
static uint8_t xferChunk[XFER_CHUNK_SIZE];
static uint32_t xferLastChunkMs = 0;
static bool xferAwaitingAck = false;
static uint32_t xferAckDeadlineMs = 0;
static uint32_t xferPostDrainUntilMs = 0;

// LED PWM
static constexpr uint32_t LEDC_FREQ_HZ = 5000;
static constexpr uint8_t LEDC_RES_BITS = 8;

// ---------------------------------------------------------------------------
// Protótipos
// ---------------------------------------------------------------------------
static void logSerial(const char* msg);
static void logSerialf(const char* fmt, ...);

static void ledInit();
static void ledSetColor(const Rgb& c);
static void ledApplyState(State s);

static void mpuWrite(uint8_t reg, uint8_t val);
static bool mpuReadBurst(int16_t& ax, int16_t& ay, int16_t& az,
                         int16_t& gx, int16_t& gy, int16_t& gz);
static bool mpuInit();

static void bleInit();
static bool bleNotifyStatus(const char* msg);
static bool bleNotifyData(const uint8_t* data, size_t len);
static bool bleIsReadyForXfer();

static void calibReset();
static bool calibTick();
static void calibFinalize();

static void acquireOne(uint32_t now_ms);
static bool buttonPressed();
static bool startRecording();
static void stopRecording();

static void xferReset();
static void xferFail();
static void xferTick();
static bool xferOpenFile();
static bool xferSendPayloadChunk();

static void transitionTo(State next);
static void onStateEnter(State entered, State previous);

// ---------------------------------------------------------------------------
// Logging (Serial apenas para desenvolvimento)
// ---------------------------------------------------------------------------
static void logSerial(const char* msg) {
  Serial.println(msg);
}

static void logSerialf(const char* fmt, ...) {
  char buf[160];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  Serial.println(buf);
}

// ---------------------------------------------------------------------------
// LED RGB — PWM
// ---------------------------------------------------------------------------
static const Rgb LED_IDLE      = {0, 0, 255};
static const Rgb LED_CALIB     = {255, 20, 100};   // rosa
static const Rgb LED_READY     = {0, 255, 0};
static const Rgb LED_RECORDING = {255, 255, 0};    // amarelo
static const Rgb LED_SAVE      = {140, 0, 255};    // roxo (B > R)
static const Rgb LED_OK        = {0, 255, 0};
static const Rgb LED_FAIL      = {255, 0, 0};
static const Rgb LED_OFF       = {0, 0, 0};

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

static void ledApplyState(State s) {
  switch (s) {
    case S_IDLE:       ledSetColor(LED_IDLE); break;
    case S_CALIB:      ledSetColor(LED_CALIB); break;
    case S_READY:      ledSetColor(LED_READY); break;
    case S_RECORDING:  ledSetColor(LED_RECORDING); break;
    case S_SAVE_XFER:  ledSetColor(LED_SAVE); break;
    case S_FLASH_OK:   ledSetColor(LED_OK); break;
    case S_FLASH_FAIL: ledSetColor(LED_FAIL); break;
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
  rd16();  // temperatura — descartada
  gx = rd16();
  gy = rd16();
  gz = rd16();
  return true;
}

static bool mpuInit() {
  mpuWrite(REG_PWR_MGMT_1, 0x01);
  delay(50);

  mpuWrite(REG_SMPLRT_DIV, 1);       // 500 Hz
  mpuWrite(REG_CONFIG, 0x03);        // DLPF ~44 Hz
  mpuWrite(REG_GYRO_CONFIG, 0x10);   // ±1000 °/s
  mpuWrite(REG_ACCEL_CONFIG, 0x10);  // ±8 g

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x75);
  if (Wire.endTransmission(false) != 0) return false;
  Wire.requestFrom(MPU_ADDR, (uint8_t)1, (uint8_t)true);
  return Wire.available() && Wire.read() == 0x68;
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

    if (state == S_IDLE) {
      bleNotifyStatus("Device conectado. Esperando....");
    }
  }

  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo, int reason) override {
    (void)connInfo;
    (void)reason;
    bleConnected = false;
    bleStatusSubscribed = false;
    bleDataSubscribed = false;
    logSerial("BLE: disconnected");

    if (state == S_SAVE_XFER) {
      bleAbortXfer = true;
    }

    NimBLEDevice::startAdvertising();
    server->startAdvertising();
  }
};

class BleControlCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo& connInfo) override {
    (void)chr;
    (void)connInfo;
    bleXferAck = true;
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
  NimBLEDevice::init(BLE_DEVICE_NAME);
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
      NIMBLE_PROPERTY::WRITE);
  bleCharControl->setCallbacks(&bleControlCb);

  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->setName(BLE_DEVICE_NAME);
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->enableScanResponse(true);
  advertising->start();

  logSerial("BLE: advertising started");
}

// ---------------------------------------------------------------------------
// Calibração estática — não bloqueante
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
    delay(0);  // alimenta stack BLE / watchdog durante I/O
  }
}

static bool buttonPressed() {
  static int last_raw = HIGH;
  static uint32_t t_last = 0;
  const int raw = digitalRead(PIN_BUTTON);
  const uint32_t now = millis();

  if (raw == LOW && last_raw == HIGH && (now - t_last) > 80) {
    t_last = now;
    last_raw = raw;
    return true;
  }
  if (raw == HIGH) last_raw = HIGH;
  return false;
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
}

// ---------------------------------------------------------------------------
// Transferência BLE — não bloqueante
// ---------------------------------------------------------------------------
static void xferReset() {
  if (xferFile) xferFile.close();
  xferPhase = XFER_OPEN_FILE;
  xferTotalBytes = 0;
  xferSentBytes = 0;
  xferLastChunkMs = 0;
  xferAwaitingAck = false;
  xferAckDeadlineMs = 0;
  xferPostDrainUntilMs = 0;
  bleXferAck = false;
  bleAbortXfer = false;
}

// 1 = ACK ok / idle, 0 = aguardando ACK, -1 = timeout
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

static bool xferSendChunkAndWaitAck() {
  if (!xferSendPayloadChunk()) return false;
  xferAwaitingAck = true;
  xferAckDeadlineMs = millis() + XFER_ACK_TIMEOUT_MS;
  return true;
}

static void xferFail() {
  if (xferFile) xferFile.close();
  transitionTo(S_FLASH_FAIL);
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

static void xferTick() {
  if (bleAbortXfer || !bleConnected) {
    logSerial("XFER: aborted — BLE disconnected");
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
      xferPhase = XFER_HDR_BEGIN;
      break;

    case XFER_HDR_BEGIN:
      if (!bleNotifyStatus("===BEGIN_LAST_RUN_BIN===")) return;
      xferPhase = XFER_HDR_PATH;
      break;

    case XFER_HDR_PATH: {
      char line[48];
      snprintf(line, sizeof(line), "PATH:%s", REC_PATH);
      if (!bleNotifyStatus(line)) return;
      xferPhase = XFER_HDR_SIZE;
      break;
    }

    case XFER_HDR_SIZE: {
      char line[32];
      snprintf(line, sizeof(line), "SIZE:%u", (unsigned)xferTotalBytes);
      if (!bleNotifyStatus(line)) return;
      xferPhase = XFER_HDR_DATA_BEGIN;
      break;
    }

    case XFER_HDR_DATA_BEGIN:
      if (!bleNotifyStatus("DATA_BEGIN")) return;
      bleXferAck = false;
      xferAwaitingAck = false;
      xferPhase = XFER_SEND_PAYLOAD;
      xferLastChunkMs = 0;
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
      if (millis() - xferLastChunkMs < XFER_CHUNK_INTERVAL_MS) return;
      if (!xferSendChunkAndWaitAck()) {
        xferFail();
        return;
      }
      xferLastChunkMs = millis();
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
      if (!bleNotifyStatus("XFER: OK")) return;
      xferPhase = XFER_FINISH;
      break;

    case XFER_FINISH:
      logSerial("XFER: OK");
      transitionTo(S_FLASH_OK);
      break;
  }
}

// ---------------------------------------------------------------------------
// FSM — transições
// ---------------------------------------------------------------------------
static void onStateEnter(State entered, State previous) {
  switch (entered) {
    case S_IDLE:
      if (bleConnected) {
        bleNotifyStatus("Device conectado. Esperando....");
      }
      break;

    case S_CALIB:
      bleNotifyStatus("Calibrando...");
      calibReset();
      break;

    case S_READY:
      bleNotifyStatus("Device Calibrado! Pronto para gravar...");
      break;

    case S_RECORDING:
      bleNotifyStatus("GRAVANDO...");
      break;

    case S_SAVE_XFER:
      bleNotifyStatus("Gravação finalizada! Transmitindo...");
      xferReset();
      break;

    case S_FLASH_FAIL:
      if (previous == S_CALIB) {
        bleNotifyStatus("ERRO: calibracao falhou");
      } else if (previous == S_SAVE_XFER) {
        bleNotifyStatus("ERRO: transferencia falhou");
      } else {
        bleNotifyStatus("ERRO: operacao falhou");
      }
      break;

  default:
    break;
  }
}

static uint32_t t_flash_entered_ms = 0;

static void transitionTo(State next) {
  const State prev = state;
  if (prev == next) return;

  state = next;
  ledApplyState(state);

  if (next == S_FLASH_OK || next == S_FLASH_FAIL) {
    t_flash_entered_ms = millis();
  }

  onStateEnter(next, prev);
  logSerialf("STATE: %u -> %u", (unsigned)prev, (unsigned)next);
}

// ---------------------------------------------------------------------------
// setup / loop
// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println(F("\n=== Etapa 11: BLE + PWM ==="));

  pinMode(PIN_BUTTON, INPUT_PULLUP);
  ledInit();

  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(400000);

  if (!mpuInit()) {
    Serial.println(F("FATAL: MPU6050 not responding"));
    while (true) {
      ledSetColor(LED_FAIL);
      delay(200);
      ledSetColor(LED_OFF);
      delay(200);
    }
  }

  if (!LittleFS.begin(true)) {
    Serial.println(F("FATAL: LittleFS mount failed"));
    while (true) {
      ledSetColor(LED_FAIL);
      delay(100);
      ledSetColor(LED_IDLE);
      delay(100);
    }
  }

  bleInit();

  state = S_IDLE;
  ledApplyState(state);
  logSerial("Ready — connect via BLE, then press button to calibrate.");
}

void loop() {
  static uint32_t t_next_sample_us = 0;

  switch (state) {

    case S_IDLE:
      if (buttonPressed()) {
        if (!bleConnected) {
          bleNotifyStatus("ERRO: conecte o app BLE antes de calibrar");
          logSerial("IDLE: button ignored — no BLE connection");
          break;
        }
        transitionTo(S_CALIB);
      }
      break;

    case S_CALIB:
      if (calibTick()) {
        calibFinalize();
        transitionTo(calib.valid ? S_READY : S_FLASH_FAIL);
      }
      delay(0);
      break;

    case S_READY:
      if (buttonPressed()) {
        if (!bleConnected) {
          bleNotifyStatus("ERRO: conecte o app BLE antes de gravar");
          break;
        }
        if (startRecording()) {
          t_next_sample_us = micros();
          transitionTo(S_RECORDING);
        } else {
          logSerial("REC: failed to open file");
          transitionTo(S_FLASH_FAIL);
        }
      }
      break;

    case S_RECORDING: {
      const uint32_t now_us = micros();
      if ((int32_t)(now_us - t_next_sample_us) >= 0) {
        t_next_sample_us += SAMPLE_PERIOD_US;
        acquireOne(millis());
      }
      delay(0);  // evita watchdog reset com BLE + LittleFS ativos

      if (buttonPressed()) {
        stopRecording();
        logSerial("REC: file closed — starting BLE transfer");
        transitionTo(S_SAVE_XFER);
      }
      break;
    }

    case S_SAVE_XFER:
      xferTick();
      break;

    case S_FLASH_OK:
    case S_FLASH_FAIL:
      if (millis() - t_flash_entered_ms > 1000) {
        transitionTo(S_IDLE);
      }
      break;
  }
}
