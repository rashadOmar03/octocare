"""Tests for doctor consultation start / check-in flow."""
import os
import sys
import uuid
from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from auth import get_current_user
from database import Base, get_db
from main import app
from models import User, Profile, Doctor, Specialty, Appointment, Payment, ClinicSettings

TEST_ENGINE = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestSession = sessionmaker(bind=TEST_ENGINE)


@pytest.fixture(autouse=True)
def _setup_db():
    Base.metadata.create_all(TEST_ENGINE)
    yield
    Base.metadata.drop_all(TEST_ENGINE)


@pytest.fixture()
def db_session():
    session = TestSession()
    session.add(ClinicSettings(clinic_name="Test Clinic", appointment_duration=30, default_fee=200.0))
    session.commit()
    yield session
    session.rollback()
    session.close()


@pytest.fixture()
def client(db_session):
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture()
def auth_as(db_session):
    def _apply(user: User):
        app.dependency_overrides[get_current_user] = lambda: user
        return user

    yield _apply
    if get_current_user in app.dependency_overrides:
        del app.dependency_overrides[get_current_user]


def _seed_users(session):
    spec = Specialty(name="Cardiology")
    session.add(spec)
    session.flush()

    doc_user = User(
        id=str(uuid.uuid4()),
        email="doc@test.com",
        password_hash="x",
        role="doctor",
        is_active=True,
    )
    rec_user = User(
        id=str(uuid.uuid4()),
        email="rec@test.com",
        password_hash="x",
        role="receptionist",
        is_active=True,
    )
    pat_user = User(
        id=str(uuid.uuid4()),
        email="pat@test.com",
        password_hash="x",
        role="patient",
        is_active=True,
    )
    session.add_all([doc_user, rec_user, pat_user])

    doc_profile = Profile(
        id=str(uuid.uuid4()),
        user_id=doc_user.id,
        first_name="Ahmed",
        last_name="Ali",
        is_complete=True,
    )
    rec_profile = Profile(
        id=str(uuid.uuid4()),
        user_id=rec_user.id,
        first_name="Rec",
        last_name="Desk",
        is_complete=True,
    )
    pat_profile = Profile(
        id=str(uuid.uuid4()),
        user_id=pat_user.id,
        first_name="Sara",
        last_name="Hassan",
        is_complete=True,
    )
    session.add_all([doc_profile, rec_profile, pat_profile])

    doctor = Doctor(id=str(uuid.uuid4()), profile_id=doc_profile.id, specialty_id=spec.id)
    session.add(doctor)
    session.commit()
    return doc_user, rec_user, pat_profile, doctor


def _make_appointment(session, patient_id, doctor_id, *, status="confirmed", paid=False):
    apt = Appointment(
        id=str(uuid.uuid4()),
        patient_id=patient_id,
        doctor_id=doctor_id,
        date=date.today(),
        time_slot="10:00",
        status=status,
    )
    session.add(apt)
    session.flush()
    if paid:
        session.add(
            Payment(
                id=str(uuid.uuid4()),
                appointment_id=apt.id,
                amount=200.0,
                payment_method="cash",
                payment_status="paid",
            )
        )
    session.commit()
    return apt


def test_doctor_start_consultation_auto_arrives_confirmed_paid(client, db_session, auth_as):
    doc_user, _rec, patient, doctor = _seed_users(db_session)
    apt = _make_appointment(db_session, patient.id, doctor.id, status="confirmed", paid=True)
    auth_as(doc_user)

    resp = client.put(f"/appointments/{apt.id}/start-consultation")

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "arrived"
    assert body["is_paid"] is True
    assert body["queue_number"] == 1


def test_doctor_start_consultation_requires_payment(client, db_session, auth_as):
    doc_user, _rec, patient, doctor = _seed_users(db_session)
    apt = _make_appointment(db_session, patient.id, doctor.id, status="confirmed", paid=False)
    auth_as(doc_user)

    resp = client.put(f"/appointments/{apt.id}/start-consultation")

    assert resp.status_code == 400
    assert "payment" in resp.json()["detail"].lower()


def test_payment_auto_confirms_pending(client, db_session, auth_as):
    _doc, rec_user, patient, doctor = _seed_users(db_session)
    apt = _make_appointment(db_session, patient.id, doctor.id, status="pending", paid=False)
    auth_as(rec_user)

    resp = client.post(
        "/receptionist/payments/json",
        json={"appointment_id": apt.id, "payment_method": "cash", "amount": 200.0},
    )

    assert resp.status_code == 201
    db_session.refresh(apt)
    assert apt.status == "confirmed"


def test_mark_arrived_accepts_pending_when_paid(client, db_session, auth_as):
    _doc, rec_user, patient, doctor = _seed_users(db_session)
    apt = _make_appointment(db_session, patient.id, doctor.id, status="pending", paid=True)
    auth_as(rec_user)

    resp = client.put(f"/appointments/{apt.id}/arrive")

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "arrived"
    assert body["queue_number"] == 1
