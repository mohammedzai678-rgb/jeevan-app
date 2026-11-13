"""Agora RTC token endpoints (compatible with both the mobile app and emergency responder invite links)."""
from __future__ import annotations

import time
from typing import Any, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from ..agora import build_rtc_token
from ..ctx import get_ctx
from ..security import User, current_user

router = APIRouter(prefix="/api/rtc", tags=["rtc"])


class PublicTokenBody(BaseModel):
    channelId: str = Field(min_length=1, max_length=128)
    uid: Optional[str] = None
    expiresInSeconds: int = Field(default=3600, ge=60, le=86400)


class CreateChannelBody(BaseModel):
    channelId: str = Field(min_length=1, max_length=128)
    uid: Optional[str] = None
    role: Literal["publisher", "subscriber"] = "publisher"
    expiresInSeconds: int = Field(default=3600, ge=60, le=86400)


def _issue(request: Request, *, channel_id: str, uid: str, role: Literal["publisher", "subscriber"], ttl: int) -> dict[str, Any]:
    s = get_ctx(request).settings
    try:
        return build_rtc_token(
            app_id=s.agora_app_id,
            app_certificate=s.agora_app_certificate,
            channel_id=channel_id,
            uid=uid,
            role=role,
            expires_in_seconds=ttl,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc


@router.post("/public-token")
async def public_token(body: PublicTokenBody, request: Request) -> dict[str, Any]:
    """Public by design so emergency contacts can join the SOS video link without creating an account."""
    return _issue(
        request,
        channel_id=body.channelId,
        uid=body.uid or f"guest-{int(time.time() * 1000)}",
        role="publisher",
        ttl=body.expiresInSeconds,
    )


@router.post("/create-channel")
async def create_channel(body: CreateChannelBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    return _issue(
        request,
        channel_id=body.channelId,
        uid=body.uid or user.id,
        role=body.role,
        ttl=body.expiresInSeconds,
    )
# Jeevan sync: 2026-11-13
