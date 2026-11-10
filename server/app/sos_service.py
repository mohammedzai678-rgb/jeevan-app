"""SOS pipeline shared by hardware button and in-app button.

Order matters for latency: (1) publish to the owner's phones in-process (<1 ms), (2) return to the caller,
(3) persist + notify contacts in the background and publish delivery results as they land.
"""
from __future__ import annotations

import logging
import re
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from .ctx import Context
from .notify import maps_link

log = logging.getLogger("jeevan.sos")


def room_id_for(event_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "", f"emergency-{event_id}")[:64]


def dispatch_sos(
    ctx: Context,
    *,
    user_id: str,
    source: str,
    lat: float,
    lng: float,
    gps_fix: bool = True,
    device_id: Optional[str] = None,
    vitals: Optional[dict[str, Any]] = None,
    notes: str = "",
    extra_location: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    event_id = str(uuid.uuid4())
    room_id = room_id_for(event_id)
    now = datetime.now(timezone.utc).isoformat()
    location = {"lat": lat, "lng": lng, "gps_fix": gps_fix, "source": source, **(extra_location or {})}
    event = {
        "event_id": event_id,
        "room_id": room_id,
        "source": source,
        "device_id": device_id,
        "location": location,
        "maps_url": maps_link(lat, lng),
        "vitals": vitals or {},
        "status": "active",
        "timestamp": now,
    }
    ctx.hub.latest_sos[user_id] = event
    ctx.hub.publish(user_id, {"type": "sos", "data": event})
    ctx.spawn(_persist_and_notify(ctx, user_id, event, notes))
    return event


async def _persist_and_notify(ctx: Context, user_id: str, event: dict[str, Any], notes: str) -> None:
    loc = event["location"]
    vit = event.get("vitals") or {}
    summary = ", ".join(f"{k} {v}" for k, v in vit.items() if v) or "n/a"
    await ctx.persist.insert(
        "sos_events",
        {
            "id": event["event_id"],
            "uid": user_id,
            "location": loc,
            "status": "active",
            "timestamp": event["timestamp"],
            "notes": (notes or f"SOS via {event['source']}. Vitals: {summary}")[:500],
        },
    )
    if event.get("device_id"):
        await ctx.persist.upsert(
            "device_live_stream",
            {
                "device_id": event["device_id"],
                "sensor": "sos_alert",
                "data": {"sos_active": True, "event_id": event["event_id"], "room_id": event["room_id"], "location": loc, "vitals": vit},
                "signal_quality": "GOOD" if loc.get("gps_fix") else "GPS_SEARCHING",
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
            "device_id",
        )

    profile = (await ctx.persist.select("profiles", {"uid": f"eq.{user_id}", "select": "name,email", "limit": "1"})) or [{}]
    summary_rows = await ctx.persist.select(
        "emergency_summaries", {"uid": f"eq.{user_id}", "select": "emergencyContacts", "limit": "1"}
    )
    contacts = list((summary_rows[0].get("emergencyContacts") if summary_rows else None) or [])
    name = profile[0].get("name") or "A Jeevan user"
    email = profile[0].get("email")
    if email and not any((c.get("email") or "").lower() == email.lower() for c in contacts):
        contacts.append({"name": name, "email": email})  # the user always gets their own confirmation

    results = await ctx.notifier.send_sos(
        user_name=name, lat=loc["lat"], lng=loc["lng"], event_id=event["event_id"], room_id=event["room_id"], contacts=contacts
    )
    ctx.hub.publish(user_id, {"type": "sos_delivery", "data": {"event_id": event["event_id"], "results": results}})


async def resolve_sos(ctx: Context, user_id: str, event_id: str) -> bool:
    latest = ctx.hub.latest_sos.get(user_id)
    known = bool(latest and latest["event_id"] == event_id)
    ok = False
    if ctx.persist.enabled:
        rows = await ctx.persist.select("sos_events", {"id": f"eq.{event_id}", "uid": f"eq.{user_id}", "select": "id", "limit": "1"})
        if rows:
            ok = await ctx.persist.update(
                "sos_events", {"id": event_id, "uid": user_id}, {"status": "resolved", "resolvedAt": datetime.now(timezone.utc).isoformat()}
            )
    if not (known or ok):
        return False
    if known:
        latest["status"] = "resolved"  # type: ignore[index]
    ctx.hub.publish(user_id, {"type": "sos_resolved", "data": {"event_id": event_id}})
    return True
