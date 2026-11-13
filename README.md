# Jeevan

## Smart Healthcare and Emergency-Response Platform

Jeevan is an integrated healthcare platform that combines a Flutter Android
application, ESP32 health devices, a FastAPI backend, AI-assisted clinical
tools, emergency communication, and secure health-data storage.

The platform is designed to help users monitor vital signs, manage medicines,
access medical guidance, contact emergency responders, and share important
health information when it matters most.

> **Important:** Jeevan is a software and hardware project for assistance and
> monitoring. It is not a replacement for a qualified medical professional or
> emergency services.

## What Jeevan Provides

- Real-time health monitoring through the JeevanCare VitaWatch
- Emergency SOS alerts with GPS location and current health data
- Smart walking-stick support for mobility and safety monitoring
- AI health assistant with voice and text interaction
- AI symptom checking, MediScan, medicine analysis, and wellbeing support
- Drug-interaction checking using OpenFDA data and a curated safety matrix
- Emergency hospital discovery and traffic-aware routing
- Live telemedicine and emergency video rooms
- Medication schedules, wearable reminders, and caregiver notifications
- Secure Health Vault for documents, prescriptions, scans, and contacts
- Emergency medical QR profile
- Blood-bank, donor, NGO, weather, and disaster-risk services
- Supabase authentication and cloud persistence
- Offline-capable local BLE monitoring when the wearable is nearby

## System Architecture

```text
                         JeevanCare VitaWatch
                    ESP32 + sensors + SOS button
                         /                  \
                  BLE GATT                  Wi-Fi
             low-latency local link             |
                         \                  /
                          Flutter Android App
                              |       |
                    REST/WebSocket     | SSE
                              v       v
                         FastAPI Backend
                    /        |          \
              AI/RAG     Emergency       Integrations
                         services
                              |
                         Supabase
                     Auth + PostgreSQL
```

### Main Components

| Component | Purpose |
| --- | --- |
| `mobile/` | Flutter Android application |
| `server/` | Python FastAPI API and real-time services |
| `firmware/` | ESP32 VitaWatch firmware |
| `supabase/` | Database schema and migrations |
| `server/app/rag/knowledge/` | Local first-aid and health knowledge |

## Feature Details

### 1. VitaWatch Health Monitoring

The ESP32 VitaWatch can collect and stream:

- Heart rate
- Blood oxygen saturation (SpO2)
- Body temperature
- Single-lead ECG waveform
- GPS location
- SOS button events
- Medicine-reminder acknowledgements

It supports both Bluetooth Low Energy and Wi-Fi. BLE allows the app to display
near-real-time readings without requiring internet access.

Hardware details and wiring are documented in
[firmware/jeevancare_ble/README.md](firmware/jeevancare_ble/README.md).

### 2. Emergency SOS

An SOS can be triggered from the mobile app or the physical wearable button.
The workflow can:

1. Start a safety countdown.
2. Capture the user's location.
3. Collect the latest available vitals.
4. Notify configured emergency contacts.
5. Share a Google Maps location link.
6. Provide an emergency video-room link.
7. Continue sending location updates when a GPS fix becomes available.

Notifications can use in-app alerts, email, SMS, and WhatsApp when the
corresponding services are configured.

### 3. Smart Walking Stick

The second ESP32 device supports:

- Fall and emergency-event detection
- Location tracking
- Geofencing
- Radar-zone status
- Event history
- Synchronization with VitaWatch
- Hardware-free simulation for development and demonstrations

### 4. AI Health Assistant

The assistant accepts text or voice questions and provides streaming,
knowledge-grounded responses. It can use:

- Curated local health and first-aid knowledge
- Hybrid keyword and dense retrieval
- Local ONNX embeddings and reranking
- Configured external language models
- User-provided private documents
- Relevant live-vitals context

External AI services have fallback paths so the application can continue to
provide local or curated responses when an integration is unavailable.

### 5. Clinical AI Tools

The clinical tools include:

- Symptom checker and risk-oriented triage
- Laboratory-report analysis
- Diagnostic-image assistance
- Medicine ingredient and usage explanations
- Drug-interaction checking
- Mental wellbeing and guided-support features
- AI-generated vitals and clinical-history summaries

These features provide assistance and explanations; they do not make a
clinical diagnosis.

### 6. Emergency Map and Telemedicine

Jeevan can help users find nearby hospitals and clinics, calculate routes,
display traffic conditions, identify road incidents, and estimate emergency
travel time.

The telemedicine module provides live Agora video rooms with microphone,
camera, speaker, camera-switching, and invite-link controls.

### 7. Medication Management

Users can:

- Add and remove medicines
- Configure medication schedules
- Receive reminders
- Acknowledge doses on the wearable
- Trigger the VitaWatch reminder LED
- Ask the AI pharmacist about missed doses
- Notify a caregiver through WhatsApp

### 8. Health Vault and Emergency QR

The Health Vault stores health documents, prescriptions, scans, alerts,
symptom-check history, emergency contacts, and profile details.

The emergency QR profile can display selected information such as:

- Patient name
- Blood group
- Allergies
- Medical conditions
- Current medicines
- Emergency contacts

### 9. Community and Disaster Services

The community module includes:

- Blood-bank search
- Donor registration
- Verified NGO discovery and contact
- Community alerts
- Weather and precipitation radar
- Flood, fire, and earthquake risk scoring
- ABDM/ABHA OTP-based identity workflows

## Technology Stack

| Area | Technologies |
| --- | --- |
| Mobile | Flutter, Dart, Riverpod |
| Backend | Python, FastAPI, REST, WebSockets, Server-Sent Events |
| Hardware | ESP32, BLE, Wi-Fi, GPS |
| Sensors | MAX30102, MAX30205, AD8232 ECG, DHT11 |
| Authentication and database | Supabase Auth and PostgreSQL |
| AI | Gemini, OpenAI, Hugging Face, ONNX, Hybrid RAG |
| Maps and traffic | TomTom APIs |
| Video | Agora RTC |
| Notifications | Brevo Email, SMS, and WhatsApp |

## Repository Setup

### Prerequisites

- Flutter SDK 3.22 or newer
- Dart SDK 3.4 or newer
- Python 3.10 or newer
- An Android device or emulator
- Arduino IDE and ESP32 board support for hardware development
- Supabase project for authentication and persistence

### 1. Configure the Backend

```powershell
cd "server"
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```

Add the required values to `server/.env`. Common settings include:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_JWT_SECRET`
- `DEVICE_API_KEY`
- `GEMINI_API_KEY`
- Optional routing, video, weather, and notification keys

Start the API from the repository root:

```powershell
uvicorn app.main:app --app-dir server --host 0.0.0.0 --port 8000 --reload
```

The API health endpoint is:

```text
http://localhost:8000/health
```

### 2. Apply the Database Schema

Run the SQL files in the Supabase SQL Editor in the required migration order.
The main schema is [supabase/supabase_schema.sql](supabase/supabase_schema.sql).
Additional device and table migrations are available in
[supabase/008_device_pairings.sql](supabase/008_device_pairings.sql) and
[supabase/009_missing_tables.sql](supabase/009_missing_tables.sql).

### 3. Run the Flutter Application

```powershell
cd "mobile"
flutter pub get
flutter devices
flutter run `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 `
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8000 `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-supabase-anon-key
```

Use the computer's LAN IP instead of `10.0.2.2` when testing from a physical
Android phone. The phone and computer must be on the same network.

The mobile package configuration is documented in
[mobile/pubspec.yaml](mobile/pubspec.yaml).

### 4. Flash the VitaWatch Firmware

1. Open [firmware/jeevancare_ble/jeevancare_ble.ino](firmware/jeevancare_ble/jeevancare_ble.ino)
   in Arduino IDE.
2. Install the ESP32 board package and the libraries listed in the firmware
   README.
3. Configure Wi-Fi, backend URL, device ID, and device API key.
4. Select the ESP32 Dev Module board.
5. Select the `Huge APP (3MB No OTA/1MB SPIFFS)` partition scheme.
6. Compile and upload the firmware.

Never commit real API keys, passwords, Wi-Fi credentials, or service-role
tokens. Keep them in local `.env` files or secure deployment secrets.

## API Domains

The FastAPI backend is organized around these domains:

- Authentication, profiles, and device pairing
- Live device telemetry and commands
- SOS events and location updates
- AI assistant and private documents
- Clinical AI tools
- Health Vault records
- Medication schedules and reminders
- Walking-stick telemetry and geofencing
- Emergency facilities, routing, and traffic
- Weather and disaster risk
- Blood banks, donors, NGOs, and ABHA workflows
- Agora telemedicine rooms

The API implementation is in
[server/app/main.py](server/app/main.py) and
[server/app/routers/](server/app/routers/).

## Testing

Backend tests are located in [server/tests/](server/tests/).

```powershell
cd "server"
pytest
```

For Flutter static analysis:

```powershell
cd "mobile"
flutter analyze
```

## Project Impact

Jeevan brings monitoring, emergency response, medical information, and
caregiver communication into a single ecosystem. Its combination of direct
wearable connectivity, real-time backend services, AI assistance, and
emergency integrations makes it suitable for demonstrations and future
healthcare-service development.

## License

No license has been specified yet. Add a license before distributing the
project publicly or accepting external contributions.
# Jeevan sync: 2026-11-13
