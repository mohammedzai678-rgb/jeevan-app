"""Jeevan App API - FastAPI entrypoint.

Run:  uvicorn app.main:app --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import asyncio
import logging
import os
from contextlib import asynccontextmanager
from typing import AsyncIterator

import httpx
from fastapi import FastAPI
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings, get_settings
from .ctx import Context
from .hub import Hub
from .notify import Notifier
from .persistence import Persistence
from .rag.index import HybridIndex
from .rag.models import Embedder, Reranker
from .routers import app_api, assistant, device, ecosystem, health_vault, rtc, stick, tomtom, web_pages

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("jeevan")


def _build_index() -> HybridIndex:
    """Blocking: loads ONNX models and embeds the knowledge base. Runs in a worker thread at startup."""
    dense = os.getenv("RAG_DENSE", "true").lower() != "false"
    rerank = os.getenv("RAG_RERANK", "true").lower() != "false"
    embedder = Embedder(os.getenv("RAG_EMBED_MODEL", "BAAI/bge-small-en-v1.5")) if dense else None
    if embedder and not embedder.load():
        embedder = None
    reranker = Reranker(os.getenv("RAG_RERANK_MODEL", "Xenova/ms-marco-MiniLM-L-6-v2")) if (rerank and embedder) else None
    if reranker and not reranker.load():
        reranker = None
    index = HybridIndex(embedder, reranker)
    index.build_shared()
    return index


def create_app(settings: Settings | None = None, index: HybridIndex | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        persist = Persistence(settings)
        await persist.start()
        hub = Hub(settings)
        if persist.enabled:
            hub.load_pairings(await persist.select("device_pairings", {"select": "device_id,user_id"}))
        idx = index or await run_in_threadpool(_build_index)
        http = httpx.AsyncClient(limits=httpx.Limits(max_keepalive_connections=10, keepalive_expiry=60))
        ctx = Context(settings=settings, hub=hub, persist=persist, notifier=Notifier(settings), index=idx, http=http)
        app.state.ctx = ctx
        watchdog = asyncio.create_task(hub.watchdog())
        if not settings.device_api_key:
            log.warning("DEVICE_API_KEY is empty: all hardware endpoints will return 503")
        try:
            yield
        finally:
            watchdog.cancel()
            for t in list(ctx.tasks):
                t.cancel()
            await http.aclose()
            await persist.stop()

    app = FastAPI(title="Jeevan App API", version="1.0.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(device.router)
    app.include_router(app_api.router)
    app.include_router(assistant.router)
    app.include_router(health_vault.router)
    app.include_router(rtc.router)
    app.include_router(tomtom.router)
    app.include_router(stick.router)
    app.include_router(ecosystem.router)
    app.include_router(web_pages.router)

    @app.get("/health")
    async def health() -> dict:
        ctx: Context = app.state.ctx
        return {
            "status": "ok",
            "persistence": ctx.persist.enabled,
            "llm": bool(settings.gemini_api_key),
            "rag": {
                "chunks": len(ctx.index.shared),
                "dense": bool(ctx.index.embedder and ctx.index.embedder.ready),
                "rerank": bool(ctx.index.reranker and ctx.index.reranker.ready),
            },
            "devices_online": sum(1 for s in ctx.hub.devices.values() if ctx.hub.is_online(s)),
        }

    return app


app = create_app()
