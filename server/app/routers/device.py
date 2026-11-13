"""ESP32-facing endpoints. Paths and payloads match the shipped firmware (/api/device/*) so no reflash is required.

Hot path rule: parse -> merge in memory -> push to phones -> reply. Nothing here awaits the network.
"""
from __future__ import annotations

import time
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request

from ..ctx import Context, get_ctx
from ..security import User, current_user, device_key_valid, require_device, supplied_device_key
from ..sos_service import dispatch_sos
from ..triage import analyze

router = APIRouter(prefix="/api/device", tags=["device"])


async def _body(request: Request) -> dict[str, Any]:
    try:
        data = await request.json()
    except ValueError:
        raise HTTPException(400, "Body must be JSON")
    if not isinstance(data, dict):
        raise HTTPException(400, "Body must be a JSON object")
    return data


def _reply(ctx: Context, device_id: str) -> dict[str, Any]:
    rem = ctx.hub.reminder(device_id)
    return {
        "status": "success",
        "command": ctx.hub.next_command(device_id),
        "timestamp": int(time.time() * 1000),
        "reminder_led": rem["active"],
        "reminder_slot": rem["slot"],
    }


def _after_ingest(ctx: Context, device_id: str, snap: dict[str, Any]) -> None:
    st = ctx.hub.devices[device_id]
    now = time.time()
    v = snap["vitals"]
    if (
        st.owner
        and ctx.persist.enabled
        and all(k in v for k in ("heart_rate", "spo2", "temperature"))
        and now - st.last_persist >= ctx.settings.persist_interval_s
        and 20 <= v["heart_rate"] <= 300
        and 40 <= v["spo2"] <= 100
        and 25 <= v["temperature"] <= 45
    ):
        st.last_persist = now
        ecg = v.get("ecg_bpm")
        ctx.spawn(
            ctx.persist.insert(
                "vitawatch_readings",
                {
                    "user_id": st.owner,
                    "heart_rate": v["heart_rate"],
                    "spo2": v["spo2"],
                    "temperature": v["temperature"],
                    "ecg_bpm": ecg if ecg and 20 <= ecg <= 300 else None,
                    "ecg_status": "leads_off" if v.get("lead_off") else ("signal_detected" if ecg else "not_available"),
                    "source": "esp32",
                    "device_id": device_id,
                    "notes": "Jeevan App live telemetry",
                    "ai_analysis": snap["analysis"],
                    "recorded_at": datetime.now(timezone.utc).isoformat(),
                },
            )
        )
    if ctx.settings.mirror_live_stream and ctx.persist.enabled and now - st.last_mirror >= ctx.settings.mirror_interval_s:
        st.last_mirror = now
        ctx.spawn(
            ctx.persist.upsert(
                "device_live_stream",
                {
                    "device_id": device_id,
                    "sensor": snap["sensor"],
                    "data": v,
                    "signal_quality": snap["signal_quality"],
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                },
                "device_id",
            )
        )


@router.get("/command")
async def get_command(request: Request, device_id: str = "") -> dict[str, Any]:
    require_device(request)
    if not device_id:
        raise HTTPException(400, "Missing device_id")
    ctx = get_ctx(request)
    ctx.hub.touch(device_id)
    return _reply(ctx, device_id)


@router.post("/command")
async def post_command(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _body(request)
    device_id = str(body.get("device_id") or "").strip()
    command = str(body.get("command") or "").strip()
    if not device_id or not command:
        raise HTTPException(400, "Missing device_id or command")
    ctx = get_ctx(request)
    try:
        resolved = ctx.hub.set_command(device_id, command)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    return {"status": "success", "command": resolved, "issued_by": user.id}


@router.post("/live-stream")
async def live_stream(request: Request) -> dict[str, Any]:
    body = await _body(request)
    require_device(request, body)
    device_id, sensor, data = body.get("device_id"), body.get("sensor"), body.get("data")
    if not device_id or not sensor or not isinstance(data, dict):
        raise HTTPException(400, "Missing required live stream fields")
    ctx = get_ctx(request)
    snap = ctx.hub.ingest_stream(str(device_id), str(sensor), data)
    _after_ingest(ctx, str(device_id), snap)
    return _reply(ctx, str(device_id))


@router.post("/ingest")
async def ingest(request: Request) -> dict[str, Any]:
    """Legacy composite sample (heart_rate + spo2 + temperature in one POST)."""
    body = await _body(request)
    require_device(request, body)
    if any(body.get(k) is None for k in ("heart_rate", "spo2", "temperature")):
        raise HTTPException(400, "Incomplete hardware sensor payload")
    ctx = get_ctx(request)
    device_id = str(body.get("device_id") or "esp32_devkit_01")
    lead_off = bool(body.get("lead_off") or body.get("ecg_status") == "leads_off")
    snap = ctx.hub.ingest_direct(
        device_id,
        {k: body.get(k) for k in ("heart_rate", "spo2", "temperature", "ecg_bpm")} | {"lead_off": lead_off},
    )
    _after_ingest(ctx, device_id, snap)
    a = snap["analysis"]
    return {
        "status": "success",
        "device_id": device_id,
        "timestamp": int(time.time() * 1000),
        "lead_status": "LEADS OFF" if lead_off else "CONNECTED",
        "ai_analysis": {"overall_status": a["overall_status"], "risk_score": a["risk_score"], "red_flags": a["red_flags"]},
    }


@router.get("/status")
async def status(request: Request, device_id: str = "esp32_jeevancare_01") -> dict[str, Any]:
    """Public liveness probe kept for the web dashboard. Exposes online flag only - no vitals."""
    ctx = get_ctx(request)
    st = ctx.hub.devices.get(device_id)
    return {"online": bool(st and ctx.hub.is_online(st)), "device_id": device_id}


@router.post("/sos")
async def hardware_sos(request: Request) -> dict[str, Any]:
    body = await _body(request)
    require_device(request, body)
    ctx = get_ctx(request)
    device_id = str(body.get("device_id") or "esp32_jeevancare_01")
    owner = ctx.hub.owner_of(device_id)
    if not owner:
        raise HTTPException(409, "Device is not paired to a user. Pair it in the app first.")
    loc = body.get("location") or {}
    lat, lng = loc.get("lat"), loc.get("lng")
    fix = bool(loc.get("fix"))
    if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)) or (lat == 0 and lng == 0):
        # No usable GPS yet: fall back to the phone's last known position if we have one, else mark as unknown.
        last = ctx.hub.devices[device_id].gps
        recent_last = bool(last and time.time() - float(last.get("at", 0)) <= 60)
        lat, lng, fix = (last["lat"], last["lng"], False) if recent_last else (0.0, 0.0, False)
    else:
        ctx.hub.devices[device_id].gps = {"lat": float(lat), "lng": float(lng), "at": time.time()}
    v = body.get("vitals") or {}
    event = dispatch_sos(
        ctx,
        user_id=owner,
        source="hardware_button",
        lat=float(lat) if (lat or lng) else None,
        lng=float(lng) if (lat or lng) else None,
        gps_fix=fix,
        device_id=device_id,
        vitals={"heart_rate": v.get("heart_rate"), "spo2": v.get("spo2"), "temperature": v.get("temperature")},
        extra_location={"satellites": loc.get("satellites", 0), "speed_kmh": loc.get("speed_kmh", 0)},
    )
    ctx.hub.latest_hardware_sos = event
    return {"status": "success", "event_id": event["event_id"], "room_id": event["room_id"]}


@router.post("/sos/location")
async def hardware_sos_location(request: Request) -> dict[str, Any]:
    body = await _body(request)
    require_device(request, body)
    ctx = get_ctx(request)
    loc = body.get("location") or {}
    if not isinstance(loc.get("lat"), (int, float)) or not isinstance(loc.get("lng"), (int, float)):
        raise HTTPException(400, "Missing valid location coordinates")
    device_id = str(body.get("device_id") or "esp32_jeevancare_01")
    owner = ctx.hub.owner_of(device_id)
    if not owner:
        raise HTTPException(409, "Device is not paired")
    ctx.hub.devices[device_id].gps = {"lat": float(loc["lat"]), "lng": float(loc["lng"]), "at": time.time()}
    latest = ctx.hub.latest_sos.get(owner)
    event_id = body.get("event_id") or (latest or {}).get("event_id")
    if event_id:
        new_loc = {"lat": loc["lat"], "lng": loc["lng"], "gps_fix": bool(loc.get("fix")), "source": "hardware_gps_update"}
        if latest:
            latest["location"] = new_loc
        if ctx.hub.latest_hardware_sos:
            ctx.hub.latest_hardware_sos["location"] = new_loc
        ctx.hub.publish(owner, {"type": "sos_location", "data": {"event_id": event_id, "location": new_loc}})
        ctx.spawn(ctx.persist.update("sos_events", {"id": str(event_id), "uid": owner}, {"location": new_loc}))
    return {"status": "success"}


@router.get("/sos/latest")
async def latest_hardware_sos(request: Request) -> dict[str, Any]:
    ctx = get_ctx(request)
    latest = getattr(ctx.hub, "latest_hardware_sos", None)
    if latest is None and ctx.hub.latest_sos:
        latest = next(iter(ctx.hub.latest_sos.values()))
    return {"latest_sos": latest}


@router.post("/record-reading")
async def record_reading(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    body = await _body(request)
    device_id = str(body.get("device_id") or "").strip()
    if not device_id:
        raise HTTPException(400, "Missing device_id")
    ctx = get_ctx(request)
    st = ctx.hub.devices.get(device_id)
    live_vitals: dict[str, Any] = {}
    if st is not None:
        live_vitals = {k: m.value for k, m in st.metrics.items()}
        live_vitals.update(ctx.hub.fresh(st, time.time()))

    hr_raw = body.get("heart_rate") if body.get("heart_rate") is not None else live_vitals.get("heart_rate")
    spo2_raw = body.get("spo2") if body.get("spo2") is not None else live_vitals.get("spo2")
    temp_raw = body.get("temperature") if body.get("temperature") is not None else live_vitals.get("temperature")
    ecg_raw = body.get("ecg_bpm") if body.get("ecg_bpm") is not None else live_vitals.get("ecg_bpm")
    lead_off = bool(body.get("lead_off") or live_vitals.get("lead_off"))

    hr = int(hr_raw) if isinstance(hr_raw, (int, float)) else 0
    s = int(spo2_raw) if isinstance(spo2_raw, (int, float)) else 0
    temp = float(temp_raw) if isinstance(temp_raw, (int, float)) else 0.0
    ecg = None if lead_off else (int(ecg_raw) if isinstance(ecg_raw, (int, float)) else None)
    ecg_status = "leads_off" if lead_off else ("signal_detected" if ecg else "not_available")

    analysis = analyze(
        heart_rate=hr if hr > 0 else None,
        spo2=s if s > 0 else None,
        temperature=temp if temp > 0 else None,
        ecg_bpm=ecg,
        lead_off=lead_off,
    )
    record = {
        "id": f"vw_{int(time.time() * 1000)}",
        "user_id": user.id,
        "heart_rate": hr,
        "spo2": s,
        "temperature": temp,
        "ecg_bpm": ecg,
        "ecg_status": ecg_status,
        "source": "esp32",
        "device_id": device_id,
        "notes": "AD8232: Leads off detected" if lead_off else "Manual record from live telemetry",
        "ai_analysis": analysis,
        "recorded_at": datetime.now(timezone.utc).isoformat(),
    }
    if hr > 0 or s > 0 or temp > 0:
        ctx.hub.ingest_direct(
            device_id,
            {"heart_rate": hr, "spo2": s, "temperature": temp, "ecg_bpm": ecg, "lead_off": lead_off},
        )
    if ctx.persist.enabled:
        ctx.spawn(ctx.persist.insert("vitawatch_readings", record))
    return {"status": "success", "reading": record, "ai_analysis": analysis}


@router.post("/reminders/trigger")
async def trigger_reminder_endpoint(request: Request) -> dict[str, Any]:
    try:
        body = await request.json()
    except ValueError:
        body = {}
    body = body if isinstance(body, dict) else {}
    ctx = get_ctx(request)
    slot = str(body.get("slot") or "morning")
    medication_name = str(body.get("medicationName") or body.get("medication") or "Medicine")
    device_id = str(body.get("device_id") or "esp32_jeevancare_01")
    ctx.hub.set_reminder(device_id, slot, medication_name)
    rem = {
        "active": True,
        "slot": slot,
        "medicationName": medication_name,
        "triggeredAt": int(time.time() * 1000),
    }
    if ctx.persist.enabled:
        ctx.spawn(
            ctx.persist.upsert(
                "device_live_stream",
                {
                    "device_id": f"reminder_{device_id}",
                    "sensor": "active",
                    "data": rem,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                },
                "device_id",
            )
        )
    return {"status": "success", "reminder": rem}


@router.get("/reminders/status")
async def reminder_status(request: Request, device_id: str = "esp32_jeevancare_01") -> dict[str, Any]:
    ctx = get_ctx(request)
    return {"reminder": ctx.hub.reminder(device_id)}


@router.post("/reminders/acknowledge")
async def ack_reminder(request: Request) -> dict[str, Any]:
    try:
        body = await request.json()
    except ValueError:
        body = {}
    body = body if isinstance(body, dict) else {}
    ctx = get_ctx(request)
    supplied = supplied_device_key(request, body)
    if supplied:
        if not device_key_valid(supplied, ctx.settings):
            raise HTTPException(403, "Unauthorized hardware device key")
    elif not ctx.settings.legacy_unauth_reminder_ack:
        raise HTTPException(403, "Device key required")
    device_id = str(body.get("device_id") or "esp32_jeevancare_01")
    ctx.hub.clear_reminder(device_id)
    return {"status": "success"}
