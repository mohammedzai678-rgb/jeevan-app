"""Answer generation: emergency detection, grounded prompt, streaming Gemini, offline extractive fallback."""
from __future__ import annotations

import json
import logging
import re
from typing import Any, AsyncIterator, Optional

import httpx

from ..config import Settings
from .index import Hit

log = logging.getLogger("jeevan.rag.llm")

_EMERGENCY = re.compile(
    r"chest (pain|tightness|pressure)|can'?t breathe|cannot breathe|difficulty breathing|not breathing|stopped breathing|"
    r"unconscious|unresponsive|passed out|seizure|convuls|stroke|face droop|slurred speech|severe bleeding|"
    r"won'?t stop bleeding|overdose|poison|swallowed|anaphyla|throat (closing|swelling)|suicid|kill myself|"
    r"snake ?bite|heart attack|choking|drown|electric shock|head injury",
    re.I,
)

SYSTEM_PROMPT = """You are Jeevan, a calm, precise health & first-aid assistant inside an emergency-readiness app.
Rules:
1. Ground every medical statement in the numbered CONTEXT passages and cite them like [1], [2]. If the context does not cover the question, say so plainly, then give only widely-accepted general guidance.
2. Use the USER PROFILE and LIVE VITALS when relevant (allergies, conditions, medications, current readings). Never invent values.
3. For anything life-threatening, FIRST line: tell the user to call their local emergency number / press the SOS button, then give the immediate steps.
4. Answer the question fully. Use clear sections and numbered steps for procedures; do not stop mid-instruction. No diagnosis certainty; you support, you do not replace a clinician.
5. Reply in the user's language."""


def detect_emergency(text: str) -> bool:
    return bool(_EMERGENCY.search(text))


def build_prompt(question: str, hits: list[Hit], profile: Optional[str], vitals: Optional[str]) -> str:
    ctx = "\n\n".join(f"[{i}] ({h.chunk.source} - {h.chunk.heading})\n{h.chunk.text}" for i, h in enumerate(hits, 1))
    parts = [f"CONTEXT:\n{ctx or '(no relevant passages found)'}"]
    if profile:
        parts.append(f"USER PROFILE:\n{profile}")
    if vitals:
        parts.append(f"LIVE VITALS:\n{vitals}")
    parts.append(f"QUESTION:\n{question}")
    return "\n\n".join(parts)


def extractive_answer(hits: list[Hit], emergency: bool) -> str:
    """No-LLM fallback: instant, offline, still grounded - returns the best passages verbatim."""
    lines = []
    if emergency:
        lines.append("**This may be an emergency. Call your local emergency number now or press SOS.**\n")
    if not hits:
        lines.append("I couldn't find guidance on that in my knowledge base. Please consult a clinician.")
        return "\n".join(lines)
    lines.append("Here is what I found in the Jeevan knowledge base:\n")
    for i, h in enumerate(hits[:3], 1):
        lines.append(f"**{h.chunk.heading}** [{i}]\n{h.chunk.text}\n")
    return "\n".join(lines)


async def stream_gemini(
    settings: Settings,
    client: httpx.AsyncClient,
    prompt: str,
    history: list[dict[str, str]],
    *,
    system_instruction: Optional[str] = None,
    max_output_tokens: int = 3000,
) -> AsyncIterator[str]:
    contents: list[dict[str, Any]] = []
    for turn in history[-8:]:
        role = "user" if turn.get("role") == "user" else "model"
        contents.append({"role": role, "parts": [{"text": str(turn.get("content", ""))[:2000]}]})
    contents.append({"role": "user", "parts": [{"text": prompt}]})
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{settings.gemini_model}:streamGenerateContent?alt=sse"
    complete_answer = ""
    for attempt in range(3):
        body = {
            "systemInstruction": {"parts": [{"text": system_instruction or SYSTEM_PROMPT}]},
            "contents": contents,
            "generationConfig": {"temperature": 0.2, "topP": 0.9, "maxOutputTokens": max_output_tokens},
        }
        finish_reason = ""
        async with client.stream(
            "POST", url, json=body, headers={"x-goog-api-key": settings.gemini_api_key}, timeout=settings.llm_timeout_s
        ) as resp:
            if resp.status_code >= 400:
                detail = (await resp.aread()).decode(errors="ignore")[:200]
                raise RuntimeError(f"Gemini HTTP {resp.status_code}: {detail}")
            async for line in resp.aiter_lines():
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if not payload or payload == "[DONE]":
                    continue
                try:
                    data = json.loads(payload)
                except ValueError:
                    continue
                for cand in data.get("candidates", []):
                    finish_reason = str(cand.get("finishReason") or finish_reason)
                    for part in cand.get("content", {}).get("parts", []):
                        text = part.get("text")
                        if text:
                            complete_answer += text
                            yield text
        if finish_reason != "MAX_TOKENS" or attempt == 2:
            break
        # Continue only when Gemini explicitly reports a token-limit cutoff.
        contents.extend([
            {"role": "model", "parts": [{"text": complete_answer}]},
            {"role": "user", "parts": [{"text": "Continue from the exact point where the answer stopped. Do not repeat earlier content; finish the response completely."}]},
        ])
# Jeevan sync: 2026-11-13
