# Walking-stick ESP32 firmware

This is the **stick ESP32 (#2)** firmware. The VitaWatch runs on its own separate ESP32 and uses a different sketch.

Open `walking_stick_esp32.ino` in Arduino IDE and select **ESP32 Dev Module**. Keep your local `config.h` next to it; `config.example.h` is the safe template if you need to recreate the configuration.

## Pin map

- HC-SR04 left: TRIG GPIO 5, ECHO GPIO 34
- HC-SR04 front: TRIG GPIO 18, ECHO GPIO 35
- HC-SR04 right: TRIG GPIO 19, ECHO GPIO 32
- LDR: GPIO 33; night headlight LED: GPIO 2
- Left turn LED: GPIO 25; right turn LED: GPIO 26
- Use a 220-ohm resistor per indicator LED. Use a MOSFET/driver for larger lamps. Share ground.

A right-side obstacle requests a left signal and phone prompt; a left-side obstacle requests right. An unsafe blocked path flashes both indicators and speaks “Stop.” The LDR continues to switch the headlight based on the configured threshold. Stick telemetry is sent to the app backend over Wi-Fi.
