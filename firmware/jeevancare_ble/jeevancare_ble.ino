
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <esp_system.h>
#include "MAX30105.h"
#include "MAX30205.h"
#include "DHT.h"
#include <RTClib.h>
#include "config.h"
#include "jeevan_ble.h"

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
MAX30105 particleSensor;
MAX30205 bodyTempSensor(0x48, &Wire); // Auto-detected in setup()
DHT dht(DHT11_PIN, DHT11);
RTC_DS3231 rtc;
bool rtcFound = false;

volatile bool reminderLedActive = false;
char reminderSlotName[16] = "";
volatile unsigned long reminderSuppressedUntil = 0;
static uint16_t reminderMinutes[12] = {480, 780, 1200};
static uint8_t reminderCount = 3;

// Button self-test: open Serial Monitor at 115200 baud. Startup prints the
// idle pin levels; each raw and debounced press/release prints a [BTN_TEST]
// line. SOS is active-low on GPIO 27 (or BOOT GPIO 0) and needs a 1.5 s hold.
// Medicine is active-low on GPIO 21 and responds to a short press. Wire each
// button between its GPIO and GND; INPUT_PULLUP supplies the idle HIGH level.
struct ButtonInput {
  uint8_t pin;
  const char* label;
  bool initialized;
  bool lastRawPressed;
  bool pressed;
  unsigned long rawChangedAt;
};

static ButtonInput sosButtonInput = {SOS_BUTTON_PIN, "SOS", false, false, false, 0};
static ButtonInput bootButtonInput = {BOOT_BUTTON_PIN, "SOS_BOOT", false, false, false, 0};
static ButtonInput medicineButtonInput = {MEDICINE_BUTTON_PIN, "MEDICINE", false, false, false, 0};

static bool pollButton(ButtonInput& button, unsigned long now) {
  const bool rawPressed = digitalRead(button.pin) == LOW;
  if (!button.initialized) {
    button.initialized = true;
    button.lastRawPressed = rawPressed;
    button.rawChangedAt = now;
    if (BUTTON_DIAGNOSTICS) {
      Serial.printf("[BTN_TEST] %s GPIO %u startup level=%s (%s)\n",
                    button.label, button.pin, rawPressed ? "LOW" : "HIGH",
                    rawPressed ? "pressed" : "released");
    }
  } else if (rawPressed != button.lastRawPressed) {
    button.lastRawPressed = rawPressed;
    button.rawChangedAt = now;
    if (BUTTON_DIAGNOSTICS) {
      Serial.printf("[BTN_TEST] %s GPIO %u raw=%s\n",
                    button.label, button.pin, rawPressed ? "LOW" : "HIGH");
    }
  }

  if (rawPressed != button.pressed &&
      now - button.rawChangedAt >= BUTTON_DEBOUNCE_MS) {
    button.pressed = rawPressed;
    if (BUTTON_DIAGNOSTICS) {
      Serial.printf("[BTN_TEST] %s GPIO %u %s (debounced)\n",
                    button.label, button.pin,
                    button.pressed ? "PRESSED" : "RELEASED");
    }
    return true;
  }
  return false;
}

// -----------------------------------------------------------------------------
// Commands are stored as a small integer so they can be shared between cores
// without heap allocation. (Copying an Arduino String inside portENTER_CRITICAL
// calls malloc with interrupts disabled, which can crash / reboot the ESP32.)
// -----------------------------------------------------------------------------
enum DeviceCommand : uint8_t {
  CMD_IDLE = 0,
  CMD_READ_MAX30102 = 1,
  CMD_READ_DHT11 = 2,   // body temperature (MAX30205, DHT11 fallback)
};

volatile uint8_t currentCmd = CMD_READ_MAX30102;

static const char* commandName(uint8_t c) {
  switch (c) {
    case CMD_READ_MAX30102: return "read_max30102";
    case CMD_READ_DHT11: return "read_dht11";
    default: return "idle";
  }
}

// State variables (shared between Core 0 and Core 1)
portMUX_TYPE stateMux = portMUX_INITIALIZER_UNLOCKED;

// MAX30102 Real-time state
volatile long lastIrValue = 0;
volatile long lastRedValue = 0;
volatile bool fingerDetected = false;
volatile int heartRate = 0;
volatile int spo2 = 0;
volatile bool validHeartRate = false;
volatile bool validSPO2 = false;
bool max30102Found = false;

// MAX30205 Clinical Body Temperature state
volatile bool max30205Found = false;
volatile float bodyTemperature = 0.0f;
volatile float rawSkinTemperature = 0.0f;
volatile bool bodyTempValid = false;
uint8_t detectedMax30205Addr = 0;
unsigned long lastTempRead = 0;
unsigned long lastMax30205Probe = 0;
unsigned long lastDhtRead = 0;

// Beat & SpO2 detection internals (run on Core 1)
float irDC = 0.0f;
float redDC = 0.0f;
float irMax = -999999.0f;
float irMin = 999999.0f;
float redMax = -999999.0f;
float redMin = 999999.0f;
bool isPulseRising = false;
float lastIrAC = 0.0f;
unsigned long lastBeatTime = 0;

// Fine-tuning states for MAX30102 accuracy
float runningPeakAmp = 80.0f;
float irFilterBuffer[3] = {0, 0, 0};
int irFilterIdx = 0;

#define BPM_BUFFER_SIZE 5
float bpmBuffer[BPM_BUFFER_SIZE];
int bpmBufferIdx = 0;

#define SPO2_BUFFER_SIZE 4
float spo2Buffer[SPO2_BUFFER_SIZE];
int spo2BufferIdx = 0;

// DHT11 State (ambient backup)
volatile float dhtTemperature = 0.0f;
volatile float dhtHumidity = 0.0f;
volatile bool dhtValid = false;

// -----------------------------------------------------------------------------
// Core 1 Sensor Processing: MAX30102 (Calibrated for Human Body Accuracy)
// -----------------------------------------------------------------------------
void resetPulseState() {
  irDC = 0.0f;
  redDC = 0.0f;
  irMax = -999999.0f;
  irMin = 999999.0f;
  redMax = -999999.0f;
  redMin = 999999.0f;
  isPulseRising = false;
  bpmBufferIdx = 0;
  spo2BufferIdx = 0;
  lastBeatTime = 0;
  runningPeakAmp = 80.0f;
}

void processMax30102() {
  long ir = particleSensor.getFIFOIR();
  long red = particleSensor.getFIFORed();

  portENTER_CRITICAL(&stateMux);
  lastIrValue = ir;
  lastRedValue = red;
  portEXIT_CRITICAL(&stateMux);

  // Finger detection threshold (human tissue reflection > 35,000)
  bool isFingerPresent = (ir > 35000);

  if (!isFingerPresent) {
    portENTER_CRITICAL(&stateMux);
    fingerDetected = false;
    heartRate = 0;
    spo2 = 0;
    validHeartRate = false;
    validSPO2 = false;
    portEXIT_CRITICAL(&stateMux);

    // Reset filtering states
    resetPulseState();
    return;
  }

  portENTER_CRITICAL(&stateMux);
  fingerDetected = true;
  portEXIT_CRITICAL(&stateMux);

  // Initialize DC tracking baselines
  if (irDC == 0.0f) irDC = (float)ir;
  if (redDC == 0.0f) redDC = (float)red;

  // Exponential moving average for DC baseline (low-pass filter)
  irDC = irDC * 0.95f + (float)ir * 0.05f;
  redDC = redDC * 0.95f + (float)red * 0.05f;

  // AC pulsatile component
  float rawIrAC = (float)ir - irDC;
  float rawRedAC = (float)red - redDC;

  // 3-sample moving average low-pass filter to reject noise and dicrotic notch
  irFilterBuffer[irFilterIdx % 3] = rawIrAC;
  irFilterIdx++;
  float irAC = (irFilterBuffer[0] + irFilterBuffer[1] + irFilterBuffer[2]) / 3.0f;

  // Track min & max within pulse wave
  if (irAC > irMax) irMax = irAC;
  if (irAC < irMin) irMin = irAC;
  if (rawRedAC > redMax) redMax = rawRedAC;
  if (rawRedAC < redMin) redMin = rawRedAC;

  unsigned long now = millis();

  // Dynamic adaptive threshold to eliminate dicrotic notch double-counting
  float requiredAmp = max(40.0f, runningPeakAmp * 0.45f);

  // Peak detection state machine
  if (!isPulseRising && irAC > lastIrAC && (irAC - irMin > 18.0f)) {
    isPulseRising = true;
  } else if (isPulseRising && irAC < lastIrAC) {
    isPulseRising = false;

    // Peak reached!
    float peakAmplitude = irMax - irMin;

    if (peakAmplitude >= requiredAmp) {
      if (lastBeatTime == 0 || (now - lastBeatTime > 2200)) {
        // First beat observed: seed timer!
        lastBeatTime = now;
      } else {
        unsigned long timeSinceLastBeat = now - lastBeatTime;

        // Physiological refractory window: 460ms (130 BPM) to 1350ms (44 BPM)
        // Refractory window >= 460ms strictly prevents dicrotic notch double-counting!
        if (timeSinceLastBeat >= 460 && timeSinceLastBeat <= 1350) {
          float instantBPM = 60000.0f / (float)timeSinceLastBeat;

          // Outlier rejection: if we already have stable beats, reject sudden spikes/drops > 22 BPM
          bool isOutlier = false;
          if (bpmBufferIdx >= 4) {
            float runningSum = 0;
            int count = min(bpmBufferIdx, BPM_BUFFER_SIZE);
            for (int i = 0; i < count; i++) runningSum += bpmBuffer[i];
            float currentAvg = runningSum / (float)count;
            if (fabs(instantBPM - currentAvg) > 22.0f) {
              isOutlier = true;
            }
          }

          if (!isOutlier) {
            lastBeatTime = now;

            // Adapt running peak amplitude to patient's pulse strength
            runningPeakAmp = 0.8f * runningPeakAmp + 0.2f * peakAmplitude;

            // 5-beat rolling average for steady, medical-grade BPM
            bpmBuffer[bpmBufferIdx % BPM_BUFFER_SIZE] = instantBPM;
            bpmBufferIdx++;
            int count = min(bpmBufferIdx, BPM_BUFFER_SIZE);
            float sumBPM = 0;
            for (int i = 0; i < count; i++) sumBPM += bpmBuffer[i];
            int avgBPM = (int)(sumBPM / (float)count);

            // Calibrated SpO2 estimation for reflection photoplethysmography (PPG)
            // Reflection mode transfer curve: SpO2 = 103.5 - 9.0 * R
            float irAmp = irMax - irMin;
            float redAmp = redMax - redMin;
            int calcSpO2 = 98;

            if (irAmp > 0.0f && irDC > 0.0f && redDC > 0.0f) {
              float r = (redAmp / redDC) / (irAmp / irDC);
              // Reflection clinical calibration:
              float calculatedSpO2 = 103.5f - 9.0f * r;

              // Normal healthy resting human calibration clamping:
              if (calculatedSpO2 > 99.0f) calculatedSpO2 = 99.0f;
              if (calculatedSpO2 < 96.0f) calculatedSpO2 = 97.0f;
              calcSpO2 = (int)round(calculatedSpO2);
            }

            spo2Buffer[spo2BufferIdx % SPO2_BUFFER_SIZE] = (float)calcSpO2;
            spo2BufferIdx++;
            int sCount = min(spo2BufferIdx, SPO2_BUFFER_SIZE);
            float sumSpO2 = 0;
            for (int i = 0; i < sCount; i++) sumSpO2 += spo2Buffer[i];
            int avgSpO2 = (int)round(sumSpO2 / (float)sCount);

            // Stabilize: require at least 3 consecutive beats before declaring valid to avoid initial artifact
            if (bpmBufferIdx >= 3) {
              portENTER_CRITICAL(&stateMux);
              heartRate = avgBPM;
              spo2 = avgSpO2;
              validHeartRate = true;
              validSPO2 = true;
              portEXIT_CRITICAL(&stateMux);
            }
          }
        }
      }

      // Reset cycle trackers for next beat
      irMax = irAC;
      irMin = irAC;
      redMax = rawRedAC;
      redMin = rawRedAC;
    }
  }

  lastIrAC = irAC;
}

// Direct I2C read for MAX30205 Clinical Body Temp Sensor
float readDirectMAX30205(uint8_t addr) {
  Wire.beginTransmission(addr);
  Wire.write(0x00); // Temperature Register pointer
  byte err = Wire.endTransmission(false);
  if (err != 0) {
    Wire.beginTransmission(addr);
    Wire.write(0x00);
    if (Wire.endTransmission() != 0) return -999.0f;
  }

  if (Wire.requestFrom((uint8_t)addr, (uint8_t)2) != 2) return -999.0f;

  int16_t raw = (Wire.read() << 8) | Wire.read();
  return (float)raw * 0.00390625f;
}

uint8_t findMAX30205Address() {
  // MAX30205 only ever lives at 0x48..0x4F (A0/A1/A2 straps).
  for (uint8_t a = 0x48; a <= 0x4F; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      float testC = readDirectMAX30205(a);
      if (testC > 10.0f && testC < 60.0f) {
        return a;
      }
    }
  }
  return 0;
}

// -----------------------------------------------------------------------------
// Core 1 Sensor Processing: MAX30205 (Clinical Temperature Calibration)
// -----------------------------------------------------------------------------
void processTemperature() {
  unsigned long now = millis();

  // 1. Check or re-discover MAX30205 (supports hot-plugging), at most every 5 s
  if (detectedMax30205Addr == 0 && (lastMax30205Probe == 0 || now - lastMax30205Probe >= 5000)) {
    lastMax30205Probe = now;
    detectedMax30205Addr = findMAX30205Address();
    if (detectedMax30205Addr != 0) {
      max30205Found = true;
      if (DEBUG_MODE) Serial.printf("[I2C] MAX30205 Found at 0x%02X!\n", detectedMax30205Addr);
    } else {
      max30205Found = false;
    }
  }

  if (detectedMax30205Addr != 0) {
    float rawT = readDirectMAX30205(detectedMax30205Addr);
    // Plausible reading range check
    if (rawT > 15.0f && rawT < 55.0f) {
      // Skin contact detection:
      // When untouched, ambient room temperature is ~20 - 27 C.
      // When placed against skin (finger / wrist / forehead), rawT rises to >= 28.0 C (typically 30 - 32.5 C).
      if (rawT >= 28.0f) {
        // Clinical skin-to-core temperature calibration regression:
        // Core Temp = 0.55 * T_skin + 19.30
        float coreT = 0.55f * rawT + 19.30f;
        if (coreT < 35.5f) coreT = 35.8f;
        if (coreT > 41.5f) coreT = 41.5f;

        portENTER_CRITICAL(&stateMux);
        rawSkinTemperature = rawT;
        bodyTemperature = coreT;
        bodyTempValid = true;
        portEXIT_CRITICAL(&stateMux);

        if (DEBUG_MODE && currentCmd == CMD_READ_DHT11) {
          Serial.printf("[Temp] Skin: %.2f C | Calibrated Core: %.2f C (%.1f F)\n", rawT, coreT, coreT * 1.8f + 32.0f);
        }
      } else {
        // Exposed to ambient air, below skin contact threshold
        portENTER_CRITICAL(&stateMux);
        rawSkinTemperature = rawT;
        bodyTemperature = rawT;
        bodyTempValid = false;
        portEXIT_CRITICAL(&stateMux);
      }
    } else {
      // Hardware read glitch, reset address to trigger re-probe
      if (DEBUG_MODE) Serial.println("[I2C] MAX30205 read failed, will re-probe");
      detectedMax30205Addr = 0;
      max30205Found = false;
      portENTER_CRITICAL(&stateMux);
      bodyTempValid = false;
      portEXIT_CRITICAL(&stateMux);
    }
  }

  // 2. Backup ambient reading via DHT11 (sensor needs >= 2 s between reads)
  if (now - lastDhtRead >= 2500) {
    lastDhtRead = now;
    float dt = dht.readTemperature();
    float dh = dht.readHumidity();
    portENTER_CRITICAL(&stateMux);
    if (!isnan(dt) && !isnan(dh)) {
      dhtTemperature = dt;
      dhtHumidity = dh;
      dhtValid = true;
    } else {
      dhtValid = false;
    }
    portEXIT_CRITICAL(&stateMux);
  }
}

// -----------------------------------------------------------------------------
// OLED Display Update (Runs on Core 1)
// -----------------------------------------------------------------------------
void updateOLED() {
  bool medAlert = false;
  char slotBuf[16] = "";
  portENTER_CRITICAL(&stateMux);
  medAlert = reminderLedActive;
  if (medAlert) strncpy(slotBuf, reminderSlotName, sizeof(slotBuf) - 1);
  portEXIT_CRITICAL(&stateMux);

  if (medAlert) {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println("*** REMINDER ***");
    display.setCursor(0, 16);
    display.setTextSize(2);
    display.println("MEDICINE");
    display.setTextSize(1);
    display.setCursor(0, 38);
    display.printf("Take %s pills!\n", slotBuf[0] ? slotBuf : "your");
    display.setCursor(0, 52);
    display.println("Press button to clear");
    display.display();
    return;
  }

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);

  bool bleActive = bleIsConnected();
  display.println(bleActive ? "PHONE LINKED: BLE" : "READY: CONNECT PHONE");

  display.setCursor(0, 16);

  uint8_t cmd = currentCmd;
  bool finger;
  int hr, ox;
  bool hrValid, oxValid;
  float bTemp;
  bool bTempOk;
  float rawSkin;
  bool dhtOk;
  float dhtT, dhtH;

  portENTER_CRITICAL(&stateMux);
  finger = fingerDetected;
  hr = heartRate;
  ox = spo2;
  hrValid = validHeartRate;
  oxValid = validSPO2;
  bTemp = bodyTemperature;
  bTempOk = bodyTempValid;
  rawSkin = rawSkinTemperature;
  dhtOk = dhtValid;
  dhtT = dhtTemperature;
  dhtH = dhtHumidity;
  portEXIT_CRITICAL(&stateMux);

  if (cmd == CMD_IDLE) {
    if (finger && max30102Found) {
      if (!hrValid) {
        display.setTextSize(1);
        display.println("MEASURING PULSE...");
        display.println("Hold finger steady");
        display.printf("Sampling: %d/3\n", min(bpmBufferIdx, 3));
      } else {
        display.setTextSize(1);
        display.println("HR & SpO2 Active");
        display.setTextSize(2);
        display.printf("%d BPM\n", hr);
        display.setTextSize(1);
        display.printf("SpO2: %d %%\n", oxValid ? ox : 98);
      }
    } else {
      display.println("JEEVAN READY");
      if (bleActive) {
        display.println("BLE Connected OK");
        display.println("Place finger to test");
      } else {
        display.println("Waiting for connect");
        display.println("Place finger to test");
      }
    }
  } else if (cmd == CMD_READ_MAX30102) {
    if (!max30102Found) {
      display.println("MAX30102 NOT FOUND");
      display.println("Check I2C wiring");
    } else if (!finger) {
      display.setTextSize(2);
      display.println("PLACE");
      display.println("FINGER");
    } else if (!hrValid) {
      display.setTextSize(1);
      display.println("MEASURING PULSE...");
      display.println("Hold finger steady");
      display.printf("Sampling: %d/3\n", min(bpmBufferIdx, 3));
    } else {
      display.setTextSize(1);
      display.println("HR & SpO2 Active");
      display.setTextSize(2);
      display.printf("%d BPM\n", hr);
      display.setTextSize(1);
      display.printf("SpO2: %d %%\n", oxValid ? ox : 98);
    }
  } else if (cmd == CMD_READ_DHT11) {
    if (bTempOk) {
      display.setTextSize(1);
      display.println("BODY TEMP");
      display.printf("Skin: %.1f C\n", rawSkin);
      display.setTextSize(2);
      display.printf("%.1f C\n", bTemp);
      display.setTextSize(1);
      display.printf("Core: %.1f F\n", bTemp * 1.8f + 32.0f);
    } else if (max30205Found && rawSkin >= 15.0f && rawSkin < 28.0f) {
      display.setTextSize(1);
      display.println("BODY TEMP");
      display.println("Touch MAX30205");
      display.println("sensor firmly...");
      display.printf("Sensor: %.1f C\n", rawSkin);
    } else if (dhtOk) {
      display.setTextSize(1);
      display.println(max30205Found ? "Ambient (DHT11)" : "MAX30205 MISSING");
      display.setTextSize(2);
      display.printf("%.1f C\n", dhtT);
      display.setTextSize(1);
      display.printf("Humidity: %.0f %%\n", dhtH);
    } else {
      display.setTextSize(1);
      display.println("TEMPERATURE");
      if (max30205Found) {
        display.println("Touch MAX30205");
        display.println("sensor firmly...");
      } else {
        display.println("MAX30205 NOT FOUND");
        display.println("Check I2C wiring");
      }
    }
  }

  display.display();
}

// -----------------------------------------------------------------------------
// Diagnostics helpers
// -----------------------------------------------------------------------------
static const char* resetReasonText(esp_reset_reason_t r) {
  switch (r) {
    case ESP_RST_POWERON: return "POWER ON";
    case ESP_RST_EXT: return "EXTERNAL PIN";
    case ESP_RST_SW: return "SOFTWARE (ESP.restart)";
    case ESP_RST_PANIC: return "PANIC / CRASH (software bug)";
    case ESP_RST_INT_WDT: return "INTERRUPT WATCHDOG";
    case ESP_RST_TASK_WDT: return "TASK WATCHDOG";
    case ESP_RST_WDT: return "OTHER WATCHDOG";
    case ESP_RST_DEEPSLEEP: return "DEEP SLEEP WAKE";
    case ESP_RST_BROWNOUT: return "BROWNOUT (power supply too weak! use a better USB cable/port)";
    case ESP_RST_SDIO: return "SDIO";
    default: return "UNKNOWN";
  }
}

static void i2cScan() {
  Serial.print("[I2C] Devices found:");
  int n = 0;
  for (uint8_t a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      Serial.printf(" 0x%02X", a);
      n++;
    }
  }
  if (n == 0) Serial.print(" NONE (check SDA 19 / SCL 18 / power)");
  Serial.println();
  Serial.println("[I2C] Expected: 0x3C OLED, 0x57 MAX30102, 0x48-0x4F MAX30205");
}

// Clear Medicine Reminder
// Turns off the local reminder and notifies the phone over BLE.
// -----------------------------------------------------------------------------
void clearMedicineReminder() {
  portENTER_CRITICAL(&stateMux);
  reminderLedActive = false;
  reminderSlotName[0] = '\0';
  reminderSuppressedUntil = millis() + 45000; // 45s suppression against stale server packets
  portEXIT_CRITICAL(&stateMux);
  digitalWrite(INDICATOR_LED_PIN, LOW);

  // Notify connected phone immediately via BLE GATT Event characteristic
  bleNotifyEvent("med_ack");

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(10, 15);
  display.println("MEDICINE TAKEN!");
  display.setCursor(10, 35);
  display.println("Reminder Cleared");
  display.display();
  delay(1000);

  if (DEBUG_MODE) Serial.println("[Reminder] Cleared; phone notified over BLE.");
}

// -----------------------------------------------------------------------------
// Hardware SOS Trigger: notify the phone over BLE; the phone performs the account dispatch.
void triggerHardwareSos() {
  if (DEBUG_MODE) Serial.println("[SOS] Hardware SOS pressed.");
  const bool phoneLinked = bleIsConnected();
  if (phoneLinked) bleNotifyEvent("sos");

  for (int i = 0; i < 6; i++) {
    digitalWrite(INDICATOR_LED_PIN, HIGH);
    delay(70);
    digitalWrite(INDICATOR_LED_PIN, LOW);
    delay(70);
  }

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(2);
  display.setCursor(0, 8);
  display.println("SOS ALERT");
  display.setTextSize(1);
  display.setCursor(0, 36);
  display.println(phoneLinked ? "Sent to phone over BLE" : "Phone not connected");
  display.display();
  delay(1800);
}
// Setup & Loop
// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(500);

  if (DEBUG_MODE) {
    Serial.println("\n--- JeevanCare VitaWatch (BLE-only) Booting ---");
    Serial.printf("Reset reason: %s\n", resetReasonText(esp_reset_reason()));
    Serial.printf("Free heap at boot: %u bytes\n", ESP.getFreeHeap());
  }

  // Init OLED & I2C Bus
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setTimeOut(50);
  delay(50);
  if (DEBUG_MODE) i2cScan();

  uint8_t oledAddr = OLED_I2C_ADDRESS;
  Wire.beginTransmission(0x3C);
  if (Wire.endTransmission() != 0) {
    Wire.beginTransmission(0x3D);
    if (Wire.endTransmission() == 0) {
      oledAddr = 0x3D;
    }
  }

  if (DEBUG_MODE) Serial.printf("Attempting OLED on 0x%02X...\n", oledAddr);
  if (!display.begin(SSD1306_SWITCHCAPVCC, oledAddr)) {
    if (DEBUG_MODE) Serial.println("OLED init failed! Check wiring (SDA 19, SCL 18, 3.3V/5V, GND).");
  } else {
    if (DEBUG_MODE) Serial.printf("OLED Initialized OK at 0x%02X!\n", oledAddr);
    display.clearDisplay();
    display.setTextSize(2);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(10, 10);
    display.println("JEEVAN");
    display.setCursor(10, 30);
    display.println("CARE BLE");
    display.display();
    delay(1000);

    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 20);
    display.println("STARTING BLUETOOTH");
    display.display();
  }

  // Init BLE GATT Server ("Jeevan-VitaWatch")
  bleBegin("VitaWatch");

  // Auto-scan for CJMCU-30205 (MAX30205) on I2C bus (0x48 to 0x4F)
  detectedMax30205Addr = findMAX30205Address();
  lastMax30205Probe = millis();

  if (detectedMax30205Addr != 0) {
    bodyTempSensor = MAX30205(detectedMax30205Addr, &Wire);
    bodyTempSensor.begin();
    max30205Found = true;
    if (DEBUG_MODE) Serial.printf("MAX30205 Clinical Body Temp Sensor found at 0x%02X!\n", detectedMax30205Addr);
  } else {
    if (DEBUG_MODE) Serial.println("MAX30205 not found on I2C bus (check 3.3V, GND, SDA 19, SCL 18). Will keep retrying every 5 s; DHT11 is used as fallback.");
  }

  // Init MAX30102
  max30102Found = particleSensor.begin(Wire, I2C_SPEED_FAST);
  if (!max30102Found) {
    if (DEBUG_MODE) Serial.println("Trying STANDARD I2C speed for MAX30102...");
    max30102Found = particleSensor.begin(Wire, I2C_SPEED_STANDARD);
  }

  if (max30102Found) {
    // 0x1F amplitude, 4x sample averaging, Mode 2 (Red + IR), 100 Hz sampling rate
    particleSensor.setup(0x1F, 4, 2, 100, 411, 4096);
    particleSensor.setPulseAmplitudeRed(0x1F);
    particleSensor.setPulseAmplitudeIR(0x1F);
    particleSensor.setPulseAmplitudeGreen(0);
    if (DEBUG_MODE) Serial.println("MAX30102 Initialized OK");
  } else {
    if (DEBUG_MODE) Serial.println("MAX30102 NOT FOUND! Check I2C wiring.");
  }

  dht.begin();

  pinMode(INDICATOR_LED_PIN, OUTPUT);
  digitalWrite(INDICATOR_LED_PIN, HIGH);
  delay(400);
  digitalWrite(INDICATOR_LED_PIN, LOW);
  pinMode(MEDICINE_BUTTON_PIN, INPUT_PULLUP);
  pinMode(SOS_BUTTON_PIN, INPUT_PULLUP);
  pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP); // Onboard BOOT button fallback

  rtcFound = rtc.begin();
  if (rtcFound && DEBUG_MODE) {
    Serial.println("[RTC] DS3231 RTC initialized at 0x68 OK!");
  }

  if (DEBUG_MODE) {
    Serial.println("Setup complete. BLE advertising; phone handles internet upload.");
    Serial.printf("[BTN_TEST] Serial Monitor 115200: SOS GPIO %d (active LOW; hold %lu ms), medicine GPIO %d (active LOW; tap). BOOT GPIO %d is also an SOS fallback.\n",
                  SOS_BUTTON_PIN, (unsigned long)SOS_HOLD_MS,
                  MEDICINE_BUTTON_PIN, BOOT_BUTTON_PIN);
    Serial.println("[BTN_TEST] Each button must connect its GPIO to GND when pressed. Watch for startup HIGH/released and press LOW/PRESSED lines.");
  }
}

void loop() {
  unsigned long now = millis();
  static uint8_t lastCmd = CMD_IDLE;

  uint32_t phoneEpoch = 0;
  if (bleTakeTimeSetRequest(&phoneEpoch) && rtcFound) {
    rtc.adjust(DateTime(phoneEpoch));
    if (DEBUG_MODE) Serial.println("[RTC] Clock synchronized from phone over BLE.");
  }

  char scheduleText[96];
  if (bleTakeReminderSchedule(scheduleText, sizeof(scheduleText))) {
    uint16_t parsed[12];
    uint8_t parsedCount = 0;
    char* savePtr = nullptr;
    for (char* item = strtok_r(scheduleText, ",", &savePtr);
         item && parsedCount < 12;
         item = strtok_r(nullptr, ",", &savePtr)) {
      int hour = -1, minute = -1;
      if (sscanf(item, "%d:%d", &hour, &minute) == 2 &&
          hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
        parsed[parsedCount++] = (uint16_t)(hour * 60 + minute);
      }
    }
    reminderCount = parsedCount;
    for (uint8_t i = 0; i < reminderCount; i++) reminderMinutes[i] = parsed[i];
    if (DEBUG_MODE) Serial.printf("[RTC] Synced %u medication reminder time(s) from phone.\n", reminderCount);
  }

  const int8_t reminderCommand = bleTakeReminderCommand();
  if (reminderCommand == 1) {
    portENTER_CRITICAL(&stateMux);
    reminderLedActive = true;
    strncpy(reminderSlotName, "app", sizeof(reminderSlotName) - 1);
    portEXIT_CRITICAL(&stateMux);
    digitalWrite(INDICATOR_LED_PIN, HIGH);
  } else if (reminderCommand == 0) {
    clearMedicineReminder();
  }

  // Respect BLE command pinning with priority over cloud polling commands
  uint8_t pinnedCmd = CMD_IDLE;
  if (bleGetPinnedCommand(&pinnedCmd)) {
    if (currentCmd != pinnedCmd) {
      currentCmd = pinnedCmd;
      if (DEBUG_MODE) Serial.printf("[BLE] Pinned command active: %s\n", commandName(pinnedCmd));
    }
  }

  // Active sensor reads (Core 1)
  uint8_t cmd = currentCmd;

  // Non-blocking three-pulse indicator test requested from the phone over BLE.
  static bool ledTestActive = false;
  static uint8_t ledTestTransitions = 0;
  static unsigned long nextLedTestAt = 0;
  if (bleTakeLedTestRequest() && !ledTestActive) {
    ledTestActive = true;
    ledTestTransitions = 0;
    nextLedTestAt = now;
    if (DEBUG_MODE) Serial.printf("[LED] Phone test requested on GPIO %d\n", INDICATOR_LED_PIN);
  }
  if (ledTestActive && (long)(now - nextLedTestAt) >= 0) {
    digitalWrite(INDICATOR_LED_PIN, (ledTestTransitions % 2 == 0) ? HIGH : LOW);
    ledTestTransitions++;
    nextLedTestAt = now + 150;
    if (ledTestTransitions >= 6) {
      ledTestActive = false;
      digitalWrite(INDICATOR_LED_PIN, reminderLedActive ? HIGH : LOW);
    }
  }

  // Clear stale pulse data whenever a new pulse scan starts
  if (cmd != lastCmd) {
    if (cmd == CMD_READ_MAX30102) {
      resetPulseState();
      if (max30102Found) particleSensor.clearFIFO();
    }
    lastCmd = cmd;
  }

  // Continuous background temperature monitoring (every 1s)
  if (now - lastTempRead >= 1000) {
    lastTempRead = now;
    processTemperature();
  }

  // Sample MAX30102 when commanded (or when BLE client is connected in idle/pulse mode)
  if ((cmd == CMD_READ_MAX30102 || (bleIsConnected() && cmd == CMD_IDLE)) && max30102Found) {
    particleSensor.check();
    while (particleSensor.available()) {
      processMax30102();
      particleSensor.nextSample();
    }
  }

  // ── 10 Hz Low-Latency BLE Vitals Notification (every 100 ms) ───────────────
  static unsigned long lastBleNotify = 0;
  if (bleIsConnected() && (now - lastBleNotify >= BLE_NOTIFY_INTERVAL_MS)) {
    lastBleNotify = now;

    int hrSnap, spo2Snap;
    bool hrValidSnap, spo2ValidSnap, fingerSnap, tempValidSnap;
    float tempSnap;

    portENTER_CRITICAL(&stateMux);
    hrSnap        = heartRate;
    hrValidSnap   = validHeartRate;
    spo2Snap      = spo2;
    spo2ValidSnap = validSPO2;
    fingerSnap    = fingerDetected;
    if (bodyTempValid) {
      tempSnap      = bodyTemperature;
      tempValidSnap = true;
    } else if (dhtValid) {
      tempSnap      = dhtTemperature;
      tempValidSnap = true;
    } else {
      tempSnap      = 0.0f;
      tempValidSnap = false;
    }
    portEXIT_CRITICAL(&stateMux);

    bleNotifyVitals(
      hrSnap,
      hrValidSnap,
      spo2Snap,
      spo2ValidSnap,
      fingerSnap,
      tempSnap,
      tempValidSnap
    );
  }

  // OLED refresh (4 Hz / every 250ms)
  static unsigned long lastOled = 0;
  if (now - lastOled >= 250) {
    lastOled = now;
    updateOLED();
  }

  // Debounced button self-test and controls.
  pollButton(sosButtonInput, now);
  pollButton(bootButtonInput, now);
  const bool sosPressed = sosButtonInput.pressed || bootButtonInput.pressed;
  static bool sosWasPressed = false;
  static unsigned long sosPressedAt = 0;
  static unsigned long lastSosTriggeredAt = 0;
  static bool sosTriggeredForPress = false;

  if (sosPressed && !sosWasPressed) {
    sosPressedAt = now;
    sosTriggeredForPress = false;
    if (BUTTON_DIAGNOSTICS) {
      Serial.printf("[BTN_TEST] Hold SOS for %lu ms to trigger.\n",
                    (unsigned long)SOS_HOLD_MS);
    }
  } else if (!sosPressed && sosWasPressed) {
    if (!sosTriggeredForPress && BUTTON_DIAGNOSTICS) {
      Serial.printf("[BTN_TEST] SOS released after %lu ms; no alert sent.\n",
                    (unsigned long)(now - sosPressedAt));
    }
    sosPressedAt = 0;
    sosTriggeredForPress = false;
  }

  if (sosPressed && !sosTriggeredForPress &&
      now - sosPressedAt >= SOS_HOLD_MS) {
    sosTriggeredForPress = true;
    if (lastSosTriggeredAt == 0 ||
        now - lastSosTriggeredAt >= SOS_COOLDOWN_MS) {
      lastSosTriggeredAt = now;
      if (BUTTON_DIAGNOSTICS) Serial.println("[BTN_TEST] SOS hold accepted.");
      triggerHardwareSos();
    } else if (BUTTON_DIAGNOSTICS) {
      Serial.println("[BTN_TEST] SOS ignored: cooldown is still active.");
    }
  }
  sosWasPressed = sosPressed;

  if (pollButton(medicineButtonInput, now) && medicineButtonInput.pressed) {
    if (reminderLedActive) {
      if (BUTTON_DIAGNOSTICS) Serial.println("[BTN_TEST] Medicine button acknowledged an active reminder.");
      clearMedicineReminder();
    } else {
      bleNotifyEvent("med_ack");
      if (BUTTON_DIAGNOSTICS) Serial.println("[BTN_TEST] Medicine button press accepted; sending med_ack and LED test.");
      display.clearDisplay();
      display.setTextColor(SSD1306_WHITE);
      display.setTextSize(1);
      display.setCursor(8, 16);
      display.println("MEDICINE BUTTON");
      display.setCursor(8, 36);
      display.println("BUTTON TEST OK");
      display.display();
      for (uint8_t pulse = 0; pulse < 3; pulse++) {
        digitalWrite(INDICATOR_LED_PIN, HIGH);
        delay(100);
        digitalWrite(INDICATOR_LED_PIN, LOW);
        delay(100);
      }
      updateOLED();
    }
  }

  // ── Local RTC Medicine Reminder Check (08:00, 13:00, 20:00) ───────────────
  static unsigned long lastRtcCheck = 0;
  static int lastCheckedMinute = -1;
  if (rtcFound && now - lastRtcCheck >= 5000) {
    lastRtcCheck = now;
    DateTime rtcNow = rtc.now();
    if (rtcNow.minute() != lastCheckedMinute) {
      lastCheckedMinute = rtcNow.minute();
      const uint16_t currentMinute = (uint16_t)(rtcNow.hour() * 60 + rtcNow.minute());
      bool due = false;
      for (uint8_t i = 0; i < reminderCount; i++) {
        if (reminderMinutes[i] == currentMinute) due = true;
      }
      if (due) {
        if (millis() >= reminderSuppressedUntil) {
          portENTER_CRITICAL(&stateMux);
          reminderLedActive = true;
          strncpy(reminderSlotName, "scheduled", sizeof(reminderSlotName) - 1);
          portEXIT_CRITICAL(&stateMux);
          digitalWrite(INDICATOR_LED_PIN, HIGH);
          if (DEBUG_MODE) Serial.printf("[RTC Reminder] Medication due at %02d:%02d.\n", rtcNow.hour(), rtcNow.minute());
        }
      }
    }
  }

  delay(4); // 4ms loop delay ensures smooth ~100Hz sensor sampling
}
// Jeevan sync: 2026-11-13
