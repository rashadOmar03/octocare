"""API tests for /ai/transcribe, /ai/speak, and /ai/voice/status."""

from __future__ import annotations

import base64
import sys
import uuid
from io import BytesIO
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from auth import get_current_user  # noqa: E402
from main import app  # noqa: E402
from models import User  # noqa: E402

client = TestClient(app)

SAMPLE_AUDIO_BYTES = b"\x00" * 512


def _user(role: str) -> User:
    return User(
        id=str(uuid.uuid4()),
        email=f"{role}@voice.test",
        password_hash="x",
        role=role,
        is_active=True,
    )


@pytest.fixture()
def auth_as():
    def _apply(role: str):
        user = _user(role)
        app.dependency_overrides[get_current_user] = lambda: user
        return user

    yield _apply
    app.dependency_overrides.clear()


def test_voice_status_requires_auth():
    response = client.get("/ai/voice/status")
    assert response.status_code == 401


def test_voice_status_authenticated(auth_as):
    auth_as("patient")
    response = client.get("/ai/voice/status")
    assert response.status_code == 200
    body = response.json()
    assert "whisper_available" in body
    assert body["doctor_model"] == "medium"
    assert body["other_roles_model"] == "small"


def test_speak_requires_auth():
    response = client.post("/ai/speak", json={"text": "Hello", "language": "en"})
    assert response.status_code == 401


@patch("routers.ai_router.synthesize_speech_sync")
def test_speak_returns_audio(mock_speak, auth_as):
    auth_as("patient")
    mock_speak.return_value = b"fake-audio-bytes"
    response = client.post("/ai/speak", json={"text": "Hello from chat", "language": "en"})
    assert response.status_code == 200
    body = response.json()
    assert body["content_type"] == "audio/mpeg"
    decoded = base64.b64decode(body["audio_base64"])
    assert decoded == b"fake-audio-bytes"
    mock_speak.assert_called_once_with("Hello from chat", "en")


def test_speak_rejects_empty_text(auth_as):
    auth_as("patient")
    response = client.post("/ai/speak", json={"text": "   ", "language": "en"})
    assert response.status_code == 400


@patch("routers.ai_router.synthesize_speech_sync")
def test_speak_arabic_uses_ar_language(mock_speak, auth_as):
    auth_as("patient")
    mock_speak.return_value = b"arabic-audio"
    response = client.post("/ai/speak", json={"text": "مرحبا", "language": "ar"})
    assert response.status_code == 200
    mock_speak.assert_called_once_with("مرحبا", "ar")


def test_transcribe_requires_auth():
    response = client.post(
        "/ai/transcribe",
        files={"file": ("voice.webm", BytesIO(b"abc"), "audio/webm")},
    )
    assert response.status_code == 401


def test_transcribe_rejects_empty_file(auth_as):
    auth_as("patient")
    response = client.post(
        "/ai/transcribe",
        files={"file": ("voice.webm", BytesIO(b""), "audio/webm")},
    )
    assert response.status_code == 400


@patch("routers.ai_router.whisper_is_available", return_value=False)
def test_transcribe_unavailable_when_whisper_missing(_mock_available, auth_as):
    auth_as("patient")
    response = client.post(
        "/ai/transcribe",
        files={"file": ("voice.webm", BytesIO(b"abc"), "audio/webm")},
    )
    assert response.status_code == 503


@patch("routers.ai_router.transcribe_bytes")
def test_transcribe_patient_uses_small_model(mock_transcribe, auth_as):
    auth_as("patient")
    mock_transcribe.return_value = {
        "transcript": "I have chest pain",
        "language": "en",
        "model": "small",
    }
    response = client.post(
        "/ai/transcribe",
        data={"language": "en"},
        files={"file": ("voice.webm", BytesIO(SAMPLE_AUDIO_BYTES), "audio/webm")},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["transcript"] == "I have chest pain"
    assert body["model"] == "small"
    assert mock_transcribe.call_args.kwargs["role"] == "patient"


@patch("routers.ai_router.transcribe_bytes")
def test_transcribe_doctor_uses_medium_model(mock_transcribe, auth_as):
    auth_as("doctor")
    mock_transcribe.return_value = {
        "transcript": "Aspirin 100 mg daily",
        "language": "en",
        "model": "medium",
    }
    response = client.post(
        "/ai/transcribe",
        files={"file": ("voice.webm", BytesIO(SAMPLE_AUDIO_BYTES), "audio/webm")},
    )
    assert response.status_code == 200
    body = response.json()
    assert "Aspirin" in body["transcript"]
    assert body["model"] == "medium"
    assert mock_transcribe.call_args.kwargs["role"] == "doctor"


@patch("routers.ai_router.transcribe_bytes")
def test_transcribe_arabic_consultation_text(mock_transcribe, auth_as):
    auth_as("doctor")
    mock_transcribe.return_value = {
        "transcript": "المريض يعاني من صداع شديد منذ 5 أيام",
        "language": "ar",
        "model": "medium",
    }
    response = client.post(
        "/ai/transcribe",
        data={"language": "ar"},
        files={"file": ("voice.webm", BytesIO(SAMPLE_AUDIO_BYTES), "audio/webm")},
    )
    assert response.status_code == 200
    assert response.json()["language"] == "ar"


@patch("routers.ai_router.transcribe_bytes")
def test_transcribe_receptionist_chat(mock_transcribe, auth_as):
    auth_as("receptionist")
    mock_transcribe.return_value = {
        "transcript": "What are your opening hours?",
        "language": "en",
        "model": "small",
    }
    response = client.post(
        "/ai/transcribe",
        files={"file": ("voice.webm", BytesIO(SAMPLE_AUDIO_BYTES), "audio/webm")},
    )
    assert response.status_code == 200
    assert mock_transcribe.call_args.kwargs["role"] == "receptionist"


@patch("routers.ai_router.transcribe_bytes")
def test_transcribe_admin_chat(mock_transcribe, auth_as):
    auth_as("admin")
    mock_transcribe.return_value = {
        "transcript": "Show me today's revenue summary",
        "language": "en",
        "model": "small",
    }
    response = client.post(
        "/ai/transcribe",
        files={"file": ("voice.webm", BytesIO(SAMPLE_AUDIO_BYTES), "audio/webm")},
    )
    assert response.status_code == 200
    assert mock_transcribe.call_args.kwargs["role"] == "admin"


@patch("routers.ai_router.transcribe_bytes")
def test_transcribe_empty_speech_returns_422(mock_transcribe, auth_as):
    auth_as("patient")
    mock_transcribe.return_value = {"transcript": "", "language": "en", "model": "small"}
    response = client.post(
        "/ai/transcribe",
        files={"file": ("voice.webm", BytesIO(SAMPLE_AUDIO_BYTES), "audio/webm")},
    )
    assert response.status_code == 422


def test_whisper_hallucination_you_on_short_audio():
    from voice_service import (
        _is_arabic_hallucination,
        _is_low_quality_transcript,
        _is_garbage_transcript,
        _is_prompt_echo,
    )

    assert _is_low_quality_transcript("you", 1500) is True
    assert _is_low_quality_transcript("thank you", 1500) is True
    assert _is_low_quality_transcript("I have chest pain", 2000) is False
    assert _is_low_quality_transcript("you", 20000) is False
    assert _is_garbage_transcript("Paternity or Pregnant", requested_lang="ar", audio_bytes=8000) is True
    assert _is_garbage_transcript("اهلا عندي كام مريض", requested_lang="ar", audio_bytes=8000) is False
    assert _is_garbage_transcript("How many patients", requested_lang="en", audio_bytes=8000) is False
    assert _is_prompt_echo("Patsient appointment doctor reception.") is True
    assert _is_garbage_transcript("Patsient appointment doctor reception", requested_lang="en", audio_bytes=8000) is True
    assert _is_arabic_hallucination("ترجمة نانسي قطر") is True
    assert _is_garbage_transcript("ترجمة نانسي قطر", requested_lang="ar", audio_bytes=8000) is True
    assert _is_arabic_hallucination("عندي كام مريض ودكتور") is False


def test_arabic_hallucination_filter():
    from voice_service import _is_arabic_hallucination

    assert _is_arabic_hallucination("ترجمة نانسي قطر") is True
    assert _is_arabic_hallucination("اشترك في القناة") is True
    assert _is_arabic_hallucination("ترجمة آلاء") is True
    assert _is_arabic_hallucination("عندي كام مريض") is False
    assert _is_arabic_hallucination("Hello") is False


@patch("routers.ai_router._call_model")
def test_chat_after_voice_message(mock_call, auth_as):
    auth_as("patient")
    mock_call.return_value = "Please rest and drink fluids."
    response = client.post("/ai/chat", json={"message": "I have a mild fever", "language": "en"})
    assert response.status_code == 200
    body = response.json()
    assert body["response"]
