"""Paid no-show banner logic — only flag real missed paid visits."""

from __future__ import annotations

import sys
import uuid
from datetime import date, timedelta
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from database import Base
from models import User, Profile, Doctor, Specialty, Appointment, Payment, ClinicSettings
from appointment_rules import (
    count_paid_no_show_action_required,
    resolve_stale_appointment_states,
)


@pytest.fixture()
def db_session():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    session.add(ClinicSettings(clinic_name="Test Clinic", appointment_duration=30, default_fee=100.0))
    session.commit()
    yield session
    session.close()


def _seed(db, apt_date: date, apt_status: str, payment_status: str = "paid"):
    spec = Specialty(name="General")
    db.add(spec)
    db.flush()
    doc_user = User(id=str(uuid.uuid4()), email="doc@test.com", password_hash="x", role="doctor", is_active=True)
    pat_user = User(id=str(uuid.uuid4()), email="pat@test.com", password_hash="x", role="patient", is_active=True)
    db.add_all([doc_user, pat_user])
    db.flush()
    doc_profile = Profile(id=str(uuid.uuid4()), user_id=doc_user.id, first_name="Dr", last_name="Test")
    pat_profile = Profile(id=str(uuid.uuid4()), user_id=pat_user.id, first_name="Pat", last_name="Test")
    db.add_all([doc_profile, pat_profile])
    db.flush()
    doctor = Doctor(id=str(uuid.uuid4()), profile_id=doc_profile.id, specialty_id=spec.id)
    db.add(doctor)
    db.flush()
    apt = Appointment(
        id=str(uuid.uuid4()),
        patient_id=pat_profile.id,
        doctor_id=doctor.id,
        date=apt_date,
        time_slot="09:00",
        status=apt_status,
    )
    db.add(apt)
    db.flush()
    db.add(
        Payment(
            id=str(uuid.uuid4()),
            appointment_id=apt.id,
            amount=100.0,
            payment_status=payment_status,
            payment_method="cash",
        )
    )
    db.commit()
    return apt


def test_cancelled_paid_not_counted(db_session):
    yesterday = date.today() - timedelta(days=1)
    apt = _seed(db_session, yesterday, "cancelled", "paid")
    assert count_paid_no_show_action_required(db_session) == 0


def test_past_paid_confirmed_is_counted(db_session):
    yesterday = date.today() - timedelta(days=1)
    _seed(db_session, yesterday, "confirmed", "paid")
    assert count_paid_no_show_action_required(db_session) == 1


def test_refunded_past_visit_not_counted(db_session):
    yesterday = date.today() - timedelta(days=1)
    _seed(db_session, yesterday, "confirmed", "refunded")
    assert count_paid_no_show_action_required(db_session) == 0


def test_resolve_stale_cancels_refunded_past_visit(db_session):
    yesterday = date.today() - timedelta(days=1)
    apt = _seed(db_session, yesterday, "confirmed", "refunded")
    changed = resolve_stale_appointment_states(db_session)
    db_session.refresh(apt)
    assert changed == 1
    assert apt.status == "cancelled"
    assert count_paid_no_show_action_required(db_session) == 0


def test_future_paid_confirmed_not_counted(db_session):
    tomorrow = date.today() + timedelta(days=1)
    _seed(db_session, tomorrow, "confirmed", "paid")
    assert count_paid_no_show_action_required(db_session) == 0
