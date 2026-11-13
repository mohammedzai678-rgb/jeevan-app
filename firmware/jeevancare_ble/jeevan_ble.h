#ifndef JEEVAN_BLE_H
#define JEEVAN_BLE_H

#include <Arduino.h>
#include <esp_bt.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// =============================================================================
// JEEVANCARE VITAWATCH — LOW-LATENCY BLE GATT SERVER
// =============================================================================
// Streams real-time vitals and accepts watch controls over Bluetooth Low Energy.
// =============================================================================

#define JEEVAN_BLE_SERVICE_UUID        "4a455645-0001-4c2b-9d3a-5a65657600a1"
#define JEEVAN_BLE_VITALS_CHAR_UUID    "4a455645-0002-4c2b-9d3a-5a65657600a1"
#define JEEVAN_BLE_COMMAND_CHAR_UUID   "4a455645-0003-4c2b-9d3a-5a65657600a1"
#define JEEVAN_BLE_EVENT_CHAR_UUID     "4a455645-0004-4c2b-9d3a-5a65657600a1"

// Command codes matching DeviceCommand enum in jeevancare_ble.ino
#define BLE_CMD_IDLE          0
#define BLE_CMD_READ_MAX30102 1
#define BLE_CMD_READ_DHT11    2

static BLEServer*         pJeevanBleServer  = nullptr;
static BLECharacteristic* pVitalsChar       = nullptr;
static BLECharacteristic* pCommandChar      = nullptr;
static BLECharacteristic* pEventChar        = nullptr;

static portMUX_TYPE   bleStateMux   = portMUX_INITIALIZER_UNLOCKED;
static volatile bool  bleConnected  = false;
static volatile bool  bleCmdPinned  = false;
static volatile bool  bleLedTestRequested = false;
static volatile uint8_t blePinnedCmd = BLE_CMD_IDLE;
static volatile int8_t bleReminderCommand = -1;
static volatile bool bleTimeSetRequested = false;
static volatile uint32_t bleUnixTime = 0;
static volatile bool bleReminderScheduleRequested = false;
static char bleReminderSchedule[96] = "";

class JeevanBleServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    portENTER_CRITICAL(&bleStateMux);
    bleConnected = true;
    portEXIT_CRITICAL(&bleStateMux);
    Serial.println("[BLE] Client connected");
  }

  void onDisconnect(BLEServer* pServer) override {
    portENTER_CRITICAL(&bleStateMux);
    bleConnected = false;
    bleCmdPinned = false;
    blePinnedCmd = BLE_CMD_IDLE;
    portEXIT_CRITICAL(&bleStateMux);
    Serial.println("[BLE] Client disconnected — restarting advertising");
    delay(20);
    pServer->startAdvertising();
  }
};

class JeevanBleCommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    // Compatible with both ESP32 Arduino Core 2.x (std::string) and 3.x (String)
    String val = pCharacteristic->getValue().c_str();
    val.trim();
    val.toLowerCase();

    if (val.length() == 0) return;

    Serial.printf("[BLE] Command received: %s\n", val.c_str());

    if (val == "test_led") {
      portENTER_CRITICAL(&bleStateMux);
      bleLedTestRequested = true;
      portEXIT_CRITICAL(&bleStateMux);
      return;
    }

    if (val == "reminder_on" || val == "reminder_off") {
      portENTER_CRITICAL(&bleStateMux);
      bleReminderCommand = val == "reminder_on" ? 1 : 0;
      portEXIT_CRITICAL(&bleStateMux);
      return;
    }

    if (val.startsWith("set_time:")) {
      const uint32_t epoch = (uint32_t)val.substring(9).toInt();
      if (epoch > 1700000000UL) {
        portENTER_CRITICAL(&bleStateMux);
        bleUnixTime = epoch;
        bleTimeSetRequested = true;
        portEXIT_CRITICAL(&bleStateMux);
      }
      return;
    }

    if (val.startsWith("set_schedule:")) {
      String schedule = val.substring(13);
      portENTER_CRITICAL(&bleStateMux);
      strncpy(bleReminderSchedule, schedule.c_str(), sizeof(bleReminderSchedule) - 1);
      bleReminderSchedule[sizeof(bleReminderSchedule) - 1] = '\0';
      bleReminderScheduleRequested = true;
      portEXIT_CRITICAL(&bleStateMux);
      return;
    }

    if (val == "auto") {
      portENTER_CRITICAL(&bleStateMux);
      bleCmdPinned = false;
      portEXIT_CRITICAL(&bleStateMux);
      return;
    }

    uint8_t parsedCmd = 255;
    if (val == "idle") {
      parsedCmd = BLE_CMD_IDLE;
    } else if (val == "read_max30102") {
      parsedCmd = BLE_CMD_READ_MAX30102;
    } else if (val == "read_dht11" || val == "read_max30205") {
      parsedCmd = BLE_CMD_READ_DHT11;
    }

    if (parsedCmd != 255) {
      portENTER_CRITICAL(&bleStateMux);
      blePinnedCmd = parsedCmd;
      bleCmdPinned = true;
      portEXIT_CRITICAL(&bleStateMux);
    }
  }
};

inline void bleBegin(const char* deviceNameSuffix = "VitaWatch") {
  // Release classic BT memory; the watch uses BLE only.
  esp_bt_mem_release(ESP_BT_MODE_CLASSIC_BT);

  String devName = String("Jeevan-") + (deviceNameSuffix ? deviceNameSuffix : "VitaWatch");
  BLEDevice::init(devName.c_str());
  BLEDevice::setMTU(100);

  pJeevanBleServer = BLEDevice::createServer();
  pJeevanBleServer->setCallbacks(new JeevanBleServerCallbacks());

  BLEService* pService = pJeevanBleServer->createService(JEEVAN_BLE_SERVICE_UUID);

  // 1. Vitals Characteristic (READ | NOTIFY)
  pVitalsChar = pService->createCharacteristic(
    JEEVAN_BLE_VITALS_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pVitalsChar->addDescriptor(new BLE2902());

  // 2. Command Characteristic (WRITE | WRITE_NR)
  pCommandChar = pService->createCharacteristic(
    JEEVAN_BLE_COMMAND_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pCommandChar->setCallbacks(new JeevanBleCommandCallbacks());

  // 3. Event Characteristic (NOTIFY) — SOS & Medicine Acknowledge events
  pEventChar = pService->createCharacteristic(
    JEEVAN_BLE_EVENT_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pEventChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(JEEVAN_BLE_SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06); // Helps with iPhone/Android connection interval
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.printf("[BLE] Advertising started as '%s' (Service: %s)\n",
                devName.c_str(), JEEVAN_BLE_SERVICE_UUID);
}

inline bool bleIsConnected() {
  bool connected;
  portENTER_CRITICAL(&bleStateMux);
  connected = bleConnected;
  portEXIT_CRITICAL(&bleStateMux);
  return connected;
}

inline bool bleGetPinnedCommand(uint8_t* outCmd) {
  bool pinned = false;
  uint8_t cmd = BLE_CMD_IDLE;
  portENTER_CRITICAL(&bleStateMux);
  if (bleConnected && bleCmdPinned) {
    pinned = true;
    cmd = blePinnedCmd;
  }
  portEXIT_CRITICAL(&bleStateMux);
  if (pinned && outCmd) {
    *outCmd = cmd;
  }
  return pinned;
}

inline bool bleTakeLedTestRequest() {
  bool requested;
  portENTER_CRITICAL(&bleStateMux);
  requested = bleLedTestRequested;
  bleLedTestRequested = false;
  portEXIT_CRITICAL(&bleStateMux);
  return requested;
}

inline int8_t bleTakeReminderCommand() {
  int8_t command;
  portENTER_CRITICAL(&bleStateMux);
  command = bleReminderCommand;
  bleReminderCommand = -1;
  portEXIT_CRITICAL(&bleStateMux);
  return command;
}

inline bool bleTakeTimeSetRequest(uint32_t* epoch) {
  bool requested;
  portENTER_CRITICAL(&bleStateMux);
  requested = bleTimeSetRequested;
  if (requested && epoch) *epoch = bleUnixTime;
  bleTimeSetRequested = false;
  portEXIT_CRITICAL(&bleStateMux);
  return requested;
}

inline bool bleTakeReminderSchedule(char* out, size_t outSize) {
  bool requested;
  portENTER_CRITICAL(&bleStateMux);
  requested = bleReminderScheduleRequested;
  if (requested && out && outSize > 0) {
    strncpy(out, bleReminderSchedule, outSize - 1);
    out[outSize - 1] = '\0';
  }
  bleReminderScheduleRequested = false;
  portEXIT_CRITICAL(&bleStateMux);
  return requested;
}

inline void bleNotifyVitals(
  int hr,
  bool hrValid,
  int spo2,
  bool spo2Valid,
  bool finger,
  float temp,
  bool tempValid
) {
  if (!bleIsConnected() || pVitalsChar == nullptr) return;

  char payload[64];
  int outHr   = (finger && hrValid) ? hr : 0;
  int outSpo2 = (finger && spo2Valid) ? spo2 : 0;
  float outT  = tempValid ? temp : 0.0f;
  int outF    = finger ? 1 : 0;

  snprintf(
    payload,
    sizeof(payload),
    "{\"hr\":%d,\"spo2\":%d,\"t\":%.1f,\"f\":%d}\n",
    outHr,
    outSpo2,
    outT,
    outF
  );

  pVitalsChar->setValue((uint8_t*)payload, strlen(payload));
  pVitalsChar->notify();
}

inline void bleNotifyEvent(const char* eventName) {
  if (!bleIsConnected() || pEventChar == nullptr || eventName == nullptr) return;

  char payload[48];
  snprintf(payload, sizeof(payload), "{\"e\":\"%s\"}\n", eventName);
  pEventChar->setValue((uint8_t*)payload, strlen(payload));
  pEventChar->notify();
}

#endif // JEEVAN_BLE_H
// Jeevan sync: 2026-11-13
