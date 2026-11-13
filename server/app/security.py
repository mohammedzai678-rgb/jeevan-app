"""Authentication: Supabase user JWTs (HS256 secret or asymmetric JWKS) and the ESP32 device key."""
from __future__ import annotations

import hmac
import uuid
from dataclasses import dataclass
from typing import Optional

import jwt
from fastapi import HTTPException, Request, WebSocket, status
from fastapi.concurrency import run_in_threadpool
from jwt import PyJWKClient

from .config import Settings, get_settings


@dataclass(frozen=True)
class User:
    id: str
    email: Optional[str] = None


_jwks_clients: dict[str, PyJWKClient] = {}


def _jwks_client(supabase_url: str) -> PyJWKClient:
    url = f"{supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"
    client = _jwks_clients.get(url)
    if client is None:
        client = PyJWKClient(url, cache_keys=True, lifespan=3600)
        _jwks_clients[url] = client
    return client


def _decode(token: str, settings: Settings) -> User:
    try:
        alg = jwt.get_unverified_header(token).get("alg", "")
    except jwt.PyJWTError as exc:
        raise ValueError("malformed token") from exc

    # Explicit allow-list per key type: never trust the header alone.
    if alg == "HS256":
        if not settings.supabase_jwt_secret:
            raise ValueError("HS256 tokens are not accepted by this server")
        key: object = settings.supabase_jwt_secret
        algorithms = ["HS256"]
    elif alg in ("ES256", "RS256"):
        if not settings.supabase_url:
            raise ValueError("asymmetric tokens are not accepted by this server")
        key = _jwks_client(settings.supabase_url).get_signing_key_from_jwt(token).key
        algorithms = [alg]
    else:
        raise ValueError("unsupported token algorithm")

    if not settings.supabase_url:
        raise ValueError("SUPABASE_URL is not configured")
    issuer = f"{settings.supabase_url.rstrip('/')}/auth/v1"
    claims = jwt.decode(
        token,
        key,
        algorithms=algorithms,
        audience="authenticated",
        issuer=issuer,
    )  # type: ignore[arg-type]
    sub = claims.get("sub")
    if not isinstance(sub, str):
        raise ValueError("token subject is not a Supabase user ID")
    try:
        user_id = str(uuid.UUID(sub))
    except (ValueError, AttributeError) as exc:
        raise ValueError("token subject is not a Supabase user ID") from exc
    if claims.get("role") != "authenticated":
        raise ValueError("token is not an authenticated user session")
    return User(id=user_id, email=claims.get("email"))


async def verify_token(token: str, settings: Settings | None = None) -> User:
    settings = settings or get_settings()
    try:
        # JWKS fetch can block on the first call; keep the event loop free.
        return await run_in_threadpool(_decode, token, settings)
    except (jwt.PyJWTError, ValueError) as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"Invalid token: {exc}") from exc


def _bearer(value: str | None) -> str | None:
    if not value:
        return None
    parts = value.split(None, 1)
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1].strip()
    return None


def _req_settings(obj: Request | WebSocket) -> Settings:
    ctx = getattr(obj.app.state, "ctx", None)
    return ctx.settings if ctx is not None else get_settings()


async def current_user(request: Request) -> User:
    token = _bearer(request.headers.get("authorization"))
    if not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing bearer token")
    return await verify_token(token, _req_settings(request))


async def websocket_user(ws: WebSocket) -> User | None:
    """Auth for WebSocket upgrades. Token comes from the Authorization header (never the URL)."""
    token = _bearer(ws.headers.get("authorization"))
    if not token:
        return None
    try:
        return await verify_token(token, _req_settings(ws))
    except HTTPException:
        return None


def device_key_valid(supplied: str | None, settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    expected = settings.device_api_key
    if not expected or not supplied:
        return False
    return hmac.compare_digest(supplied.encode(), expected.encode())


def supplied_device_key(request: Request, body: dict | None = None) -> str | None:
    header = request.headers.get("x-device-key") or _bearer(request.headers.get("authorization"))
    if header:
        return header
    if body and isinstance(body.get("api_key"), str):
        return body["api_key"]
    return request.query_params.get("api_key")


def require_device(request: Request, body: dict | None = None) -> None:
    settings = _req_settings(request)
    if not settings.device_api_key:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "DEVICE_API_KEY is not configured on the server")
    if not device_key_valid(supplied_device_key(request, body), settings):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Unauthorized hardware device key")
# Jeevan sync: 2026-11-13
