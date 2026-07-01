"""Workflow and maintenance tests for Smart Clinic backend."""
import os
import sqlite3
import sys
import tempfile
import uuid
from datetime import date
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from database import Base
from models import User, Profile, Doctor, Specialty, Appointment, Payment, MedicalRecord
from db_maintenance import clean_legacy_invalid_data, drop_spo2_column


@pytest.fixture()
def db_session():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


def _seed_patient_doctor(session):
    spec = Specialty(name="Cardiology")
    session.add(spec)
    session.flush()
    doc_user = User(id=str(uuid.uuid4()), email="doc@test.com", password_hash="x", role="doctor", is_active=True)
    pat_user = User(id=str(uuid.uuid4()), email="pat@test.com", password_hash="x", role="patient", is_active=True)
    session.add_all([doc_user, pat_user])
    doc_profile = Profile(id=str(uuid.uuid4()), user_id=doc_user.id, first_name="Doc", last_name="Test", is_complete=True)
    pat_profile = Profile(id=str(uuid.uuid4()), user_id=pat_user.id, first_name="Pat", last_name="Test", is_complete=True)
    session.add_all([doc_profile, pat_profile])
    doctor = Doctor(id=str(uuid.uuid4()), profile_id=doc_profile.id, specialty_id=spec.id)
    session.add(doctor)
    session.commit()
    return pat_profile, doctor


def test_clean_legacy_completed_without_payment(db_session):
    patient, doctor = _seed_patient_doctor(db_session)
    apt = Appointment(
        id=str(uuid.uuid4()),
        patient_id=patient.id,
        doctor_id=doctor.id,
        date=date.today(),
        time_slot="10:00",
        status="completed",
    )
    db_session.add(apt)
    db_session.commit()

    stats = clean_legacy_invalid_data(db_session)
    db_session.refresh(apt)

    assert stats["completed_unpaid_cancelled"] == 1
    assert apt.status == "cancelled"


def test_clean_legacy_arrived_without_payment(db_session):
    patient, doctor = _seed_patient_doctor(db_session)
    apt = Appointment(
        id=str(uuid.uuid4()),
        patient_id=patient.id,
        doctor_id=doctor.id,
        date=date.today(),
        time_slot="11:00",
        status="arrived",
        queue_number=1,
    )
    db_session.add(apt)
    db_session.commit()

    stats = clean_legacy_invalid_data(db_session)
    db_session.refresh(apt)

    assert stats["arrived_unpaid_reset"] == 1
    assert apt.status == "confirmed"
    assert apt.queue_number is None


def test_clean_legacy_keeps_valid_completed_visit(db_session):
    patient, doctor = _seed_patient_doctor(db_session)
    apt = Appointment(
        id=str(uuid.uuid4()),
        patient_id=patient.id,
        doctor_id=doctor.id,
        date=date.today(),
        time_slot="09:00",
        status="completed",
    )
    db_session.add(apt)
    db_session.add(Payment(id=str(uuid.uuid4()), appointment_id=apt.id, amount=200, payment_status="paid"))
    db_session.add(
        MedicalRecord(
            id=str(uuid.uuid4()),
            appointment_id=apt.id,
            patient_id=patient.id,
            doctor_id=doctor.id,
            chief_complaint="c",
            symptoms="s",
            diagnosis="d",
            severity="mild",
            treatment_plan="t",
        )
    )
    db_session.commit()

    stats = clean_legacy_invalid_data(db_session)
    db_session.refresh(apt)

    assert apt.status == "completed"
    assert stats["completed_unpaid_cancelled"] == 0
    assert stats["completed_no_record_cancelled"] == 0


def test_drop_spo2_column_sqlite(monkeypatch):
    with tempfile.TemporaryDirectory() as tmp:
        db_path = Path(tmp) / "test.db"
        conn = sqlite3.connect(str(db_path))
        conn.execute(
            """
            CREATE TABLE sensor_data (
                id INTEGER PRIMARY KEY,
                patient_id TEXT NOT NULL,
                heart_rate INTEGER NOT NULL,
                spo2 INTEGER NOT NULL,
                temperature REAL NOT NULL,
                ecg REAL DEFAULT 0,
                emg REAL DEFAULT 0,
                gsr REAL DEFAULT 0,
                waveforms TEXT,
                timestamp DATETIME
            )
            """
        )
        conn.execute(
            "INSERT INTO sensor_data (patient_id, heart_rate, spo2, temperature) VALUES ('p1', 72, 98, 36.6)"
        )
        conn.commit()
        conn.close()

        monkeypatch.setattr("db_maintenance._sqlite_db_path", lambda: db_path)
        assert drop_spo2_column() is True

        conn = sqlite3.connect(str(db_path))
        cols = {row[1] for row in conn.execute("PRAGMA table_info(sensor_data)")}
        conn.close()
        assert "spo2" not in cols
        assert "heart_rate" in cols


def test_sensor_model_has_no_spo2_column():
    from models import SensorData

    assert "spo2" not in SensorData.__table__.columns
