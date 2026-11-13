
#ifndef WALKING_STICK_CONFIG_H
#define WALKING_STICK_CONFIG_H

// =============================================================================
// JEEVANCARE WALKING STICK  (ESP32 #2)
// ESP32 DevKit / NodeMCU ESP32 CP2102  -  Arduino IDE board: "ESP32 Dev Module"
//
// ESP32 #1 (Jeevan Watch + medicine timer) keeps its own firmware:
//   firmware/jeevancare_esp32/jeevancare_esp32.ino
// This ESP32 #2 carries the 3 ultrasonic sensors + the LDR automatic light.
// =============================================================================

// --- Wi-Fi & Backend Endpoint Configuration ---
#define WIFI_SSID              "YOUR_WIFI_SSID"
#define WIFI_PASSWORD          "YOUR_WIFI_PASSWORD"

// Jeevan backend: Vercel cloud backend or local IP (e.g. "http://192.168.x.x:4000")
#define BACKEND_BASE_URL       "https://jeevan-backend-nine.vercel.app"
#define STICK_TELEMETRY_URL    BACKEND_BASE_URL "/api/stick/telemetry"
#define STICK_EVENT_URL        BACKEND_BASE_URL "/api/stick/event"
#define DEVICE_ID              "esp32_walking_stick_01"
#define DEVICE_API_KEY         "YOUR_DEVICE_API_KEY"
#define ENABLE_WIFI            true    // false = fully offline (LED + Serial still work)
#define TELEMETRY_INTERVAL_MS  1000

// --- Ultrasonic sensors (HC-SR04, powered from VIN / 5V) ---
// TRIG -> direct to the ESP32 pin.
// ECHO -> voltage divider: ECHO -> 1 kOhm -> [ESP32 pin] -> 2 kOhm -> GND
// Mount: Sensor 1 = LEFT, Sensor 2 = FRONT, Sensor 3 = RIGHT.
// (If you mount them differently, just swap the numbers below.)
#define LEFT_TRIG_PIN    5    // Sensor 1 TRIG
#define LEFT_ECHO_PIN    34   // Sensor 1 ECHO (input-only pin, via divider)
#define FRONT_TRIG_PIN   18   // Sensor 2 TRIG
#define FRONT_ECHO_PIN   35   // Sensor 2 ECHO (input-only pin, via divider)
#define RIGHT_TRIG_PIN   19   // Sensor 3 TRIG
#define RIGHT_ECHO_PIN   32   // Sensor 3 ECHO (via divider)

// --- LDR automatic light ---
// 3V3 -> LDR -> GPIO 33 -> 4.7 kOhm -> GND   (bright = high reading, dark = low)
// GPIO 2 -> 220 Ohm -> LED anode (long leg); LED cathode (short leg) -> GND
#define LDR_PIN                 33    // ADC1 channel
#define LIGHT_LED_PIN           2
// Separate turn indicator LEDs; use a 220 ohm resistor per LED.
// GPIO 25 -> LEFT LED anode, GPIO 26 -> RIGHT LED anode; both cathodes -> GND.
// Use a MOSFET/driver instead of GPIO for larger lamps or LED strips.
#define LEFT_TURN_LED_PIN       25
#define RIGHT_TURN_LED_PIN      26
#define TURN_SIGNAL_BLINK_MS    350
#define LDR_DEFAULT_THRESHOLD   100   // darkness threshold matching user hardware (0..4095)
#define LDR_DEFAULT_HYSTERESIS  0     // 0 for instant zero-delay switching
#define LDR_CHECK_INTERVAL_MS   30    // check every 30ms for instant response
#define LDR_PRINT_INTERVAL_MS   500   // print interval

// --- Obstacle guidance tuning ---
#define OBSTACLE_WARN_CM        80    // obstacle closer than this is announced
#define OBSTACLE_NEAR_CM        35    // "Stop" level for the front sensor
#define CONTACT_CM              4     // closer than this = touching
#define CONTACT_HINT_CM         15    // echo lost right after being this close = touching
#define MAX_RANGE_CM            400
#define ECHO_TIMEOUT_US         45000UL  // > 38 ms so "nothing in range" pulses are seen
#define SENSOR_GAP_MS           30    // pause between sensors (prevents cross-talk)
#define GUIDANCE_STABLE_CYCLES  3     // same result 3 times before speaking
#define GUIDANCE_REPEAT_MS      8000  // repeat a persisting warning every 8 s
#define GUIDANCE_MIN_GAP_MS     4000  // minimum gap between two different messages (lets previous speech finish)
#define STICK_PRINT_INTERVAL_MS 500

#define SERIAL_BAUD             115200

#endif // WALKING_STICK_CONFIG_H
