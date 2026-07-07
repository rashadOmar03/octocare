"""Speech-to-text (Whisper) and text-to-speech (Edge TTS) for Octocare Clinic.

Supports two Whisper backends:
  1. Groq Whisper API  — preferred on Railway (no GPU needed)
  2. Local faster-whisper — fallback for local dev with GPU
"""

from __future__ import annotations

import asyncio
import os
import tempfile
from typing import Literal

ModelSize = Literal["small", "medium"]

_whisper_models: dict[str, object] = {}
_whisper_available: bool | None = None

VOICE_MAP = {
    "en": os.getenv("TTS_VOICE_EN", "en-US-JennyNeural"),
    "ar": os.getenv("TTS_VOICE_AR", "ar-EG-SalmaNeural"),
}

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "") or os.getenv("LM_API_KEY", "")
GROQ_WHISPER_MODEL = os.getenv("GROQ_WHISPER_MODEL", "whisper-large-v3")

# Whisper often hallucinates these on silence or very short English clips only.
_WHISPER_HALLUCINATIONS = frozenset({
    "you", "you.", "thank you", "thank you.", "thanks", "thanks.",
    "thanks for watching", "thank you for watching",
    "subscribe", "bye", "bye bye", "the end",
    "...", "mm", "hmm", "uh", "um", "okay", "ok",
})


def _mime_for_suffix(suffix: str) -> str:
    ext = suffix.lower().lstrip(".")
    if ext in ("mp4", "m4a"):
        return "audio/mp4"
    if ext == "ogg":
        return "audio/ogg"
    if ext == "wav":
        return "audio/wav"
    return "audio/webm"


def _is_low_quality_transcript(transcript: str, audio_bytes: bytes | int) -> bool:
    """True only for obvious English silence hallucinations on tiny clips."""
    cleaned = (transcript or "").strip().lower().rstrip(".,!?")
    if not cleaned:
        return True
    size = audio_bytes if isinstance(audio_bytes, int) else len(audio_bytes)
    word_count = len(cleaned.split())
    if cleaned in _WHISPER_HALLUCINATIONS and size < 3000:
        return True
    if word_count >= 2:
        return False
    if len(cleaned) <= 2 and size < 1200:
        return True
    return False


def _normalize_language(code: str | None, fallback: str = "en") -> str:
    """Map Whisper/Groq language codes to ar or en."""
    if not code:
        return fallback
    lowered = code.lower().strip()
    if lowered.startswith("ar") or "arab" in lowered:
        return "ar"
    return "en"


def _groq_whisper_available() -> bool:
    """Groq Whisper is available if we have an API key and the base URL points to Groq."""
    if not GROQ_API_KEY or GROQ_API_KEY in ("lm-studio", "ollama"):
        return False
    base = os.getenv("LM_STUDIO_URL", "")
    return "groq" in base.lower() or bool(os.getenv("GROQ_API_KEY", ""))


def whisper_is_available() -> bool:
    if _groq_whisper_available():
        return True
    global _whisper_available
    if _whisper_available is None:
        try:
            from faster_whisper import WhisperModel  # noqa: F401
            _whisper_available = True
        except ImportError:
            _whisper_available = False
    return _whisper_available


def _transcribe_groq(audio_bytes: bytes, suffix: str = ".webm", language: str | None = None) -> dict:
    """Transcribe via Groq Whisper API (cloud, no GPU)."""
    import httpx

    if not suffix or suffix == ".":
        suffix = ".webm"

    if len(audio_bytes) < 400:
        return {"transcript": "", "language": language or "en", "model": f"groq-{GROQ_WHISPER_MODEL}"}

    def _call(lang: str | None, *, use_prompt: bool) -> dict:
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            tmp.write(audio_bytes)
            tmp_path = tmp.name
        try:
            mime = _mime_for_suffix(suffix)
            with open(tmp_path, "rb") as f:
                files = {"file": (f"audio{suffix}", f, mime)}
                data: dict = {
                    "model": GROQ_WHISPER_MODEL,
                    "response_format": "verbose_json",
                    "temperature": "0",
                }
                if use_prompt:
                    data["prompt"] = "Medical clinic. Patient or staff speaking Arabic or English."
                if lang in ("ar", "en"):
                    data["language"] = lang

                resp = httpx.post(
                    "https://api.groq.com/openai/v1/audio/transcriptions",
                    headers={"Authorization": f"Bearer {GROQ_API_KEY}"},
                    files=files,
                    data=data,
                    timeout=90.0,
                )

            if resp.status_code != 200:
                return {"transcript": "", "language": lang or "en", "error": resp.text[:300]}

            body = resp.json()
            transcript = (body.get("text") or "").strip()
            detected = _normalize_language(body.get("language"), fallback=lang or "en")
            if _is_low_quality_transcript(transcript, audio_bytes):
                transcript = ""
            return {
                "transcript": transcript,
                "language": detected,
                "model": f"groq-{GROQ_WHISPER_MODEL}",
            }
        finally:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    attempts: list[tuple[str | None, bool]] = [
        (language, True),
        (language, False),
        (None, False),
    ]
    if language == "ar":
        attempts.append(("en", False))
    elif language == "en":
        attempts.append(("ar", False))

    last: dict = {"transcript": "", "language": language or "en", "model": f"groq-{GROQ_WHISPER_MODEL}"}
    for lang, use_prompt in attempts:
        result = _call(lang, use_prompt=use_prompt)
        last = result
        if result.get("transcript"):
            return result

    return last


def model_for_role(role: str) -> ModelSize:
    return "medium" if role == "doctor" else "small"


def _load_whisper(model_size: ModelSize):
    if model_size in _whisper_models:
        return _whisper_models[model_size]
    from faster_whisper import WhisperModel

    device = os.getenv("WHISPER_DEVICE", "auto")
    if device == "auto":
        try:
            import torch
            device = "cuda" if torch.cuda.is_available() else "cpu"
        except ImportError:
            device = "cpu"
    compute_type = os.getenv("WHISPER_COMPUTE", "float16" if device == "cuda" else "int8")
    model = WhisperModel(model_size, device=device, compute_type=compute_type)
    _whisper_models[model_size] = model
    return model


def transcribe_file(
    file_path: str,
    *,
    role: str = "patient",
    language: str | None = None,
) -> dict:
    if _groq_whisper_available():
        with open(file_path, "rb") as f:
            return _transcribe_groq(f.read(), language=language)

    if not _whisper_available:
        raise RuntimeError(
            "Whisper is not available. Set GROQ_API_KEY or install faster-whisper."
        )

    model_size = model_for_role(role)
    model = _load_whisper(model_size)
    lang = language if language in ("ar", "en") else None

    def _run(*, vad_filter: bool) -> tuple[str, object]:
        segments, info = model.transcribe(
            file_path,
            beam_size=5,
            vad_filter=vad_filter,
            language=lang,
        )
        text = " ".join(segment.text.strip() for segment in segments).strip()
        return text, info

    transcript, info = _run(vad_filter=True)
    if not transcript:
        transcript, info = _run(vad_filter=False)
    detected = _normalize_language(getattr(info, "language", None), fallback=lang or "en")
    with open(file_path, "rb") as f:
        raw = f.read()
    if _is_low_quality_transcript(transcript, raw):
        transcript = ""
    return {
        "transcript": transcript,
        "language": detected,
        "model": model_size,
    }


def transcribe_bytes(
    audio_bytes: bytes,
    *,
    suffix: str = ".webm",
    role: str = "patient",
    language: str | None = None,
) -> dict:
    if _groq_whisper_available():
        return _transcribe_groq(audio_bytes, suffix=suffix, language=language)

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name
    try:
        return transcribe_file(tmp_path, role=role, language=language)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


async def synthesize_speech(text: str, language: str = "en") -> bytes:
    import edge_tts

    cleaned = (text or "").strip()
    if not cleaned:
        raise ValueError("Text is required for speech synthesis")

    lang = "ar" if language.startswith("ar") else "en"
    voice = VOICE_MAP.get(lang, VOICE_MAP["en"])
    communicate = edge_tts.Communicate(cleaned, voice)
    chunks: list[bytes] = []
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            chunks.append(chunk["data"])
    if not chunks:
        raise RuntimeError("TTS produced no audio")
    return b"".join(chunks)


def synthesize_speech_sync(text: str, language: str = "en") -> bytes:
    return asyncio.run(synthesize_speech(text, language))
