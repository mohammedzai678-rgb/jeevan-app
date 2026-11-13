"""RAG assistant: hybrid retrieval over the shared knowledge base + the user's own documents, streamed over SSE."""
from __future__ import annotations

import json
import logging
import time
from typing import Any, AsyncIterator, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from ..ctx import Context, get_ctx
from ..rag import llm
from ..security import User, current_user

log = logging.getLogger("jeevan.assistant")
router = APIRouter(prefix="/api/assistant", tags=["assistant"])
PROFILE_TTL_S = 300


class Turn(BaseModel):
    role: str
    content: str = Field(max_length=4000)


class ChatBody(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    history: list[Turn] = Field(default_factory=list, max_length=20)
    device_id: Optional[str] = None


class DocBody(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    text: str = Field(min_length=1, max_length=50_000)


def _sse(event: str, data: Any) -> bytes:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n".encode()


async def _ensure_user_docs(ctx: Context, user_id: str) -> None:
    """Load the user's saved documents (once per process) into the in-memory index."""
    if user_id in ctx.docs_loaded:
        return
    ctx.docs_loaded.add(user_id)
    rows = await ctx.persist.select("rag_documents", {"user_id": f"eq.{user_id}", "select": "title,content", "order": "created_at.asc"})
    if rows:
        ctx.user_docs_mem[user_id] = [(r["title"], r["content"]) for r in rows]
        await run_in_threadpool(ctx.index.set_user_documents, user_id, ctx.user_docs_mem[user_id])

async def _profile_text(ctx: Context, user_id: str) -> Optional[str]:
    cached = ctx.profile_cache.get(user_id)
    if cached and time.time() - cached[0] < PROFILE_TTL_S:
        return cached[1] or None
    rows = await ctx.persist.select(
        "emergency_summaries",
        {"uid": f"eq.{user_id}", "select": "name,bloodType,dob,allergies,conditions,currentMedications", "limit": "1"},
    )
    text = ""
    if rows:
        r = rows[0]
        bits = [
            f"Blood type: {r['bloodType']}" if r.get("bloodType") else "",
            f"Allergies: {', '.join(r['allergies'])}" if r.get("allergies") else "",
            f"Conditions: {', '.join(r['conditions'])}" if r.get("conditions") else "",
            f"Current medications: {', '.join(r['currentMedications'])}" if r.get("currentMedications") else "",
        ]
        text = "\n".join(b for b in bits if b)
    ctx.profile_cache[user_id] = (time.time(), text)
    return text or None


def _vitals_text(ctx: Context, user_id: str, device_id: Optional[str]) -> Optional[str]:
    dev = device_id if device_id and ctx.hub.owner_of(device_id) == user_id else next(iter(ctx.hub.devices_for(user_id)), None)
    if not dev:
        return None
    snap = ctx.hub.snapshot(dev)
    v = snap["vitals"]
    if not snap["online"] or not v:
        return None
    parts = []
    if "heart_rate" in v:
        parts.append(f"heart rate {v['heart_rate']} BPM")
    if "spo2" in v:
        parts.append(f"SpO2 {v['spo2']}%")
    if "temperature" in v:
        parts.append(f"temperature {v['temperature']} °C")
    if "ecg_bpm" in v:
        parts.append(f"ECG rate {v['ecg_bpm']} BPM")
    if not parts:
        return None
    return f"{', '.join(parts)} (overall: {snap['analysis']['overall_status']})"


def _retrieval_query(message: str, history: list[Turn]) -> str:
    """Cheap follow-up resolution: short/pronoun-heavy questions borrow the previous user turn for retrieval."""
    if len(message.split()) <= 6:
        for t in reversed(history):
            if t.role == "user":
                return f"{t.content} {message}"
    return message


@router.post("/chat")
async def chat(body: ChatBody, request: Request, user: User = Depends(current_user)) -> StreamingResponse:
    ctx = get_ctx(request)

    async def events() -> AsyncIterator[bytes]:
        t0 = time.perf_counter()
        emergency = llm.detect_emergency(body.message)
        if emergency:
            # Don't wait for retrieval or the model: this reaches the screen immediately.
            yield _sse("emergency", {"message": "This may be an emergency. Call your local emergency number or press SOS now."})

        await _ensure_user_docs(ctx, user.id)
        hits = await run_in_threadpool(ctx.index.search, _retrieval_query(body.message, body.history), user.id, 5)
        sources = [
            {"n": i, "title": h.chunk.source, "heading": h.chunk.heading, "private": h.chunk.owner is not None, "snippet": h.chunk.text[:220]}
            for i, h in enumerate(hits, 1)
        ]
        yield _sse("meta", {"sources": sources, "retrieval_ms": int((time.perf_counter() - t0) * 1000), "emergency": emergency})

        profile = await _profile_text(ctx, user.id)
        vitals = _vitals_text(ctx, user.id, body.device_id)
        prompt = llm.build_prompt(body.message, hits, profile, vitals)

        produced = False
        if ctx.settings.gemini_api_key:
            try:
                first = True
                async for token in llm.stream_gemini(ctx.settings, ctx.http, prompt, [t.model_dump() for t in body.history]):
                    if first:
                        first = False
                        yield _sse("timing", {"first_token_ms": int((time.perf_counter() - t0) * 1000)})
                    produced = True
                    yield _sse("token", {"t": token})
            except Exception as exc:  # noqa: BLE001 - never leave the user without an answer
                log.warning("LLM failed, using extractive fallback: %s", exc)
                if produced:
                    yield _sse("token", {"t": "\n\nThe connection interrupted this answer. Please retry to receive the complete guidance."})
        if not produced:
            yield _sse("token", {"t": llm.extractive_answer(hits, emergency)})
            yield _sse("fallback", {"reason": "llm_unavailable" if not ctx.settings.gemini_api_key else "llm_error"})
        yield _sse("done", {"total_ms": int((time.perf_counter() - t0) * 1000)})

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"},
    )


@router.post("/documents")
async def add_document(body: DocBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    """Add a private document (prescription text, discharge summary, allergy list...) to the user's own index."""
    ctx = get_ctx(request)
    await _ensure_user_docs(ctx, user.id)
    docs = ctx.user_docs_mem.setdefault(user.id, [])
    docs.append((body.title, body.text))
    count = await run_in_threadpool(ctx.index.set_user_documents, user.id, docs)
    if ctx.persist.enabled:
        ctx.spawn(ctx.persist.insert("rag_documents", {"user_id": user.id, "title": body.title, "content": body.text}))
    return {"status": "indexed", "chunks": count}


@router.get("/documents")
async def documents_status(request: Request, user: User = Depends(current_user)) -> dict[str, int]:
    ctx = get_ctx(request)
    await _ensure_user_docs(ctx, user.id)
    return {"chunks": ctx.index.user_document_count(user.id)}


@router.delete("/documents")
async def clear_documents(request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    if ctx.persist.enabled:
        await ctx.persist._send("DELETE", "rag_documents", params={"user_id": f"eq.{user.id}"})
    ctx.user_docs_mem.pop(user.id, None)
    await run_in_threadpool(ctx.index.set_user_documents, user.id, [])
    return {"status": "cleared"}
# Jeevan sync: 2026-11-13
