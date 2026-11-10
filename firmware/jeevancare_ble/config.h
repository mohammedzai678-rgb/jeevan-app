#ifndef JEEVANCARE_CONFIG_H
#define JEEVANCARE_CONFIG_H

// =============================================================================
// JEEVANCARE VITAWATCH (ESP32 #1) - BLE + FASTAPI CLOUD CONFIGURATION
// ESP32 DevKit / NodeMCU ESP32 CP2102
// Arduino IDE Board: "ESP32 Dev Module"
// Partition Scheme:  "Huge APP (3MB No OTA/1MB SPIFFS)" (Required for WiFi+BLE)
//
// The walking stick runs on its OWN, separate ESP32 (#2):
//   firmware/walking_stick_esp32/walking_stick_esp32.ino
// =============================================================================

// --- Wi-Fi & FastAPI Backend Endpoint Configuration ---
#define WIFI_SSID           "YOUR_WIFI_SSID"
#define WIFI_PASSWORD       "YOUR_WIFI_PASSWORD"

// Jeevan FastAPI backend URL (use your laptop's LAN IP when running locally,
// e.g. "http://192.168.1.100:8000", or your deployed cloud URL).
#define BACKEND_BASE_URL    "http://192.168.1.100:8000"
#define DEVICE_ID           "esp32_jeevancare_01"
#define DEVICE_API_KEY      "jeevan_esp32_prod_2026"

#define BACKEND_INGEST_URL  BACKEND_BASE_URL "/api/device/ingest"
#define COMMAND_POLL_URL    BACKEND_BASE_URL "/api/device/command"
#define LIVE_STREAM_URL     BACKEND_BASE_URL "/api/device/live-stream"
#define SOS_ALERT_URL       BACKEND_BASE_URL "/api/device/sos"
#define SOS_LOCATION_URL    BACKEND_BASE_URL "/api/device/sos/location"
#define REMINDER_ACK_URL    BACKEND_BASE_URL "/api/device/reminders/acknowledge"

// --- Telemetry & BLE Streaming Intervals (in milliseconds) ---
#define BLE_NOTIFY_INTERVAL_MS        100   // 10 Hz low-latency BLE vitals stream (~40ms latency)
#define TELEMETRY_INTERVAL_MS         2000
#define COMMAND_POLL_INTERVAL_MS      3000
#define LIVE_STREAM_INTERVAL_MS       1000  // Wi-Fi stream rate when BLE is disconnected
#define WIFI_STREAM_BLE_CONNECTED_MS  3000  // Reduced Wi-Fi stream rate while BLE is active (radio coexistence)

// --- Authoritative JeevanCare Pin Map ---
// I2C Bus (Shared across OLED, MAX30102, MAX30205, DS3231 RTC)
#define I2C_SCL_PIN         18 // GPIO 18 / D18 -> OLED SCL, MAX30102 SCL, MAX30205 SCL, RTC SCL
#define I2C_SDA_PIN         19 // GPIO 19 / D19 -> OLED SDA, MAX30102 SDA, MAX30205 SDA, RTC SDA

// Two separate push buttons (each: one leg -> GPIO, other leg -> GND, INPUT_PULLUP)
#define SOS_BUTTON_PIN      27 // GPIO 27 / D27 -> SOS button   (HOLD 1.5 s -> SMS alert + GPS location)
#define MEDICINE_BUTTON_PIN 21 // GPIO 21 / D21 -> Medicine button (press -> "pills taken", clears reminder)
#define INDICATOR_LED_PIN   22 // GPIO 22 / D22 -> LED (+220R). Solid = medicine due, fast blink = SOS

// GY-NEO6MV2 GPS module (u-blox NEO-6M, UART, 9600 baud NMEA)
//   GPS VCC -> 3V3 (or VIN/5V, module has its own regulator)
//   GPS GND -> GND
//   GPS TX  -> GPIO 16 (ESP32 RX2)
//   GPS RX  -> GPIO 17 (ESP32 TX2)  (optional - only needed to configure the module)
#define GPS_RX_PIN          16
#define GPS_TX_PIN          17
#define GPS_BAUD            9600

// SOS behaviour
#define SOS_HOLD_MS               1500   // hold SOS button this long (prevents accidental alerts)
#define SOS_RETRY_INTERVAL_MS     3000   // retry delivery while server / Wi-Fi is unreachable
#define SOS_COOLDOWN_MS           15000  // minimum gap between two SOS alerts
#define SOS_SCREEN_MS             20000  // how long the OLED keeps showing the SOS status
#define SOS_LOCATION_FOLLOWUP_MS  600000 // send GPS follow-up up to 10 min after an SOS without fix
#define GPS_FIX_MAX_AGE_MS        10000  // a fix older than this is reported as "last known"

// AD8232 Single-Lead ECG Front-End
#define AD8232_LO_PLUS_PIN  32 // GPIO 32 / D32 -> AD8232 LO+ (Lead-off detect)
#define AD8232_LO_MINUS_PIN 33 // GPIO 33 / D33 -> AD8232 LO- (Lead-off detect)
#define AD8232_OUTPUT_PIN   34 // GPIO 34 / D34 -> AD8232 OUTPUT (Analog ECG waveform)

// --- I2C Addresses ---
#define OLED_I2C_ADDRESS     0x3C
#define MAX30205_I2C_ADDRESS 0x4F
#define MAX30102_I2C_ADDRESS 0x57

// --- OLED Display Configuration ---
#define SCREEN_WIDTH         128
#define SCREEN_HEIGHT        64
#define OLED_RESET           -1

#define DHT11_PIN           4
#define DEBUG_MODE          true

#endif // JEEVANCARE_CONFIG_H
