"""Smart Walking Stick (ESP32 #2) telemetry, 3-zone ultrasonic radar, LDR headlight & safe-zone geofencing.

100% compatible with firmware/walking_stick_esp32/walking_stick_esp32.ino and web /api/stick/* endpoints,
plus instant WebSocket broadcast (`type: "stick"`) to subscribed mobile apps.
"""
from __future__ import annotations

import math
import time
from typing import Any

from fastapi import APIRouter, HTTPException, Request

from ..ctx import Context, get_ctx
from ..security import require_device

router = APIRouter(prefix="/api/stick", tags=["stick"])


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


class StickState:
    def __init__(self) -> None:
        self.geofence: dict[str, Any] = {
            "enabled": True,
            "center_lat": 12.9716,
            "center_lng": 77.5946,
            "radius_m": 250.0,
            "label": "Home Safety Zone",
        }
        self.telemetry: dict[str, Any] = {
            "left_cm": -1.0,
            "front_cm": -1.0,
            "right_cm": -1.0,
            "left_contact": False,
            "front_contact": False,
            "right_contact": False,
            "guidance": "clear",
            "ldr_raw": 500,
            "ldr_avg": 500,
            "ldr_threshold": 100,
            "ldr_hysteresis": 0,
            "light_on": False,
            "rssi": -60,
            "uptime_s": 0,
            "lat": 12.9716,
            "lng": 77.5946,
            "accuracy_m": 10.0,
            "speed_kmh": 0.0,
            "heading": 0.0,
            "address": "MG Road, Bangalore, Karnataka",
            "tracking_mode": "simulated",
            "location_updated_at": int(time.time() * 1000),
            "geofence_status": "safe",
        }
        self.last_telemetry_ms: int = 0
        self.next_event_id: int = 1
        self.events: list[dict[str, Any]] = []

    def evaluate_geofence(self, lat: float | None, lng: float | None) -> str:
        if not self.geofence.get("enabled") or lat is None or lng is None:
            return "safe"
        dist = _haversine_m(lat, lng, float(self.geofence["center_lat"]), float(self.geofence["center_lng"]))
        radius = float(self.geofence["radius_m"])
        if dist > radius:
            return "breached"
        if dist > radius * 0.85:
            return "warning"
        return "safe"

    def push_event(self, source: str, code: str, message: str, priority: int = 1, data: dict[str, Any] | None = None) -> dict[str, Any]:
        ev = {
            "id": self.next_event_id,
            "source": source if source in ("stick", "light", "geofence", "collision") else "stick",
            "code": code,
            "message": message,
            "priority": priority,
            "data": data or {},
            "received_at": int(time.time() * 1000),
        }
        self.next_event_id += 1
        self.events.append(ev)
        if len(self.events) > 50:
            self.events.pop(0)
        return ev


_STICK = StickState()


def _broadcast_stick(ctx: Context) -> None:
    now_ms = int(time.time() * 1000)
    age_ms = (now_ms - _STICK.last_telemetry_ms) if _STICK.last_telemetry_ms else 999999
    payload = {
        "online": _STICK.last_telemetry_ms > 0 and age_ms < 10000,
        "device_id": "esp32_walking_stick_01",
        "data": _STICK.telemetry,
        "geofence": _STICK.geofence,
        "age_ms": age_ms,
        "latest_events": _STICK.events[-5:],
    }
    for uid in list(ctx.hub._subs.keys()):  # noqa: SLF001
        ctx.hub.publish(uid, {"type": "stick", "data": payload})


@router.post("/telemetry")
async def stick_telemetry(request: Request) -> dict[str, Any]:
    body = await request.json()
    require_device(request, body if isinstance(body, dict) else None)
    data = (body or {}).get("data")
    if not isinstance(data, dict):
        raise HTTPException(400, "Missing telemetry data payload")

    t = _STICK.telemetry
    lat = float(data["lat"]) if isinstance(data.get("lat"), (int, float)) else t["lat"]
    lng = float(data["lng"]) if isinstance(data.get("lng"), (int, float)) else t["lng"]
    g_status = _STICK.evaluate_geofence(lat, lng)
    if g_status == "breached" and t.get("geofence_status") != "breached":
        _STICK.push_event(
            "geofence",
            "geofence_breach",
            "Safe Zone Alert: Walking stick has exited the designated safe perimeter!",
            3,
            {"lat": lat, "lng": lng, "radius_m": _STICK.geofence["radius_m"]},
        )

    now_ms = int(time.time() * 1000)
    _STICK.telemetry = {
        "left_cm": float(data.get("left_cm", -1)),
        "front_cm": float(data.get("front_cm", -1)),
        "right_cm": float(data.get("right_cm", -1)),
        "left_contact": bool(data.get("left_contact")),
        "front_contact": bool(data.get("front_contact")),
        "right_contact": bool(data.get("right_contact")),
        "guidance": str(data.get("guidance") or "clear"),
        "ldr_raw": int(data.get("ldr_raw") or 0),
        "ldr_avg": int(data.get("ldr_avg") or 0),
        "ldr_threshold": int(data.get("ldr_threshold") or 100),
        "ldr_hysteresis": int(data.get("ldr_hysteresis") or 0),
        "light_on": bool(data.get("light_on")),
        "rssi": int(data["rssi"]) if isinstance(data.get("rssi"), (int, float)) else t.get("rssi", -60),
        "uptime_s": int(data["uptime_s"]) if isinstance(data.get("uptime_s"), (int, float)) else t.get("uptime_s", 0),
        "lat": lat,
        "lng": lng,
        "accuracy_m": float(data.get("accuracy_m") or t.get("accuracy_m", 10)),
        "speed_kmh": float(data.get("speed_kmh") or t.get("speed_kmh", 0)),
        "heading": float(data.get("heading") or t.get("heading", 0)),
        "address": data.get("address") or t.get("address"),
        "tracking_mode": data.get("tracking_mode") or ("gps" if isinstance(data.get("lat"), (int, float)) else t.get("tracking_mode")),
        "location_updated_at": now_ms if isinstance(data.get("lat"), (int, float)) else t.get("location_updated_at"),
        "geofence_status": g_status,
    }
    _STICK.last_telemetry_ms = now_ms
    _broadcast_stick(get_ctx(request))
    return {"status": "success", "received_at": now_ms, "geofence_status": g_status}


@router.post("/event")
async def stick_event(request: Request) -> dict[str, Any]:
    body = await request.json()
    require_device(request, body if isinstance(body, dict) else None)
    data = body.get("data") if isinstance(body.get("data"), dict) else {}
    ev = _STICK.push_event(
        str(body.get("source") or "stick"),
        str(body.get("code") or "event"),
        str(body.get("message") or ""),
        int(body.get("priority") or 1),
        data,
    )
    for k in ("left_cm", "front_cm", "right_cm"):
        if k in data and isinstance(data[k], (int, float)):
            _STICK.telemetry[k] = float(data[k])
    if "light_on" in data:
        _STICK.telemetry["light_on"] = bool(data["light_on"])
    _STICK.last_telemetry_ms = int(time.time() * 1000)
    _broadcast_stick(get_ctx(request))
    return {"status": "success", "event_id": ev["id"]}


@router.post("/location")
async def stick_location(request: Request) -> dict[str, Any]:
    body = await request.json()
    lat, lng = body.get("lat"), body.get("lng")
    if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
        raise HTTPException(400, "Missing or invalid latitude/longitude numbers")
    old_status = _STICK.telemetry.get("geofence_status")
    new_status = _STICK.evaluate_geofence(float(lat), float(lng))
    _STICK.telemetry.update(
        {
            "lat": float(lat),
            "lng": float(lng),
            "tracking_mode": body.get("tracking_mode", "phone_gps"),
            "location_updated_at": int(time.time() * 1000),
            "geofence_status": new_status,
        }
    )
    if new_status == "breached" and old_status != "breached":
        _STICK.push_event(
            "geofence",
            "geofence_breach",
            "Safe Zone Alert: Walking stick has moved outside the designated perimeter!",
            3,
            {"lat": lat, "lng": lng, "radius_m": _STICK.geofence["radius_m"]},
        )
    _broadcast_stick(get_ctx(request))
    return {"status": "success", "data": _STICK.telemetry}


@router.post("/sync-watch")
async def sync_watch(request: Request) -> dict[str, Any]:
    ctx = get_ctx(request)
    st = ctx.hub.devices.get("esp32_jeevancare_01") or next(iter(ctx.hub.devices.values()), None)
    if st and st.gps:
        lat, lng = st.gps["lat"], st.gps["lng"]
        _STICK.telemetry.update(
            {
                "lat": lat,
                "lng": lng,
                "tracking_mode": "watch_synced",
                "location_updated_at": int(time.time() * 1000),
                "geofence_status": _STICK.evaluate_geofence(lat, lng),
            }
        )
        _STICK.push_event("stick", "watch_gps_synced", "Walking stick position synchronized with VitaWatch GPS fix.", 1, {"lat": lat, "lng": lng})
        _broadcast_stick(ctx)
        return {"status": "synced", "source": "vitawatch_gps", "location": {"lat": lat, "lng": lng}}
    return {
        "status": "notice",
        "message": "No live GPS lock from VitaWatch found yet. Using current location coordinates.",
        "location": {"lat": _STICK.telemetry["lat"], "lng": _STICK.telemetry["lng"]},
    }


@router.get("/geofence")
async def get_geofence() -> dict[str, Any]:
    return {"geofence": _STICK.geofence, "status": _STICK.telemetry.get("geofence_status", "safe")}


@router.post("/geofence")
async def set_geofence(request: Request) -> dict[str, Any]:
    body = await request.json()
    if "enabled" in body:
        _STICK.geofence["enabled"] = bool(body["enabled"])
    if isinstance(body.get("center_lat"), (int, float)):
        _STICK.geofence["center_lat"] = float(body["center_lat"])
    if isinstance(body.get("center_lng"), (int, float)):
        _STICK.geofence["center_lng"] = float(body["center_lng"])
    if isinstance(body.get("radius_m"), (int, float)) and body["radius_m"] > 0:
        _STICK.geofence["radius_m"] = float(body["radius_m"])
    if body.get("label"):
        _STICK.geofence["label"] = str(body["label"])
    _STICK.telemetry["geofence_status"] = _STICK.evaluate_geofence(_STICK.telemetry.get("lat"), _STICK.telemetry.get("lng"))
    _broadcast_stick(get_ctx(request))
    return {"status": "success", "geofence": _STICK.geofence, "geofence_status": _STICK.telemetry["geofence_status"]}


@router.get("/status")
async def stick_status() -> dict[str, Any]:
    now_ms = int(time.time() * 1000)
    age_ms = (now_ms - _STICK.last_telemetry_ms) if _STICK.last_telemetry_ms else 999999
    return {
        "online": _STICK.last_telemetry_ms > 0 and age_ms < 10000,
        "device_id": "esp32_walking_stick_01",
        "data": _STICK.telemetry,
        "geofence": _STICK.geofence,
        "updated_at": _STICK.last_telemetry_ms,
        "age_ms": age_ms,
        "latest_event_id": _STICK.events[-1]["id"] if _STICK.events else 0,
        "latest_events": _STICK.events[-10:],
    }


@router.get("/events")
async def stick_events(after: int = -1) -> dict[str, Any]:
    latest = _STICK.events[-1]["id"] if _STICK.events else 0
    if after < 0:
        return {"events": _STICK.events[-10:], "latest_event_id": latest}
    return {"events": [e for e in _STICK.events if e["id"] > after], "latest_event_id": latest}


@router.post("/simulate")
async def stick_simulate(request: Request) -> dict[str, Any]:
    body = await request.json()
    t = _STICK.telemetry
    for k in ("left_cm", "front_cm", "right_cm", "lat", "lng", "speed_kmh", "heading"):
        if isinstance(body.get(k), (int, float)):
            t[k] = float(body[k])
    if "light_on" in body:
        t["light_on"] = bool(body["light_on"])
    if isinstance(body.get("ldr_raw"), (int, float)):
        t["ldr_raw"] = int(body["ldr_raw"])
    if body.get("guidance"):
        t["guidance"] = str(body["guidance"])
    t["left_contact"] = 0 <= t["left_cm"] <= 4
    t["front_contact"] = 0 <= t["front_cm"] <= 4
    t["right_contact"] = 0 <= t["right_cm"] <= 4
    t["tracking_mode"] = "simulated"
    t["location_updated_at"] = int(time.time() * 1000)
    t["geofence_status"] = _STICK.evaluate_geofence(t["lat"], t["lng"])
    _STICK.last_telemetry_ms = int(time.time() * 1000)
    if body.get("message"):
        _STICK.push_event(
            "stick",
            str(body.get("code") or "simulated_event"),
            str(body["message"]),
            int(body.get("priority") or 2),
            {"left_cm": t["left_cm"], "front_cm": t["front_cm"], "right_cm": t["right_cm"], "light_on": t["light_on"]},
        )
    _broadcast_stick(get_ctx(request))
    return {"status": "simulated", "data": t, "geofence_status": t["geofence_status"]}
# Jeevan sync: 2026-11-13
