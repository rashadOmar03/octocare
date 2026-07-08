"""Tests for admin user deletion with cascade."""
import os
import sys
import uuid
from datetime import date
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from auth import get_current_user
from database import Base, get_db
from main import app
from models import User, Profile, Doctor, Specialty, Appointment, ClinicSettings
from user_delete import delete_user_account

TEST_ENGINE = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)


@event.listens_for(TEST_ENGINE, "connect")
def _set_sqlite_pragma(dbapi_connection, _):
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


@pytest.fixture(autouse=True)
def _setup_db():
    Base.metadata.create_all(TEST_ENGINE)
    yield
    Base.metadata.drop_all(TEST_ENGINE)


@pytest.fixture()
def db_session():
    session = sessionmaker(bind=TEST_ENGINE)()
    session.add(ClinicSettings(clinic_name="Test", appointment_duration=30, default_fee=100))
    session.commit()
    yield session
    session.rollback()
    session.close()


def _seed_patient_with_appointment(db):
    spec = Specialty(name="Cardiology")
    db.add(spec)
    db.flush()
    doc_u = User(id=str(uuid.uuid4()), email="doc@test.com", password_hash="x", role="doctor", is_active=True)
    pat_u = User(id=str(uuid.uuid4()), email="pat@test.com", password_hash="x", role="patient", is_active=True)
    db.add_all([doc_u, pat_u])
    db.flush()
    doc_p = Profile(id=str(uuid.uuid4()), user_id=doc_u.id, first_name="Doc", last_name="One")
    pat_p = Profile(id=str(uuid.uuid4()), user_id=pat_u.id, first_name="Pat", last_name="One")
    db.add_all([doc_p, pat_p])
    db.flush()
    doctor = Doctor(id=str(uuid.uuid4()), profile_id=doc_p.id, specialty_id=spec.id)
    db.add(doctor)
    db.flush()
    db.add(
        Appointment(
            id=str(uuid.uuid4()),
            patient_id=pat_p.id,
            doctor_id=doctor.id,
            date=date.today(),
            time_slot="10:00",
            status="confirmed",
        )
    )
    db.commit()
    return pat_u, doc_u


def test_delete_patient_with_appointments(db_session):
    patient, _ = _seed_patient_with_appointment(db_session)
    stats = delete_user_account(db_session, patient)
    db_session.commit()
    assert stats["appointments"] == 1
    assert db_session.query(User).filter(User.role == "patient").count() == 0
    assert db_session.query(Appointment).count() == 0


def test_admin_can_delete_other_admin(db_session):
    admin = User(id=str(uuid.uuid4()), email="admin@test.com", password_hash="x", role="admin", is_active=True)
    other_admin = User(id=str(uuid.uuid4()), email="other@test.com", password_hash="x", role="admin", is_active=True)
    db_session.add_all([admin, other_admin])
    db_session.commit()

    def override_db():
        yield db_session

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: admin
    client = TestClient(app)
    with patch("routers.admin._notify_staff"):
        resp = client.delete(f"/admin/users/{other_admin.id}")
    app.dependency_overrides.clear()
    assert resp.status_code == 200
    assert db_session.query(User).filter(User.email == "other@test.com").count() == 0


def test_admin_cannot_delete_self(db_session):
    admin = User(id=str(uuid.uuid4()), email="admin@test.com", password_hash="x", role="admin", is_active=True)
    db_session.add(admin)
    db_session.commit()

    def override_db():
        yield db_session

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: admin
    client = TestClient(app)
    resp = client.delete(f"/admin/users/{admin.id}")
    app.dependency_overrides.clear()
    assert resp.status_code == 400
