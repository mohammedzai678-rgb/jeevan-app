"""Phone-facing API: live WebSocket, device management, SOS, vitals history."""
from __future__ import annotations

import asyncio
import json
import time
from datetime import datetime, timezone
from typing import Any, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from ..ctx import Context, get_ctx
from ..security import User, current_user, websocket_user
from ..sos_service import dispatch_sos, resolve_sos
from .. import triage

router = APIRouter(tags=["app"])


# ── Live WebSocket ───────────────────────────────────────────────────────
@router.websocket("/ws/live")
async def live_ws(ws: WebSocket) -> None:
    ctx: Context = ws.app.state.ctx
    user = await websocket_user(ws)
    if user is None:
        await ws.close(code=4401)
        return
    await ws.accept()
    sub = ctx.hub.subscribe(user.id)
    # Hand the phone current state immediately so the UI never starts empty.
    for did in ctx.hub.devices_for(user.id):
        await ws.send_json({"type": "vitals", "data": ctx.hub.snapshot(did)})
    sos = ctx.hub.latest_sos.get(user.id)
    if sos and sos.get("status") == "active":
        await ws.send_json({"type": "sos", "data": sos})

    async def sender() -> None:
        while True:
            await ws.send_json(await sub.queue.get())

    async def receiver() -> None:
        while True:
            msg = json.loads(await ws.receive_text())
            kind = msg.get("type")
            if kind == "ping":
                # echo the client's timestamp so it can measure true round-trip latency
                await ws.send_json({"type": "pong", "t": msg.get("t"), "server_ms": int(time.time() * 1000)})
            elif kind == "ble_vitals":
                # The authenticated phone is the only network gateway for a BLE watch.
                did = str(msg.get("device_id", ""))
                vitals = msg.get("vitals")
                valid_id = bool(did) and len(did) <= 64 and all(
                    ch.isalnum() or ch in "_-" for ch in did
                )
                if valid_id and isinstance(vitals, dict):
                    owner = ctx.hub.owner_of(did)
                    if owner is None and ctx.hub.pair(did, user.id):
                        owner = user.id
                        ctx.spawn(ctx.persist.upsert(
                            "device_pairings", {"device_id": did, "user_id": user.id}, "device_id"
                        ))
                    if owner == user.id:
                        ctx.hub.ingest_direct(did, vitals)
            elif kind == "command":
                did, cmd = str(msg.get("device_id", "")), str(msg.get("command", ""))
                if ctx.hub.owner_of(did) == user.id:
                    try:
                        ctx.hub.set_command(did, cmd)
                    except ValueError:
                        pass

    tasks = [asyncio.create_task(sender()), asyncio.create_task(receiver())]
    try:
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for t in done:
            exc = t.exception()  # retrieve so asyncio doesn't warn; disconnects/bad frames are expected
            if exc and not isinstance(exc, (WebSocketDisconnect, ValueError, RuntimeError)):
                raise exc
    finally:
        for t in tasks:
            t.cancel()
        ctx.hub.unsubscribe(sub)
        try:
            await ws.close()
        except RuntimeError:
            pass


# ── Devices ──────────────────────────────────────────────────────────────
class PairBody(BaseModel):
    device_id: str = Field(min_length=2, max_length=64, pattern=r"^[A-Za-z0-9_\-]+$")


class CommandBody(BaseModel):
    command: Literal["auto", "idle", "read_max30102", "read_dht11", "read_ad8232"]


class ReminderBody(BaseModel):
    slot: str = "morning"
    medication: str = "Medicine"


@router.get("/api/devices")
async def list_devices(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    return {"devices": [ctx.hub.snapshot(d) for d in ctx.hub.devices_for(user.id)]}


@router.post("/api/devices/pair")
async def pair_device(body: PairBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    if not ctx.hub.pair(body.device_id, user.id):
        raise HTTPException(409, "Device is already paired to another account")
    ctx.spawn(ctx.persist.upsert("device_pairings", {"device_id": body.device_id, "user_id": user.id}, "device_id"))
    return {"status": "paired", "device": ctx.hub.snapshot(body.device_id)}


@router.delete("/api/devices/{device_id}")
async def unpair_device(device_id: str, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    if not ctx.hub.unpair(device_id, user.id):
        raise HTTPException(404, "Device not found")
    if ctx.persist.enabled:
        ctx.spawn(ctx.persist._send("DELETE", "device_pairings", params={"device_id": f"eq.{device_id}", "user_id": f"eq.{user.id}"}))
    return {"status": "unpaired"}


def _owned(ctx: Context, device_id: str, user: User) -> None:
    if ctx.hub.owner_of(device_id) != user.id:
        raise HTTPException(404, "Device not found")


@router.post("/api/devices/{device_id}/command")
async def device_command(device_id: str, body: CommandBody, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    _owned(ctx, device_id, user)
    return {"command": ctx.hub.set_command(device_id, body.command)}


@router.post("/api/devices/{device_id}/reminder")
async def device_reminder(device_id: str, body: ReminderBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    _owned(ctx, device_id, user)
    ctx.hub.trigger_reminder(device_id, body.slot[:24], body.medication[:80])
    return {"status": "triggered"}


@router.post("/api/devices/{device_id}/reminder/ack")
async def device_reminder_ack(device_id: str, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    _owned(ctx, device_id, user)
    ctx.hub.clear_reminder(device_id)
    return {"status": "cleared"}


# ── SOS ──────────────────────────────────────────────────────────────────
class SosBody(BaseModel):
    lat: Optional[float] = Field(default=None, ge=-90, le=90)
    lng: Optional[float] = Field(default=None, ge=-180, le=180)
    notes: str = Field(default="", max_length=300)
    device_id: Optional[str] = None
    vitals: Optional[dict[str, Any]] = None
    user_name: Optional[str] = Field(default=None, max_length=120)
    blood_group: Optional[str] = Field(default=None, max_length=30)
    allergies: Optional[list[str]] = None
    conditions: Optional[list[str]] = None
    medications: Optional[list[str]] = None
    contacts: Optional[list[dict[str, Any]]] = None


class SosLocationBody(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


@router.post("/api/sos")
async def trigger_sos(body: SosBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    vitals: dict[str, Any] = {}
    dev = body.device_id or next(iter(ctx.hub.devices_for(user.id)), None)
    if dev and ctx.hub.owner_of(dev) == user.id:
        v = ctx.hub.snapshot(dev)["vitals"]
        vitals = {"heart_rate": v.get("heart_rate"), "spo2": v.get("spo2"), "temperature": v.get("temperature")}
    if body.vitals:
        for key, limits in {
            "heart_rate": (20, 300),
            "spo2": (40, 100),
            "temperature": (25, 45),
        }.items():
            value = body.vitals.get(key)
            if isinstance(value, (int, float)) and limits[0] <= value <= limits[1]:
                vitals[key] = value
    event = dispatch_sos(
        ctx,
        user_id=user.id,
        source="app_button",
        lat=body.lat,
        lng=body.lng,
        gps_fix=body.lat is not None and body.lng is not None,
        device_id=dev,
        vitals=vitals,
        notes=body.notes,
        profile=body.model_dump(exclude_none=True),
    )
    return {"status": "success", "event_id": event["event_id"], "room_id": event["room_id"]}


@router.post("/api/sos/{event_id}/location")
async def sos_location(event_id: str, body: SosLocationBody, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    latest = ctx.hub.latest_sos.get(user.id)
    if not latest or latest["event_id"] != event_id or latest["status"] != "active":
        raise HTTPException(404, "No active SOS with that id")
    loc = {"lat": body.lat, "lng": body.lng, "gps_fix": True, "source": "app_gps_update"}
    latest["location"] = loc
    latest["maps_url"] = f"https://maps.google.com/?q={body.lat},{body.lng}"
    ctx.hub.publish(user.id, {"type": "sos_location", "data": {"event_id": event_id, "location": loc}})
    ctx.spawn(ctx.persist.update("sos_events", {"id": event_id, "uid": user.id}, {"location": loc}))
    return {"status": "success"}


@router.post("/api/sos/{event_id}/resolve")
async def sos_resolve(event_id: str, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    if not await resolve_sos(ctx, user.id, event_id):
        raise HTTPException(404, "SOS event not found")
    return {"status": "resolved"}


# ── Vitals ───────────────────────────────────────────────────────────────
class ManualReading(BaseModel):
    heart_rate: int = Field(ge=20, le=300)
    spo2: int = Field(ge=40, le=100)
    temperature: float = Field(ge=25, le=45)
    systolic_bp: Optional[int] = Field(default=None, ge=40, le=300)
    diastolic_bp: Optional[int] = Field(default=None, ge=20, le=200)


class BleReading(BaseModel):
    device_id: str = Field(min_length=2, max_length=64, pattern=r"^[A-Za-z0-9_\-]+$")
    heart_rate: Optional[int] = Field(default=None, ge=20, le=300)
    spo2: Optional[int] = Field(default=None, ge=40, le=100)
    temperature: Optional[float] = Field(default=None, ge=25, le=45)


@router.get("/api/vitals/history")
async def vitals_history(request: Request, limit: int = 100, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    rows = await ctx.persist.select(
        "vitawatch_readings",
        {
            "user_id": f"eq.{user.id}",
            "select": "id,heart_rate,spo2,temperature,ecg_bpm,systolic_bp,diastolic_bp,source,recorded_at,ai_analysis",
            "order": "recorded_at.desc",
            "limit": str(max(1, min(limit, 500))),
        },
    )
    return {"readings": rows}


@router.post("/api/vitals/record")
async def record_vitals(body: ManualReading, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    analysis = triage.analyze(body.heart_rate, body.spo2, body.temperature, systolic_bp=body.systolic_bp, diastolic_bp=body.diastolic_bp)
    ctx.spawn(
        ctx.persist.insert(
            "vitawatch_readings",
            {**body.model_dump(), "user_id": user.id, "source": "manual", "ai_analysis": analysis, "ecg_status": "not_available"},
        )
    )
    return {"analysis": analysis}


@router.post("/api/vitals/ble/record")
async def record_ble_vitals(body: BleReading, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    """Save one user-requested snapshot received by the phone over BLE."""
    values = body.model_dump(exclude={"device_id"}, exclude_none=True)
    if not values:
        raise HTTPException(400, "The watch has not supplied a reading yet")
    analysis = triage.analyze(
        heart_rate=body.heart_rate,
        spo2=body.spo2,
        temperature=body.temperature,
    )
    record = {
        **values,
        "user_id": user.id,
        "device_id": body.device_id,
        "source": "ble",
        "ecg_status": "not_available",
        "notes": "Saved from VitaWatch over Bluetooth",
        "ai_analysis": analysis,
        "recorded_at": datetime.now(timezone.utc).isoformat(),
    }
    ctx = get_ctx(request)
    ctx.spawn(ctx.persist.insert("vitawatch_readings", record))
    return {"reading": record, "analysis": analysis}
# Jeevan sync: 2026-11-13
