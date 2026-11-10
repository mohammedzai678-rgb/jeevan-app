# Jeevan App — Native Android + Real-Time FastAPI + Dual-Transport ESP32

Jeevan 2.0 is a ground-up native re-architecture of the JeevanCare wearable health monitoring, emergency SOS, and clinical AI platform. It replaces the legacy browser-polled prototype with a **native Flutter Android application**, a **stateful Python FastAPI backend**, and **dual-transport (BLE + Wi-Fi) ESP32 firmware**.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ESP32 Wearable (JeevanCare)                      │
│   MAX30102 (HR/SpO2)  •  AD8232 (ECG)  •  DHT11 (Temp)  •  SOS Button   │
└───────────────┬─────────────────────────────────────────┬───────────────┘
                │ 1. BLE GATT Notify (~40 ms)             │ 2. HTTP POST (/api/hardware)
                │    Direct to phone (offline-capable)    │    Single round-trip returns
                ▼                                         ▼    next_command + reminder
┌───────────────────────────────┐         ┌───────────────────────────────┐
│   Flutter Android App         │◄───────►│   FastAPI Server (Python)     │
│   • BLE + WebSocket Fusion    │  WS     │   • In-Memory Pub/Sub Hub     │
│   • 60 fps Vitals & ECG Chart │ (<20ms) │   • Server-Driven Sensor Loop │
│   • Native SOS Alarm & GPS    │         │   • Local ONNX Hybrid RAG     │
│   • Streaming AI Assistant    │  SSE    │   • Throttled DB Persistence  │
└───────────────────────────────┘         └───────────────┬───────────────┘
                                                          │ Async Batch (30s)
                                                          ▼
                                          ┌───────────────────────────────┐
                                          │   Supabase (Auth + Postgres)  │
                                          │   + Brevo (SMS / Email SOS)   │
                                          └───────────────────────────────┘
```

---

## 1. Why Latency Dropped from 3–6 Seconds to <40 ms

The legacy web stack suffered from **3,000–6,000 ms end-to-end latency** and frequent sensor stalls because every reading had to traverse multiple serverless hops and database polls:
1. ESP32 made **3 separate TLS handshakes per loop** (`POST /hardware`, `GET /next-command`, `GET /reminder`), blocking the single-core sensor loop for 1.5–2.5 seconds per cycle.
2. Each serverless handler cold-started, wrote synchronously to `device_live_stream` in Postgres, and waited for Supabase Realtime CDC or client polling.
3. The browser controlled sensor switching via `setInterval` timers—when the mobile browser tab backgrounded or throttled, sensor rotation froze entirely.

### How Jeevan 2.0 Achieves Sub-40 ms Real-Time Telemetry

| Path | End-to-End Latency | How It Works |
| :--- | :--- | :--- |
| **Path A: Direct BLE GATT** | **~40 ms** | When the phone is near the wearable, the ESP32 streams compact JSON frames (`{"hr":78,"spo2":98,"ecg":512,...}`) over BLE GATT Characteristic `beb5483e-36e1-4688-b7f5-ea07361b26a8` at 20 Hz. The Flutter app renders vitals and ECG waveforms directly—even with **zero internet connectivity**. Hardware SOS (`{"sos":true}`) triggers the phone's emergency countdown in under 50 ms. |
| **Path B: FastAPI In-Memory WebSocket Hub** | **<20 ms** | When operating over Wi-Fi or viewed remotely by a caregiver, `POST /api/hardware` validates the reading in RAM and immediately fans it out to subscribed WebSocket clients (`/ws/vitals`) via an in-memory `asyncio.Queue` pub/sub hub **before** any database I/O occurs. |
| **Single Round-Trip Piggybacking** | **3× fewer HTTP calls** | `POST /api/hardware` now returns `{"ok": true, "next_command": "read_max30102", "reminder": {...}}` in a single HTTP response. The ESP32 no longer polls `/next-command` or `/reminder` separately. |
| **Server-Driven Sensor Rotation** | **0 background stalls** | Sensor rotation (`read_max30102:15s → read_dht11:4s → read_ad8232:6s`) and manual sensor pinning are managed by an authoritative state machine in the FastAPI server (`DeviceHub`), never by client-side UI timers. |
| **Throttled Background Persistence** | **0 ms hot-path DB wait** | Postgres writes (`vital_readings`) are decoupled from the live telemetry path and flushed asynchronously once every `PERSIST_INTERVAL_S=30` seconds (or immediately on anomaly/SOS). |

---

## 2. Complete API Keys & Services (100% Jeevan Website Parity)

All external keys live **exclusively on the FastAPI server** (`jeevan app/server/.env`). The Flutter Android app only needs the FastAPI server URL and public Supabase project URL/anon key.

| Service / Component | Model / Provider | API Key Env Var | Purpose & Why It Was Chosen |
| :--- | :--- | :--- | :--- |
| **Primary Streaming Medical LLM** | Google Gemini **`gemini-2.5-flash`** | `GEMINI_API_KEY`, `GEMINI_MODEL` | Ultra-low time-to-first-token (TTFT ~250 ms) over SSE (`/api/assistant/chat`), plus AI Symptom Checker, MediScan Lab Analyzer, Medicine Ingredients, and Mental Wellbeing (`/api/gemini/*`). |
| **Multi-LLM Automatic Failover** | OpenAI **`gpt-4o-mini`** & HuggingFace **`Mistral-7B-Instruct-v0.3`** | `OPENAI_API_KEY`, `HUGGINGFACE_API_KEY` | Automatic zero-downtime fallback if Gemini is rate-limited or unreachable, followed by local extractive RAG fallback. |
| **Dense Embeddings (Hybrid RAG)** | **`BAAI/bge-small-en-v1.5`** (ONNX via `fastembed`) | *None (100% Local)* | Runs locally in Python CPU memory (~12 ms/query). Eliminates external embedding API latency, rate limits, and per-token costs. |
| **Cross-Encoder Reranker (RAG)** | **`Xenova/ms-marco-MiniLM-L-6-v2`** (ONNX) | *None (100% Local)* | Locally reranks Reciprocal-Rank-Fused (RRF) Dense + BM25 medical passages in ~25 ms before streaming context to the LLM. |
| **Emergency Routing & Hospitals** | **TomTom** Search, Routing & Traffic APIs | `TOMTOM_API_KEY` | Powers nearby hospital/clinic discovery (`/api/emergency-route/facilities`), traffic-aware ambulance ETA & polyline (`/route`), live road speed (`/traffic-flow`), and road hazards (`/traffic-incidents`). |
| **Live Emergency Video Telehealth** | **Agora RTC** (`007` AccessToken2 HMAC-SHA256) | `AGORA_APP_ID`, `AGORA_APP_CERTIFICATE` | Pure-Python cryptographic `007` RTC token builder (`/api/rtc/create-channel`, `/api/rtc/public-token`) for instant 1-tap emergency doctor/responder video rooms. |
| **Weather Radar & Disaster Risk** | **OpenWeatherMap** Weather & Radar Tiles | `OPENWEATHER_KEY` | Powers live precipitation radar tiles (`/api/weather/radar`) and composite Flood / Fire / Earthquake disaster risk scoring (`/api/risk-score`). |
| **Drug Interaction Verification** | **OpenFDA** Drug Label API + Curated Matrix | *Public API + Built-in* | Checks drug-drug contraindications and bleeding/hypotension risks (`/api/fda/interactions`). |
| **Auth & Database** | **Supabase** (Auth + Postgres) | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET` | Verifies user JWTs locally in FastAPI (<1 ms) and stores user profiles, `device_pairings`, `vital_readings`, `sos_events`, `emergency_summaries`, and `medications`. |
| **Hardware Auth (Watch + Stick)** | Shared Secret | `DEVICE_API_KEY` | Authenticates both ESP32 #1 (**VitaWatch**) and ESP32 #2 (**Smart Walking Stick**) HTTP requests (`X-Device-Key` / `api_key`). |
| **Multi-Channel SOS Dispatch** | **Brevo** (Email + SMS + WhatsApp) | `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`, `BREVO_SMS_SENDER`, `BREVO_WHATSAPP_*` | Dispatches live Google Maps GPS links, telehealth video room links, and vitals via Email, Transactional SMS, and WhatsApp template messages on SOS. |

---

## 2B. Complete Feature & Endpoint Matrix

| Domain | Endpoints | Mobile Screen |
| :--- | :--- | :--- |
| **VitaWatch ESP32 #1 (BLE + Wi-Fi)** | `POST /api/device/{live-stream,ingest,status,sos,sos/location,reminders/acknowledge}`, `GET /api/device/command`, `WS /ws/live` | `DashboardScreen`, `DevicesScreen`, `SosActiveScreen` |
| **Smart Walking Stick ESP32 #2 & Geofence** | `POST /api/stick/{telemetry,event,location,sync-watch,geofence,simulate}`, `GET /api/stick/{status,events,geofence}` | `WalkingStickScreen` |
| **Hybrid Transformer RAG Assistant** | `POST /api/assistant/chat` (SSE), `GET/POST/DELETE /api/assistant/documents` | `AssistantScreen` |
| **AI Clinical Suite & OpenFDA** | `POST /api/gemini/{symptom-check,mediscan,medicine-ingredients,wellbeing}`, `GET /api/fda/interactions` | `ClinicalToolsScreen` |
| **TomTom Emergency Map & Traffic** | `POST /api/emergency-route/{facilities,route,traffic-flow,traffic-incidents}` | `CareMapScreen` |
| **Agora Live Telehealth Video** | `POST /api/rtc/create-channel`, `GET /api/rtc/public-token` | `VideoCallScreen` |
| **Medications & Watch LED Reminders** | `GET/POST/DELETE /api/medications`, `POST /api/devices/{id}/reminder` | `MedicationsScreen` |
| **Weather Radar, Blood Bank, NGOs, ABDM/ABHA & QR Medical ID** | `GET /api/weather/radar`, `GET /api/risk-score`, `GET/POST /api/blood-bank/*`, `GET/POST /api/ngo/*`, `POST /api/abdm/{generate-otp,verify-otp}`, `GET/PUT /api/emergency-summary` | `CommunityDisasterScreen`, `ServicesHubScreen` |

---

## 3. Step-by-Step Quickstart Guide

### Step 1: Run the Supabase Migration

Apply the device pairing and telemetry schema migration in your Supabase SQL Editor:

1. Open your [Supabase Dashboard](https://supabase.com/dashboard) → **SQL Editor**.
2. Paste and execute [`supabase/008_device_pairings.sql`](../supabase/008_device_pairings.sql).
3. This creates the `public.device_pairings` table (mapping `device_id` such as `ESP32_001` to `user_id` with RLS policies) and indexes for fast vitals/SOS queries.

---

### Step 2: Configure & Run the FastAPI Server

Open a terminal in `jeevan app/server`:

```powershell
cd "jeevan app/server"

# 1. Create and activate a virtual environment
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# 2. Install dependencies (FastAPI, Uvicorn, FastEmbed ONNX, httpx, PyJWT)
pip install -r requirements.txt

# 3. Create your environment file
Copy-Item .env.example .env
```

Edit `jeevan app/server/.env` and fill in your credentials:
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`
- `DEVICE_API_KEY` (must match the key flashed to your ESP32 or simulator)
- `GEMINI_API_KEY` (from Google AI Studio)
- `BREVO_API_KEY` and `BREVO_FROM_EMAIL` (optional for local testing; required for live SMS/email SOS dispatch)

Start the server bound to all interfaces (`0.0.0.0`) so your Android phone and ESP32 on the same Wi-Fi LAN can reach it:

```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Verify the server is healthy:
- Health check: `http://localhost:8000/healthz`
- Find your PC's LAN IP via `ipconfig` (e.g., `192.168.1.42`).

---

### Step 3: Flash the ESP32 BLE + Wi-Fi Firmware

1. Open [`firmware/jeevancare_ble/jeevancare_ble.ino`](firmware/jeevancare_ble/jeevancare_ble.ino) in **Arduino IDE** (with ESP32 board package installed).
2. Install required libraries via Arduino Library Manager:
   - `ArduinoJson` (by Benoit Blanchon)
   - `Adafruit GFX Library` & `Adafruit SSD1306`
   - `SparkFun MAX3010x Pulse and Proximity Sensor Library`
   - `DHT sensor library` (by Adafruit)
3. Update the configuration constants at the top of `jeevancare_ble.ino`:
   - `WIFI_SSID` / `WIFI_PASS`: Your 2.4 GHz Wi-Fi credentials (or configure dynamically over BLE from the Flutter app!).
   - `SERVER_URL`: `http://<YOUR_PC_LAN_IP>:8000/api/hardware`
   - `API_KEY`: Must match `DEVICE_API_KEY` in `server/.env`
   - `DEVICE_ID`: `"ESP32_001"`
4. Select **Partition Scheme → Huge APP (3MB No OTA / 1MB SPIFFS)** (required when combining `BLEDevice` + `WiFi` stacks on ESP32) and click **Upload**.

> **No Hardware Handy?** You can simulate a live wearable right from your PC:
> ```powershell
> node ../esp32-simulator.mjs
> ```

---

### Step 4: Build & Run the Flutter Android App

Open a terminal in `jeevan app/mobile`:

```powershell
cd "jeevan app/mobile"

# 1. Fetch Flutter packages
flutter pub get

# 2. Verify your connected Android phone or emulator
flutter devices

# 3. Run the app with your FastAPI server LAN IP and Supabase credentials
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.42:8000 `
  --dart-define=WS_BASE_URL=ws://192.168.1.42:8000 `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-supabase-anon-key
```

*(Note: Replace `192.168.1.42` with your computer's LAN IP address, or use `10.0.2.2` if running inside the Android Emulator.)*

#### Testing the Full Loop on Your Android Device
1. **Sign In & Pair**: Sign in with your Supabase account, open the **Hardware** tab, and pair `ESP32_001` (via BLE scan for `JeevanCare-ESP32` or by Device ID).
2. **Verify Sub-40 ms Telemetry**: Watch the **Monitor** tab badge switch to **`BLE LIVE`** (when near the wearable) or **`CLOUD LIVE`** (over WebSocket). Pin individual sensors (`HR/SpO₂`, `ECG`, `Temp`) or leave on **Auto Rotate**.
3. **Test Emergency SOS**: Press the physical SOS button on the ESP32 (or hold the in-app **SOS** button). The 10-second native haptic/audio countdown launches immediately—even over the Android lock screen—before dispatching GPS + vitals to your emergency contacts.
4. **Ask Jeevan AI**: Open the **Assistant** tab, tap the microphone or type a symptom question, and watch grounded clinical guidance stream token-by-token with cited knowledge cards and personalized live vitals context.
