"""Transformer models (ONNX via fastembed): dense embedder + optional cross-encoder reranker.

Both are optional at runtime: if `fastembed` or a model download is unavailable the index transparently
degrades to BM25-only, so the API always answers.
"""
from __future__ import annotations

import logging
from collections import OrderedDict
from typing import Optional

import numpy as np

log = logging.getLogger("jeevan.rag.models")

DEFAULT_EMBED_MODEL = "BAAI/bge-small-en-v1.5"
DEFAULT_RERANK_MODEL = "Xenova/ms-marco-MiniLM-L-6-v2"
# BGE retrieval models expect this prefix on *queries* (not documents).
_BGE_QUERY_PREFIX = "Represent this sentence for searching relevant passages: "


class Embedder:
    def __init__(self, model_name: str = DEFAULT_EMBED_MODEL, cache_size: int = 512) -> None:
        self.model_name = model_name
        self._model = None
        self._cache: OrderedDict[str, np.ndarray] = OrderedDict()
        self._cache_size = cache_size

    def load(self) -> bool:
        try:
            from fastembed import TextEmbedding  # heavy import, keep lazy

            self._model = TextEmbedding(model_name=self.model_name)
            # warm-up: first ONNX call JITs kernels; pay it at startup rather than on the first user query
            list(self._model.embed(["warm up"]))
            log.info("embedding model ready: %s", self.model_name)
            return True
        except Exception as exc:  # noqa: BLE001 - any failure means "run without dense"
            log.warning("dense embeddings unavailable (%s) - falling back to BM25 only", exc)
            self._model = None
            return False

    @property
    def ready(self) -> bool:
        return self._model is not None

    @staticmethod
    def _norm(mat: np.ndarray) -> np.ndarray:
        n = np.linalg.norm(mat, axis=-1, keepdims=True)
        return mat / np.maximum(n, 1e-12)

    def embed_documents(self, texts: list[str]) -> np.ndarray:
        assert self._model is not None
        vecs = np.asarray(list(self._model.embed(texts)), dtype=np.float32)
        return self._norm(vecs)

    def embed_query(self, text: str) -> np.ndarray:
        assert self._model is not None
        hit = self._cache.get(text)
        if hit is not None:
            self._cache.move_to_end(text)
            return hit
        prefix = _BGE_QUERY_PREFIX if "bge" in self.model_name.lower() else ""
        vec = self._norm(np.asarray(list(self._model.embed([prefix + text])), dtype=np.float32))[0]
        self._cache[text] = vec
        if len(self._cache) > self._cache_size:
            self._cache.popitem(last=False)
        return vec


class Reranker:
    def __init__(self, model_name: str = DEFAULT_RERANK_MODEL) -> None:
        self.model_name = model_name
        self._model = None

    def load(self) -> bool:
        try:
            from fastembed.rerank.cross_encoder import TextCrossEncoder

            self._model = TextCrossEncoder(model_name=self.model_name)
            list(self._model.rerank("warm up", ["warm up"]))
            log.info("reranker ready: %s", self.model_name)
            return True
        except Exception as exc:  # noqa: BLE001
            log.warning("reranker unavailable (%s) - skipping rerank stage", exc)
            self._model = None
            return False

    @property
    def ready(self) -> bool:
        return self._model is not None

    def score(self, query: str, passages: list[str]) -> Optional[list[float]]:
        if not self._model or not passages:
            return None
        return [float(s) for s in self._model.rerank(query, passages)]
# Jeevan sync: 2026-11-13
