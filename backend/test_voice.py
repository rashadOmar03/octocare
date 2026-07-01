"""Extended voice service tests."""

import pytest

from voice_service import (
    VOICE_MAP,
    model_for_role,
    synthesize_speech_sync,
    transcribe_bytes,
    whisper_is_available,
)


def test_model_for_all_roles():
    assert model_for_role("doctor") == "medium"
    for role in ("patient", "receptionist", "admin", "unknown"):
        assert model_for_role(role) == "small"


def test_arabic_voice_configured():
    assert "ar-EG" in VOICE_MAP["ar"] or "ar-" in VOICE_MAP["ar"]


def test_english_voice_configured():
    assert VOICE_MAP["en"].endswith("Neural")


@pytest.mark.skipif(not whisper_is_available(), reason="faster-whisper not installed")
def test_synthesize_english_audio():
    audio = synthesize_speech_sync("Hello", "en")
    assert isinstance(audio, bytes)
    assert len(audio) > 1000


@pytest.mark.skipif(not whisper_is_available(), reason="faster-whisper not installed")
def test_synthesize_arabic_audio():
    audio = synthesize_speech_sync("مرحبا", "ar")
    assert isinstance(audio, bytes)
    assert len(audio) > 1000


def test_transcribe_bytes_invalid_audio_raises():
    if not whisper_is_available():
        pytest.skip("faster-whisper not installed")
    with pytest.raises(Exception):
        transcribe_bytes(b"not-real-audio", suffix=".webm", role="patient")
