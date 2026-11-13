#ifndef JEEVANCARE_CONFIG_H
#define JEEVANCARE_CONFIG_H

// JeevanCare VitaWatch ESP32 #1 — BLE-only link to the phone.
// The phone handles account login, internet access, live upload, and history.

#define BLE_NOTIFY_INTERVAL_MS 100

// Shared I2C bus: OLED, MAX30102, MAX30205 and DS3231 RTC.
#define I2C_SCL_PIN 18
#define I2C_SDA_PIN 19

#define SOS_BUTTON_PIN 27
#define MEDICINE_BUTTON_PIN 21
#define BOOT_BUTTON_PIN 0
#define INDICATOR_LED_PIN 22
#define SOS_HOLD_MS 1500
#define SOS_COOLDOWN_MS 15000
#define BUTTON_DEBOUNCE_MS 35
#define BUTTON_DIAGNOSTICS true

#define DHT11_PIN 4

#define OLED_I2C_ADDRESS 0x3C
#define MAX30205_I2C_ADDRESS 0x4F
#define MAX30102_I2C_ADDRESS 0x57
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1

#define DEBUG_MODE true

#endif // JEEVANCARE_CONFIG_H
