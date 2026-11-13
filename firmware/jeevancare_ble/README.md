# JeevanCare VitaWatch — BLE-only firmware

The ESP32 connects to the JeevanCare phone app over Bluetooth Low Energy. The phone handles account login and internet upload; the watch firmware contains no Wi-Fi credentials or cloud API key.

## Hardware

| Part | Connection |
| --- | --- |
| Shared I2C bus | SDA GPIO 19, SCL GPIO 18 |
| MAX30102 | I2C address `0x57`; heart rate and SpO₂ |
| MAX30205 | I2C `0x48`–`0x4F`; body temperature |
| DHT11 fallback | GPIO 4 |
| OLED | I2C `0x3C` (or `0x3D`) |
| DS3231 RTC | I2C `0x68`; time is synchronized from the phone over BLE |
| SOS button | Active low, GPIO 27; hold for 1.5 seconds |
| Medicine button | Active low, GPIO 21; clears a reminder |
| Reminder/test LED | GPIO 22 |

The watch has an indicator LED but no buzzer or speaker. Medication and SOS sounds come from the phone's notifications.

## Build

Open `jeevancare_ble.ino` in Arduino IDE and select **ESP32 Dev Module**. Install Adafruit GFX, Adafruit SSD1306, SparkFun MAX3010x, ClosedCube MAX30205, Adafruit DHT, and RTClib libraries. No Wi-Fi setup, API key, or server URL is needed.

## Bluetooth interface

- Advertised name: `Jeevan-VitaWatch`
- Vitals notifications: 10 Hz JSON containing actual heart rate, SpO₂, temperature, and finger detection.
- App controls: `read_max30102`, `read_dht11`, `auto`, `idle`, `test_led`, `reminder_on`, `reminder_off`, and `set_time:<unix-seconds>`.
- Watch events: `sos` and `med_ack`.

The phone forwards live readings through its signed-in live connection. The user can save a snapshot from the VitaWatch screen for account history and analysis. Scheduled phone medication reminders use the saved medication times and play sound on the phone. When connected, the app copies those times to the watch RTC; without a phone sync, the watch uses its 08:00, 13:00, and 20:00 defaults.
