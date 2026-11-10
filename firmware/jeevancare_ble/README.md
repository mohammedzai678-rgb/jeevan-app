# JeevanCare VitaWatch — BLE + Wi-Fi ESP32 Firmware (`jeevancare_ble`)

Low-latency Bluetooth Low Energy (BLE) GATT server + Wi-Fi cloud streaming firmware for the **JeevanCare VitaWatch (ESP32 #1)**. Streams live patient vitals directly to the Flutter Android app at **10 Hz (~40 ms latency)** over BLE while simultaneously syncing telemetry, SOS alerts, and medicine reminders with the Jeevan FastAPI backend.

---

## 1. Hardware Pin Map (ESP32 Dev Module)

| Peripheral | Signal | ESP32 Pin | Notes |
| :--- | :--- | :--- | :--- |
| **Shared I2C Bus** | `SCL` | `GPIO 18` | Shared across OLED (`0x3C`), MAX30102 (`0x57`), MAX30205 (`0x48–0x4F`), DS3231 RTC (`0x68`) |
| **Shared I2C Bus** | `SDA` | `GPIO 19` | 3.3V logic with internal/board pull-ups |
| **MAX30102** | PPG HR & SpO2 | I2C (`0x57`) | Calibrated reflection PPG with 3-sample moving average & outlier rejection |
| **MAX30205** | Clinical Body Temp | I2C (`0x48–0x4F`) | Auto-discovered on boot & hot-plug; skin-to-core calibration |
| **DHT11** | Backup Temp/Humidity | `GPIO 4` | Ambient fallback when MAX30205 is not touching skin |
| **AD8232 ECG** | `LO+` / `LO-` | `GPIO 32` / `GPIO 33` | Lead-off detection inputs |
| **AD8232 ECG** | `OUTPUT` | `GPIO 34` (ADC1) | Analog single-lead ECG waveform |
| **SOS Button** | Active-LOW (`INPUT_PULLUP`) | `GPIO 27` (or `GPIO 0`) | Triggers immediate BLE `"sos"` event + FastAPI `/api/device/sos` POST |
| **Medicine Button** | Active-LOW (`INPUT_PULLUP`) | `GPIO 21` | Clears reminder, emits BLE `"med_ack"` event + `/api/device/reminders/acknowledge` |
| **Indicator LED** | Digital Output | `GPIO 22` | Solid = medicine reminder due; rapid strobe = SOS triggered |
| **NEO-6M GPS** | `RX2` / `TX2` | `GPIO 16` / `GPIO 17` | 9600 baud UART NMEA |

---

## 2. Arduino IDE Setup & Partition Scheme (Important!)

Because this firmware runs both the **Wi-Fi/HTTP stack** and the **ESP32 BLE stack** simultaneously, the compiled binary exceeds the default 1.2 MB app partition.

1. Open `jeevancare_ble.ino` in **Arduino IDE 2.x**.
2. Select **Tools → Board → esp32 → ESP32 Dev Module**.
3. Select **Tools → Partition Scheme → `"Huge APP (3MB No OTA/1MB SPIFFS)"`**.
4. Install required libraries via Library Manager:
   - `ArduinoJson` (v7.x)
   - `Adafruit GFX Library` & `Adafruit SSD1306`
   - `SparkFun MAX3010x Pulse and Proximity Sensor Library`
   - `ClosedCube MAX30205` (or local `MAX30205.h`)
   - `DHT sensor library` (Adafruit)
   - `RTClib` (Adafruit)
5. Edit `config.h` with your Wi-Fi credentials (`WIFI_SSID`, `WIFI_PASSWORD`) and your FastAPI server address (`BACKEND_BASE_URL`).

---

## 3. BLE GATT Profile (`Jeevan-VitaWatch`)

- **Advertised Device Name:** `Jeevan-VitaWatch`
- **MTU:** `185` bytes
- **Notification Rate:** `10 Hz` (`100 ms` interval)

| Role | UUID | Properties | Payload Format |
| :--- | :--- | :--- | :--- |
| **Service** | `4a455645-0001-4c2b-9d3a-5a65657600a1` | Primary Service | — |
| **Vitals Characteristic** | `4a455645-0002-4c2b-9d3a-5a65657600a1` | `READ \| NOTIFY` (`BLE2902`) | `{"hr":78,"spo2":98,"t":36.8,"ecg":72,"lo":0,"f":1,"v":1234}\n` |
| **Command Characteristic** | `4a455645-0003-4c2b-9d3a-5a65657600a1` | `WRITE \| WRITE_NR` | ASCII: `"auto"`, `"idle"`, `"read_max30102"`, `"read_dht11"`, `"read_ad8232"` |
| **Event Characteristic** | `4a455645-0004-4c2b-9d3a-5a65657600a1` | `NOTIFY` (`BLE2902`) | `{"e":"sos"}\n` or `{"e":"med_ack"}\n` |

### Command Pinning Behavior
When the Flutter app writes `"read_max30102"`, `"read_dht11"`, `"read_ad8232"`, or `"idle"` to the Command Characteristic, the ESP32 **pins** that mode locally and ignores cloud-polled command changes until `"auto"` is written or the BLE connection disconnects.

---

## 4. FastAPI `.env` Configuration

Ensure the `DEVICE_API_KEY` and `DEVICE_ID` in `config.h` match your FastAPI backend `.env`:

```env
DEVICE_ID=esp32_jeevancare_01
DEVICE_API_KEY=jeevan_esp32_prod_2026
```
