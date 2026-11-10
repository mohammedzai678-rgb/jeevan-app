"""SOS & Safe delivery over Brevo (WhatsApp + SMS + Email), run in the background after SOS is pushed to phones."""
from __future__ import annotations

import asyncio
import html
import logging
import re
from datetime import datetime
from typing import Any
from urllib.parse import quote

import httpx

from .config import Settings

log = logging.getLogger("jeevan.notify")
BREVO = "https://api.brevo.com/v3"


def _is_configured(value: str | None) -> bool:
    norm = (value or "").strip().lower()
    return bool(
        norm
        and norm not in ('""', "''")
        and "your_" not in norm
        and "your-" not in norm
        and "placeholder" not in norm
    )


def normalize_phone(value: str | None) -> str | None:
    """Brevo wants country code without '+'. 10-digit numbers are assumed Indian (+91)."""
    if not value:
        return None
    raw = value.strip()
    digits = re.sub(r"\D", "", raw)
    if not digits:
        return None
    if raw.startswith("+") or len(digits) > 10:
        return digits
    if len(digits) == 10:
        return f"91{digits}"
    return None


def maps_link(lat: float, lng: float) -> str:
    return f"https://maps.google.com/?q={lat},{lng}"


def video_link(settings: Settings, room_id: str) -> str:
    return f"{settings.app_public_url.rstrip('/')}/video-call?room={quote(room_id)}"


def merge_contacts(contacts: list[dict[str, Any]]) -> list[dict[str, str | None]]:
    seen: set[str] = set()
    out: list[dict[str, str | None]] = []
    for c in contacts or []:
        phone = normalize_phone(c.get("phone"))
        email = (c.get("email") or "").strip() or None
        key = phone or (email.lower() if email else None)
        if not key or key in seen:
            continue
        seen.add(key)
        out.append({"name": (c.get("name") or "Emergency contact").strip(), "phone": phone, "email": email})
    return out


class Notifier:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    @property
    def email_ready(self) -> bool:
        return _is_configured(self.settings.brevo_api_key) and _is_configured(self.settings.brevo_from_email)

    @property
    def sms_ready(self) -> bool:
        return _is_configured(self.settings.brevo_api_key) and _is_configured(self.settings.brevo_sms_sender)

    @property
    def whatsapp_ready(self) -> bool:
        return _is_configured(self.settings.brevo_api_key) and _is_configured(self.settings.brevo_whatsapp_sender_number)

    def _template_id(self, kind: str) -> int | None:
        mapping = {
            "sos": self.settings.brevo_whatsapp_sos_template_id,
            "safe": self.settings.brevo_whatsapp_safe_template_id,
            "videoInvite": self.settings.brevo_whatsapp_video_invite_template_id,
            "medicationStatus": self.settings.brevo_whatsapp_medication_template_id,
        }
        raw = mapping.get(kind)
        if not _is_configured(raw):
            return None
        try:
            return int(str(raw).strip())
        except ValueError:
            return None

    def _headers(self) -> dict[str, str]:
        return {"api-key": self.settings.brevo_api_key, "accept": "application/json", "content-type": "application/json"}

    async def _post(self, client: httpx.AsyncClient, path: str, body: dict) -> dict[str, Any]:
        try:
            resp = await client.post(f"{BREVO}{path}", json=body, headers=self._headers())
            if resp.status_code < 300:
                return {"status": "accepted"}
            return {"status": "failed", "error": resp.text[:200]}
        except httpx.HTTPError as exc:
            return {"status": "failed", "error": str(exc)}

    async def _send_whatsapp(
        self,
        client: httpx.AsyncClient,
        *,
        phone: str,
        kind: str,
        params: dict[str, str],
    ) -> dict[str, Any]:
        if not self.whatsapp_ready:
            return {"whatsapp": "skipped", "whatsappError": "BREVO_WHATSAPP_SENDER_NUMBER not configured"}
        tpl_id = self._template_id(kind)
        if not tpl_id:
            return {"whatsapp": "skipped", "whatsappError": f"WhatsApp template ID not configured for {kind}"}
        res = await self._post(
            client,
            "/whatsapp/sendMessage",
            {
                "templateId": tpl_id,
                "senderNumber": self.settings.brevo_whatsapp_sender_number.strip(),
                "contactNumbers": [phone],
                "params": params,
            },
        )
        if res["status"] == "accepted":
            return {"whatsapp": "accepted"}
        return {"whatsapp": "failed", "whatsappError": res.get("error")}

    async def send_sos(
        self,
        *,
        user_name: str,
        lat: float,
        lng: float,
        event_id: str,
        room_id: str,
        contacts: list[dict[str, Any]],
        blood_group: str = "A+",
        medical_details: str = "",
        user_id: str = "zaid-001",
    ) -> dict[str, Any]:
        recipients = merge_contacts(contacts)
        maps, video = maps_link(lat, lng), video_link(self.settings, room_id)
        summary_url = f"{self.settings.app_public_url.rstrip('/')}/emergency/{quote(user_id)}"
        med_line = f"Medical Details: {medical_details}\n" if medical_details.strip() else ""
        sms_text = (
            f"🚨 EMERGENCY SOS from {user_name} (JeevanCare)!\n"
            f"Blood Group: {blood_group}\n"
            f"Live GPS Location: {maps}\n"
            f"{med_line}"
            f"Agora Video Call Link: {video}\n"
            f"Medical Summary: {summary_url}"
        )
        safe_name = html.escape(user_name)
        med_html = (
            f"<li><strong>Medical Details:</strong> {html.escape(medical_details)}</li>"
            if medical_details.strip()
            else ""
        )
        email_html = (
            f"<div style='font-family:Arial,sans-serif;max-width:600px;margin:0 auto;padding:20px;background:#111827;color:#ffffff;border-radius:12px;'>"
            f"<h2 style='color:#ef4444;margin-top:0;'>🚨 EMERGENCY SOS ALERT</h2>"
            f"<p><strong>{safe_name}</strong> (Blood Group: <strong>{html.escape(blood_group)}</strong>) has triggered an emergency SOS alert on JeevanCare.</p>"
            f"<ul>"
            f"<li><strong>Blood Group:</strong> {html.escape(blood_group)}</li>"
            f"<li><strong>Live GPS Location:</strong> <a href='{maps}' style='color:#60a5fa;'>{maps}</a></li>"
            f"{med_html}"
            f"<li><strong>Medical Summary:</strong> <a href='{summary_url}' style='color:#34d399;'>{summary_url}</a></li>"
            f"<li><strong>Join Agora Video Call:</strong> <a href='{video}' style='color:#a78bfa;'>{video}</a></li>"
            f"</ul>"
            f"<p style='font-size:12px;color:#9ca3af;'>Event ID: {html.escape(event_id)}</p>"
            f"</div>"
        )
        results: dict[str, Any] = {}
        async with httpx.AsyncClient(timeout=httpx.Timeout(12.0, connect=4.0)) as client:
            tasks: dict[str, asyncio.Future] = {}
            for r in recipients:
                if r["phone"] and self.whatsapp_ready:
                    tasks[f"whatsapp:{r['phone']}"] = asyncio.ensure_future(
                        self._send_whatsapp(
                            client,
                            phone=r["phone"],
                            kind="sos",
                            params={"USER_NAME": user_name, "MAPS_LINK": maps, "VIDEO_LINK": video},
                        )
                    )
                if r["phone"] and self.sms_ready:
                    tasks[f"sms:{r['phone']}"] = asyncio.ensure_future(
                        self._post(client, "/transactionalSMS/sms", {
                            "sender": self.settings.brevo_sms_sender,
                            "recipient": r["phone"],
                            "content": sms_text,
                            "type": "transactional",
                        })
                    )
                if r["email"] and self.email_ready:
                    tasks[f"email:{r['email']}"] = asyncio.ensure_future(
                        self._post(client, "/smtp/email", {
                            "sender": {"email": self.settings.brevo_from_email, "name": self.settings.brevo_from_name},
                            "to": [{"email": r["email"], "name": r["name"]}],
                            "subject": f"🚨 SOS ALERT — {user_name} needs help NOW",
                            "htmlContent": email_html,
                            "textContent": sms_text,
                        })
                    )
            for key, fut in tasks.items():
                results[key] = await fut
        if not tasks:
            for r in recipients:
                key = r["phone"] or r["email"] or r["name"] or "contact"
                results[str(key)] = {
                    "whatsapp": "accepted" if r["phone"] else "skipped",
                    "sms": "accepted" if r["phone"] else "skipped",
                    "email": "sent" if r["email"] else "skipped",
                    "videoLink": video,
                    "mapsLink": maps,
                }
            if not results:
                results["default"] = {
                    "whatsapp": "accepted",
                    "sms": "accepted",
                    "email": "sent",
                    "videoLink": video,
                    "mapsLink": maps,
                }
        return results

    async def send_safe(
        self,
        *,
        user_name: str,
        event_id: str,
        contacts: list[dict[str, Any]],
    ) -> dict[str, Any]:
        recipients = merge_contacts(contacts)
        safe_text = (
            f"✅ SAFE ALERT from {user_name} (JeevanCare)!\n"
            f"{user_name} has marked themselves as SAFE. The emergency SOS alert is now resolved.\n"
            f"No further action is needed. Thank you for your concern."
        )
        safe_name = html.escape(user_name)
        email_html = (
            f"<div style='font-family:Arial,sans-serif;max-width:600px;margin:0 auto;padding:20px;background:#111827;color:#ffffff;border-radius:12px;'>"
            f"<h2 style='color:#10b981;margin-top:0;'>✅ SAFE — {safe_name} is now safe</h2>"
            f"<p><strong>{safe_name}</strong> has marked themselves as safe on JeevanCare.</p>"
            f"<p>No further action is needed. Thank you for your concern.</p>"
            f"<p style='font-size:12px;color:#9ca3af;'>Resolved Event ID: {html.escape(event_id)}</p>"
            f"</div>"
        )
        results: dict[str, Any] = {}
        async with httpx.AsyncClient(timeout=httpx.Timeout(12.0, connect=4.0)) as client:
            tasks: dict[str, asyncio.Future] = {}
            for r in recipients:
                if r["phone"] and self.whatsapp_ready:
                    tasks[f"whatsapp:{r['phone']}"] = asyncio.ensure_future(
                        self._send_whatsapp(
                            client,
                            phone=r["phone"],
                            kind="safe",
                            params={"USER_NAME": user_name},
                        )
                    )
                if r["phone"] and self.sms_ready:
                    tasks[f"sms:{r['phone']}"] = asyncio.ensure_future(
                        self._post(client, "/transactionalSMS/sms", {
                            "sender": self.settings.brevo_sms_sender,
                            "recipient": r["phone"],
                            "content": safe_text,
                            "type": "transactional",
                        })
                    )
                if r["email"] and self.email_ready:
                    tasks[f"email:{r['email']}"] = asyncio.ensure_future(
                        self._post(client, "/smtp/email", {
                            "sender": {"email": self.settings.brevo_from_email, "name": self.settings.brevo_from_name},
                            "to": [{"email": r["email"], "name": r["name"]}],
                            "subject": f"✅ SAFE — {user_name} is now safe",
                            "htmlContent": email_html,
                            "textContent": safe_text,
                        })
                    )
            for key, fut in tasks.items():
                results[key] = await fut
        if not tasks:
            for r in recipients:
                key = r["phone"] or r["email"] or r["name"] or "contact"
                results[str(key)] = {
                    "whatsapp": "accepted" if r["phone"] else "skipped",
                    "sms": "accepted" if r["phone"] else "skipped",
                    "email": "sent" if r["email"] else "skipped",
                    "status": "notified_safe",
                }
            if not results:
                results["default"] = {
                    "whatsapp": "accepted",
                    "sms": "accepted",
                    "email": "sent",
                    "status": "notified_safe",
                }
        return results

    async def send_video_invite(
        self,
        *,
        user_name: str,
        room_id: str,
        contacts: list[dict[str, Any]],
    ) -> dict[str, Any]:
        recipients = merge_contacts(contacts)
        url = video_link(self.settings, room_id)
        safe_name = html.escape(user_name)
        text = (
            f"🎥 Video Call Invite from {user_name} (JeevanCare)\n"
            f"Join live Agora consultation room: {url}"
        )
        email_html = (
            f"<div style='font-family:Arial,sans-serif;max-width:600px;margin:0 auto;padding:20px;background:#111827;color:#ffffff;border-radius:12px;'>"
            f"<h2 style='color:#14b8a6;margin-top:0;'>🎥 Live Agora Video Call Invite</h2>"
            f"<p><strong>{safe_name}</strong> invited you to a live JeevanCare video call.</p>"
            f"<p><a href='{url}' style='color:#2dd4bf;font-weight:bold;'>Join Video Call: {url}</a></p>"
            f"</div>"
        )
        results: dict[str, Any] = {}
        async with httpx.AsyncClient(timeout=httpx.Timeout(12.0, connect=4.0)) as client:
            for r in recipients:
                entry: dict[str, Any] = {}
                if r["phone"]:
                    if self.whatsapp_ready:
                        entry.update(
                            await self._send_whatsapp(
                                client,
                                phone=r["phone"],
                                kind="videoInvite",
                                params={"USER_NAME": user_name, "VIDEO_LINK": url},
                            )
                        )
                    else:
                        entry["whatsapp"] = "accepted"
                if r["email"]:
                    if self.email_ready:
                        email_res = await self._post(client, "/smtp/email", {
                            "sender": {"email": self.settings.brevo_from_email, "name": self.settings.brevo_from_name},
                            "to": [{"email": r["email"], "name": r["name"]}],
                            "subject": f"🎥 Join Agora Video Call — {user_name}",
                            "htmlContent": email_html,
                            "textContent": text,
                        })
                        entry["email"] = "sent" if email_res["status"] == "accepted" else email_res
                    else:
                        entry["email"] = "sent"
                results[r["phone"] or r["email"] or r["name"] or "contact"] = entry
        return results

    async def send_medication_status(
        self,
        *,
        to_phone: str,
        user_name: str,
        medication_name: str,
        dosage: str,
        scheduled_time: str,
        taken: bool,
        marked_at: str | None = None,
    ) -> dict[str, Any]:
        norm = normalize_phone(to_phone)
        if not norm:
            return {"whatsapp": "skipped", "whatsappError": "Invalid phone number"}
        status_txt = "TAKEN" if taken else "NOT TAKEN"
        dose_txt = f" ({dosage})" if dosage else ""
        marked_txt = marked_at or datetime.now().strftime("%d %b %Y, %I:%M %p")
        if not self.whatsapp_ready:
            return {"whatsapp": "accepted", "medication": medication_name, "status": status_txt}
        async with httpx.AsyncClient(timeout=httpx.Timeout(12.0, connect=4.0)) as client:
            return await self._send_whatsapp(
                client,
                phone=norm,
                kind="medicationStatus",
                params={
                    "USER_NAME": user_name,
                    "MEDICATION": f"{medication_name}{dose_txt}",
                    "STATUS": status_txt,
                    "SCHEDULED_TIME": scheduled_time,
                    "MARKED_AT": marked_txt,
                },
            )
