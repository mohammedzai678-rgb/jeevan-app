"""Smart Walking Stick (ESP32 #2) telemetry, 3-zone ultrasonic radar, LDR headlight & safe-zone geofencing.

100% compatible with firmware/walking_stick_esp32/walking_stick_esp32.ino and web /api/stick/* endpoints,
plus instant WebSocket broadcast (`type: "stick"`) to subscribed mobile apps.
"""
from __future__ import annotations

import math
import time
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from ..security import User, current_user

from ..ctx import Context, get_ctx
from ..security import require_device

router = APIRouter(prefix="/api/stick", tags=["stick"])
STICK_DEVICE_ID = "esp32_walking_stick_01"
OBSTACLE_WARNING_CM = 80.0


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


class StickState:
    def __init__(self) -> None:
        self.geofence: dict[str, Any] = {
            "enabled": False,
            "center_lat": None,
            "center_lng": None,
            "radius_m": 250.0,
            "label": "Home Safety Zone",
        }
        self.telemetry: dict[str, Any] = {
            "left_cm": None,
            "front_cm": None,
            "right_cm": None,
            "left_contact": False,
            "front_contact": False,
            "right_contact": False,
            "guidance": "unknown",
            "recommended_direction": "unknown",
            "turn_light": "off",
            "voice_prompt": None,
            "ldr_raw": None,
            "ldr_avg": None,
            "ldr_threshold": 100,
            "ldr_hysteresis": 20,
            "light_on": False,
            "light_source": "unavailable",
            "rssi": None,
            "uptime_s": 0,
            "lat": None,
            "lng": None,
            "accuracy_m": None,
            "speed_kmh": None,
            "heading": None,
            "address": None,
            "tracking_mode": "unavailable",
            "location_updated_at": 0,
            "geofence_status": "disabled",
        }
        self.last_telemetry_ms: int = 0
        self.next_event_id: int = 1
        self.events: list[dict[str, Any]] = []

    def evaluate_geofence(self, lat: float | None, lng: float | None) -> str:
        if not self.geofence.get("enabled"):
            return "disabled"
        if lat is None or lng is None or self.geofence.get("center_lat") is None or self.geofence.get("center_lng") is None:
            return "unconfigured"
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
        "device_id": STICK_DEVICE_ID,
        "data": _STICK.telemetry,
        "geofence": _STICK.geofence,
        "age_ms": age_ms,
        "latest_events": _STICK.events[-5:],
    }
    # A stick's location and obstacle events belong only to its paired account.
    owner = ctx.hub.owner_of(STICK_DEVICE_ID)
    if owner:
        ctx.hub.publish(owner, {"type": "stick", "data": payload})


def _require_stick_owner(ctx: Context, user: User) -> None:
    if ctx.hub.owner_of(STICK_DEVICE_ID) != user.id:
        raise HTTPException(404, "Walking stick is not paired to this account")


def _number(value: Any, field: str, minimum: float, maximum: float,
            *, sentinel: float | None = None) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise HTTPException(422, f"{field} must be a finite number")
    result = float(value)
    if sentinel is not None and result == sentinel:
        return result
    if not minimum <= result <= maximum:
        raise HTTPException(422, f"{field} must be between {minimum:g} and {maximum:g}")
    return result


def _apply_obstacle_guidance(telemetry: dict[str, Any]) -> None:
    def distance(key: str) -> float | None:
        value = telemetry.get(key)
        if value is None:
            return None
        return 201.0 if value == -1 else float(value)

    left, front, right = (distance(key) for key in ("left_cm", "front_cm", "right_cm"))
    left_blocked = telemetry.get("left_contact") is True or (left is not None and left <= OBSTACLE_WARNING_CM)
    front_blocked = telemetry.get("front_contact") is True or (front is not None and front <= OBSTACLE_WARNING_CM)
    right_blocked = telemetry.get("right_contact") is True or (right is not None and right <= OBSTACLE_WARNING_CM)
    left_clear = left is not None and left > OBSTACLE_WARNING_CM and not telemetry.get("left_contact")
    right_clear = right is not None and right > OBSTACLE_WARNING_CM and not telemetry.get("right_contact")

    if front_blocked:
        if left_clear and right_clear:
            direction = "left" if left >= right else "right"
            prompt = f"Obstacle ahead. Go {direction}."
        elif left_clear:
            direction, prompt = "left", "Obstacle ahead. Go left."
        elif right_clear:
            direction, prompt = "right", "Obstacle ahead. Go right."
        else:
            direction, prompt = "stop", "Stop. The path ahead is blocked."
    elif right_blocked and left_blocked:
        direction, prompt = "stop", "Stop. Obstacles on both sides."
    elif right_blocked:
        direction = "left" if left_clear else "stop"
        prompt = "Obstacle on your right. Go left." if left_clear else "Stop. Obstacle on your right."
    elif left_blocked:
        direction = "right" if right_clear else "stop"
        prompt = "Obstacle on your left. Go right." if right_clear else "Stop. Obstacle on your left."
    else:
        has_reading = any(telemetry.get(key) is not None for key in ("left_cm", "front_cm", "right_cm"))
        direction = "clear" if has_reading else "unknown"
        prompt = None

    telemetry["recommended_direction"] = direction
    telemetry["turn_light"] = {
        "left": "left",
        "right": "right",
        "stop": "hazard",
    }.get(direction, "off")
    telemetry["voice_prompt"] = prompt
    telemetry["guidance"] = prompt or ("clear" if direction == "clear" else "unknown")


@router.post("/telemetry")
async def stick_telemetry(request: Request) -> dict[str, Any]:
    body = await request.json()
    require_device(request, body if isinstance(body, dict) else None)
    data = (body or {}).get("data")
    if not isinstance(data, dict):
        raise HTTPException(400, "Missing telemetry data payload")
    if body.get("device_id") not in (None, STICK_DEVICE_ID):
        raise HTTPException(403, "Device ID does not match the walking stick")

    t = _STICK.telemetry
    gps_keys = ("lat" in data, "lng" in data)
    if gps_keys[0] != gps_keys[1]:
        raise HTTPException(422, "lat and lng must be sent together")
    lat_value = _number(data.get("lat"), "lat", -90, 90)
    lng_value = _number(data.get("lng"), "lng", -180, 180)
    lat = lat_value if lat_value is not None else t["lat"]
    lng = lng_value if lng_value is not None else t["lng"]
    now_ms = int(time.time() * 1000)
    def sensor_distance(key: str) -> float | None:
        value = _number(data.get(key, t[key]), key, 0, 5000, sentinel=-1)
        return value

    for key in ("left_contact", "front_contact", "right_contact", "light_on"):
        if key in data and not isinstance(data[key], bool):
            raise HTTPException(422, f"{key} must be a boolean")
    for key in ("guidance", "tracking_mode", "address"):
        if key in data and data[key] is not None and not isinstance(data[key], str):
            raise HTTPException(422, f"{key} must be text")

    left = sensor_distance("left_cm")
    front = sensor_distance("front_cm")
    right = sensor_distance("right_cm")
    ldr_raw = _number(data.get("ldr_raw", t["ldr_raw"]), "ldr_raw", 0, 65535)
    ldr_avg = _number(data.get("ldr_avg", t["ldr_avg"]), "ldr_avg", 0, 65535)
    ldr_threshold = _number(data.get("ldr_threshold", t["ldr_threshold"]), "ldr_threshold", 0, 65535)
    ldr_hysteresis = _number(data.get("ldr_hysteresis", t["ldr_hysteresis"]), "ldr_hysteresis", 0, 65535)
    if "light_on" in data:
        light_on = data["light_on"]
        light_source = "device"
    elif ldr_raw is None:
        light_on = t["light_on"]
        light_source = "unavailable"
    elif ldr_threshold is not None and ldr_raw <= ldr_threshold:
        light_on = True
        light_source = "ldr_auto"
    elif ldr_threshold is not None and ldr_raw >= ldr_threshold + (ldr_hysteresis or 0):
        light_on = False
        light_source = "ldr_auto"
    else:
        light_on = t["light_on"]
        light_source = "ldr_auto"
    location_received = gps_keys[0]
    g_status = _STICK.evaluate_geofence(lat, lng)
    guidance = data.get("guidance") or t.get("guidance") or "unknown"
    address = data.get("address") or t.get("address")
    if g_status == "breached" and t.get("geofence_status") != "breached":
        _STICK.push_event(
            "geofence",
            "geofence_breach",
            "Safe Zone Alert: Walking stick has exited the designated safe perimeter!",
            3,
            {"lat": lat, "lng": lng, "radius_m": _STICK.geofence["radius_m"]},
        )
    _STICK.telemetry = {
        "left_cm": left,
        "front_cm": front,
        "right_cm": right,
        "left_contact": data.get("left_contact", left is not None and 0 <= left <= 4),
        "front_contact": data.get("front_contact", front is not None and 0 <= front <= 4),
        "right_contact": data.get("right_contact", right is not None and 0 <= right <= 4),
        "guidance": guidance[:120],
        "ldr_raw": ldr_raw,
        "ldr_avg": ldr_avg,
        "ldr_threshold": ldr_threshold,
        "ldr_hysteresis": ldr_hysteresis,
        "rssi": _number(data.get("rssi", t["rssi"]), "rssi", -127, 0),
        "light_on": light_on,
        "light_source": light_source,
        "uptime_s": _number(data.get("uptime_s", t["uptime_s"]), "uptime_s", 0, 4_294_967_295),
        "lat": lat,
        "lng": lng,
        "accuracy_m": _number(data.get("accuracy_m", t["accuracy_m"]), "accuracy_m", 0, 100_000),
        "speed_kmh": _number(data.get("speed_kmh", t["speed_kmh"]), "speed_kmh", 0, 300),
        "heading": _number(data.get("heading", t["heading"]), "heading", 0, 360),
        "address": address,
        "tracking_mode": data.get("tracking_mode") or ("gps" if location_received else t.get("tracking_mode", "unavailable")),
        "location_updated_at": now_ms if location_received else t.get("location_updated_at", 0),
        "geofence_status": g_status,
    }
    if isinstance(_STICK.telemetry["address"], str):
        _STICK.telemetry["address"] = _STICK.telemetry["address"][:200]
    _apply_obstacle_guidance(_STICK.telemetry)
    _STICK.last_telemetry_ms = now_ms
    _broadcast_stick(get_ctx(request))
    return {"status": "success", "received_at": now_ms, "geofence_status": g_status}


@router.post("/event")
async def stick_event(request: Request) -> dict[str, Any]:
    body = await request.json()
    require_device(request, body if isinstance(body, dict) else None)
    if body.get("device_id") not in (None, STICK_DEVICE_ID):
        raise HTTPException(403, "Device ID does not match the walking stick")
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
    _apply_obstacle_guidance(_STICK.telemetry)
    _STICK.last_telemetry_ms = int(time.time() * 1000)
    _broadcast_stick(get_ctx(request))
    return {"status": "success", "event_id": ev["id"]}


@router.post("/location")
async def stick_location(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    _require_stick_owner(get_ctx(request), user)
    body = await request.json()
    lat, lng = body.get("lat"), body.get("lng")
    if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
        raise HTTPException(400, "Missing or invalid latitude/longitude numbers")
    lat = _number(lat, "lat", -90, 90)
    lng = _number(lng, "lng", -180, 180)
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
async def sync_watch(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    _require_stick_owner(ctx, user)
    st = next((ctx.hub.devices[did] for did in ctx.hub.devices_for(user.id)
               if did in ctx.hub.devices and ctx.hub.devices[did].gps), None)
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
        "message": "No live GPS fix is available from this account's VitaWatch.",
        "location": None,
    }


@router.get("/geofence")
async def get_geofence(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    _require_stick_owner(get_ctx(request), user)
    return {"geofence": _STICK.geofence, "status": _STICK.telemetry.get("geofence_status", "safe")}


@router.post("/geofence")
async def set_geofence(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    _require_stick_owner(ctx, user)
    body = await request.json()
    enabled = body.get("enabled", _STICK.geofence["enabled"])
    if not isinstance(enabled, bool):
        raise HTTPException(422, "enabled must be a boolean")
    center_lat = (
        _number(body["center_lat"], "center_lat", -90, 90)
        if "center_lat" in body else _STICK.geofence["center_lat"]
    )
    center_lng = (
        _number(body["center_lng"], "center_lng", -180, 180)
        if "center_lng" in body else _STICK.geofence["center_lng"]
    )
    radius = (
        _number(body["radius_m"], "radius_m", 25, 50_000)
        if "radius_m" in body else _STICK.geofence["radius_m"]
    )
    label = body.get("label", _STICK.geofence["label"])
    if not isinstance(label, str) or not label.strip() or len(label) > 80:
        raise HTTPException(422, "label must contain 1 to 80 characters")
    if enabled and (center_lat is None or center_lng is None):
        raise HTTPException(422, "Set a safe-zone center before enabling the geofence")
    _STICK.geofence.update(
        enabled=enabled,
        center_lat=center_lat,
        center_lng=center_lng,
        radius_m=radius,
        label=label.strip(),
    )
    _STICK.telemetry["geofence_status"] = _STICK.evaluate_geofence(
        _STICK.telemetry.get("lat"), _STICK.telemetry.get("lng")
    )
    _broadcast_stick(ctx)
    return {"status": "success", "geofence": _STICK.geofence, "geofence_status": _STICK.telemetry["geofence_status"]}


@router.get("/status")
async def stick_status(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    _require_stick_owner(get_ctx(request), user)
    now_ms = int(time.time() * 1000)
    age_ms = (now_ms - _STICK.last_telemetry_ms) if _STICK.last_telemetry_ms else 999999
    return {
        "online": _STICK.last_telemetry_ms > 0 and age_ms < 10000,
        "device_id": STICK_DEVICE_ID,
        "data": _STICK.telemetry,
        "geofence": _STICK.geofence,
        "updated_at": _STICK.last_telemetry_ms,
        "age_ms": age_ms,
        "latest_event_id": _STICK.events[-1]["id"] if _STICK.events else 0,
        "latest_events": _STICK.events[-10:],
    }


@router.get("/events")
async def stick_events(request: Request, after: int = -1, user: User = Depends(current_user)) -> dict[str, Any]:
    _require_stick_owner(get_ctx(request), user)
    latest = _STICK.events[-1]["id"] if _STICK.events else 0
    if after < 0:
        return {"events": _STICK.events[-10:], "latest_event_id": latest}
    return {"events": [e for e in _STICK.events if e["id"] > after], "latest_event_id": latest}


@router.post("/simulate")
async def stick_simulate(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    _require_stick_owner(ctx, user)
    body = await request.json()
    t = _STICK.telemetry
    for k in ("left_cm", "front_cm", "right_cm", "lat", "lng", "speed_kmh", "heading"):
        if isinstance(body.get(k), (int, float)):
            t[k] = float(body[k])
    if isinstance(body.get("ldr_raw"), (int, float)):
        t["ldr_raw"] = int(body["ldr_raw"])
    if "light_on" in body:
        t["light_on"] = bool(body["light_on"])
        t["light_source"] = "device"
    else:
        raw, threshold = t.get("ldr_raw"), t.get("ldr_threshold", 100)
        hysteresis = t.get("ldr_hysteresis", 20) or 0
        if isinstance(raw, (int, float)) and isinstance(threshold, (int, float)):
            if raw <= threshold:
                t["light_on"] = True
            elif raw >= threshold + hysteresis:
                t["light_on"] = False
            t["light_source"] = "ldr_auto"
    if body.get("guidance"):
        t["guidance"] = str(body["guidance"])
    t["left_contact"] = t["left_cm"] is not None and 0 <= t["left_cm"] <= 4
    t["front_contact"] = t["front_cm"] is not None and 0 <= t["front_cm"] <= 4
    t["right_contact"] = t["right_cm"] is not None and 0 <= t["right_cm"] <= 4
    t["tracking_mode"] = "simulated"
    t["location_updated_at"] = int(time.time() * 1000)
    t["geofence_status"] = _STICK.evaluate_geofence(t["lat"], t["lng"])
    _apply_obstacle_guidance(t)
    _STICK.last_telemetry_ms = int(time.time() * 1000)
    if body.get("message"):
        _STICK.push_event(
            "stick",
            str(body.get("code") or "simulated_event"),
            str(body["message"]),
            int(body.get("priority") or 2),
            {"left_cm": t["left_cm"], "front_cm": t["front_cm"], "right_cm": t["right_cm"], "light_on": t["light_on"]},
        )
    _broadcast_stick(ctx)
    return {"status": "simulated", "data": t, "geofence_status": t["geofence_status"]}
# Jeevan sync: 2026-11-13
