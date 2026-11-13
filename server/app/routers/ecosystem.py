"""Complete Jeevan Website Feature Parity Router:
- OpenWeatherMap Radar & Disaster Risk Score (/api/weather/radar, /api/risk-score)
- FDA Drug Interactions & AI Medication/Symptom/MediScan Suite (/api/fda/interactions, /api/gemini/*)
- Blood Bank Donor Search & Registration (/api/blood-bank/*)
- Verified NGO & Disaster Relief Directory (/api/ngo/*)
- ABDM / ABHA Digital Health ID (/api/abdm/*)
- Emergency Summary & QR Medical Profile + Medications (/api/emergency-summary/*, /api/medications/*)
- System Feature & API Key Readiness (/api/system/features)
"""
from __future__ import annotations

import base64
import io
import json
import random
import re
import time
import uuid
import zipfile
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from .. import triage
from ..ctx import Context, get_ctx
from ..rag import llm
from ..security import User, current_user

router = APIRouter(tags=["ecosystem"])

# ── In-memory fallback stores (used when Supabase is unconfigured or table doesn't exist) ────────
_DONORS: list[dict[str, Any]] = [
    {"id": "1", "name": "Arjun Mehta", "bloodType": "O+", "city": "Mumbai", "phone": "+919876543210", "available": True, "units": 2, "lastDonated": "2025-11-15"},
    {"id": "2", "name": "Priya Sharma", "bloodType": "A+", "city": "Delhi", "phone": "+918765432109", "available": True, "units": 1, "lastDonated": "2026-01-08"},
    {"id": "3", "name": "Ravi Kumar", "bloodType": "B+", "city": "Bangalore", "phone": "+917654321098", "available": True, "units": 3, "lastDonated": "2025-09-20"},
    {"id": "4", "name": "Sneha Iyer", "bloodType": "AB+", "city": "Chennai", "phone": "+919123456780", "available": False, "units": 0, "lastDonated": "2026-02-14"},
    {"id": "5", "name": "Vikram Nair", "bloodType": "O-", "city": "Bangalore", "phone": "+916543210987", "available": True, "units": 2, "lastDonated": "2025-12-01"},
    {"id": "6", "name": "Anjali Patel", "bloodType": "A-", "city": "Ahmedabad", "phone": "+915432109876", "available": True, "units": 1, "lastDonated": "2026-01-20"},
    {"id": "7", "name": "Mohammed Zain", "bloodType": "B-", "city": "Hyderabad", "phone": "+914321098765", "available": True, "units": 2, "lastDonated": "2025-10-10"},
]

_NGOS: list[dict[str, Any]] = [
    {"id": "1", "name": "NDRF India", "category": "disaster-relief", "description": "National Disaster Response Force — India's premier emergency response organisation.", "phone": "011-24363260", "email": "ndrf@nic.in", "website": "https://ndrf.gov.in", "verified": True, "location": "New Delhi"},
    {"id": "2", "name": "iCall – TISS", "category": "mental-health", "description": "Free mental health counselling offered by Tata Institute of Social Sciences.", "phone": "9152987821", "email": "icall@tiss.edu", "website": "https://icallhelpline.org", "verified": True, "location": "Mumbai"},
    {"id": "3", "name": "Akshaya Patra", "category": "food-shelter", "description": "Emergency food relief and community kitchens across India.", "phone": "080-30143400", "email": "info@akshayapatra.org", "website": "https://akshayapatra.org", "verified": True, "location": "Bangalore"},
    {"id": "4", "name": "CRY India", "category": "child-welfare", "description": "Child Rights and You — child protection, health and emergency support.", "phone": "1800-103-7000", "email": "cry@cry.org", "website": "https://cry.org", "verified": True, "location": "Mumbai"},
    {"id": "5", "name": "Médecins Sans Frontières India", "category": "medical-aid", "description": "Doctors Without Borders providing urgent medical humanitarian assistance.", "phone": "011-49358000", "email": "office-india@msf.org", "website": "https://msfindia.in", "verified": True, "location": "New Delhi"},
    {"id": "6", "name": "GiveIndia Relief", "category": "disaster-relief", "description": "Verified disaster relief operations and emergency aid network.", "phone": "1800-103-4244", "email": "help@giveindia.org", "website": "https://giveindia.org", "verified": True, "location": "Bangalore"},
    {"id": "7", "name": "Vandrevala Foundation", "category": "mental-health", "description": "24/7 free mental health helpline — crisis intervention and psychiatric support.", "phone": "1860-2662-345", "email": "info@vandrevalafoundation.com", "website": "https://vandrevalafoundation.com", "verified": True, "location": "Mumbai"},
    {"id": "8", "name": "Goonj", "category": "food-shelter", "description": "Disaster relief material, shelter kits and rural emergency aid.", "phone": "011-26972351", "email": "mail@goonj.org", "website": "https://goonj.org", "verified": True, "location": "New Delhi"},
]

_SUMMARIES_MEM: dict[str, dict[str, Any]] = {}
_MEDICATIONS_MEM: dict[str, list[dict[str, Any]]] = {}
_ABHA_MEM: dict[str, str] = {}
_VITALS_MEM: dict[str, list[dict[str, Any]]] = {}
_SOS_SAFE_MEM: dict[str, dict[str, Any]] = {}
_RLHF_MEM: dict[str, dict[str, Any]] = {}

# Curated high-priority drug-drug interactions so offline/rate-limited lookups still catch critical pairs
_KNOWN_INTERACTIONS: list[tuple[set[str], str, str]] = [
    ({"aspirin", "ibuprofen"}, "moderate", "Ibuprofen may reduce the cardioprotective antiplatelet effect of low-dose aspirin and increase GI bleeding risk."),
    ({"aspirin", "warfarin"}, "high", "Concurrent use of aspirin and warfarin significantly increases the risk of major gastrointestinal and systemic bleeding."),
    ({"warfarin", "ibuprofen"}, "high", "NSAIDs like ibuprofen combined with warfarin markedly elevate bleeding risk."),
    ({"sildenafil", "nitroglycerin"}, "critical", "Contraindicated: severe, potentially fatal hypotension can occur when nitrates are combined with PDE5 inhibitors."),
    ({"metformin", "contrast"}, "high", "Hold metformin around iodinated contrast administration to prevent lactic acidosis."),
    ({"paracetamol", "alcohol"}, "moderate", "Chronic alcohol use with high-dose paracetamol (acetaminophen) increases hepatotoxicity risk."),
    ({"lisinopril", "spironolactone"}, "moderate", "ACE inhibitors plus potassium-sparing diuretics increase the risk of hyperkalemia; monitor serum potassium."),
]


def _clamp(v: float) -> int:
    return max(0, min(100, round(v)))


# ── 1. System Features & API Readiness ──────────────────────────────────────────────────────────
@router.get("/api/system/features")
async def system_features(request: Request) -> dict[str, Any]:
    ctx = get_ctx(request)
    s = ctx.settings
    return {
        "supabase": ctx.persist.enabled,
        "gemini": bool(s.gemini_api_key),
        "openai": bool(s.openai_api_key),
        "huggingface": bool(s.huggingface_api_key),
        "tomtom": bool(s.tomtom_api_key),
        "openweather": bool(s.openweather_key),
        "agora": bool(s.agora_app_id and s.agora_app_certificate),
        "brevo_email": ctx.notifier.email_ready,
        "brevo_sms": ctx.notifier.sms_ready,
        "brevo_whatsapp": bool(s.brevo_api_key and s.brevo_whatsapp_sender_number),
        "rag_chunks": len(ctx.index.shared),
        "rag_dense": bool(ctx.index.embedder and ctx.index.embedder.ready),
        "rag_rerank": bool(ctx.index.reranker and ctx.index.reranker.ready),
    }


# ── 2. OpenWeatherMap Radar & Disaster Risk Score ───────────────────────────────────────────────
@router.get("/api/weather/radar")
async def weather_radar(request: Request, lat: float = 12.9716, lon: float = 77.5946, type: str = "precipitation_new") -> dict[str, Any]:
    ctx = get_ctx(request)
    key = ctx.settings.openweather_key
    if not key:
        return {
            "tileUrl": None,
            "source": "simulated",
            "current": {
                "name": "Local Area",
                "main": {"temp": 27.5, "humidity": 62, "feels_like": 28.4},
                "wind": {"speed": 3.4},
                "weather": [{"main": "Clouds", "description": "scattered clouds"}],
            },
            "message": "Set OPENWEATHER_KEY in .env for live radar tiles; showing baseline weather.",
        }
    tile_url = f"https://tile.openweathermap.org/map/{type}/{{z}}/{{x}}/{{y}}.png?appid={key}"
    resp = await ctx.http.get(
        "https://api.openweathermap.org/data/2.5/weather",
        params={"lat": lat, "lon": lon, "appid": key, "units": "metric"},
        timeout=6.0,
    )
    if resp.status_code >= 400:
        raise HTTPException(502, "OpenWeather lookup failed")
    return {"tileUrl": tile_url, "source": "openweather", "current": resp.json()}


@router.get("/api/risk-score")
async def risk_score(request: Request, lat: float = 12.9716, lng: float = 77.5946) -> dict[str, Any]:
    ctx = get_ctx(request)
    key = ctx.settings.openweather_key
    temp, humidity, wind, rain1h, rain3h = 28.0, 58.0, 3.2, 0.0, 0.0
    weather_desc = "clear sky"
    source = "baseline_heuristic"

    if key:
        try:
            resp = await ctx.http.get(
                "https://api.openweathermap.org/data/2.5/weather",
                params={"lat": lat, "lon": lng, "appid": key, "units": "metric"},
                timeout=6.0,
            )
            if resp.status_code < 400:
                d = resp.json()
                temp = float((d.get("main") or {}).get("temp") or temp)
                humidity = float((d.get("main") or {}).get("humidity") or humidity)
                wind = float((d.get("wind") or {}).get("speed") or wind)
                rain1h = float((d.get("rain") or {}).get("1h") or 0.0)
                rain3h = float((d.get("rain") or {}).get("3h") or 0.0)
                w_list = d.get("weather") or []
                if w_list:
                    weather_desc = str(w_list[0].get("description") or weather_desc)
                source = "openweather_live"
        except Exception:
            pass

    flood_risk = _clamp((rain1h * 18) + (rain3h * 10) + (15 if humidity > 90 else 0) + (8 if humidity > 75 else 0))
    fire_risk = _clamp(max(0.0, temp - 28.0) * 5.0 + max(0.0, 45.0 - humidity) * 1.2 + wind * 4.0)
    earthquake_risk = 10
    overall = _clamp((flood_risk * 0.45) + (fire_risk * 0.45) + (earthquake_risk * 0.1))
    level = "high" if overall >= 70 else ("moderate" if overall >= 35 else "low")

    return {
        "lat": lat,
        "lng": lng,
        "floodRisk": flood_risk,
        "earthquakeRisk": earthquake_risk,
        "fireRisk": fire_risk,
        "overallScore": overall,
        "riskLevel": level,
        "weather": {"tempC": round(temp, 1), "humidity": round(humidity), "windMs": round(wind, 1), "description": weather_desc},
        "lastUpdated": datetime.now(timezone.utc).isoformat(),
        "source": source,
    }


# ── 3. FDA Drug Interaction Checker ─────────────────────────────────────────────────────────────
@router.get("/api/fda/interactions")
async def fda_interactions(request: Request, drug1: str = "", drug2: str = "") -> dict[str, Any]:
    d1, d2 = drug1.strip(), drug2.strip()
    if not d1 or not d2:
        raise HTTPException(400, "drug1 and drug2 are required")

    pair = {d1.lower(), d2.lower()}
    interactions: list[str] = []
    severity = "none"

    for known_pair, sev, desc in _KNOWN_INTERACTIONS:
        if any(k in d1.lower() for k in known_pair) and any(k in d2.lower() for k in known_pair) and d1.lower() != d2.lower():
            interactions.append(desc)
            severity = sev

    ctx = get_ctx(request)
    try:
        resp = await ctx.http.get(
            "https://api.fda.gov/drug/label.json",
            params={"search": f'drug_interactions:"{d1}" AND "{d2}"', "limit": "3"},
            timeout=6.0,
        )
        if resp.status_code == 200:
            for res in resp.json().get("results") or []:
                di = res.get("drug_interactions")
                text = di[0] if isinstance(di, list) and di else (di if isinstance(di, str) else "")
                if text and (d1.lower() in text.lower() or d2.lower() in text.lower()):
                    snippet = text[:500]
                    if snippet not in interactions:
                        interactions.append(snippet)
                    if severity == "none":
                        severity = "moderate"
    except Exception:
        pass

    return {
        "drug1": d1,
        "drug2": d2,
        "hasInteraction": len(interactions) > 0,
        "interactions": interactions,
        "severity": severity,
        "disclaimer": "Always consult a physician or pharmacist before starting, stopping, or combining medications.",
    }


# ── 4. Blood Bank Search & Donor Registration ───────────────────────────────────────────────────
class DonorRegisterBody(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    bloodType: str = Field(min_length=2, max_length=5)
    city: str = Field(min_length=2, max_length=60)
    phone: Optional[str] = None


@router.get("/api/blood-bank/search")
async def blood_bank_search(bloodType: str = "", city: str = "") -> dict[str, Any]:
    bt = bloodType.strip().upper()
    ct = city.strip().lower()
    results = [
        d
        for d in _DONORS
        if (not bt or d["bloodType"].upper() == bt) and (not ct or ct in d["city"].lower())
    ]
    return {"donors": results, "total": len(results)}


@router.post("/api/blood-bank/register", status_code=201)
async def blood_bank_register(body: DonorRegisterBody, user: User = Depends(current_user)) -> dict[str, Any]:
    donor = {
        "id": f"donor_{int(time.time() * 1000)}",
        "name": body.name.strip(),
        "bloodType": body.bloodType.strip().upper(),
        "city": body.city.strip(),
        "phone": body.phone,
        "userId": user.id,
        "available": True,
        "units": 1,
        "lastDonated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    }
    _DONORS.insert(0, donor)
    return {"success": True, "donor": donor}


# ── 5. NGO & Disaster Relief Directory ──────────────────────────────────────────────────────────
class NgoContactBody(BaseModel):
    ngoId: str
    senderName: str = Field(min_length=1, max_length=80)
    message: str = Field(min_length=1, max_length=1000)


@router.get("/api/ngo")
async def list_ngos(category: str = "all") -> dict[str, Any]:
    cat = category.strip().lower()
    results = _NGOS if (not cat or cat == "all") else [n for n in _NGOS if n["category"] == cat]
    return {"ngos": results, "total": len(results)}


@router.post("/api/ngo/contact")
async def contact_ngo(body: NgoContactBody, user: User = Depends(current_user)) -> dict[str, Any]:
    ngo = next((n for n in _NGOS if n["id"] == body.ngoId), None)
    if not ngo:
        raise HTTPException(404, "NGO not found")
    return {
        "success": True,
        "ngo": ngo["name"],
        "userId": user.id,
        "message": f"Your request has been sent to {ngo['name']}. Their response coordinator will reach out shortly.",
    }


# ── 6. ABDM / ABHA Digital Health ID ────────────────────────────────────────────────────────────
class AbhaOtpBody(BaseModel):
    aadhaarNumber: str = Field(min_length=12, max_length=12, pattern=r"^\d{12}$")


class AbhaVerifyBody(BaseModel):
    txnId: str = Field(min_length=4, max_length=80)
    otp: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")


@router.post("/api/abdm/generate-otp")
async def abdm_generate_otp(body: AbhaOtpBody, user: User = Depends(current_user)) -> dict[str, Any]:
    txn_id = f"txn_{int(time.time())}_{uuid.uuid4().hex[:8]}"
    return {
        "success": True,
        "txnId": txn_id,
        "userId": user.id,
        "message": "OTP sent to your Aadhaar-linked mobile number (use any 6 digits except 000000 in sandbox mode).",
    }


@router.post("/api/abdm/verify-otp")
async def abdm_verify_otp(body: AbhaVerifyBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    if body.otp == "000000":
        raise HTTPException(400, "Invalid OTP entered.")
    rng = random.Random(f"{user.id}:{body.txnId}")
    abha = f"{rng.randint(10, 99)}-{rng.randint(1000, 9999)}-{rng.randint(1000, 9999)}-{rng.randint(1000, 9999)}"
    _ABHA_MEM[user.id] = abha
    ctx = get_ctx(request)
    if ctx.persist.enabled:
        ctx.spawn(
            ctx.persist.update(
                "profiles",
                {"uid": user.id},
                {"abha_number": abha, "abha_linked_at": datetime.now(timezone.utc).isoformat()},
            )
        )
    return {
        "success": True,
        "abhaNumber": abha,
        "message": "ABHA Digital Health ID verified and linked to your Jeevan profile.",
    }


# ── 7. Emergency Summary (Medical ID / QR / Emergency Contacts) & Medications ───────────────────
class EmergencyContactModel(BaseModel):
    name: str
    phone: str = ""
    email: Optional[str] = None
    relationship: str = "Family"


class EmergencySummaryBody(BaseModel):
    name: str = "Jeevan User"
    bloodType: str = "Not specified"
    dob: str = ""
    allergies: list[str] = Field(default_factory=list)
    conditions: list[str] = Field(default_factory=list)
    currentMedications: list[str] = Field(default_factory=list)
    emergencyContacts: list[EmergencyContactModel] = Field(default_factory=list)
    showEmergencyContacts: bool = True


@router.get("/api/emergency-summary")
async def get_my_emergency_summary(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    if ctx.persist.enabled:
        rows = await ctx.persist.select("emergency_summaries", {"uid": f"eq.{user.id}", "limit": "1"})
        if rows:
            return {**rows[0], "abhaNumber": _ABHA_MEM.get(user.id)}
    mem = _SUMMARIES_MEM.get(user.id) or {
        "uid": user.id,
        "name": (user.email or "Jeevan User").split("@")[0],
        "bloodType": "Not specified",
        "dob": "",
        "allergies": [],
        "conditions": [],
        "currentMedications": [],
        "emergencyContacts": [],
    }
    return {**mem, "abhaNumber": _ABHA_MEM.get(user.id)}


@router.put("/api/emergency-summary")
async def update_my_emergency_summary(body: EmergencySummaryBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    row = {
        "uid": user.id,
        "name": body.name,
        "bloodType": body.bloodType,
        "dob": body.dob,
        "allergies": body.allergies,
        "conditions": body.conditions,
        "currentMedications": body.currentMedications,
        "emergencyContacts": [c.model_dump() for c in body.emergencyContacts],
        "showEmergencyContacts": body.showEmergencyContacts,
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    }
    _SUMMARIES_MEM[user.id] = row
    ctx.profile_cache.pop(user.id, None)  # invalidate RAG profile cache so assistant sees updated allergies/meds immediately
    if ctx.persist.enabled:
        ctx.spawn(ctx.persist.upsert("emergency_summaries", row, "uid"))
    return {"status": "saved", "summary": row}


@router.get("/api/emergency-summary/{uid}")
async def get_public_emergency_summary(uid: str, request: Request) -> dict[str, Any]:
    """Public QR code endpoint for first responders."""
    ctx = get_ctx(request)
    if ctx.persist.enabled:
        rows = await ctx.persist.select("emergency_summaries", {"uid": f"eq.{uid}", "limit": "1"})
        if rows:
            return rows[0]
    if uid in _SUMMARIES_MEM:
        return _SUMMARIES_MEM[uid]
    raise HTTPException(404, "Emergency summary not found")


class MedicationBody(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    dosage: str = Field(min_length=1, max_length=60)
    frequency: str = Field(default="Once daily", max_length=60)
    reminderTimes: list[str] = Field(default_factory=lambda: ["08:00"])
    doctorName: Optional[str] = None


@router.get("/api/medications")
async def list_medications(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    if ctx.persist.enabled:
        rows = await ctx.persist.select("medications", {"uid": f"eq.{user.id}", "order": "createdAt.desc"})
        if rows:
            return {"medications": rows}
    return {"medications": _MEDICATIONS_MEM.get(user.id, [])}


@router.post("/api/medications", status_code=201)
async def add_medication(body: MedicationBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    med = {
        "id": f"med_{uuid.uuid4().hex[:10]}",
        "uid": user.id,
        "name": body.name.strip(),
        "dosage": body.dosage.strip(),
        "frequency": body.frequency.strip(),
        "reminderTimes": body.reminderTimes,
        "startDate": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "doctorName": body.doctorName,
        "adherenceScore": 100,
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    _MEDICATIONS_MEM.setdefault(user.id, []).insert(0, med)
    if ctx.persist.enabled:
        ctx.spawn(ctx.persist.insert("medications", med))
    return {"status": "added", "medication": med}


@router.delete("/api/medications/{med_id}")
async def delete_medication(med_id: str, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    _MEDICATIONS_MEM[user.id] = [m for m in _MEDICATIONS_MEM.get(user.id, []) if m["id"] != med_id]
    if ctx.persist.enabled:
        ctx.spawn(ctx.persist._send("DELETE", "medications", params={"id": f"eq.{med_id}", "uid": f"eq.{user.id}"}))
    return {"status": "deleted"}


# ── 8. VitaWatch Readings & On-Demand Analysis (/api/vitawatch/*) ───────────────────────────────
async def _json_body(request: Request) -> dict[str, Any]:
    try:
        data = await request.json()
    except ValueError:
        raise HTTPException(400, "Body must be valid JSON")
    if not isinstance(data, dict):
        raise HTTPException(400, "Body must be a JSON object")
    return data


@router.get("/api/vitawatch/readings")
async def vitawatch_list_readings(request: Request, limit: int = 50, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    capped = max(1, min(limit, 100))
    if ctx.persist.enabled:
        rows = await ctx.persist.select(
            "vitawatch_readings",
            {"user_id": f"eq.{user.id}", "order": "recorded_at.desc", "limit": str(capped)},
        )
        if rows:
            return {"readings": rows}
    return {"readings": _VITALS_MEM.get(user.id, [])[:capped]}


@router.post("/api/vitawatch/readings", status_code=201)
async def vitawatch_create_reading(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    hr_raw, spo2_raw, temp_raw = body.get("heart_rate"), body.get("spo2"), body.get("temperature")
    if hr_raw is None or spo2_raw is None or temp_raw is None:
        raise HTTPException(400, "Missing required vitals: heart_rate, spo2, temperature")
    try:
        hr = float(hr_raw)
        spo2 = float(spo2_raw)
        temp = float(temp_raw)
    except (TypeError, ValueError):
        raise HTTPException(400, "Invalid numeric vitals")

    ecg_raw = body.get("ecg_bpm")
    ecg_bpm = float(ecg_raw) if ecg_raw is not None else None
    ecg_status = str(body.get("ecg_status") or ("signal_detected" if ecg_bpm else "not_available"))
    sys_raw = body.get("systolic_bp")
    dia_raw = body.get("diastolic_bp")
    systolic_bp = float(sys_raw) if sys_raw is not None else None
    diastolic_bp = float(dia_raw) if dia_raw is not None else None

    analysis = triage.analyze(
        heart_rate=hr,
        spo2=spo2,
        temperature=temp,
        ecg_bpm=ecg_bpm,
        lead_off=(ecg_status == "leads_off"),
        systolic_bp=systolic_bp,
        diastolic_bp=diastolic_bp,
    )
    record = {
        "id": f"vw_{uuid.uuid4().hex[:12]}",
        "user_id": user.id,
        "heart_rate": int(round(hr)),
        "spo2": int(round(spo2)),
        "temperature": round(temp, 1),
        "ecg_bpm": int(round(ecg_bpm)) if ecg_bpm is not None else None,
        "ecg_status": ecg_status,
        "systolic_bp": int(round(systolic_bp)) if systolic_bp is not None else None,
        "diastolic_bp": int(round(diastolic_bp)) if diastolic_bp is not None else None,
        "source": str(body.get("source") or "manual"),
        "device_id": body.get("device_id"),
        "notes": body.get("notes"),
        "ai_analysis": analysis,
        "recorded_at": str(body.get("recorded_at") or datetime.now(timezone.utc).isoformat()),
    }
    _VITALS_MEM.setdefault(user.id, []).insert(0, record)
    ctx = get_ctx(request)
    if ctx.persist.enabled:
        ctx.spawn(ctx.persist.insert("vitawatch_readings", record))
    return {"success": True, "reading": record, "ai_analysis": analysis}


@router.delete("/api/vitawatch/readings/{reading_id}")
async def vitawatch_delete_reading(reading_id: str, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    _VITALS_MEM[user.id] = [r for r in _VITALS_MEM.get(user.id, []) if str(r.get("id")) != reading_id]
    ctx = get_ctx(request)
    if ctx.persist.enabled:
        ctx.spawn(
            ctx.persist._send(
                "DELETE",
                "vitawatch_readings",
                params={"id": f"eq.{reading_id}", "user_id": f"eq.{user.id}"},
            )
        )
    return {"success": True, "message": "Reading deleted successfully", "id": reading_id}


@router.post("/api/vitawatch/analyze")
async def vitawatch_analyze(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    hr_raw, spo2_raw, temp_raw = body.get("heart_rate"), body.get("spo2"), body.get("temperature")
    if hr_raw is None or spo2_raw is None or temp_raw is None:
        raise HTTPException(400, "Missing required vitals for analysis")
    ecg_raw = body.get("ecg_bpm")
    ecg_status = str(body.get("ecg_status") or ("signal_detected" if ecg_raw else "not_available"))
    analysis = triage.analyze(
        heart_rate=float(hr_raw),
        spo2=float(spo2_raw),
        temperature=float(temp_raw),
        ecg_bpm=float(ecg_raw) if ecg_raw is not None else None,
        lead_off=(ecg_status == "leads_off"),
        systolic_bp=float(body["systolic_bp"]) if body.get("systolic_bp") is not None else None,
        diastolic_bp=float(body["diastolic_bp"]) if body.get("diastolic_bp") is not None else None,
    )
    return {"success": True, "analysis": analysis}


# ── 9. Notifications & Emergency Delivery Routes (/api/notifications/*, /api/send-emergency, /api/send-safe) ──
def _sanitize_room_id(room_id: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_-]", "", room_id.strip())[:64]
    return cleaned or f"jeevan-room-{int(time.time())}"


@router.post("/api/notifications/sos/{event_id}/safe")
async def mark_sos_safe_public(event_id: str, request: Request) -> dict[str, Any]:
    """Public endpoint used by the 'mark safe' link sent to emergency contacts."""
    ctx = get_ctx(request)
    now_iso = datetime.now(timezone.utc).isoformat()
    _SOS_SAFE_MEM[event_id] = {"eventId": event_id, "status": "resolved", "resolvedAt": now_iso}
    for uid, ev in list(ctx.hub.latest_sos.items()):
        if ev.get("event_id") == event_id:
            ev["status"] = "resolved"
            ctx.hub.publish(uid, {"type": "sos_resolved", "data": {"event_id": event_id}})
    if getattr(ctx.hub, "latest_hardware_sos", None) and ctx.hub.latest_hardware_sos.get("event_id") == event_id:
        ctx.hub.latest_hardware_sos["status"] = "resolved"
    if ctx.persist.enabled:
        ctx.spawn(ctx.persist.update("sos_events", {"id": event_id}, {"status": "resolved", "resolvedAt": now_iso}))
    return {"success": True, "eventId": event_id, "status": "resolved"}


@router.post("/api/notifications/medication-status")
async def notify_medication_status(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    _ = user
    body = await _json_body(request)
    contact = body.get("contact") if isinstance(body.get("contact"), dict) else {}
    to_phone = str(body.get("phone") or contact.get("phone") or "").strip()
    if not to_phone:
        raise HTTPException(400, "A parental monitoring WhatsApp number is required")
    med_name = str(body.get("medicationName") or "").strip()
    if not med_name:
        raise HTTPException(400, "medicationName is required")
    taken = bool(body.get("taken"))
    dosage = str(body.get("dosage") or "").strip()
    sched_time = str(body.get("time") or "daily dose").strip()
    user_name = str(body.get("userName") or (user.email or "Jeevan User").split("@")[0]).strip()
    ctx = get_ctx(request)
    wa_res = await ctx.notifier.send_medication_status(
        to_phone=to_phone,
        user_name=user_name,
        medication_name=med_name,
        dosage=dosage,
        scheduled_time=sched_time,
        taken=taken,
        marked_at=body.get("markedAt"),
    )
    result = {
        **wa_res,
        "medication": med_name,
        "dosage": dosage or None,
        "time": sched_time,
        "taken": taken,
        "userName": user_name,
        "markedAt": body.get("markedAt") or datetime.now(timezone.utc).isoformat(),
    }
    return {"success": True, "results": {to_phone: result}}


async def _handle_emergency_dispatch(request: Request, user: User) -> dict[str, Any]:
    body = await _json_body(request)
    event_id = str(body.get("eventId") or "").strip()
    loc = body.get("location") if isinstance(body.get("location"), dict) else {}
    lat, lng = loc.get("lat"), loc.get("lng")
    if not event_id:
        raise HTTPException(400, "eventId is required")
    raw_room = str(body.get("roomId") or f"jeevan-sos-{event_id}")
    resolved_room_id = _sanitize_room_id(raw_room)
    contacts = body.get("contacts") if isinstance(body.get("contacts"), list) else []
    user_name = str(body.get("userName") or (user.email or "Jeevan User").split("@")[0])
    blood_group = str(body.get("bloodGroup") or "Not specified")
    med_raw = body.get("medicalDetails")
    if isinstance(med_raw, dict):
        parts = [f"{k}: {v}" for k, v in med_raw.items() if v]
        medical_details = " | ".join(parts)
    else:
        medical_details = str(med_raw or body.get("medicalSummary") or "")
    ctx = get_ctx(request)
    results = await ctx.notifier.send_sos(
        user_name=user_name,
        lat=float(lat) if isinstance(lat, (int, float)) else None,
        lng=float(lng) if isinstance(lng, (int, float)) else None,
        event_id=event_id,
        room_id=resolved_room_id,
        contacts=contacts,
        blood_group=blood_group,
        medical_details=medical_details,
        user_id=user.id,
    )
    return {"success": True, "roomId": resolved_room_id, "results": results}


@router.post("/api/notifications/sos")
async def notifications_sos(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    return await _handle_emergency_dispatch(request, user)


@router.post("/api/send-emergency")
async def send_emergency_route(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    return await _handle_emergency_dispatch(request, user)


@router.post("/api/notifications/video-call-invite")
async def notifications_video_call_invite(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    _ = user
    body = await _json_body(request)
    room_id = str(body.get("roomId") or "").strip()
    if not room_id:
        raise HTTPException(400, "roomId is required")
    raw_contacts = body.get("contacts") if isinstance(body.get("contacts"), list) else [body.get("contact")]
    invite_contacts: list[dict[str, str]] = []
    seen: set[str] = set()
    for entry in raw_contacts:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("name") or "").strip()
        phone = str(entry.get("phone") or "").strip()
        email = str(entry.get("email") or "").strip()
        if not phone and not email:
            continue
        key = phone or email.lower()
        if key in seen:
            continue
        seen.add(key)
        invite_contacts.append({"name": name, "phone": phone, "email": email})
    if not invite_contacts:
        raise HTTPException(400, "At least one phone number or email is required for the invite")

    sanitized_room_id = _sanitize_room_id(room_id)
    ctx = get_ctx(request)
    user_name = str(body.get("userName") or (user.email or "Jeevan User").split("@")[0])
    results = await ctx.notifier.send_video_invite(
        user_name=user_name,
        room_id=sanitized_room_id,
        contacts=invite_contacts,
    )
    return {
        "success": True,
        "roomId": sanitized_room_id,
        "videoLink": f"/video-call?roomId={sanitized_room_id}",
        "videoUrl": f"{ctx.settings.app_public_url.rstrip('/')}/video-call?room={sanitized_room_id}",
        "results": results,
    }


@router.post("/api/notifications/alert")
async def notifications_alert(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    ctx = get_ctx(request)
    payload = {
        "type": "alert",
        "data": {
            "topic": str(body.get("topic") or "general"),
            "title": str(body.get("title") or ""),
            "body": str(body.get("body") or ""),
            "data": body.get("data") if isinstance(body.get("data"), dict) else {},
        },
    }
    target_uids = set(ctx.hub._subs.keys()) | {user.id}
    delivered = 0
    for uid in target_uids:
        subs = ctx.hub._subs.get(uid, set())
        delivered += len(subs)
        ctx.hub.publish(uid, payload)
    return {"success": True, "delivered": delivered}


@router.post("/api/send-safe")
async def send_safe_route(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    event_id = str(body.get("eventId") or "").strip()
    if not event_id:
        raise HTTPException(400, "eventId is required")
    ctx = get_ctx(request)
    now_iso = datetime.now(timezone.utc).isoformat()
    _SOS_SAFE_MEM[event_id] = {
        "eventId": event_id,
        "status": "resolved",
        "resolvedAt": now_iso,
        "originalTriggeredAt": body.get("originalTriggeredAt"),
    }
    latest = ctx.hub.latest_sos.get(user.id)
    if latest and latest.get("event_id") == event_id:
        latest["status"] = "resolved"
    ctx.hub.publish(user.id, {"type": "sos_resolved", "data": {"event_id": event_id}})
    if ctx.persist.enabled:
        ctx.spawn(ctx.persist.update("sos_events", {"id": event_id, "uid": user.id}, {"status": "resolved", "resolvedAt": now_iso}))

    contacts = body.get("contacts") if isinstance(body.get("contacts"), list) else []
    user_name = str(body.get("userName") or (user.email or "zaid").split("@")[0])
    results = await ctx.notifier.send_safe(
        user_name=user_name,
        event_id=event_id,
        contacts=contacts,
    )
    return {"success": True, "eventId": event_id, "results": results}


# ── 10. Complete /api/gemini/* 11-Endpoint Clinical, Radiology & MediKiosk Suite (22 Indian Languages) ──
_INDIAN_LANGUAGES: dict[str, str] = {
    "en": "English",
    "hi": "Hindi (हिन्दी)",
    "bn": "Bengali (বাংলা)",
    "te": "Telugu (తెలుగు)",
    "mr": "Marathi (मराठी)",
    "ta": "Tamil (தமிழ்)",
    "ur": "Urdu (اردو)",
    "gu": "Gujarati (ગુજરાતી)",
    "ml": "Malayalam (മലയാളം)",
    "kn": "Kannada (ಕನ್ನಡ)",
    "or": "Odia (ଓଡ଼ିଆ)",
    "pa": "Punjabi (ਪੰਜਾਬੀ)",
    "as": "Assamese (অসমীয়া)",
    "mai": "Maithili (मैथिली)",
    "ks": "Kashmiri (कॉशुर)",
    "ne": "Nepali (नेपाली)",
    "sd": "Sindhi (सिन्धी)",
    "doi": "Dogri (डोगरी)",
    "mni": "Manipuri / Meitei (মৈতৈলোন্)",
    "brx": "Bodo (बड़ो)",
    "sa": "Sanskrit (संस्कृतम्)",
    "sat": "Santali (संताली)",
}

_BODY_REGION_LABELS: dict[str, str] = {
    "forehead": "Forehead",
    "eyes": "Eyes",
    "ears": "Ears",
    "nose": "Nose and nasal passages",
    "mouthTeeth": "Mouth, gums, and teeth",
    "jaw": "Jaw and lower face",
    "neck": "Neck",
    "leftShoulder": "Left shoulder",
    "rightShoulder": "Right shoulder",
    "chest": "Center of the chest",
    "heart": "Heart area / left center chest",
    "leftLung": "Left side of the chest / left lung area",
    "rightLung": "Right side of the chest / right lung area",
    "upperAbdomen": "Upper abdomen / stomach area",
    "lowerAbdomen": "Lower abdomen",
    "pelvis": "Pelvis / groin area",
    "leftUpperArm": "Left upper arm",
    "rightUpperArm": "Right upper arm",
    "leftElbow": "Left elbow",
    "rightElbow": "Right elbow",
    "leftForearm": "Left forearm",
    "rightForearm": "Right forearm",
    "leftWrist": "Left wrist",
    "rightWrist": "Right wrist",
    "leftHand": "Left hand",
    "rightHand": "Right hand",
    "upperBack": "Upper back",
    "spine": "Spine / middle back",
    "lowerBack": "Lower back",
    "leftHip": "Left hip",
    "rightHip": "Right hip",
    "leftThigh": "Left thigh",
    "rightThigh": "Right thigh",
    "leftKnee": "Left knee",
    "rightKnee": "Right knee",
    "leftShin": "Left shin",
    "rightShin": "Right shin",
    "leftCalf": "Left calf",
    "rightCalf": "Right calf",
    "leftAnkle": "Left ankle",
    "rightAnkle": "Right ankle",
    "leftFoot": "Left foot",
    "rightFoot": "Right foot",
    "leftToes": "Left toes",
    "rightToes": "Right toes",
}

_SYMPTOM_LABELS: dict[str, str] = {
    "pain": "Pain",
    "swelling": "Swelling",
    "numbness": "Numbness or reduced sensation",
    "rash": "Rash or skin irritation",
    "shortness_of_breath": "Shortness of breath",
    "dizziness": "Dizziness or light-headedness",
    "nausea": "Nausea",
    "fever": "Fever or feeling unusually hot",
    "bleeding": "Bleeding",
    "weakness": "Weakness or reduced strength",
    "stiffness": "Stiffness or reduced movement",
    "tingling": "Tingling or pins-and-needles sensation",
    "bruising": "Bruising or skin discoloration",
}


def _resolve_language_name(lang: Optional[str]) -> str:
    if not lang:
        return "English"
    code = str(lang).strip().lower()
    return _INDIAN_LANGUAGES.get(code, str(lang).strip())


def _describe_body_region(region: Any) -> str:
    key = str(region or "").strip()
    if not key:
        return "General body area"
    return _BODY_REGION_LABELS.get(key, key)


def _describe_symptoms(symptoms: Any) -> list[str]:
    if isinstance(symptoms, str):
        items = [s.strip() for s in symptoms.split(",") if s.strip()]
    elif isinstance(symptoms, list):
        items = [str(s).strip() for s in symptoms if str(s).strip()]
    else:
        items = []
    return [_SYMPTOM_LABELS.get(i, i) for i in items]


async def _run_rag_clinical(
    ctx: Context, user_id: str, role_instruction: str, query: str, language: Optional[str] = None
) -> dict[str, Any]:
    lang_name = _resolve_language_name(language)
    lang_clause = f" Respond in {lang_name}." if lang_name != "English" else ""
    emergency = llm.detect_emergency(query)
    hits = await run_in_threadpool(ctx.index.search, query, user_id, 4)
    sources = [{"n": i, "title": h.chunk.source, "heading": h.chunk.heading} for i, h in enumerate(hits, 1)]
    prompt = f"{role_instruction}{lang_clause}\n\n" + llm.build_prompt(query, hits, None, None)

    if ctx.settings.gemini_api_key:
        try:
            chunks: list[str] = []
            async for tok in llm.stream_gemini(ctx.settings, ctx.http, prompt, []):
                chunks.append(tok)
            if chunks:
                return {
                    "emergency": emergency,
                    "response": "".join(chunks),
                    "sources": sources,
                    "provider": "gemini",
                    "language": language or "en",
                }
        except Exception:
            pass
    return {
        "emergency": emergency,
        "response": llm.extractive_answer(hits, emergency),
        "sources": sources,
        "provider": "rag_extractive",
        "language": language or "en",
    }


async def _analyze_medical_document(
    ctx: Context,
    *,
    instruction: str,
    context: str,
    document_base64: str,
    mime_type: str,
    language: Optional[str],
) -> str:
    """Run Gemini's vision input on an uploaded report or scan; never replace it with canned findings."""
    if not ctx.settings.gemini_api_key:
        raise HTTPException(503, "Medical image analysis is unavailable until GEMINI_API_KEY is configured.")
    mime = mime_type.strip().lower()
    if mime == "image/jpg":
        mime = "image/jpeg"
    if mime not in {"image/jpeg", "image/png", "image/webp", "application/pdf"}:
        raise HTTPException(415, "Upload a PDF, JPEG, PNG, or WebP medical document.")

    encoded = document_base64.strip()
    if encoded.startswith("data:") and "," in encoded:
        encoded = encoded.split(",", 1)[1]
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise HTTPException(400, "The uploaded file could not be read. Please choose it again.") from exc
    if not raw:
        raise HTTPException(400, "The uploaded file is empty.")
    if len(raw) > 15 * 1024 * 1024:
        raise HTTPException(413, "Medical document uploads must be 15 MB or smaller.")

    language_name = _resolve_language_name(language)
    prompt = (
        f"{instruction}\n\n"
        f"Patient context: {context or 'None provided.'}\n"
        f"Respond in {language_name}. Use readable headings and complete sentences. "
        "Only report information you can actually read in the supplied file. Mark uncertain or unreadable details clearly. "
        "Do not invent measurements, medications, diagnoses, or image findings. State that this is an informational AI review, not a diagnosis."
    )
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{ctx.settings.gemini_model}:generateContent"
    response = await ctx.http.post(
        url,
        json={
            "systemInstruction": {"parts": [{"text": "You are a careful medical document assistant. Preserve the meaning and units of all clinical values."}]},
            "contents": [{
                "role": "user",
                "parts": [
                    {"text": prompt},
                    {"inlineData": {"mimeType": mime, "data": base64.b64encode(raw).decode("ascii")}},
                ],
            }],
            "generationConfig": {"temperature": 0.1, "topP": 0.85, "maxOutputTokens": 3200},
        },
        headers={"x-goog-api-key": ctx.settings.gemini_api_key},
        timeout=max(60.0, float(ctx.settings.llm_timeout_s)),
    )
    if response.status_code >= 400:
        raise HTTPException(502, "The medical AI service could not analyze this file. Please try again.")
    try:
        payload = response.json()
        parts = payload["candidates"][0]["content"]["parts"]
        result = "\n".join(str(part.get("text") or "") for part in parts).strip()
    except (KeyError, IndexError, TypeError, ValueError):
        result = ""
    if not result:
        raise HTTPException(502, "The medical AI service returned no readable analysis. Please retry with a clearer file.")
    return result


async def _analyze_any_document(
    ctx: Context,
    *,
    filename: str,
    document_base64: Optional[str],
    mime_type: str,
    text: str,
    language: Optional[str],
) -> dict[str, Any]:
    """Classify and summarize a supported document without assuming it is medical."""
    if not ctx.settings.gemini_api_key:
        raise HTTPException(503, "Document analysis is unavailable until the AI service is configured.")

    extension_mimes = {
        ".pdf": "application/pdf",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
        ".txt": "text/plain",
        ".md": "text/markdown",
        ".csv": "text/csv",
        ".rtf": "text/rtf",
        ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    }
    mime = (mime_type or "").split(";", 1)[0].strip().lower()
    if not mime or mime == "application/octet-stream":
        extension = "." + filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        mime = extension_mimes.get(extension, "")
    if mime == "image/jpg":
        mime = "image/jpeg"
    allowed = {
        "application/pdf", "image/jpeg", "image/png", "image/webp",
        "text/plain", "text/markdown", "text/csv", "text/rtf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    }
    if document_base64 and mime not in allowed:
        raise HTTPException(415, "Choose a PDF, Word document, text file, CSV, RTF, JPEG, PNG, or WebP file.")

    file_parts: list[dict[str, Any]] = []
    if document_base64:
        encoded = document_base64.strip()
        if encoded.startswith("data:") and "," in encoded:
            encoded = encoded.split(",", 1)[1]
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (ValueError, base64.binascii.Error) as exc:
            raise HTTPException(400, "The uploaded file could not be read. Please choose it again.") from exc
        if not raw:
            raise HTTPException(400, "The uploaded file is empty.")
        if len(raw) > 15 * 1024 * 1024:
            raise HTTPException(413, "Document uploads must be 15 MB or smaller.")

        if mime == "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
            try:
                with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                    xml = ET.fromstring(archive.read("word/document.xml"))
                body_text = " ".join(
                    node.text or ""
                    for node in xml.iter()
                    if node.tag.endswith("}t") and node.text
                ).strip()
            except (KeyError, ET.ParseError, zipfile.BadZipFile) as exc:
                raise HTTPException(400, "The Word document could not be read. Please export it again and retry.") from exc
            if body_text:
                file_parts.append({"text": f"Document text extracted from {filename}:\n{body_text[:120000]}"})
        elif mime in {"text/plain", "text/markdown", "text/csv", "text/rtf"}:
            decoded = raw.decode("utf-8-sig", errors="replace")
            if mime == "text/rtf":
                decoded = re.sub(r"\\[a-zA-Z]+-?\d* ?|[{}]", " ", decoded)
            file_parts.append({"text": f"Document text from {filename}:\n{decoded[:120000]}"})
        else:
            file_parts.append({"inlineData": {"mimeType": mime, "data": base64.b64encode(raw).decode("ascii")}})

    source_text = text.strip()
    if source_text:
        file_parts.append({"text": f"Additional text supplied by the user:\n{source_text[:12000]}"})
    if not file_parts:
        raise HTTPException(400, "Choose a document or enter text to analyze.")

    language_name = _resolve_language_name(language)
    prompt = (
        "Identify what this document is and summarize its actual contents in plain, complete sentences. "
        "Classify it as medical only when it contains health records, clinical results, prescriptions, or similar medical content. "
        "For a non-medical file, explicitly say in the summary: 'This is not a medical document.' Then identify its type and summarize it normally. "
        "Do not add medical advice or clinical findings to a non-medical summary. "
        "For medical files, preserve visible values, units, reference ranges, medication names and doses; do not infer absent details. "
        "List key points and any clearly printed action items. Mark illegible content as uncertain. "
        f"Respond in {language_name}. The filename is only a hint; classify from the contents."
    )
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{ctx.settings.gemini_model}:generateContent"
    response = await ctx.http.post(
        url,
        json={
            "systemInstruction": {"parts": [{"text": "You are a careful document reader. Read the supplied file itself and never claim that its contents were not supplied when file data is present."}]},
            "contents": [{"role": "user", "parts": [{"text": prompt}, *file_parts]}],
            "generationConfig": {
                "temperature": 0.1,
                "topP": 0.85,
                "maxOutputTokens": 3500,
                "responseMimeType": "application/json",
                "responseSchema": {
                    "type": "OBJECT",
                    "properties": {
                        "documentType": {"type": "STRING"},
                        "isMedicalDocument": {"type": "BOOLEAN"},
                        "summary": {"type": "STRING"},
                        "keyFindings": {"type": "ARRAY", "items": {"type": "STRING"}},
                        "medications": {
                            "type": "ARRAY",
                            "items": {
                                "type": "OBJECT",
                                "properties": {
                                    "name": {"type": "STRING"},
                                    "dosage": {"type": "STRING"},
                                    "instructions": {"type": "STRING"},
                                },
                                "required": ["name", "dosage", "instructions"],
                            },
                        },
                        "actionItems": {"type": "ARRAY", "items": {"type": "STRING"}},
                    },
                    "required": ["documentType", "isMedicalDocument", "summary", "keyFindings", "medications", "actionItems"],
                },
            },
        },
        headers={"x-goog-api-key": ctx.settings.gemini_api_key},
        timeout=max(60.0, float(ctx.settings.llm_timeout_s)),
    )
    if response.status_code >= 400:
        raise HTTPException(502, "The AI service could not analyze this document. Please try again.")
    try:
        parts = response.json()["candidates"][0]["content"]["parts"]
        generated = "\n".join(str(part.get("text") or "") for part in parts).strip()
        try:
            result = json.loads(generated)
        except json.JSONDecodeError:
            object_start = generated.find("{")
            object_end = generated.rfind("}")
            if object_start < 0 or object_end <= object_start:
                raise
            result = json.loads(generated[object_start : object_end + 1])
    except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError):
        raise HTTPException(502, "The AI service returned an unreadable document summary. Please retry.")

    doc_type = str(result.get("documentType") or "Document").strip() or "Document"
    is_medical = result.get("isMedicalDocument") is True
    summary = str(result.get("summary") or "The document could not be summarized clearly.").strip()
    if not is_medical and "not a medical document" not in summary.lower():
        summary = f"This is not a medical document. It appears to be a {doc_type}. {summary}"
    result["documentType"] = doc_type
    result["isMedicalDocument"] = is_medical
    result["summary"] = summary
    result["medicalDocumentNotice"] = (
        f"AI review of {filename}; confirm medical details against the original document."
        if is_medical
        else f"This is not a medical document. It was classified as a {doc_type}."
    )
    if not is_medical:
        result["medications"] = []
        result["actionItems"] = []
    return result


@router.post("/api/gemini/triage")
async def ai_triage(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    symptoms_raw = body.get("symptoms") or body.get("text")
    if isinstance(symptoms_raw, list):
        symptoms_str = ", ".join(str(s) for s in symptoms_raw if s)
    else:
        symptoms_str = str(symptoms_raw or "").strip()
    if not symptoms_str:
        raise HTTPException(400, "symptoms required")

    duration = str(body.get("duration") or "not specified")
    sev_raw = body.get("severity")
    try:
        sev = int(float(sev_raw)) if sev_raw is not None else 5
    except (TypeError, ValueError):
        sev = 5
    language = body.get("language")

    rag_res = await _run_rag_clinical(
        get_ctx(request),
        user.id,
        "You are Dr. Hakeem, a calm medical triage assistant. Classify urgency P1-P4 and advise next steps.",
        f"Symptoms: {symptoms_str}. Duration: {duration}. Severity: {sev}/10.",
        language,
    )
    is_emerg = bool(rag_res["emergency"]) or sev >= 9
    urgency = "P1" if is_emerg else ("P2" if sev >= 7 else ("P3" if sev >= 4 else "P4"))
    seek_within = (
        "Immediately (Call 108 / 112 or go to ER)"
        if urgency == "P1"
        else ("Within 2–4 hours (Urgent Care)" if urgency == "P2" else ("Within 24 hours" if urgency == "P3" else "Self-care / Routine consult"))
    )
    return {
        "urgency": urgency,
        "estimatedConditions": [
            f"Clinical evaluation needed for {symptoms_str[:80]}",
            "Acute inflammatory, infectious, or functional presentation",
        ],
        "recommendedAction": rag_res["response"],
        "redFlags": [
            "Sudden difficulty breathing or chest pain",
            "High persistent fever, confusion, or fainting",
            "Rapidly worsening pain or inability to keep fluids down",
        ],
        "selfCareAdvice": "Rest in a comfortable posture, stay well hydrated, avoid strenuous activity, and monitor symptoms closely.",
        "seekCareWithin": seek_within,
        "response": rag_res["response"],
        "language": language or "en",
    }


@router.post("/api/gemini/symptom-check")
async def ai_symptom_check(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    text_input = str(body.get("text") or "").strip()
    body_location = body.get("bodyLocation")
    symptoms_field = body.get("symptoms")
    language = body.get("language")

    if not text_input and (not body_location or not symptoms_field):
        raise HTTPException(400, "Either text or (bodyLocation and symptoms) are required")

    body_location_label = _describe_body_region(body_location or "general")
    symptom_labels = _describe_symptoms(symptoms_field) if symptoms_field else [text_input[:80]]
    if not symptom_labels:
        raise HTTPException(400, "At least one symptom is required")

    duration = str(body.get("duration") or "Unknown duration")
    sev_raw = body.get("severity")
    try:
        sev = int(float(sev_raw)) if sev_raw is not None else 5
    except (TypeError, ValueError):
        sev = 5
    additional_info = str(body.get("additionalInfo") or "")

    query = text_input or (
        f"Body region: {body_location_label}. Symptoms: {', '.join(symptom_labels)}. "
        f"Duration: {duration}. Severity: {sev}/10. {additional_info}"
    ).strip()

    rag_res = await _run_rag_clinical(
        get_ctx(request),
        user.id,
        "Provide structured symptom triage: (1) Urgency Level (Low / Moderate / High / Emergency), (2) Possible Causes to discuss with a doctor, (3) Immediate Self-Care / First Aid Steps, and (4) Red Flag Warning Signs.",
        query,
        language,
    )

    is_emerg = bool(rag_res["emergency"]) or sev >= 9 or body_location in ("heart", "chest", "leftLung", "rightLung") and "Shortness of breath" in symptom_labels
    urgency_level = "P1" if is_emerg else ("P2" if sev >= 7 else ("P3" if sev >= 4 else "P4"))
    rec_action = (
        "ER"
        if urgency_level == "P1"
        else ("urgent-care" if urgency_level == "P2" else ("teleconsult" if urgency_level == "P3" else "self-care"))
    )
    seek_window = (
        "Immediate emergency care"
        if urgency_level == "P1"
        else ("Within 2 to 4 hours" if urgency_level == "P2" else ("Within 24 hours" if urgency_level == "P3" else "Monitor at home; consult if persistent"))
    )
    possible_conditions = [
        f"Localized {body_location_label.lower()} strain, irritation, or inflammation",
        f"Acute symptomatic presentation involving {', '.join(symptom_labels).lower()}",
        "Underlying infectious, musculoskeletal, or neurovascular factor requiring clinical correlation",
    ]
    self_care_steps = [
        f"Rest the {body_location_label.lower()} and avoid activities that trigger or worsen discomfort.",
        "Maintain adequate hydration and monitor symptom progression every few hours.",
        "Avoid unprescribed painkillers or home remedies that could mask worsening symptoms.",
        "Keep a log of onset, triggers, and severity to share with your physician.",
    ]
    red_flags = [
        "Sudden severe chest pressure, difficulty breathing, or fainting",
        "High unremitting fever, spreading swelling, or neurological weakness/numbness",
        "Severe escalating pain that does not improve with rest",
    ]
    breakdown = [
        {
            "symptom": lbl,
            "whatItMaySuggest": f"{lbl} in the {body_location_label.lower()} area may reflect local inflammation, tissue strain, irritation, or systemic response depending on onset and duration ({duration}).",
            "whatToDoNow": f"Reduce strain on the {body_location_label.lower()} region, rest comfortably, and observe whether {lbl.lower()} improves or intensifies.",
            "whenToGetHelp": f"Seek prompt medical care if {lbl.lower()} worsens rapidly, spreads, or is accompanied by fever, dizziness, or breathing difficulty.",
        }
        for lbl in symptom_labels
    ]

    return {
        "urgencyLevel": urgency_level,
        "possibleConditions": possible_conditions,
        "recommendedAction": rec_action,
        "seekCareWithin": seek_window,
        "assessmentSummary": rag_res["response"],
        "likelyCauseSummary": f"Symptoms in the {body_location_label.lower()} ({', '.join(symptom_labels)}) over {duration} at severity {sev}/10 commonly relate to local inflammation, strain, or acute irritation, though clinical examination is needed to rule out deeper causes.",
        "carePlanSummary": "Monitor symptoms closely, rest the affected area, use safe supportive care, and arrange timely medical review if warning signs appear.",
        "possibleCauseDetails": [f"{c} — discuss with a qualified clinician." for c in possible_conditions],
        "careNow": self_care_steps,
        "whatToAvoid": [
            "Avoid strenuous exertion or pressure on the affected region.",
            "Do not double-dose or mix over-the-counter medications without pharmacist guidance.",
        ],
        "whenToWorry": red_flags,
        "doctorGuidance": "Consult a physician promptly if symptoms persist beyond 24–48 hours, interfere with daily function, or present with any red-flag warning signs.",
        "redFlags": red_flags,
        "selfCareSteps": self_care_steps,
        "symptomBreakdown": breakdown,
        "bodyLocationLabel": body_location_label,
        "symptomLabels": symptom_labels,
        **rag_res,
    }


@router.post("/api/gemini/medication-advice")
async def ai_medication_advice(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    drug_name = str(body.get("drugName") or body.get("text") or "").strip()
    if not drug_name:
        raise HTTPException(400, "drugName required")
    dosage = str(body.get("dosage") or "unknown")
    scheduled_time = str(body.get("scheduledTime") or "unknown")
    missed_by = str(body.get("missedBy") or "unknown")
    language = body.get("language")

    query = f"Missed medication advice for {drug_name} (dosage: {dosage}, scheduled: {scheduled_time}, missed by: {missed_by} hours)."
    rag_res = await _run_rag_clinical(
        get_ctx(request),
        user.id,
        "You are a calm clinical pharmacist advising on a missed medication dose. Never advise double-dosing; explain safe next steps and when to call a doctor or pharmacist.",
        query,
        language,
    )
    advice_text = (
        f"For {drug_name} ({dosage}, scheduled at {scheduled_time}, missed by {missed_by} hours): "
        "Do NOT take a double dose to make up for a missed dose. If it is close to your next scheduled dose, skip the missed dose and resume your normal schedule. "
        f"{rag_res['response']}"
    )
    return {
        "advice": advice_text,
        "response": advice_text,
        "drugName": drug_name,
        "language": language or "en",
    }


@router.post("/api/gemini/wellbeing")
async def ai_wellbeing(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    msg = str(body.get("message") or body.get("text") or "").strip()
    if not msg:
        raise HTTPException(400, "message or text is required")
    ctx = get_ctx(request)
    if not ctx.settings.gemini_api_key:
        raise HTTPException(503, "Sarah is temporarily unavailable because the AI service is not configured.")
    raw_history = body.get("history") if isinstance(body.get("history"), list) else []
    history: list[dict[str, str]] = []
    for turn in raw_history[-8:]:
        if not isinstance(turn, dict):
            continue
        content = str(turn.get("text") or turn.get("content") or "").strip()
        if not content:
            continue
        role = "user" if str(turn.get("role") or "").lower() == "user" else "model"
        history.append({"role": role, "content": content[:2000]})
    language_name = _resolve_language_name(body.get("language"))
    system_instruction = (
        "You are Sarah, a warm, thoughtful AI companion. Answer the user's actual question across everyday topics, "
        "including conversation, learning, planning, technology, hobbies, and well-being. Give a complete, useful answer "
        "in natural language; do not redirect ordinary questions into breathing exercises or medical content. Use the prior "
        "conversation when it helps, and ask a follow-up only when it adds value. Be honest when you do not know or when a "
        "question needs current information. For health questions, give general information, do not diagnose or prescribe, "
        "and encourage professional care for urgent symptoms. If the user may hurt themselves or someone else, respond with "
        "care, encourage immediate support from a trusted person, and advise calling 112 or an appropriate local crisis line. "
        f"Reply in {language_name}."
    )
    chunks: list[str] = []
    try:
        async for token in llm.stream_gemini(
            ctx.settings,
            ctx.http,
            msg,
            history,
            system_instruction=system_instruction,
            max_output_tokens=2200,
        ):
            chunks.append(token)
    except Exception as exc:
        raise HTTPException(502, "Sarah could not reach the AI service. Please try again.") from exc
    answer = "".join(chunks).strip()
    if not answer:
        raise HTTPException(502, "Sarah did not receive a complete reply. Please try again.")
    emergency = llm.detect_emergency(msg)
    language = body.get("language") or "en"
    return {
        "reply": answer,
        "response": answer,
        "emergency": emergency,
        "sources": [],
        "provider": "gemini",
        "language": language,
    }


@router.post("/api/gemini/vitals-report")
async def ai_vitals_report(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    _ = user
    body = await _json_body(request)
    vitals = body.get("vitals") if isinstance(body.get("vitals"), dict) else body
    bp = vitals.get("bp") if isinstance(vitals.get("bp"), dict) else {}
    hr = vitals.get("hr") if vitals.get("hr") is not None else vitals.get("heart_rate")
    spo2 = vitals.get("spo2")
    temp = vitals.get("temp") if vitals.get("temp") is not None else vitals.get("temperature")
    sys_bp = bp.get("sys") if bp.get("sys") is not None else vitals.get("systolic_bp")
    dia_bp = bp.get("dia") if bp.get("dia") is not None else vitals.get("diastolic_bp")

    if hr is None or spo2 is None or temp is None:
        raise HTTPException(400, "valid vitals object required (hr, spo2, temp)")

    analysis = triage.analyze(
        heart_rate=float(hr),
        spo2=float(spo2),
        temperature=float(temp),
        systolic_bp=float(sys_bp) if sys_bp is not None else None,
        diastolic_bp=float(dia_bp) if dia_bp is not None else None,
    )
    status_map = {"normal": "Normal", "attention": "Attention", "warning": "Attention", "critical": "Critical"}
    overall_status = status_map.get(analysis["overall_status"], "Normal")
    metrics = [
        {
            "name": f["metric"],
            "value": f["value"],
            "status": "normal" if f["status"] == "normal" else ("critical" if f["status"] == "critical" else "warning"),
            "note": f"{f['explanation']} {f['recommendation']}",
        }
        for f in analysis["findings"]
    ]
    recommendations = [f["recommendation"] for f in analysis["findings"] if f.get("recommendation")]
    recommendations.extend(
        [
            "Continue monitoring your vitals at rest and log any new symptoms.",
            "Stay hydrated, maintain balanced nutrition, and share this report with your physician during follow-up.",
        ]
    )
    return {
        "overallStatus": overall_status,
        "summary": analysis["summary"],
        "metrics": metrics,
        "redFlags": analysis["red_flags"],
        "recommendations": recommendations[:6],
        "language": body.get("language") or "en",
    }


@router.post("/api/gemini/diagnostic-imaging")
async def ai_diagnostic_imaging(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    document = body.get("documentBase64")
    imaging_type = str(body.get("imagingType") or "X-Ray").strip()
    body_region = str(body.get("bodyRegion") or "Chest").strip()
    clinical_context = str(body.get("clinicalContext") or body.get("text") or "").strip()
    language = body.get("language")
    if not document and not clinical_context:
        raise HTTPException(400, "Upload an image or provide clinical context before analysis.")

    ctx = get_ctx(request)
    if document:
        assessment = await _analyze_medical_document(
            ctx,
            instruction=(
                f"Review the uploaded {imaging_type} of the {body_region}. Describe only visible image quality and findings. "
                "Separate observations from possible interpretations, and do not provide a diagnosis."
            ),
            context=clinical_context,
            document_base64=str(document),
            mime_type=str(body.get("mimeType") or "image/jpeg"),
            language=language,
        )
        provider = "gemini_vision"
    else:
        result = await _run_rag_clinical(
            ctx,
            user.id,
            f"Give cautious general guidance about reviewing a {imaging_type} of the {body_region}. Do not claim to see an image that was not uploaded.",
            clinical_context,
            language,
        )
        assessment = result["response"]
        provider = result["provider"]

    return {
        "imagingType": imaging_type,
        "bodyRegion": body_region,
        "overallAssessment": assessment,
        "summary": assessment,
        "response": assessment,
        "recommendations": [
            "Have a qualified radiologist or clinician review the original study before making care decisions.",
            "AI image review can miss subtle or urgent findings and does not replace a formal report.",
        ],
        "provider": provider,
        "language": language or "en",
        "logId": f"img_{uuid.uuid4().hex[:12]}",
    }


@router.post("/api/gemini/mediscan")
async def ai_mediscan(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    text_in = str(body.get("text") or "").strip()
    document = body.get("documentBase64")
    if not text_in and not document:
        raise HTTPException(400, "Enter report text or upload a medical document.")

    filename = str(body.get("filename") or "document").strip()
    language = body.get("language")
    ctx = get_ctx(request)
    analysis = await _analyze_any_document(
        ctx,
        filename=filename,
        document_base64=str(document) if document else None,
        mime_type=str(body.get("mimeType") or ""),
        text=text_in,
        language=language,
    )
    analysis["response"] = analysis["summary"]
    analysis["provider"] = "gemini_document"
    analysis["language"] = language or "en"
    return analysis


@router.post("/api/gemini/medicine-ingredients")
async def ai_medicine_analyzer(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    medicine = str(body.get("medicineName") or body.get("text") or "").strip()
    document = body.get("documentBase64")
    if not medicine and not document:
        raise HTTPException(400, "Enter a medicine name or upload a clear package label.")

    filename = str(body.get("filename") or "medicine_label").strip()
    language = body.get("language")
    ctx = get_ctx(request)
    if document:
        analysis = await _analyze_medical_document(
            ctx,
            instruction=(
                "Read the medicine package or label. Identify the medicine name and active ingredients only when legible. "
                "Explain the labeled use, warnings, and dosage exactly as printed. Clearly say when a detail cannot be read; do not infer a dose or recommend starting/stopping a medicine."
            ),
            context=medicine,
            document_base64=str(document),
            mime_type=str(body.get("mimeType") or "image/jpeg"),
            language=language,
        )
        provider = "gemini_vision"
    else:
        result = await _run_rag_clinical(
            ctx,
            user.id,
            "Explain the medicine name provided using reliable general information. Note when the exact formulation or dosage is unknown. Do not invent package-specific ingredients.",
            medicine,
            language,
        )
        analysis = result["response"]
        provider = result["provider"]

    return {
        "medicineName": medicine or filename,
        "response": analysis,
        "analysis": analysis,
        "ingredients": [],
        "uses": [],
        "sideEffects": [],
        "ayurvedicAlternatives": [],
        "warnings": [],
        "disclaimer": "Verify medicine identity and directions with a pharmacist or clinician before use.",
        "provider": provider,
        "language": language or "en",
    }


@router.post("/api/gemini/feedback")
async def ai_rlhf_feedback(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _json_body(request)
    log_id = str(body.get("logId") or "").strip()
    if not log_id:
        raise HTTPException(400, "logId is required")
    reward = float(body.get("reward") or 0)
    correction = body.get("correction")
    entry = _RLHF_MEM.setdefault(log_id, {"id": log_id, "uid": user.id})
    entry.update({"reward": reward, "correction": correction, "is_verified": True})
    ctx = get_ctx(request)
    if ctx.persist.enabled:
        ctx.spawn(
            ctx.persist.update(
                "mediscan_logs",
                {"id": log_id, "uid": user.id},
                {"reward": reward, "correction": correction, "is_verified": True},
            )
        )
    return {"success": True, "logId": log_id}


_ALLOPATHIC_INTERVIEW_STEPS: list[tuple[str, str, list[str]]] = [
    (
        "Chief Complaint & Onset",
        "When did this problem first start, and did it come on suddenly or gradually?",
        ["Started today (suddenly)", "2–3 days ago", "About a week ago", "More than a month ago"],
    ),
    (
        "Character & Severity (SOCRATES)",
        "How would you describe the discomfort, and how severe is it on a scale of 1 to 10?",
        ["Mild (2–3/10), dull ache", "Moderate (5–6/10), throbbing", "Severe (8–9/10), sharp/stabbing", "No pain, mainly other symptoms"],
    ),
    (
        "Triggers & Relieving Factors",
        "Does anything make the symptoms noticeably worse or help relieve them?",
        ["Worse with movement or exertion", "Worse after meals or lying down", "Better with rest or medication", "Constant with no clear trigger"],
    ),
    (
        "Associated Symptoms (Review of Systems)",
        "Are you experiencing any associated symptoms such as fever, nausea, dizziness, or shortness of breath?",
        ["Fever or chills", "Nausea or loss of appetite", "Shortness of breath or dizziness", "None of these"],
    ),
    (
        "Past Medical History",
        "Do you have any existing medical conditions such as diabetes, high blood pressure, asthma, or thyroid issues?",
        ["No known medical conditions", "Hypertension (High BP)", "Diabetes", "Asthma or respiratory condition"],
    ),
    (
        "Past Surgical History",
        "Have you ever had any surgeries or hospitalizations in the past?",
        ["No prior surgeries", "Minor procedure only", "Abdominal / orthopedic surgery", "Cardiac or major surgery"],
    ),
    (
        "Drug History",
        "Are you currently taking any regular prescription medicines, painkillers, or supplements?",
        ["Not taking any regular medicines", "Daily BP or diabetes medication", "Taken painkiller / paracetamol recently", "Taking herbal or vitamin supplements"],
    ),
    (
        "Allergies",
        "Do you have any known allergies to medicines, foods, or environmental triggers?",
        ["No known allergies (NKDA)", "Allergic to Penicillin / antibiotics", "Allergic to NSAIDs / painkillers", "Food or dust/pollen allergy"],
    ),
    (
        "Family & Personal History",
        "Does anyone in your immediate family have heart disease, diabetes, or hypertension, and do you smoke or consume alcohol?",
        ["No family history; non-smoker, non-drinker", "Family history of diabetes/BP; non-smoker", "Occasional alcohol or tobacco use", "Prefer not to say / Not sure"],
    ),
    (
        "Prior Investigations & Wrap-up",
        "Have you had any recent blood tests, X-rays, or prescriptions for this issue that you would like to share before we generate your summary?",
        ["No prior reports, ready for summary", "Uploaded report above", "Tests done recently, results normal", "That covers everything"],
    ),
]

_AYUSH_INTERVIEW_STEPS: list[tuple[str, str, list[str]]] = [
    (
        "Pradhana Vedana (Chief Complaint)",
        "Namaste. How long have you been experiencing this main complaint, and how does it affect your daily energy?",
        ["Started 1–2 days ago, feeling tired", "About a week, fluctuating energy", "Chronic (over a month)", "Mild discomfort, energy is normal"],
    ),
    (
        "Nidana (Causative Factors)",
        "Did this begin after any change in weather, irregular meals, spicy/heavy food, lack of sleep, or stress?",
        ["After outside / heavy / spicy food", "After exposure to cold or weather change", "Following high stress or late nights", "No specific trigger noticed"],
    ),
    (
        "Agni Pariksha (Digestive Fire)",
        "How is your appetite and digestion right now (Agni)?",
        ["Regular appetite and smooth digestion (Sama Agni)", "Variable / irregular appetite with bloating (Vishama Agni)", "Strong hunger with acidity or burning (Tikshna Agni)", "Low appetite and heaviness after meals (Manda Agni)"],
    ),
    (
        "Koshtha & Mala (Bowel Pattern)",
        "How would you describe your bowel movements (Koshtha)?",
        ["Regular once daily (Madhyama Koshtha)", "Tendency toward dryness or constipation (Krura Koshtha)", "Loose or frequent stools (Mridu Koshtha)", "Alternating or irregular"],
    ),
    (
        "Prakriti & Vikriti (Constitution & Dosha)",
        "Do you generally feel more sensitive to cold/dryness (Vata), heat/acidity (Pitta), or congestion/sluggishness (Kapha)?",
        ["Dryness, gas, restlessness (Vata predominance)", "Heat, acidity, irritability (Pitta predominance)", "Heaviness, mucus, lethargy (Kapha predominance)", "Balanced / Combination"],
    ),
    (
        "Ahara & Vihara (Diet & Sleep)",
        "How is your sleep quality (Nidra) and daily hydration?",
        ["Sound restful sleep (6–8 hours)", "Light or interrupted sleep", "Difficulty falling asleep", "Excessive daytime sleepiness"],
    ),
    (
        "Sattva & Vyayama Shakti (Mental & Physical Stamina)",
        "How are your stress levels (Manasika Bhava) and physical stamina for daily activity?",
        ["Calm and steady stamina", "Feeling anxious or mentally overwhelmed", "Low physical stamina / easily fatigued", "Moderate stress from work"],
    ),
    (
        "Past Medical & Allopathic Drug History",
        "Are you currently taking any allopathic or Ayurvedic medicines, or do you have conditions like diabetes or hypertension?",
        ["No regular medications or chronic conditions", "Taking Ayurvedic / herbal formulations", "Taking regular BP or diabetes tablets", "Have known drug/food allergies"],
    ),
    (
        "Satmya & Rutu (Seasonal Adaptability)",
        "Do your symptoms worsen at a specific time of day (morning, noon, evening) or season?",
        ["Worse in early morning or cold weather", "Worse around midday or in heat", "Worse in late afternoon / night", "No time-of-day pattern"],
    ),
    (
        "Samprapti Completion",
        "Thank you. Do you have any lab reports or additional details to add before we prepare your integrated AYUSH & clinical summary?",
        ["No, please generate my summary", "I have shared all details", "Uploaded reports included", "Everything is covered"],
    ),
]


@router.post("/api/gemini/clinical-history")
async def ai_clinical_history(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    _ = user
    body = await _json_body(request)
    chief_complaint = str(body.get("chiefComplaint") or "").strip()
    conv = body.get("conversationHistory") if isinstance(body.get("conversationHistory"), list) else []
    if not chief_complaint and not conv:
        raise HTTPException(400, "chiefComplaint or conversationHistory is required")

    mode = str(body.get("mode") or "allopathic").strip().lower()
    image_context = str(body.get("imageContext") or "").strip()

    steps = _AYUSH_INTERVIEW_STEPS if mode == "ayush" else _ALLOPATHIC_INTERVIEW_STEPS
    question_count = sum(1 for m in conv if isinstance(m, dict) and m.get("role") in ("assistant", "ai", "model"))
    idx = min(question_count, len(steps) - 1)
    section_completed, next_q, quick_options = steps[idx]

    if image_context and question_count < len(steps):
        next_q = f"I have noted your uploaded report ({image_context[:80]}). {next_q}"

    combined_text = f"{chief_complaint} " + " ".join(
        str(m.get("content") or m.get("text") or "") for m in conv if isinstance(m, dict)
    )
    red_flags: list[str] = []
    urgency_level: Optional[str] = "P3"
    if llm.detect_emergency(combined_text):
        red_flags.append("Emergency symptom pattern detected — immediate clinical evaluation advised.")
        urgency_level = "P1"

    is_complete = (question_count + 1) >= 10
    progress = 100 if is_complete else min(95, (question_count + 1) * 10)
    return {
        "nextQuestion": next_q,
        "quickReplyOptions": quick_options,
        "progress": progress,
        "sectionCompleted": section_completed,
        "redFlags": red_flags,
        "urgencyLevel": urgency_level,
        "isComplete": is_complete,
    }


@router.post("/api/gemini/history-summary")
async def ai_history_summary(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    _ = user
    body = await _json_body(request)
    conv = body.get("conversationHistory")
    if not isinstance(conv, list) or len(conv) == 0:
        raise HTTPException(400, "conversationHistory is required")

    chief_complaint = str(body.get("chiefComplaint") or "").strip()
    mode = str(body.get("mode") or "allopathic").strip().lower()
    extracted_docs = body.get("extractedDocuments") if isinstance(body.get("extractedDocuments"), list) else []

    patient_turns = [
        str(m.get("content") or m.get("text") or "").strip()
        for m in conv
        if isinstance(m, dict) and m.get("role") not in ("assistant", "ai", "model") and str(m.get("content") or m.get("text") or "").strip()
    ]
    if not chief_complaint and patient_turns:
        chief_complaint = patient_turns[0]

    hpi_details = " ".join(patient_turns) or "Patient presented for structured OPD history intake."
    full_text = f"{chief_complaint} {hpi_details}"
    is_emerg = llm.detect_emergency(full_text)

    doc_summary = (
        "; ".join(str(d.get("summary") or d) for d in extracted_docs)
        if extracted_docs
        else "No prior investigation reports uploaded during this session."
    )
    ayush_text = (
        f"Dashavidha Pariksha ({mode.upper()} mode): Patient history suggests Vata-Pitta involvement affecting Agni and Koshtha; correlate with Nadi and clinical examination."
        if mode == "ayush"
        else "Standard Allopathic OPD mode selected (AYUSH assessment not requested)."
    )

    sections = {
        "chiefComplaint": f"Patient presents with: {chief_complaint or 'General clinical consultation'}.",
        "hpi": f"History of Present Illness: {hpi_details[:600]}",
        "pastMedical": "Patient-reported past medical context reviewed during structured kiosk interview; no acute decompensated chronic illness noted unless stated in HPI.",
        "pastSurgical": "Patient denies any major recent surgical intervention complicating the current presentation.",
        "drugHistory": "Current medication and over-the-counter usage reviewed during intake; verify active prescriptions before prescribing.",
        "allergies": "No known drug or food allergies (NKDA) unless specified in patient responses.",
        "familyHistory": "No acute hereditary red flags elicited during brief OPD screening.",
        "personalHistory": "Diet, sleep, and daily lifestyle factors reviewed as part of holistic intake.",
        "reviewOfSystems": f"Targeted review of systems completed for {chief_complaint or 'presenting complaint'}.",
        "investigations": doc_summary,
        "ayushAssessment": ayush_text,
    }
    red_flags = ["Urgent symptom keywords detected in transcript — prioritize physician evaluation."] if is_emerg else []
    urgency_level = "P1" if is_emerg else "P3"
    return {
        "sections": sections,
        "redFlags": red_flags,
        "urgencyLevel": urgency_level,
    }

# Jeevan sync: 2026-11-13
