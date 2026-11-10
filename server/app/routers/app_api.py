"""Phone-facing API: live WebSocket, device management, SOS, vitals history."""
from __future__ import annotations

import asyncio
import hashlib
import json
import time
from typing import Any, Literal, Optional

import jwt
from fastapi import APIRouter, Depends, HTTPException, Request, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from ..ctx import Context, get_ctx
from ..security import User, current_user, websocket_user, _req_settings
from ..sos_service import dispatch_sos, resolve_sos
from .. import triage

router = APIRouter(tags=["app"])


class LocalAuthBody(BaseModel):
    email: str = Field(min_length=3, max_length=120)
    password: str = Field(min_length=1, max_length=120)
    name: Optional[str] = None


def _issue_local_session(request: Request, email: str, name: str | None = None) -> dict[str, Any]:
    ctx = get_ctx(request)
    settings = _req_settings(request)
    secret = settings.supabase_jwt_secret
    if not secret:
        raise HTTPException(503, "SUPABASE_JWT_SECRET is not configured for local token issuance")
    clean_email = email.strip().lower()
    uid = "u_" + hashlib.sha256(clean_email.encode()).hexdigest()[:16]
    now = int(time.time())
    exp = now + 86400 * 7
    token = jwt.encode(
        {"sub": uid, "email": clean_email, "name": name or clean_email.split("@")[0], "aud": "authenticated", "iat": now, "exp": exp},
        secret,
        algorithm="HS256",
    )
    # Auto-pair and seed live demo vitals on esp32_jeevancare_01 if not paired yet so Dashboard is live immediately
    if not ctx.hub.devices_for(uid):
        did = "esp32_jeevancare_01" if ctx.hub.owner_of("esp32_jeevancare_01") in (None, uid) else f"esp32_{uid[:6]}"
        ctx.hub.pair(did, uid)
        ctx.hub.ingest_direct(
            did,
            {
                "heart_rate": 76,
                "spo2": 98,
                "temperature": 36.7,
                "ecg_bpm": 75,
                "ecg": [512, 520, 540, 490, 680, 380, 530, 515, 510, 512],
                "lead_off": False,
                "finger_detected": True,
                "rssi": -54,
            },
        )
    return {
        "access_token": token,
        "refresh_token": token,
        "expires_in": 86400 * 7,
        "user": {"id": uid, "email": clean_email, "name": name or clean_email.split("@")[0]},
    }


@router.post("/api/auth/login")
async def local_auth_login(body: LocalAuthBody, request: Request) -> dict[str, Any]:
    return _issue_local_session(request, body.email, body.name)


@router.post("/api/auth/signup")
async def local_auth_signup(body: LocalAuthBody, request: Request) -> dict[str, Any]:
    return _issue_local_session(request, body.email, body.name)


class GoogleAuthBody(BaseModel):
    id_token: str = Field(min_length=1)


@router.post("/api/auth/google")
async def google_auth(body: GoogleAuthBody, request: Request) -> dict[str, Any]:
    """Verify a Google ID token and issue a local session."""
    import httpx as _httpx

    # Verify token with Google's tokeninfo endpoint
    async with _httpx.AsyncClient() as client:
        resp = await client.get(
            "https://oauth2.googleapis.com/tokeninfo",
            params={"id_token": body.id_token},
            timeout=10,
        )
        if resp.status_code != 200:
            raise HTTPException(401, "Invalid Google ID token")
        info = resp.json()

    email = info.get("email")
    if not email:
        raise HTTPException(401, "Google token has no email")
    if info.get("email_verified") != "true":
        raise HTTPException(401, "Google email not verified")

    name = info.get("name") or info.get("given_name") or email.split("@")[0]
    return _issue_local_session(request, email, name)


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
                # Phone acts as BLE gateway: sub-100 ms path from watch to everyone else watching this user.
                did = str(msg.get("device_id", ""))
                if did and ctx.hub.owner_of(did) == user.id and isinstance(msg.get("vitals"), dict):
                    ctx.hub.ingest_direct(did, msg["vitals"])
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
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    notes: str = Field(default="", max_length=300)
    device_id: Optional[str] = None


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
    event = dispatch_sos(ctx, user_id=user.id, source="app_button", lat=body.lat, lng=body.lng, device_id=dev, vitals=vitals, notes=body.notes)
    return {"status": "success", "event_id": event["event_id"], "room_id": event["room_id"]}


@router.post("/api/sos/{event_id}/location")
async def sos_location(event_id: str, body: SosLocationBody, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    latest = ctx.hub.latest_sos.get(user.id)
    if not latest or latest["event_id"] != event_id or latest["status"] != "active":
        raise HTTPException(404, "No active SOS with that id")
    loc = {"lat": body.lat, "lng": body.lng, "gps_fix": True, "source": "app_gps_update"}
    latest["location"] = loc
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
