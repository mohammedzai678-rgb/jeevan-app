"""Railway-hosted lightweight HTML pages for the JeevanCare app so SOS Agora Video Calls,
First Responder Medical ID QR summaries, and root service status run 100% on Railway
without relying on the separate website domain.
"""
from __future__ import annotations

import html
from typing import Any

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse

from ..ctx import get_ctx

router = APIRouter(tags=["web"])


@router.get("/", response_model=None)
async def root_status(request: Request) -> JSONResponse | HTMLResponse:
    ctx = get_ctx(request)
    accept = request.headers.get("accept", "")
    if "text/html" in accept:
        return HTMLResponse(
            """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Jeevan App Backend — Railway</title>
<style>body{font-family:system-ui,-apple-system,sans-serif;background:#0b1120;color:#f8fafc;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px}
.card{max-width:460px;background:#111827;border:1px solid #1f2937;border-radius:20px;padding:28px;box-shadow:0 20px 50px rgba(0,0,0,.4)}
.pill{display:inline-block;padding:5px 12px;border-radius:999px;background:rgba(16,185,129,.15);color:#34d399;font-size:12px;font-weight:700}
h1{margin:14px 0 8px;font-size:24px}p{color:#94a3b8;line-height:1.5;font-size:14px}a{color:#2dd4bf;text-decoration:none;font-weight:600}</style></head>
<body><div class="card"><span class="pill">ONLINE • RAILWAY</span><h1>JeevanCare App Backend</h1>
<p>Dedicated FastAPI, WebSocket &amp; Emergency SOS server for the JeevanCare Android app and ESP32 wearables.</p>
<p><a href="/health">/health</a> · <a href="/video-call?room=jeevan-consult-108">Agora Video Room</a></p></div></body></html>"""
        )
    return JSONResponse({
        "service": "JeevanCare App Backend",
        "status": "ok",
        "health": "/health",
        "persistence": ctx.persist.enabled,
    })


@router.get("/video-call", response_class=HTMLResponse)
async def agora_video_call_page(
    request: Request,
    room: str = Query(default=""),
    roomId: str = Query(default=""),
) -> HTMLResponse:
    _ = request
    channel = html.escape((room or roomId or "sos-room-108").strip())
    return HTMLResponse(
        f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>JeevanCare Emergency Video Call — {channel}</title>
  <script src="https://download.agora.io/sdk/release/AgoraRTC_N-4.20.2.js"></script>
  <style>
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0; font-family: system-ui, -apple-system, sans-serif;
      background: #090d16; color: #f8fafc; min-height: 100vh;
      display: flex; flex-direction: column;
    }}
    header {{
      padding: 16px 20px; border-bottom: 1px solid #1e293b;
      display: flex; justify-content: space-between; align-items: center; gap: 12px;
      background: #0f172a;
    }}
    .badge {{
      padding: 5px 11px; border-radius: 999px; font-size: 12px; font-weight: 700;
      background: rgba(20, 184, 166, 0.16); color: #2dd4bf; border: 1px solid rgba(45, 212, 191, 0.35);
    }}
    main {{
      flex: 1; padding: 20px; display: flex; flex-direction: column;
      align-items: center; justify-content: center; gap: 16px;
    }}
    .grid {{
      display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 16px; width: 100%; max-width: 960px;
    }}
    .video-box {{
      background: #111827; border: 1px solid #1f2937; border-radius: 18px;
      aspect-ratio: 16/10; overflow: hidden; position: relative;
      display: flex; align-items: center; justify-content: center; color: #94a3b8;
    }}
    .controls {{ display: flex; gap: 12px; flex-wrap: wrap; justify-content: center; }}
    button {{
      border: 0; border-radius: 12px; padding: 12px 20px; font-size: 14px; font-weight: 700;
      cursor: pointer; background: #14b8a6; color: #042f2a;
    }}
    button.danger {{ background: #ef4444; color: #fff; }}
    button.secondary {{ background: #1e293b; color: #f8fafc; }}
    #status {{ font-size: 13px; color: #cbd5e1; text-align: center; max-width: 640px; }}
  </style>
</head>
<body>
  <header>
    <div>
      <div style="font-weight:800;font-size:17px;">JeevanCare Live Agora Emergency Room</div>
      <div style="font-size:12px;color:#94a3b8;">Room ID: <code>{channel}</code></div>
    </div>
    <span class="badge" id="liveBadge">AGORA RTC • READY</span>
  </header>
  <main>
    <div id="status">Tap <strong>Join Call</strong> to connect audio &amp; video with the JeevanCare app user.</div>
    <div class="grid">
      <div class="video-box" id="local-player">Local Camera Preview</div>
      <div class="video-box" id="remote-player">Waiting for remote participant…</div>
    </div>
    <div class="controls">
      <button id="joinBtn" onclick="joinCall()">Join Call</button>
      <button class="secondary" onclick="toggleMic()">Mute / Unmute</button>
      <button class="danger" onclick="leaveCall()">Leave Call</button>
    </div>
  </main>
  <script>
    const channelId = {channel!r};
    const client = window.AgoraRTC ? AgoraRTC.createClient({{ mode: "rtc", codec: "vp8" }}) : null;
    let localTracks = [];
    let micMuted = false;

    async function joinCall() {{
      const st = document.getElementById("status");
      if (!client) {{
        st.textContent = "Agora Web SDK could not load. Check internet connectivity.";
        return;
      }}
      try {{
        st.textContent = "Requesting signed Agora token for room " + channelId + "…";
        const res = await fetch("/api/rtc/public-token", {{
          method: "POST",
          headers: {{ "Content-Type": "application/json" }},
          body: JSON.stringify({{ channelId }})
        }});
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Agora RTC keys are not configured on the server yet.");
        client.on("user-published", async (user, mediaType) => {{
          await client.subscribe(user, mediaType);
          if (mediaType === "video") {{
            const remoteBox = document.getElementById("remote-player");
            remoteBox.innerHTML = "";
            user.videoTrack.play(remoteBox);
          }}
          if (mediaType === "audio") user.audioTrack.play();
        }});
        await client.join(data.appId, data.channelId, data.token, data.uid);
        localTracks = await AgoraRTC.createMicrophoneAndCameraTracks();
        const localBox = document.getElementById("local-player");
        localBox.innerHTML = "";
        localTracks[1].play(localBox);
        await client.publish(localTracks);
        document.getElementById("liveBadge").textContent = "CONNECTED • LIVE";
        st.textContent = "Connected to Agora room " + channelId;
      }} catch (err) {{
        st.textContent = "Unable to join Agora call: " + (err.message || err);
      }}
    }}

    function toggleMic() {{
      if (!localTracks[0]) return;
      micMuted = !micMuted;
      localTracks[0].setEnabled(!micMuted);
    }}

    async function leaveCall() {{
      for (const t of localTracks) {{ t.stop(); t.close(); }}
      localTracks = [];
      if (client) await client.leave();
      document.getElementById("status").textContent = "Left call.";
      document.getElementById("liveBadge").textContent = "DISCONNECTED";
    }}
  </script>
</body>
</html>"""
    )


@router.get("/emergency/{user_id}", response_class=HTMLResponse)
async def emergency_medical_id_page(user_id: str, request: Request) -> HTMLResponse:
    ctx = get_ctx(request)
    uid = html.escape(user_id.strip())
    summary: dict[str, Any] = {}
    if ctx.persist.enabled:
        rows = await ctx.persist.select(
            "emergency_summaries",
            {"uid": f"eq.{user_id.strip()}", "limit": "1"},
        )
        if rows:
            summary = rows[0]

    name = html.escape(str(summary.get("name") or "Jeevan User"))
    blood = html.escape(str(summary.get("bloodType") or "Not specified"))
    dob = html.escape(str(summary.get("dob") or "Not provided"))
    allergies = summary.get("allergies") or []
    conditions = summary.get("conditions") or []
    meds = summary.get("currentMedications") or []
    contacts = summary.get("emergencyContacts") or []
    if summary.get("showEmergencyContacts") is False:
        contacts = []

    def _chips(items: Any) -> str:
        if isinstance(items, str):
            items = [x.strip() for x in items.split(",") if x.strip()]
        values = [
            str(item).strip()
            for item in (items or [])
            if str(item).strip()
            and str(item).strip().lower() not in {"none", "none reported", "not provided", "not specified", "unknown"}
        ]
        return "".join(f"<span class='chip'>{html.escape(value)}</span>" for value in values) or "<span class='muted'>Not provided</span>"

    def _contact_row(contact: dict[str, Any]) -> str:
        phone = str(contact.get("phone") or "").strip()
        call_link = (
            f"<a class='call' href='tel:{html.escape(phone.replace(' ', ''))}'>"
            f"Call {html.escape(phone)}</a>"
            if phone
            else ""
        )
        return (
            f"<div class='row'><div><strong>{html.escape(str(contact.get('name') or 'Emergency contact'))}</strong>"
            f"<div class='muted'>{html.escape(str(contact.get('relationship') or ''))}</div>"
            f"<div class='muted'>{html.escape(str(contact.get('email') or ''))}</div></div>"
            f"{call_link}</div>"
        )

    contact_rows = "".join(
        _contact_row(contact) for contact in contacts if isinstance(contact, dict)
    ) or "<div class='muted'>No emergency contacts have been added.</div>"

    return HTMLResponse(
        f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Emergency Medical ID — {name}</title>
  <style>
    body{{margin:0;font-family:system-ui,-apple-system,sans-serif;background:#f8fafc;color:#0f172a;padding:20px}}
    .wrap{{max-width:540px;margin:0 auto;display:grid;gap:14px}}
    .hero{{background:linear-gradient(135deg,#ef4444,#b91c1c);color:#fff;padding:22px;border-radius:18px}}
    .card{{background:#fff;border:1px solid #e2e8f0;border-radius:16px;padding:16px}}
    .blood{{display:inline-block;background:rgba(255,255,255,.2);padding:6px 12px;border-radius:10px;font-weight:800;margin-top:8px}}
    .chip{{display:inline-block;background:#fef2f2;color:#b91c1c;padding:5px 10px;border-radius:999px;font-size:13px;font-weight:700;margin:4px 6px 0 0}}
    .row{{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:8px 0}}
    .muted{{font-size:12px;color:#64748b}}
    .call{{background:#10b981;color:#fff;text-decoration:none;padding:9px 14px;border-radius:10px;font-weight:700;font-size:13px}}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div style="font-size:11px;font-weight:800;letter-spacing:1px;">JEEVANCARE EMERGENCY MEDICAL ID</div>
      <h1 style="margin:6px 0 2px;font-size:26px;">{name}</h1>
      <div style="font-size:12px;opacity:.85;">Patient ID: {uid}</div>
      <div style="font-size:12px;opacity:.85;">Date of birth: {dob}</div>
      <div class="blood">🩸 Blood Group: {blood}</div>
    </div>
    <div class="card"><strong>⚠️ Allergies</strong><div>{_chips(allergies)}</div></div>
    <div class="card"><strong>🏥 Medical Conditions</strong><div>{_chips(conditions)}</div></div>
    <div class="card"><strong>💊 Current Medications</strong><div>{_chips(meds)}</div></div>
    <div class="card"><strong>📞 Emergency Contacts</strong>{contact_rows}</div>
  </div>
</body>
</html>"""
    )
# Jeevan sync: 2026-11-13
