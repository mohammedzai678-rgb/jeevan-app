#ifndef WALKING_STICK_CONFIG_H
#define WALKING_STICK_CONFIG_H

// Bluetooth-only walking-stick ESP32 (#2). The phone app relays telemetry to
// the cloud using the signed-in user's session; this firmware stores no keys.

// Same Jeevan BLE GATT layout and MTU used by VitaWatch. The unique name lets
// the app distinguish this separate ESP32 from the watch.
#define STICK_BLE_DEVICE_NAME       "Jeevan-Stick"
#define BLE_NOTIFY_INTERVAL_MS      100
#define JEEVAN_BLE_SERVICE_UUID     "4a455645-0001-4c2b-9d3a-5a65657600a1"
#define JEEVAN_BLE_VITALS_CHAR_UUID "4a455645-0002-4c2b-9d3a-5a65657600a1"
#define JEEVAN_BLE_COMMAND_CHAR_UUID "4a455645-0003-4c2b-9d3a-5a65657600a1"
#define JEEVAN_BLE_EVENT_CHAR_UUID  "4a455645-0004-4c2b-9d3a-5a65657600a1"

// HC-SR04 sensors: ECHO must pass through a divider to 3.3 V.
#define LEFT_TRIG_PIN    5
#define LEFT_ECHO_PIN    34
#define FRONT_TRIG_PIN   18
#define FRONT_ECHO_PIN   35
#define RIGHT_TRIG_PIN   19
#define RIGHT_ECHO_PIN   32

// 3V3 -> LDR -> GPIO 33 -> 4.7 kOhm -> GND; GPIO 2 drives headlight LED.
#define LDR_PIN                 33
#define LIGHT_LED_PIN           2
#define LEFT_TURN_LED_PIN       25
#define RIGHT_TURN_LED_PIN      26
#define TURN_SIGNAL_BLINK_MS    350
#define LDR_DEFAULT_THRESHOLD   100
#define LDR_DEFAULT_HYSTERESIS  0
#define LDR_CHECK_INTERVAL_MS   30
#define LDR_PRINT_INTERVAL_MS   500

#define OBSTACLE_WARN_CM        80
#define OBSTACLE_NEAR_CM        35
#define CONTACT_CM              4
#define CONTACT_HINT_CM         15
#define MAX_RANGE_CM            400
#define ECHO_TIMEOUT_US         45000UL
#define SENSOR_GAP_MS           30
#define GUIDANCE_STABLE_CYCLES  3
#define GUIDANCE_REPEAT_MS      8000
#define GUIDANCE_MIN_GAP_MS     4000
#define STICK_PRINT_INTERVAL_MS 500
#define SERIAL_BAUD             115200

#endif // WALKING_STICK_CONFIG_H
