"""Application context shared by routers (one instance, created in the lifespan)."""
from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from typing import Any, Coroutine

import httpx
from fastapi import Request

from .config import Settings
from .hub import Hub
from .notify import Notifier
from .persistence import Persistence
from .rag.index import HybridIndex

log = logging.getLogger("jeevan.ctx")


@dataclass
class Context:
    settings: Settings
    hub: Hub
    persist: Persistence
    notifier: Notifier
    index: HybridIndex
    http: httpx.AsyncClient
    tasks: set[asyncio.Task] = field(default_factory=set)
    docs_loaded: set[str] = field(default_factory=set)
    user_docs_mem: dict[str, list[tuple[str, str]]] = field(default_factory=dict)
    profile_cache: dict[str, tuple[float, str]] = field(default_factory=dict)

    def spawn(self, coro: Coroutine[Any, Any, Any]) -> None:
        """Run work off the request path. Holds a strong ref so the task isn't garbage-collected mid-flight."""
        task = asyncio.create_task(coro)
        self.tasks.add(task)

        def _done(t: asyncio.Task) -> None:
            self.tasks.discard(t)
            if not t.cancelled() and t.exception():
                log.error("background task failed: %r", t.exception())

        task.add_done_callback(_done)


def get_ctx(request: Request) -> Context:
    return request.app.state.ctx

