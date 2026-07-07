"""Language-agnostic fuzzy evidence matching for extraction validation."""

from __future__ import annotations

import re
import unicodedata


def normalize_text(text: str) -> str:
    if not text:
        return ""
    t = unicodedata.normalize("NFKC", text)
    t = re.sub(r"[\u0640\u200f\u200e]", "", t)
    t = re.sub(r"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]", "", t)
    t = re.sub(r"[^\w\s\-]", " ", t, flags=re.UNICODE)
    return re.sub(r"\s+", " ", t).strip().lower()


def token_set(text: str) -> set[str]:
    return {t for t in normalize_text(text).split() if len(t) > 1}


def _map_to_original(source: str, norm_start: int, norm_len: int) -> tuple[int, int]:
    """Best-effort map normalized indices back to original string span."""
    if not source:
        return -1, -1
    norm = normalize_text(source)
    if norm_start < 0 or norm_start >= len(norm):
        return -1, -1
    # Walk original string to approximate position
    ni = 0
    start_orig = -1
    end_orig = -1
    for i, ch in enumerate(source):
        chunk = normalize_text(ch)
        if not chunk:
            continue
        if ni == norm_start and start_orig < 0:
            start_orig = i
        ni += len(chunk)
        if ni >= norm_start + norm_len:
            end_orig = i + 1
            break
    if start_orig >= 0 and end_orig < 0:
        end_orig = len(source)
    return start_orig, end_orig


def fuzzy_in_source(
    needle: str,
    source: str,
    *,
    min_token_ratio: float = 0.5,
) -> tuple[bool, int, int, str]:
    """Return (found, start, end, evidence_snippet) using fuzzy token overlap."""
    if not needle or not source:
        return False, -1, -1, ""

    needle_norm = normalize_text(needle)
    source_norm = normalize_text(source)
    if not needle_norm or not source_norm:
        return False, -1, -1, ""

    if needle_norm in source_norm:
        idx = source_norm.find(needle_norm)
        start, end = _map_to_original(source, idx, len(needle_norm))
        if start >= 0:
            pad = 40
            return True, start, end, source[max(0, start - pad) : min(len(source), end + pad)].strip()
        idx_raw = source.lower().find(needle.lower())
        if idx_raw >= 0:
            end_raw = idx_raw + len(needle)
            pad = 40
            return True, idx_raw, end_raw, source[max(0, idx_raw - pad) : min(len(source), end_raw + pad)].strip()

    nt = token_set(needle)
    if not nt:
        return False, -1, -1, ""

    words = source_norm.split()
    best_ratio = 0.0
    best_span: tuple[int, int] | None = None

    for i in range(len(words)):
        for j in range(i + 1, min(i + 10, len(words)) + 1):
            chunk = " ".join(words[i:j])
            ct = token_set(chunk)
            if not ct:
                continue
            overlap = len(nt & ct) / len(nt)
            if overlap > best_ratio:
                best_ratio = overlap
                best_span = (i, j)

    if best_ratio >= min_token_ratio and best_span:
        chunk = " ".join(words[best_span[0] : best_span[1]])
        idx = source_norm.find(chunk)
        if idx >= 0:
            start, end = _map_to_original(source, idx, len(chunk))
            if start >= 0:
                pad = 40
                return True, start, end, source[max(0, start - pad) : min(len(source), end + pad)].strip()

    # Single-token drug/term match
    if len(nt) == 1:
        token = next(iter(nt))
        if len(token) >= 4 and token in source_norm:
            idx = source_norm.find(token)
            start, end = _map_to_original(source, idx, len(token))
            if start >= 0:
                pad = 40
                return True, start, end, source[max(0, start - pad) : min(len(source), end + pad)].strip()

    return False, -1, -1, ""


def find_in_source(name: str, source: str) -> tuple[int, int, str]:
    """Drop-in replacement for literal substring search."""
    found, start, end, evidence = fuzzy_in_source(name, source)
    if found:
        return start, end, evidence
    for term in {name, name.lower(), name.title()}:
        idx = source.lower().find(term.lower())
        if idx >= 0:
            end_i = idx + len(term)
            pad = 40
            return idx, end_i, source[max(0, idx - pad) : min(len(source), end_i + pad)].strip()
    return -1, -1, ""
