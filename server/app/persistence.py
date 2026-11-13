"""Fire-and-forget persistence to Supabase (PostgREST). Never on the hot path; failures are logged only."""
from __future__ import annotations

import logging
from typing import Any, Optional

import httpx

from .config import Settings

log = logging.getLogger("jeevan.persist")


class PersistenceQueryError(RuntimeError):
    def __init__(
        self,
        status_code: int | None = None,
        error_code: str | None = None,
    ) -> None:
        self.status_code = status_code
        self.error_code = error_code
        super().__init__("Supabase query failed")


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
        headers = {"apikey": key, "Content-Type": "application/json"}
        # New Supabase secret keys (sb_secret_...) are opaque API keys, not
        # JWTs. Sending one as a Bearer token makes PostgREST reject it as an
        # invalid JWT. Legacy service-role keys are JWTs and still need the
        # Authorization header to select the service_role database role.
        if not key.startswith("sb_secret_"):
            headers["Authorization"] = f"Bearer {key}"
        self._client = httpx.AsyncClient(
            base_url=f"{self.settings.supabase_url.rstrip('/')}/rest/v1",
            headers=headers,
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

    async def _send_required(self, method: str, table: str, *, json: Any = None, params: dict | None = None, prefer: str = "return=minimal") -> httpx.Response:
        if not self._client:
            raise PersistenceQueryError()
        try:
            resp = await self._client.request(
                method,
                f"/{table}",
                json=json,
                params=params,
                headers={"Prefer": prefer},
            )
        except httpx.HTTPError as exc:
            log.warning("supabase %s %s failed: %s", method, table, exc)
            raise PersistenceQueryError() from exc
        if resp.status_code >= 400:
            log.warning("supabase %s %s -> %s %s", method, table, resp.status_code, resp.text[:200])
            error_code = None
            try:
                error_body = resp.json()
                if isinstance(error_body, dict):
                    code = error_body.get("code")
                    error_code = code if isinstance(code, str) else None
            except ValueError:
                pass
            raise PersistenceQueryError(resp.status_code, error_code)
        return resp

    async def insert_required(self, table: str, row: dict[str, Any]) -> None:
        await self._send_required("POST", table, json=row)

    async def upsert_required(self, table: str, row: dict[str, Any], on_conflict: str) -> None:
        await self._send_required(
            "POST",
            table,
            json=row,
            params={"on_conflict": on_conflict},
            prefer="resolution=merge-duplicates,return=minimal",
        )

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

    async def select_required(self, table: str, params: dict[str, str]) -> list[dict[str, Any]]:
        """Select rows when an empty result must be distinguishable from a database failure."""
        resp = await self._send_required(
            "GET", table, params=params, prefer="return=representation"
        )
        try:
            data = resp.json()
        except ValueError as exc:
            raise PersistenceQueryError(resp.status_code) from exc
        if not isinstance(data, list):
            raise PersistenceQueryError(resp.status_code)
        return data
