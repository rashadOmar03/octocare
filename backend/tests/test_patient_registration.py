"""Tests for receptionist/admin patient registration with email OTP."""

from __future__ import annotations

import sys
import uuid
from datetime import date
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from auth import get_current_user, hash_password  # noqa: E402
from main import app  # noqa: E402
from models import User  # noqa: E402

client = TestClient(app)

PATIENT_PAYLOAD = {
    "first_name": "Ahmed",
    "last_name": "Hassan",
    "email": "newpatient@example.com",
    "phone": "01012345678",
    "date_of_birth": "1990-05-15",
    "gender": "male",
    "address": "Cairo",
}


def _patient_payload(suffix: str = "") -> dict:
    token = suffix or uuid.uuid4().hex[:8]
    numeric = sum(ord(c) for c in token)
    digits = f"010{numeric % 100000000:08d}"
    return {
        **PATIENT_PAYLOAD,
        "email": f"patient.{token}@example.com",
        "phone": digits,
    }


def _staff(role: str) -> User:
    return User(
        id=str(uuid.uuid4()),
        email=f"{role}@reg.test",
        password_hash=hash_password("secret"),
        role=role,
        is_active=True,
        email_verified=True,
    )


@pytest.fixture()
def auth_as():
    def _apply(role: str):
        user = _staff(role)
        app.dependency_overrides[get_current_user] = lambda: user
        return user

    yield _apply
    app.dependency_overrides.clear()


@patch("routers.receptionist.send_patient_welcome_email", return_value=True)
@patch("routers.receptionist.create_and_send_otp", return_value=True)
def test_receptionist_register_patient_requires_email_verification(
    mock_otp, mock_welcome, auth_as
):
    auth_as("receptionist")
    response = client.post("/receptionist/patients", json=_patient_payload())
    assert response.status_code == 201
    body = response.json()
    assert body["otp_sent"] is True
    assert body["login_blocked_until_verified"] is True
    assert body["temp_password"]
    mock_otp.assert_called_once()
    mock_welcome.assert_called_once()


@patch("routers.receptionist.send_patient_welcome_email", return_value=True)
@patch("routers.receptionist.create_and_send_otp", return_value=True)
def test_admin_register_patient_requires_email_verification(
    mock_otp, mock_welcome, auth_as
):
    payload = _patient_payload("admin")
    auth_as("admin")
    response = client.post("/receptionist/patients", json=payload)
    assert response.status_code == 201
    body = response.json()
    assert body["login_blocked_until_verified"] is True
    assert body["otp_sent"] is True


@patch("routers.receptionist.send_patient_welcome_email", return_value=True)
@patch("routers.receptionist.create_and_send_otp", return_value=True)
@patch("routers.auth_router.create_and_send_otp", return_value=True)
def test_staff_registered_patient_cannot_login_before_otp(
    mock_login_otp, mock_register_otp, mock_welcome, auth_as
):
    payload = _patient_payload("blocked")
    auth_as("receptionist")
    created = client.post("/receptionist/patients", json=payload)
    assert created.status_code == 201
    temp_password = created.json()["temp_password"]
    email = payload["email"]

    app.dependency_overrides.clear()
    login = client.post(
        "/auth/login",
        json={"email_or_phone": email, "password": temp_password},
    )
    assert login.status_code == 403
    assert "verify your email" in login.json()["detail"].lower()
    mock_login_otp.assert_called_once()
