"""Speech-to-text (Whisper) and text-to-speech (Edge TTS) for Smart Clinic."""

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


def whisper_is_available() -> bool:
    global _whisper_available
    if _whisper_available is None:
        try:
            from faster_whisper import WhisperModel  # noqa: F401
            _whisper_available = True
        except ImportError:
            _whisper_available = False
    return _whisper_available


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
    if not whisper_is_available():
        raise RuntimeError(
            "Whisper is not installed. Install faster-whisper on the server to enable voice input."
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
