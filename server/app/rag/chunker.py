"""Markdown chunker: split on headings, then pack paragraphs into ~target-word windows with overlap."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional

_HEADING = re.compile(r"^(#{1,3})\s+(.*)$")


@dataclass
class Chunk:
    id: str
    source: str  # document title / file stem
    heading: str
    text: str
    owner: Optional[str] = None  # None = shared knowledge base, else a user id
    meta: dict = field(default_factory=dict)

    @property
    def indexed_text(self) -> str:
        """What gets embedded/BM25-indexed: heading context improves recall for short chunks."""
        return f"{self.source} - {self.heading}\n{self.text}" if self.heading else f"{self.source}\n{self.text}"


def chunk_markdown(source: str, markdown: str, owner: Optional[str] = None, target_words: int = 140, overlap_words: int = 25) -> list[Chunk]:
    # Track the full heading path ("Snake bite > What to do"): innermost-only headings like "What to do"
    # are ambiguous across topics and wreck retrieval.
    sections: list[tuple[str, list[str]]] = []
    path: list[tuple[int, str]] = []
    buf: list[str] = []

    def label() -> str:
        return " > ".join(h for _, h in path) or source

    for line in markdown.splitlines():
        m = _HEADING.match(line.strip())
        if m:
            if buf:
                sections.append((label(), buf))
            level, title = len(m.group(1)), m.group(2).strip()
            while path and path[-1][0] >= level:
                path.pop()
            path.append((level, title))
            buf = []
        else:
            buf.append(line)
    if buf:
        sections.append((label(), buf))

    chunks: list[Chunk] = []
    for head, lines in sections:
        body = "\n".join(lines).strip()
        if not body:
            continue
        words = body.split()
        if len(words) <= target_words * 1.4:
            windows = [body]
        else:
            windows, start = [], 0
            while start < len(words):
                end = min(start + target_words, len(words))
                windows.append(" ".join(words[start:end]))
                if end == len(words):
                    break
                start = end - overlap_words
        for w in windows:
            chunks.append(Chunk(id=f"{owner or 'kb'}:{source}:{len(chunks)}", source=source, heading=head, text=w, owner=owner))
    return chunks
# Jeevan sync: 2026-11-13
