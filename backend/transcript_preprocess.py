"""Normalize clinical transcripts before LLM extraction."""

from __future__ import annotations

import re
import unicodedata


def preprocess_transcript(text: str) -> str:
    if not text:
        return ""
    t = unicodedata.normalize("NFKC", text)
    t = re.sub(r"[\u0640\u200f\u200e\u202a\u202c]", "", t)
    t = t.replace("\r\n", "\n").replace("\r", "\n")
    t = re.sub(r"[ \t]+", " ", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    # Common ASR / typing confusables in mixed notes
    t = re.sub(r"\bHbA1[cC]\b", "HbA1c", t)
    t = re.sub(r"\bEF\s*(\d+)\s*%", r"EF \1%", t)
    return t.strip()
