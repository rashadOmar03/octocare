"""Tests for doctor vacation blocking bookings and notifications."""

import os
import sys
import uuid
from datetime import date, timedelta
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
from models import User, Profile, Doctor, Specialty, Appointment, ClinicSettings, DoctorSchedule, Notification

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
    session.add(
        ClinicSettings(
            clinic_name="Test Clinic",
            appointment_duration=30,
            default_fee=200.0,
            working_days="5,6,0,1,2,3",
            working_hours_start="09:00",
            working_hours_end="17:00",
        )
    )
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


def _next_bookable_day(from_day: date | None = None) -> date:
    working = {5, 6, 0, 1, 2, 3}
    day = from_day or date.today()
    for _ in range(14):
        day += timedelta(days=1)
        if day.weekday() in working:
            return day
    return date.today() + timedelta(days=2)


def _seed(db_session):
    spec = Specialty(name="Cardiology")
    db_session.add(spec)
    db_session.flush()

    admin = User(id=str(uuid.uuid4()), email="admin@test.com", password_hash="x", role="admin", is_active=True)
    doctor_user = User(id=str(uuid.uuid4()), email="doc@test.com", password_hash="x", role="doctor", is_active=True)
    receptionist = User(id=str(uuid.uuid4()), email="rec@test.com", password_hash="x", role="receptionist", is_active=True)
    patient_user = User(id=str(uuid.uuid4()), email="pat@test.com", password_hash="x", role="patient", is_active=True)
    db_session.add_all([admin, doctor_user, receptionist, patient_user])

    doc_profile = Profile(id=str(uuid.uuid4()), user_id=doctor_user.id, first_name="Ahmed", last_name="Ali", is_complete=True)
    pat_profile = Profile(id=str(uuid.uuid4()), user_id=patient_user.id, first_name="Sara", last_name="Hassan", is_complete=True)
    db_session.add_all([doc_profile, pat_profile])

    doctor = Doctor(id=str(uuid.uuid4()), profile_id=doc_profile.id, specialty_id=spec.id)
    db_session.add(doctor)
    for day in (5, 6, 0, 1, 2, 3):
        db_session.add(
            DoctorSchedule(
                doctor_id=doctor.id,
                day_of_week=day,
                start_time="09:00",
                end_time="17:00",
                is_available=True,
            )
        )

    bookable_day = _next_bookable_day()
    apt = Appointment(
        id=str(uuid.uuid4()),
        patient_id=pat_profile.id,
        doctor_id=doctor.id,
        date=bookable_day,
        time_slot="10:00",
        status="confirmed",
    )
    db_session.add(apt)
    db_session.commit()
    return {
        "admin": admin,
        "doctor_user": doctor_user,
        "receptionist": receptionist,
        "patient_user": patient_user,
        "doctor": doctor,
        "patient_profile": pat_profile,
        "appointment": apt,
        "tomorrow": bookable_day,
    }


def test_vacation_blocks_available_slots(client, db_session, auth_as):
    data = _seed(db_session)
    auth_as(data["admin"])

    start = data["tomorrow"]
    resp = client.post(
        f"/admin/doctors/{data['doctor'].id}/time-off",
        json={"start_date": start.isoformat(), "end_date": start.isoformat(), "reason": "Annual leave"},
    )
    assert resp.status_code == 201

    auth_as(data["patient_user"])
    slots = client.get(
        "/appointments/available-slots",
        params={"doctor_id": data["doctor"].id, "date": start.isoformat()},
    )
    assert slots.status_code == 200
    body = slots.json()
    assert body["doctor_on_vacation"] is True
    assert body["slots"] == []


def test_vacation_sends_notifications(client, db_session, auth_as):
    data = _seed(db_session)
    auth_as(data["admin"])

    start = data["tomorrow"]
    resp = client.post(
        f"/admin/doctors/{data['doctor'].id}/time-off",
        json={"start_date": start.isoformat(), "end_date": start.isoformat(), "reason": "Conference"},
    )
    assert resp.status_code == 201

    doctor_notes = (
        db_session.query(Notification)
        .filter(Notification.user_id == data["doctor_user"].id)
        .all()
    )
    rec_notes = (
        db_session.query(Notification)
        .filter(Notification.user_id == data["receptionist"].id)
        .all()
    )
    patient_notes = (
        db_session.query(Notification)
        .filter(Notification.user_id == data["patient_user"].id)
        .all()
    )

    assert any("Time off" in n.title for n in doctor_notes)
    assert any("unavailable" in n.message.lower() for n in rec_notes)
    assert any("not available" in n.message.lower() for n in patient_notes)


def test_doctor_can_add_own_time_off(client, db_session, auth_as):
    data = _seed(db_session)
    auth_as(data["doctor_user"])

    start = data["tomorrow"] + timedelta(days=2)
    end = start + timedelta(days=1)
    resp = client.post(
        "/doctors/me/time-off",
        json={"start_date": start.isoformat(), "end_date": end.isoformat(), "reason": "Family trip"},
    )
    assert resp.status_code == 201

    listed = client.get("/doctors/me/time-off")
    assert listed.status_code == 200
    assert len(listed.json()) == 1


def test_reschedule_slots_exclude_current_appointment(client, db_session, auth_as):
    data = _seed(db_session)
    apt = data["appointment"]
    slot_date = data["tomorrow"]

    auth_as(data["receptionist"])
    blocked = client.get(
        "/receptionist/available-slots",
        params={"doctor_id": data["doctor"].id, "date": slot_date.isoformat()},
    )
    assert blocked.status_code == 200
    assert apt.time_slot not in blocked.json()["slots"]

    freed = client.get(
        "/receptionist/available-slots",
        params={
            "doctor_id": data["doctor"].id,
            "date": slot_date.isoformat(),
            "exclude_appointment_id": apt.id,
        },
    )
    assert freed.status_code == 200
    assert apt.time_slot in freed.json()["slots"]
