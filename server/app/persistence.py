"""Fire-and-forget persistence to Supabase (PostgREST). Never on the hot path; failures are logged only."""
from __future__ import annotations

import logging
from typing import Any, Optional

import httpx

from .config import Settings

log = logging.getLogger("jeevan.persist")


class Persistence:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.enabled = settings.persistence_enabled
        self._client: Optional[httpx.AsyncClient] = None

    async def start(self) -> None:
        if not self.enabled:
            log.warning("Supabase not configured - running in memory-only mode (no history, no SOS records)")
            return
        key = self.settings.supabase_service_role_key
        self._client = httpx.AsyncClient(
            base_url=f"{self.settings.supabase_url.rstrip('/')}/rest/v1",
            headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            timeout=httpx.Timeout(8.0, connect=3.0),
            limits=httpx.Limits(max_keepalive_connections=10, keepalive_expiry=60),
        )

    async def stop(self) -> None:
        if self._client:
            await self._client.aclose()

    async def _send(self, method: str, table: str, *, json: Any = None, params: dict | None = None, prefer: str = "return=minimal") -> Optional[httpx.Response]:
        if not self._client:
            return None
        for attempt in (1, 2):
            try:
                resp = await self._client.request(method, f"/{table}", json=json, params=params, headers={"Prefer": prefer})
                if resp.status_code < 400:
                    return resp
                log.warning("supabase %s %s -> %s %s", method, table, resp.status_code, resp.text[:200])
                if resp.status_code < 500:
                    return None
            except httpx.HTTPError as exc:
                log.warning("supabase %s %s failed (attempt %d): %s", method, table, attempt, exc)
        return None

    async def insert(self, table: str, row: dict[str, Any]) -> bool:
        return await self._send("POST", table, json=row) is not None

    async def upsert(self, table: str, row: dict[str, Any], on_conflict: str) -> bool:
        return (
            await self._send("POST", table, json=row, params={"on_conflict": on_conflict}, prefer="resolution=merge-duplicates,return=minimal")
            is not None
        )

    async def update(self, table: str, match: dict[str, str], values: dict[str, Any]) -> bool:
        params = {k: f"eq.{v}" for k, v in match.items()}
        return await self._send("PATCH", table, json=values, params=params) is not None

    async def select(self, table: str, params: dict[str, str]) -> list[dict[str, Any]]:
        resp = await self._send("GET", table, params=params, prefer="return=representation")
        if resp is None:
            return []
        try:
            data = resp.json()
        except ValueError:
            return []
        return data if isinstance(data, list) else []
