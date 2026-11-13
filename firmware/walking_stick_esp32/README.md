# Walking-stick ESP32 firmware

This is the **stick ESP32 (#2)** firmware. The VitaWatch runs on its own separate ESP32 and uses a different sketch.

Open `walking_stick_esp32.ino` in Arduino IDE and select **ESP32 Dev Module**. The firmware is Bluetooth Low Energy only: it contains no Wi-Fi connection code, cloud URL, password, or device API key. The phone app receives telemetry over BLE and relays it to the cloud through the signed-in user's internet connection.

## Pin map

- HC-SR04 left: TRIG GPIO 5, ECHO GPIO 34
- HC-SR04 front: TRIG GPIO 18, ECHO GPIO 35
- HC-SR04 right: TRIG GPIO 19, ECHO GPIO 32
- LDR: GPIO 33; night headlight LED: GPIO 2
- Left turn LED: GPIO 25; right turn LED: GPIO 26
- Use a 220-ohm resistor per indicator LED. Use a MOSFET/driver for larger lamps. Share ground.

A right-side obstacle requests a left signal and phone prompt; a left-side obstacle requests right. An unsafe blocked path flashes both indicators and speaks “Stop. Turn back slowly.” The LDR continues to switch the headlight based on the configured threshold. Obstacle and light readings stream to the phone over Bluetooth.

## Bluetooth and phone location

The stick advertises as `Jeevan-Stick` and uses the same GATT service UUIDs and 100-byte MTU as the separate VitaWatch. To fit that MTU, the ESP32 sends each JSON reading as ordered BLE notification chunks; the app reassembles the line. The app filters by the stick name and saves its connection separately from the watch. `test_led` flashes both turn LEDs three times.

When the Walking Stick screen is open, the phone requests location permission and sends the phone's GPS fix as the person's location. It also relays the BLE sensor readings to the cloud about once per second. These cloud features need the phone's internet connection; the stick itself remains Bluetooth-only. Foreground GPS tracking stops when the screen closes.
