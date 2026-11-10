"""Pure-Python Agora AccessToken2 (007) builder for RTC channels.

Matches the official `agora-token` `RtcTokenBuilder.buildTokenWithUserAccount` binary format
using standard-library `hmac`, `hashlib`, `struct`, `zlib`, and `base64` (<0.1 ms per token).
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import re
import secrets
import struct
import time
import zlib
from typing import Literal

VERSION = "007"
SERVICE_TYPE_RTC = 1

PRIVILEGE_JOIN_CHANNEL = 1
PRIVILEGE_PUBLISH_AUDIO = 2
PRIVILEGE_PUBLISH_VIDEO = 3
PRIVILEGE_PUBLISH_DATA = 4

Role = Literal["publisher", "subscriber"]


def _pack_uint16(v: int) -> bytes:
    return struct.pack("<H", v)


def _pack_uint32(v: int) -> bytes:
    return struct.pack("<I", v)


def _pack_string(s: str | bytes) -> bytes:
    raw = s.encode("utf-8") if isinstance(s, str) else s
    return _pack_uint16(len(raw)) + raw


def _pack_map_uint32(m: dict[int, int]) -> bytes:
    items = sorted(m.items(), key=lambda kv: kv[0])
    return _pack_uint16(len(items)) + b"".join(_pack_uint16(k) + _pack_uint32(v) for k, v in items)


def sanitize_channel(channel_id: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9!#$%&()+\-:;<=.>?@\[\]^_{|}~,\s]", "-", (channel_id or "").strip())
    return cleaned[:63]


def sanitize_uid(uid: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9_-]", "-", (uid or "").strip())
    return (cleaned or f"guest-{int(time.time())}")[:64]


def build_rtc_token(
    *,
    app_id: str,
    app_certificate: str,
    channel_id: str,
    uid: str,
    role: Role = "publisher",
    expires_in_seconds: int = 3600,
) -> dict[str, object]:
    channel = sanitize_channel(channel_id)
    if not channel:
        raise ValueError("channelId required")
    if not app_id or not app_certificate:
        raise RuntimeError("Agora credentials are not configured")

    account = sanitize_uid(uid)
    now = int(time.time())
    ttl = max(60, min(int(expires_in_seconds or 3600), 24 * 3600))
    expires_at = now + ttl
    salt = secrets.randbits(32) or 1

    privileges: dict[int, int] = {PRIVILEGE_JOIN_CHANNEL: expires_at}
    if role == "publisher":
        privileges[PRIVILEGE_PUBLISH_AUDIO] = expires_at
        privileges[PRIVILEGE_PUBLISH_VIDEO] = expires_at
        privileges[PRIVILEGE_PUBLISH_DATA] = expires_at

    # Signing key hierarchy per Agora AccessToken2 specification
    sig_key = hmac.new(_pack_uint32(now), app_certificate.encode("utf-8"), hashlib.sha256).digest()
    sig_key = hmac.new(_pack_uint32(salt), sig_key, hashlib.sha256).digest()

    service_payload = (
        _pack_uint16(SERVICE_TYPE_RTC)
        + _pack_map_uint32(privileges)
        + _pack_string(channel)
        + _pack_string(account)
    )
    signing_info = (
        _pack_string(app_id)
        + _pack_uint32(now)
        + _pack_uint32(ttl)
        + _pack_uint32(salt)
        + _pack_uint16(1)  # 1 service (RTC)
        + service_payload
    )
    signature = hmac.new(sig_key, signing_info, hashlib.sha256).digest()
    compressed = zlib.compress(_pack_string(signature) + signing_info)
    token = VERSION + base64.b64encode(compressed).decode("ascii")

    return {
        "appId": app_id,
        "channelId": channel,
        "uid": account,
        "role": role,
        "token": token,
        "expiresAt": expires_at,
    }
