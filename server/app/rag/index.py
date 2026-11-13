"""Hybrid retriever: BM25 + dense (bge-small, ONNX) fused with Reciprocal Rank Fusion, optional cross-encoder rerank.

Shared knowledge-base vectors are cached on disk (keyed by content + model hash) so restarts are instant.
Per-user documents live in the same index with an `owner` tag and are only ever returned to that user.
"""
from __future__ import annotations

import hashlib
import logging
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np

from .bm25 import BM25
from .chunker import Chunk, chunk_markdown
from .models import Embedder, Reranker

log = logging.getLogger("jeevan.rag.index")
KNOWLEDGE_DIR = Path(__file__).parent / "knowledge"
CACHE_DIR = Path(__file__).resolve().parents[2] / ".cache"
RRF_K = 60


@dataclass
class Hit:
    chunk: Chunk
    score: float


class HybridIndex:
    def __init__(self, embedder: Optional[Embedder] = None, reranker: Optional[Reranker] = None) -> None:
        self.embedder = embedder
        self.reranker = reranker
        self._lock = threading.RLock()
        self.shared: list[Chunk] = []
        self._shared_vecs: Optional[np.ndarray] = None
        self._shared_bm25: Optional[BM25] = None
        self._user_chunks: dict[str, list[Chunk]] = {}
        self._user_vecs: dict[str, Optional[np.ndarray]] = {}
        self._user_bm25: dict[str, BM25] = {}

    # ── building ─────────────────────────────────────────────────
    def build_shared(self, directory: Path = KNOWLEDGE_DIR) -> None:
        chunks: list[Chunk] = []
        for path in sorted(directory.glob("*.md")):
            title = path.stem.replace("_", " ").replace("-", " ").title()
            chunks.extend(chunk_markdown(title, path.read_text(encoding="utf-8")))
        texts = [c.indexed_text for c in chunks]
        vecs = self._load_or_embed(texts) if self.embedder and self.embedder.ready else None
        with self._lock:
            self.shared, self._shared_vecs, self._shared_bm25 = chunks, vecs, BM25(texts)
        log.info("knowledge base: %d chunks, dense=%s", len(chunks), vecs is not None)

    def _load_or_embed(self, texts: list[str]) -> np.ndarray:
        assert self.embedder is not None
        digest = hashlib.sha256((self.embedder.model_name + "\x00" + "\x00".join(texts)).encode()).hexdigest()[:20]
        path = CACHE_DIR / f"kb_{digest}.npy"
        if path.exists():
            try:
                return np.load(path)
            except (OSError, ValueError):
                pass
        vecs = self.embedder.embed_documents(texts)
        try:
            CACHE_DIR.mkdir(exist_ok=True)
            np.save(path, vecs)
        except OSError:
            pass
        return vecs

    def set_user_documents(self, user_id: str, docs: list[tuple[str, str]]) -> int:
        """Replace a user's private documents. docs = [(title, text)]."""
        chunks: list[Chunk] = []
        for title, text in docs:
            chunks.extend(chunk_markdown(title, text, owner=user_id))
        texts = [c.indexed_text for c in chunks]
        vecs = self.embedder.embed_documents(texts) if (chunks and self.embedder and self.embedder.ready) else None
        with self._lock:
            self._user_chunks[user_id] = chunks
            self._user_vecs[user_id] = vecs
            if chunks:
                self._user_bm25[user_id] = BM25(texts)
            else:
                self._user_bm25.pop(user_id, None)
        return len(chunks)

    def has_user_documents(self, user_id: str) -> bool:
        return user_id in self._user_chunks

    def user_document_count(self, user_id: str) -> int:
        return len(self._user_chunks.get(user_id, []))

    # ── search ───────────────────────────────────────────────────
    def search(self, query: str, user_id: Optional[str] = None, k: int = 5, pool: int = 16) -> list[Hit]:
        with self._lock:
            chunks = list(self.shared)
            bm = [self._shared_bm25.scores(query)] if self._shared_bm25 else [[]]
            vec_parts = [self._shared_vecs]
            if user_id and self._user_chunks.get(user_id):
                chunks += self._user_chunks[user_id]
                bm.append(self._user_bm25[user_id].scores(query))
                vec_parts.append(self._user_vecs.get(user_id))
        if not chunks:
            return []
        fused: dict[int, float] = {}
        # BM25 scores are only comparable *within* a corpus (IDF differs), so rank each corpus on its own
        # and fuse by rank. Otherwise a tiny private corpus is drowned out by the shared knowledge base.
        offset = 0
        for part in bm:
            arr = np.asarray(part, dtype=np.float32)
            for rank, idx in enumerate(np.argsort(-arr)[:pool]):
                if arr[idx] > 0:
                    gi = offset + int(idx)
                    fused[gi] = fused.get(gi, 0.0) + 1.0 / (RRF_K + rank + 1)
            offset += len(arr)

        if self.embedder and self.embedder.ready and all(v is not None for v in vec_parts):
            matrix = np.vstack([v for v in vec_parts if v is not None])
            dense = matrix @ self.embedder.embed_query(query)  # cosine (vectors are L2-normalised); comparable across corpora
            for rank, idx in enumerate(np.argsort(-dense)[:pool]):
                fused[int(idx)] = fused.get(int(idx), 0.0) + 1.0 / (RRF_K + rank + 1)
        ranked = sorted(fused.items(), key=lambda kv: kv[1], reverse=True)[:pool]
        if not ranked:
            return []

        if self.reranker and self.reranker.ready and len(ranked) > 1:
            scores = self.reranker.score(query, [chunks[i].indexed_text for i, _ in ranked])
            if scores is not None:
                ranked = sorted(((i, s) for (i, _), s in zip(ranked, scores)), key=lambda kv: kv[1], reverse=True)
        return [Hit(chunks[i], float(s)) for i, s in ranked[:k]]

# Jeevan sync: 2026-11-13
