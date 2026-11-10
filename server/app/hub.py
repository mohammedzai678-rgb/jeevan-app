"""In-memory real-time hub.

All live data flows through here with zero network hops: the device request handler merges the sample,
computes triage and pushes to every subscribed phone before replying. Persistence is done off the hot
path (see persistence.py).
"""
from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Any, Optional

from . import triage
from .config import Settings

log = logging.getLogger("jeevan.hub")

REMINDER_TTL_S = 10 * 60
VALID_COMMANDS = {"idle", "read_max30102", "read_dht11", "read_ad8232"}


def _now() -> float:
    return time.time()


@dataclass
class Metric:
    value: Any
    ts: float


@dataclass
class DeviceState:
    device_id: str
    owner: Optional[str] = None
    metrics: dict[str, Metric] = field(default_factory=dict)
    last_seen: float = 0.0
    sensor: str = "idle"
    signal_quality: str = "UNKNOWN"
    rssi: Optional[int] = None
    pinned: Optional[str] = None
    rot_idx: int = 0
    rot_started: float = 0.0
    reminder: dict[str, Any] = field(
        default_factory=lambda: {"active": False, "slot": "", "medication": "", "medicationName": "", "at": 0.0, "triggeredAt": 0}
    )
    gps: Optional[dict[str, Any]] = None
    seq: int = 0
    last_persist: float = 0.0
    last_mirror: float = 0.0
    was_online: bool = False


class Subscription:
    """Bounded per-client queue. A slow phone never blocks the hub: the oldest event is dropped instead."""

    def __init__(self, user_id: str, maxsize: int = 256) -> None:
        self.user_id = user_id
        self.queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=maxsize)

    def push(self, event: dict[str, Any]) -> None:
        try:
            self.queue.put_nowait(event)
        except asyncio.QueueFull:
            try:
                self.queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
            self.queue.put_nowait(event)


class Hub:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.devices: dict[str, DeviceState] = {}
        self._subs: dict[str, set[Subscription]] = {}
        self._sequence = settings.parsed_sequence()
        self.latest_sos: dict[str, dict[str, Any]] = {}
        self.latest_hardware_sos: Optional[dict[str, Any]] = None

    # ── ownership ────────────────────────────────────────────────
    def _state(self, device_id: str) -> DeviceState:
        st = self.devices.get(device_id)
        if st is None:
            st = DeviceState(device_id=device_id)
            if self.settings.default_owner_user_id:
                st.owner = self.settings.default_owner_user_id
            self.devices[device_id] = st
        return st

    def owner_of(self, device_id: str) -> Optional[str]:
        return self._state(device_id).owner

    def pair(self, device_id: str, user_id: str) -> bool:
        st = self._state(device_id)
        if st.owner and st.owner != user_id and st.owner != self.settings.default_owner_user_id:
            return False
        st.owner = user_id
        return True

    def unpair(self, device_id: str, user_id: str) -> bool:
        st = self.devices.get(device_id)
        if not st or st.owner != user_id:
            return False
        st.owner = None
        return True

    def load_pairings(self, rows: list[dict[str, Any]]) -> None:
        for row in rows:
            did, uid = row.get("device_id"), row.get("user_id")
            if did and uid:
                self._state(str(did)).owner = str(uid)

    def devices_for(self, user_id: str) -> list[str]:
        return [d for d, st in self.devices.items() if st.owner == user_id]

    # ── pub/sub ──────────────────────────────────────────────────
    def subscribe(self, user_id: str) -> Subscription:
        sub = Subscription(user_id)
        self._subs.setdefault(user_id, set()).add(sub)
        return sub

    def unsubscribe(self, sub: Subscription) -> None:
        subs = self._subs.get(sub.user_id)
        if subs:
            subs.discard(sub)
            if not subs:
                self._subs.pop(sub.user_id, None)

    def publish(self, user_id: Optional[str], event: dict[str, Any]) -> None:
        if not user_id:
            return
        for sub in tuple(self._subs.get(user_id, ())):
            sub.push(event)

    # ── ingest ───────────────────────────────────────────────────
    def ingest_stream(
        self, device_id: str, sensor: str, data: dict[str, Any], now: Optional[float] = None
    ) -> dict[str, Any]:
        """Merge one firmware `live-stream` sample (one sensor at a time) into the device's vitals."""
        now = now or _now()
        st = self._state(device_id)
        st.last_seen = now
        st.sensor = sensor
        st.signal_quality = str(data.get("signal_quality") or st.signal_quality)
        if isinstance(data.get("rssi"), (int, float)):
            st.rssi = int(data["rssi"])

        def put(name: str, value: Any) -> None:
            st.metrics[name] = Metric(value, now)

        def drop(*names: str) -> None:
            for n in names:
                st.metrics.pop(n, None)

        if sensor == "max30102":
            finger = bool(data.get("finger_detected"))
            put("finger_detected", finger)
            if finger and data.get("heart_rate_valid") and (data.get("heart_rate") or 0) > 0:
                put("heart_rate", int(data["heart_rate"]))
            if finger and data.get("spo2_valid") and (data.get("spo2") or 0) > 0:
                put("spo2", int(data["spo2"]))
            if not finger:
                drop("heart_rate", "spo2")
        elif sensor == "dht11":
            if data.get("valid") and isinstance(data.get("temperature"), (int, float)):
                put("temperature", round(float(data["temperature"]), 1))
                if isinstance(data.get("humidity"), (int, float)):
                    put("humidity", float(data["humidity"]))
        elif sensor == "ad8232":
            lead_off = bool(data.get("lead_off"))
            put("lead_off", lead_off)
            if isinstance(data.get("ecg_value"), (int, float)):
                put("ecg_value", int(data["ecg_value"]))
            if not lead_off and data.get("ecg_bpm_valid") and (data.get("ecg_bpm") or 0) > 0:
                put("ecg_bpm", int(data["ecg_bpm"]))
            if lead_off:
                drop("ecg_bpm")
        return self._emit(st, now)

    def ingest_direct(self, device_id: str, vitals: dict[str, Any], now: Optional[float] = None) -> dict[str, Any]:
        """Composite sample (legacy /ingest or phone BLE gateway)."""
        now = now or _now()
        st = self._state(device_id)
        st.last_seen = now
        st.sensor = "composite"
        for key in ("heart_rate", "spo2", "temperature", "ecg_bpm", "humidity"):
            val = vitals.get(key)
            if isinstance(val, (int, float)) and val > 0:
                st.metrics[key] = Metric(round(float(val), 1) if key in ("temperature", "humidity") else int(val), now)
        if "lead_off" in vitals:
            st.metrics["lead_off"] = Metric(bool(vitals["lead_off"]), now)
        if "finger_detected" in vitals:
            st.metrics["finger_detected"] = Metric(bool(vitals["finger_detected"]), now)
        return self._emit(st, now)

    def touch(self, device_id: str, now: Optional[float] = None) -> None:
        st = self._state(device_id)
        st.last_seen = now or _now()

    def _emit(self, st: DeviceState, now: float) -> dict[str, Any]:
        st.seq += 1
        snap = self.snapshot(st.device_id, now)
        st.was_online = True
        self.publish(st.owner, {"type": "vitals", "data": snap})
        return snap

    # ── read side ────────────────────────────────────────────────
    def fresh(self, st: DeviceState, now: float) -> dict[str, Any]:
        ttl = self.settings.metric_ttl_s
        return {k: m.value for k, m in st.metrics.items() if now - m.ts <= ttl}

    def snapshot(self, device_id: str, now: Optional[float] = None) -> dict[str, Any]:
        now = now or _now()
        st = self._state(device_id)
        vit = self.fresh(st, now)
        analysis = triage.analyze(
            heart_rate=vit.get("heart_rate"),
            spo2=vit.get("spo2"),
            temperature=vit.get("temperature"),
            ecg_bpm=vit.get("ecg_bpm"),
            lead_off=bool(vit.get("lead_off")),
        )
        return {
            "device_id": device_id,
            "online": self.is_online(st, now),
            "last_seen_ms": int(st.last_seen * 1000) if st.last_seen else None,
            "server_ts_ms": int(now * 1000),
            "sensor": st.sensor,
            "command": self._peek_command(st),
            "signal_quality": st.signal_quality,
            "rssi": st.rssi,
            "seq": st.seq,
            "vitals": vit,
            "ages_ms": {k: int((now - m.ts) * 1000) for k, m in st.metrics.items() if k in vit},
            "analysis": analysis,
            "reminder": self.reminder(device_id, now),
        }

    def is_online(self, st: DeviceState, now: Optional[float] = None) -> bool:
        return bool(st.last_seen) and (now or _now()) - st.last_seen < self.settings.device_online_s

    # ── commands (sensor selection) ──────────────────────────────
    def set_command(self, device_id: str, command: str) -> str:
        """`auto` returns to server-driven sensor rotation; anything else pins that sensor."""
        st = self._state(device_id)
        if command == "auto":
            st.pinned = None
            return "auto"
        if command not in VALID_COMMANDS:
            raise ValueError(f"unknown command {command!r}")
        st.pinned = command
        return command

    def _peek_command(self, st: DeviceState) -> str:
        return st.pinned or self._sequence[st.rot_idx % len(self._sequence)][0]

    def next_command(self, device_id: str, now: Optional[float] = None) -> str:
        """Command returned to the ESP32 in every reply, so it switches sensors with no polling delay."""
        now = now or _now()
        st = self._state(device_id)
        if st.pinned:
            return st.pinned
        if not st.rot_started:
            st.rot_started = now
        cmd, dwell = self._sequence[st.rot_idx % len(self._sequence)]
        if len(self._sequence) > 1 and now - st.rot_started >= dwell:
            st.rot_idx = (st.rot_idx + 1) % len(self._sequence)
            st.rot_started = now
            cmd = self._sequence[st.rot_idx][0]
        return cmd

    # ── medicine reminder ────────────────────────────────────────
    def trigger_reminder(self, device_id: str, slot: str, medication: str) -> dict[str, Any]:
        st = self._state(device_id)
        now = _now()
        st.reminder = {
            "active": True,
            "slot": slot,
            "medication": medication,
            "medicationName": medication,
            "at": now,
            "triggeredAt": int(now * 1000),
        }
        self.publish(st.owner, {"type": "reminder", "data": self.reminder(device_id, now)})
        return st.reminder

    def set_reminder(self, device_id: str, slot: str, medication: str) -> dict[str, Any]:
        return self.trigger_reminder(device_id, slot, medication)

    def clear_reminder(self, device_id: str) -> None:
        st = self._state(device_id)
        st.reminder = {"active": False, "slot": "", "medication": "", "medicationName": "", "at": 0.0, "triggeredAt": 0}
        self.publish(st.owner, {"type": "reminder", "data": self.reminder(device_id)})

    def reminder(self, device_id: str, now: Optional[float] = None) -> dict[str, Any]:
        st = self._state(device_id)
        rem = st.reminder
        if rem["active"] and (now or _now()) - rem["at"] > REMINDER_TTL_S:
            st.reminder = {"active": False, "slot": "", "medication": "", "medicationName": "", "at": 0.0, "triggeredAt": 0}
            rem = st.reminder
        return {
            "active": rem["active"],
            "slot": rem["slot"],
            "medication": rem.get("medication", ""),
            "medicationName": rem.get("medicationName") or rem.get("medication", ""),
            "triggeredAt": int(rem.get("triggeredAt") or (int(rem["at"] * 1000) if rem.get("at") else 0)),
        }

    # ── liveness ─────────────────────────────────────────────────
    async def watchdog(self, interval: float = 3.0) -> None:
        """Push `device_status` when a device goes silent so the phone shows OFFLINE within seconds."""
        while True:
            await asyncio.sleep(interval)
            now = _now()
            for st in self.devices.values():
                online = self.is_online(st, now)
                if st.was_online and not online:
                    st.was_online = False
                    self.publish(st.owner, {"type": "device_status", "data": {"device_id": st.device_id, "online": False}})
