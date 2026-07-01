"""Speech-to-text (Whisper) and text-to-speech (Edge TTS) for Smart Clinic.

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

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name

    try:
        with open(tmp_path, "rb") as f:
            files = {"file": (f"audio{suffix}", f, "audio/webm")}
            data: dict = {"model": GROQ_WHISPER_MODEL, "response_format": "json"}
            if language in ("ar", "en"):
                data["language"] = language

            resp = httpx.post(
                "https://api.groq.com/openai/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {GROQ_API_KEY}"},
                files=files,
                data=data,
                timeout=30.0,
            )
            resp.raise_for_status()
            body = resp.json()

        transcript = (body.get("text") or "").strip()
        detected = body.get("language") or language or "en"
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
    detected = info.language or lang or "en"
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
