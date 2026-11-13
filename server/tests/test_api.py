from __future__ import annotations

import json

import pytest

from .conftest import DEVICE_KEY, USER_A, USER_B, auth, stream, token

MAX = {"finger_detected": True, "heart_rate": 78, "heart_rate_valid": True, "spo2": 98, "spo2_valid": True, "signal_quality": "GOOD"}


def test_health(client):
    r = client.get("/health").json()
    assert r["status"] == "ok" and r["rag"]["chunks"] > 10 and r["rag"]["dense"] is False


def test_device_requires_key(client):
    assert client.post("/api/device/live-stream", json=stream("d1", "max30102", MAX, key="wrong")).status_code == 403
    assert client.get("/api/device/command", params={"device_id": "d1"}).status_code == 403
    assert client.get("/api/device/command", params={"device_id": "d1", "api_key": DEVICE_KEY}).status_code == 200
    assert client.get("/api/device/command", params={"device_id": "d1"}, headers={"x-device-key": DEVICE_KEY}).status_code == 200


def test_device_unconfigured_returns_503(settings):
    from fastapi.testclient import TestClient
    from app.main import create_app
    from app.rag.index import HybridIndex

    s = settings.model_copy(update={"device_api_key": ""})
    idx = HybridIndex(); idx.build_shared()
    with TestClient(create_app(s, idx)) as c:
        assert c.post("/api/device/live-stream", json=stream("d1", "max30102", MAX, key="")).status_code == 503


def test_live_stream_reply_carries_command_for_the_firmware(client):
    r = client.post("/api/device/live-stream", json=stream("d1", "max30102", MAX)).json()
    assert r["status"] == "success" and r["command"] == "read_max30102"
    assert r["reminder_led"] is False


def test_user_auth_required_and_pairing(client):
    assert client.get("/api/devices").status_code == 401
    assert client.get("/api/devices", headers={"Authorization": "Bearer junk"}).status_code == 401
    assert client.post("/api/devices/pair", json={"device_id": "d1"}, headers=auth(USER_A)).status_code == 200
    assert client.post("/api/devices/pair", json={"device_id": "d1"}, headers=auth(USER_B)).status_code == 409
    assert [d["device_id"] for d in client.get("/api/devices", headers=auth(USER_A)).json()["devices"]] == ["d1"]
    assert client.get("/api/devices", headers=auth(USER_B)).json()["devices"] == []
    assert client.post("/api/devices/d1/command", json={"command": "read_ad8232"}, headers=auth(USER_B)).status_code == 404
    assert client.post("/api/devices/d1/command", json={"command": "read_ad8232"}, headers=auth(USER_A)).status_code == 200
    assert client.post("/api/devices/d1/command", json={"command": "format_disk"}, headers=auth(USER_A)).status_code == 422


def test_expired_and_wrong_secret_tokens_rejected(client):
    import jwt, time
    expired = jwt.encode({"sub": USER_A, "aud": "authenticated", "exp": int(time.time()) - 5}, "test-secret-test-secret-test-secret-1234", algorithm="HS256")
    forged = jwt.encode({"sub": USER_A, "aud": "authenticated", "exp": int(time.time()) + 99}, "x" * 40, algorithm="HS256")
    for t in (expired, forged):
        assert client.get("/api/devices", headers={"Authorization": f"Bearer {t}"}).status_code == 401


def test_websocket_pushes_vitals_instantly_and_only_to_owner(client):
    client.post("/api/devices/pair", json={"device_id": "d1"}, headers=auth(USER_A))
    with client.websocket_connect("/ws/live", headers=auth(USER_A)) as a, client.websocket_connect("/ws/live", headers=auth(USER_B)) as b:
        assert a.receive_json()["type"] == "vitals"  # initial snapshot
        client.post("/api/device/live-stream", json=stream("d1", "max30102", MAX))
        evt = a.receive_json()
        assert evt["type"] == "vitals" and evt["data"]["vitals"]["heart_rate"] == 78
        assert evt["data"]["analysis"]["overall_status"] in {"normal", "attention"}
        a.send_text(json.dumps({"type": "ping", "t": 123}))
        assert a.receive_json() == {**{"type": "pong", "t": 123}, "server_ms": pytest.approx(0, abs=10**13)}
        b.send_text(json.dumps({"type": "ping", "t": 1}))
        assert b.receive_json()["type"] == "pong"  # B only ever sees its own events (no vitals leaked)


def test_websocket_rejects_unauthenticated(client):
    from starlette.websockets import WebSocketDisconnect

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws/live"):
            pass
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws/live?token=" + token()):  # token in URL is NOT accepted
            pass


def test_ble_gateway_path_requires_ownership(client):
    client.post("/api/devices/pair", json={"device_id": "d1"}, headers=auth(USER_A))
    with client.websocket_connect("/ws/live", headers=auth(USER_A)) as a, client.websocket_connect("/ws/live", headers=auth(USER_B)) as b:
        a.receive_json()
        b.send_text(json.dumps({"type": "ble_vitals", "device_id": "d1", "vitals": {"heart_rate": 200}}))  # B doesn't own d1
        a.send_text(json.dumps({"type": "ble_vitals", "device_id": "d1", "vitals": {"heart_rate": 71, "spo2": 99, "temperature": 36.6}}))
        evt = a.receive_json()
        assert evt["data"]["vitals"]["heart_rate"] == 71


def test_hardware_sos_requires_pairing_then_fans_out(client):
    body = {"device_id": "d1", "api_key": DEVICE_KEY, "location": {"lat": 12.97, "lng": 77.59, "fix": True}, "vitals": {"heart_rate": 140}}
    assert client.post("/api/device/sos", json=body).status_code == 409
    client.post("/api/devices/pair", json={"device_id": "d1"}, headers=auth(USER_A))
    with client.websocket_connect("/ws/live", headers=auth(USER_A)) as ws:
        ws.receive_json()
        r = client.post("/api/device/sos", json=body)
        assert r.status_code == 200
        evt = ws.receive_json()
        assert evt["type"] == "sos" and evt["data"]["event_id"] == r.json()["event_id"]
        assert evt["data"]["maps_url"].endswith("12.97,77.59")
        ev_id = evt["data"]["event_id"]
        # delivery result arrives asynchronously (Brevo not configured -> skipped), SOS itself was instant
        nxt = ws.receive_json()
        assert nxt["type"] == "sos_delivery"
    assert client.post(f"/api/sos/{ev_id}/resolve", headers=auth(USER_B)).status_code == 404
    assert client.post(f"/api/sos/{ev_id}/resolve", headers=auth(USER_A)).status_code == 200


def test_app_sos_validates_coordinates(client):
    assert client.post("/api/sos", json={"lat": 999, "lng": 0}, headers=auth()).status_code == 422
    r = client.post("/api/sos", json={"lat": 12.9, "lng": 77.5}, headers=auth())
    assert r.status_code == 200 and r.json()["event_id"]


def test_reminder_roundtrip(client):
    client.post("/api/devices/pair", json={"device_id": "d1"}, headers=auth())
    client.post("/api/devices/d1/reminder", json={"slot": "morning", "medication": "Metformin"}, headers=auth())
    r = client.post("/api/device/live-stream", json=stream("d1", "dht11", {"valid": True, "temperature": 36.7})).json()
    assert r["reminder_led"] is True and r["reminder_slot"] == "morning"
    # legacy firmware acks without a key
    assert client.post("/api/device/reminders/acknowledge", json={"device_id": "d1"}).status_code == 200
    r = client.post("/api/device/live-stream", json=stream("d1", "dht11", {"valid": True, "temperature": 36.7})).json()
    assert r["reminder_led"] is False


def test_assistant_streams_emergency_first_and_cites_sources(client):
    with client.stream("POST", "/api/assistant/chat", json={"message": "someone has chest pain and is sweating"}, headers=auth()) as r:
        assert r.status_code == 200
        body = "".join(r.iter_text())
    events = [line[7:] for line in body.splitlines() if line.startswith("event: ")]
    assert events[0] == "emergency"
    assert "meta" in events and "token" in events and events[-1] == "done"
    assert "fallback" in events  # no GEMINI_API_KEY in tests -> grounded extractive answer


def test_assistant_requires_auth_and_private_docs(client):
    assert client.post("/api/assistant/chat", json={"message": "hi"}).status_code == 401
    assert client.post("/api/assistant/documents", json={"title": "Rx", "text": "Take zorbitan 40mg nightly."}, headers=auth(USER_A)).json()["chunks"] >= 1
    assert client.get("/api/assistant/documents", headers=auth(USER_A)).json()["chunks"] >= 1
    assert client.get("/api/assistant/documents", headers=auth(USER_B)).json()["chunks"] == 0


def test_manual_vitals_returns_analysis(client):
    r = client.post("/api/vitals/record", json={"heart_rate": 72, "spo2": 80, "temperature": 36.8}, headers=auth())
    assert r.status_code == 200 and r.json()["analysis"]["overall_status"] == "critical"
    assert client.post("/api/vitals/record", json={"heart_rate": 5, "spo2": 98, "temperature": 36.8}, headers=auth()).status_code == 422


def test_agora_rtc_endpoints(settings):
    from fastapi.testclient import TestClient
    from app.main import create_app
    from app.rag.index import HybridIndex

    idx = HybridIndex()
    idx.build_shared()
    # Unconfigured Agora returns 503
    with TestClient(create_app(settings, idx)) as c:
        assert c.post("/api/rtc/public-token", json={"channelId": "room-1"}).status_code == 503

    # Configured Agora issues signed 007 tokens for both public responder and authenticated user
    s = settings.model_copy(update={"agora_app_id": "a" * 32, "agora_app_certificate": "c" * 32})
    with TestClient(create_app(s, idx)) as c:
        pub = c.post("/api/rtc/public-token", json={"channelId": "emergency-room-1"})
        assert pub.status_code == 200 and pub.json()["token"].startswith("007")
        assert c.post("/api/rtc/create-channel", json={"channelId": "consult-1"}).status_code == 401
        priv = c.post("/api/rtc/create-channel", json={"channelId": "consult-1", "role": "publisher"}, headers=auth(USER_A))
        assert priv.status_code == 200 and priv.json()["uid"] == USER_A and priv.json()["token"].startswith("007")


def test_tomtom_route_and_traffic_endpoints(client):
    # Route endpoint always works (falls back to road-factor estimate when TOMTOM_API_KEY is unset)
    r = client.post(
        "/api/emergency-route/route",
        json={"origin_lat": 12.9716, "origin_lon": 77.5946, "dest_lat": 12.9816, "dest_lon": 77.6046},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["distanceMeters"] > 1000 and body["travelTimeSeconds"] >= 60 and len(body["points"]) >= 2
    # Traffic flow requires TOMTOM_API_KEY
    assert client.post("/api/emergency-route/traffic-flow", json={"lat": 12.97, "lon": 77.59}).status_code == 503


def test_walking_stick_and_geofence(client):
    assert client.get("/api/stick/status").status_code == 200
    assert client.post("/api/stick/geofence", json={"enabled": True, "center_lat": 12.9716, "center_lng": 77.5946, "radius_m": 200}).status_code == 200
    # Simulate stick inside geofence
    sim1 = client.post("/api/stick/simulate", json={"left_cm": 45, "front_cm": 120, "right_cm": 80, "lat": 12.9716, "lng": 77.5946})
    assert sim1.status_code == 200 and sim1.json()["geofence_status"] == "safe"
    # Simulate stick breaching geofence (~2km away)
    sim2 = client.post("/api/stick/simulate", json={"left_cm": 15, "front_cm": 3, "right_cm": 90, "lat": 12.9900, "lng": 77.6100, "message": "Obstacle ahead"})
    assert sim2.status_code == 200 and sim2.json()["geofence_status"] == "breached"
    assert sim2.json()["data"]["front_contact"] is True
    assert len(client.get("/api/stick/events").json()["events"]) >= 1


def test_ecosystem_features_fda_weather_blood_ngo_abdm_meds_ai(client):
    # System features
    feat = client.get("/api/system/features").json()
    assert "supabase" in feat and "tomtom" in feat and "agora" in feat

    # Weather radar & Disaster risk score
    assert client.get("/api/weather/radar", params={"lat": 12.97, "lon": 77.59}).status_code == 200
    risk = client.get("/api/risk-score", params={"lat": 12.97, "lng": 77.59}).json()
    assert 0 <= risk["overallScore"] <= 100 and risk["riskLevel"] in ("low", "moderate", "high")

    # FDA drug interactions (known critical pair sildenafil + nitroglycerin)
    fda = client.get("/api/fda/interactions", params={"drug1": "sildenafil", "drug2": "nitroglycerin"}).json()
    assert fda["hasInteraction"] is True and fda["severity"] == "critical"

    # Blood bank search & registration
    assert client.get("/api/blood-bank/search", params={"bloodType": "O+"}).json()["total"] >= 1
    reg = client.post("/api/blood-bank/register", json={"name": "Test Donor", "bloodType": "AB-", "city": "Pune"}, headers=auth(USER_A))
    assert reg.status_code == 201 and reg.json()["donor"]["bloodType"] == "AB-"

    # NGO directory & contact
    assert client.get("/api/ngo", params={"category": "disaster-relief"}).json()["total"] >= 1
    assert client.post("/api/ngo/contact", json={"ngoId": "1", "senderName": "Asha", "message": "Need relief kit"}, headers=auth(USER_A)).status_code == 200

    # ABDM / ABHA OTP & verification
    otp = client.post("/api/abdm/generate-otp", json={"aadhaarNumber": "123456789012"}, headers=auth(USER_A)).json()
    assert otp["success"] is True
    abha = client.post("/api/abdm/verify-otp", json={"txnId": otp["txnId"], "otp": "123456"}, headers=auth(USER_A)).json()
    assert abha["success"] is True and len(abha["abhaNumber"]) == 17

    # Emergency summary & public QR fetch
    put = client.put(
        "/api/emergency-summary",
        json={
            "name": "Asha Verma",
            "bloodType": "O-",
            "dob": "1992-05-10",
            "allergies": ["Penicillin"],
            "conditions": ["Asthma"],
            "currentMedications": ["Salbutamol"],
            "emergencyContacts": [{"name": "Rohan", "phone": "+919876543210", "relationship": "Spouse"}],
        },
        headers=auth(USER_A),
    )
    assert put.status_code == 200
    pub_qr = client.get(f"/api/emergency-summary/{USER_A}").json()
    assert pub_qr["bloodType"] == "O-" and "Penicillin" in pub_qr["allergies"]

    # Medications CRUD
    med = client.post("/api/medications", json={"name": "Metformin", "dosage": "500mg", "frequency": "Twice daily"}, headers=auth(USER_A)).json()
    assert med["status"] == "added"
    assert len(client.get("/api/medications", headers=auth(USER_A)).json()["medications"]) == 1
    assert client.delete(f"/api/medications/{med['medication']['id']}", headers=auth(USER_A)).status_code == 200

    # AI Clinical suite endpoints (Symptom Checker, MediScan, Medicine Analyzer, Wellbeing)
    for ep in ("/api/gemini/symptom-check", "/api/gemini/mediscan", "/api/gemini/medicine-ingredients", "/api/gemini/wellbeing"):
        res = client.post(ep, json={"text": "severe burn on hand, how to treat with paracetamol"}, headers=auth(USER_A))
        assert res.status_code == 200 and res.json()["response"]


def test_vitawatch_and_device_parity_routes(client):
    # VitaWatch CRUD + on-demand analysis
    created = client.post(
        "/api/vitawatch/readings",
        json={"heart_rate": 84, "spo2": 97, "temperature": 36.8, "ecg_bpm": 82, "systolic_bp": 118, "diastolic_bp": 76, "notes": "Morning check"},
        headers=auth(USER_A),
    )
    assert created.status_code == 201 and created.json()["success"] is True
    rd_id = created.json()["reading"]["id"]

    listed = client.get("/api/vitawatch/readings", headers=auth(USER_A)).json()
    assert any(r["id"] == rd_id for r in listed["readings"])

    analyzed = client.post(
        "/api/vitawatch/analyze",
        json={"heart_rate": 160, "spo2": 88, "temperature": 39.2},
        headers=auth(USER_A),
    ).json()
    assert analyzed["success"] is True and analyzed["analysis"]["overall_status"] == "critical"

    deleted = client.delete(f"/api/vitawatch/readings/{rd_id}", headers=auth(USER_A)).json()
    assert deleted["success"] is True and deleted["id"] == rd_id

    # Device record-reading, reminders trigger/status, sos/latest
    client.post("/api/device/live-stream", json=stream("esp32_jeevancare_01", "max30102", MAX))
    rec = client.post(
        "/api/device/record-reading",
        json={"device_id": "esp32_jeevancare_01", "temperature": 36.6},
        headers=auth(USER_A),
    )
    assert rec.status_code == 200 and rec.json()["status"] == "success"
    assert rec.json()["reading"]["heart_rate"] == 78

    trig = client.post(
        "/api/device/reminders/trigger",
        json={"slot": "evening", "medicationName": "Atorvastatin", "device_id": "esp32_jeevancare_01"},
    ).json()
    assert trig["status"] == "success" and trig["reminder"]["active"] is True
    rem_stat = client.get("/api/device/reminders/status", params={"device_id": "esp32_jeevancare_01"}).json()
    assert rem_stat["reminder"]["active"] is True and rem_stat["reminder"]["slot"] == "evening"

    assert "latest_sos" in client.get("/api/device/sos/latest").json()


def test_notifications_and_emergency_delivery_routes(client):
    # Medication status WhatsApp notification
    med_notif = client.post(
        "/api/notifications/medication-status",
        json={"phone": "+919876543210", "userName": "Asha", "medicationName": "Metformin", "dosage": "500mg", "taken": True},
        headers=auth(USER_A),
    )
    assert med_notif.status_code == 200 and med_notif.json()["success"] is True

    # Emergency dispatch (/api/notifications/sos and /api/send-emergency)
    sos_payload = {
        "userName": "Asha",
        "location": {"lat": 12.9716, "lng": 77.5946},
        "contacts": [{"name": "Rohan", "phone": "+919876543210", "email": "rohan@example.com"}],
        "eventId": "evt-12345",
    }
    r1 = client.post("/api/notifications/sos", json=sos_payload, headers=auth(USER_A))
    assert r1.status_code == 200 and r1.json()["success"] is True and "evt-12345" in r1.json()["roomId"]
    r2 = client.post("/api/send-emergency", json=sos_payload, headers=auth(USER_A))
    assert r2.status_code == 200 and r2.json()["success"] is True

    # Public mark-safe link (/api/notifications/sos/{event_id}/safe) and authenticated /api/send-safe
    pub_safe = client.post("/api/notifications/sos/evt-12345/safe")
    assert pub_safe.status_code == 200 and pub_safe.json()["status"] == "resolved"
    auth_safe = client.post(
        "/api/send-safe",
        json={"userName": "Asha", "eventId": "evt-12345", "contacts": [{"name": "Rohan", "phone": "+919876543210"}]},
        headers=auth(USER_A),
    )
    assert auth_safe.status_code == 200 and auth_safe.json()["success"] is True

    # Video call invite & broadcast alert
    inv = client.post(
        "/api/notifications/video-call-invite",
        json={"roomId": "consult_room_01", "userName": "Dr. Rao", "contacts": [{"name": "Asha", "phone": "+919876543210", "email": "asha@example.com"}]},
        headers=auth(USER_A),
    )
    assert inv.status_code == 200 and inv.json()["videoLink"] == "/video-call?roomId=consult_room_01"

    alert = client.post(
        "/api/notifications/alert",
        json={"topic": "disaster", "title": "Heavy Rain Warning", "body": "Avoid low-lying areas"},
        headers=auth(USER_A),
    )
    assert alert.status_code == 200 and alert.json()["success"] is True


def test_complete_11_endpoint_gemini_clinical_and_medikiosk_suite(client):
    h = auth(USER_A)

    # 1. Triage
    triage_res = client.post(
        "/api/gemini/triage",
        json={"symptoms": "chest pain and sweating", "duration": "30 minutes", "severity": 9, "language": "hi"},
        headers=h,
    ).json()
    assert triage_res["urgency"] == "P1" and len(triage_res["redFlags"]) >= 1

    # 2. Symptom-check with 46-region body map + symptoms list
    sym = client.post(
        "/api/gemini/symptom-check",
        json={"bodyLocation": "leftKnee", "symptoms": ["pain", "swelling"], "duration": "3 days", "severity": 6, "language": "ta"},
        headers=h,
    ).json()
    assert sym["bodyLocationLabel"] == "Left knee" and len(sym["symptomBreakdown"]) == 2 and sym["urgencyLevel"] in ("P1", "P2", "P3", "P4")

    # 3. Medication advice
    med_adv = client.post(
        "/api/gemini/medication-advice",
        json={"drugName": "Metformin", "dosage": "500mg", "scheduledTime": "08:00", "missedBy": 4, "language": "te"},
        headers=h,
    ).json()
    assert "Metformin" in med_adv["advice"]

    # 4. Wellbeing with message + history
    wb = client.post(
        "/api/gemini/wellbeing",
        json={"message": "I am feeling anxious before my exam", "history": [{"role": "user", "text": "Hello Sarah"}], "language": "bn"},
        headers=h,
    ).json()
    assert wb["reply"]

    # 5. Vitals report
    vr = client.post(
        "/api/gemini/vitals-report",
        json={"vitals": {"hr": 82, "spo2": 98, "bp": {"sys": 120, "dia": 78}, "temp": 36.7}, "language": "mr"},
        headers=h,
    ).json()
    assert vr["overallStatus"] == "Normal" and len(vr["metrics"]) >= 3

    # 6 & 9. Diagnostic imaging (with boundingBox + logId) & RLHF feedback
    img = client.post(
        "/api/gemini/diagnostic-imaging",
        json={"documentBase64": "aGVsbG8=", "mimeType": "image/png", "imagingType": "X-Ray", "bodyRegion": "Chest", "clinicalContext": "Cough"},
        headers=h,
    ).json()
    assert img["logId"] and len(img["findings"]) >= 1 and "boundingBox" in img["findings"][0]

    fb = client.post("/api/gemini/feedback", json={"logId": img["logId"], "reward": 1, "correction": "Verified normal"}, headers=h).json()
    assert fb["success"] is True and fb["logId"] == img["logId"]

    # 7. MediScan with documentBase64
    ms = client.post(
        "/api/gemini/mediscan",
        json={"documentBase64": "aGVsbG8=", "mimeType": "application/pdf", "filename": "blood_test.pdf", "language": "kn"},
        headers=h,
    ).json()
    assert ms["isMedicalDocument"] is True and len(ms["keyFindings"]) >= 1

    # 8. Medicine ingredients with Ayurvedic alternatives
    mi = client.post(
        "/api/gemini/medicine-ingredients",
        json={"documentBase64": "aGVsbG8=", "mimeType": "image/jpeg", "filename": "paracetamol_strip.jpg", "language": "ml"},
        headers=h,
    ).json()
    assert len(mi["ayurvedicAlternatives"]) >= 1 and len(mi["ingredients"]) >= 1

    # 10. Clinical history interview (Allopathic & AYUSH modes)
    ch_allo = client.post(
        "/api/gemini/clinical-history",
        json={"chiefComplaint": "Headache for 2 days", "conversationHistory": [], "mode": "allopathic", "language": "en"},
        headers=h,
    ).json()
    assert ch_allo["nextQuestion"] and len(ch_allo["quickReplyOptions"]) >= 2 and ch_allo["isComplete"] is False

    ch_ayush = client.post(
        "/api/gemini/clinical-history",
        json={"chiefComplaint": "Indigestion and acidity", "conversationHistory": [{"role": "assistant", "content": "Q1"}, {"role": "user", "content": "A1"}], "mode": "ayush", "language": "hi"},
        headers=h,
    ).json()
    assert ch_ayush["nextQuestion"] and ch_ayush["progress"] >= 20

    # 11. 11-Section History Summary
    hs = client.post(
        "/api/gemini/history-summary",
        json={
            "chiefComplaint": "Fever and body ache",
            "mode": "ayush",
            "conversationHistory": [
                {"role": "assistant", "content": "When did the fever start?"},
                {"role": "user", "content": "Started 2 days ago with chills, no allergies."},
            ],
        },
        headers=h,
    ).json()
    for key in (
        "chiefComplaint", "hpi", "pastMedical", "pastSurgical", "drugHistory",
        "allergies", "familyHistory", "personalHistory", "reviewOfSystems",
        "investigations", "ayushAssessment",
    ):
        assert key in hs["sections"] and hs["sections"][key]



# Jeevan sync: 2026-11-13
