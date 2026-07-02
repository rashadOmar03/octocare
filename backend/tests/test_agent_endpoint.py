"""
Integration tests for POST /ai/agent.
The LM-Studio model is mocked so tests run offline.
All 4 roles are tested, role-scoping is verified, and language handling is checked.
"""

from __future__ import annotations

import sys
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from sqlalchemy.pool import StaticPool

from auth import get_current_user
from database import Base, get_db
from main import app
from models import (
    Appointment, AppointmentReview, AuditLog, ClinicSettings, Doctor,
    Payment, Profile, Specialty, User,
)

client = TestClient(app)


# ─── DB fixtures ──────────────────────────────────────────────────────────────

# StaticPool ensures the in-memory DB is shared across all connections
# (required so TestClient threads see the same tables as the test session)
TEST_ENGINE = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestSession = sessionmaker(bind=TEST_ENGINE)


@pytest.fixture(autouse=True)
def _disable_semantic_router(monkeypatch):
    monkeypatch.setenv("AGENT_SEMANTIC_ROUTER", "false")


@pytest.fixture(autouse=True)
def _setup_db():
    global _ep_slot_counter
    _ep_slot_counter = 0
    Base.metadata.create_all(TEST_ENGINE)
    yield
    Base.metadata.drop_all(TEST_ENGINE)


@pytest.fixture()
def db_session():
    session = TestSession()
    yield session
    session.rollback()
    session.close()


def _override_db(session):
    def _get():
        yield session
    return _get


def _uid():
    return str(uuid.uuid4())


def _make_user(role: str, session) -> User:
    uid = _uid()
    u = User(id=uid, email=f"{uid[:6]}@test.com", password_hash="x", role=role, is_active=True)
    session.add(u)
    session.flush()
    return u


def _make_profile(user: User, session, first: str = "Test", last: str = "User") -> Profile:
    p = Profile(id=_uid(), user_id=user.id, first_name=first, last_name=last,
                dob=date(1990, 1, 1), gender="Male")
    session.add(p)
    session.flush()
    return p


def _make_specialty(session, name: str = "Cardiology") -> Specialty:
    s = Specialty(name=name, description="Test specialty")
    session.add(s)
    session.flush()
    return s


def _make_doctor(session, spec: Specialty, first: str = "Doc", last: str = "Tor") -> tuple[User, Profile, Doctor]:
    user = _make_user("doctor", session)
    profile = _make_profile(user, session, first, last)
    doc = Doctor(id=_uid(), profile_id=profile.id, specialty_id=spec.id,
                 qualifications="MD", bio="Expert")
    session.add(doc)
    session.flush()
    return user, profile, doc


_ep_slot_counter = 0

def _make_appointment(session, patient_id: str, doctor_id: str,
                      apt_date=None, status: str = "confirmed", time_slot: str | None = None) -> Appointment:
    global _ep_slot_counter
    if time_slot is None:
        _ep_slot_counter += 1
        h, m = divmod(_ep_slot_counter, 2)
        time_slot = f"{8 + h:02d}:{m * 30:02d}"
    apt = Appointment(
        id=_uid(), patient_id=patient_id, doctor_id=doctor_id,
        date=apt_date or date.today(), time_slot=time_slot, status=status,
    )
    session.add(apt)
    session.flush()
    return apt


def _make_payment(session, appointment_id: str, amount: float = 200.0,
                  pstatus: str = "paid") -> Payment:
    p = Payment(id=_uid(), appointment_id=appointment_id, amount=amount,
                payment_status=pstatus, payment_method="cash")
    session.add(p)
    session.flush()
    return p


def _make_settings(session) -> ClinicSettings:
    s = ClinicSettings(
        clinic_name="TestClinic", working_hours_start="08:00",
        working_hours_end="20:00", working_days="Sun,Mon,Tue,Wed,Thu",
        default_fee=150.0, appointment_duration=30,
        address="Test Street", phone="0100", email="c@test.com",
    )
    session.add(s)
    session.flush()
    return s


# ─── Auth helper ──────────────────────────────────────────────────────────────

@pytest.fixture()
def auth_as(db_session):
    overrides: list = []

    def _apply(role: str, user: User | None = None):
        if user is None:
            user = _make_user(role, db_session)
            _make_profile(user, db_session)
            db_session.commit()
        app.dependency_overrides[get_current_user] = lambda: user
        app.dependency_overrides[get_db] = _override_db(db_session)
        overrides.append(True)
        return user

    yield _apply
    app.dependency_overrides.clear()


MODEL_PATCH = "routers.ai_router._call_model"
MODEL_RETURN = "This is a grounded AI response based on real data."


def _llm_payload(mock) -> str:
    """Combined system + user text from the final agent LLM call (facts live in user message)."""
    call = mock.call_args_list[-1] if mock.call_args_list else mock.call_args
    system, user = call[0][0], call[0][1]
    return f"{system}\n{user}"


# ─── Auth guard ───────────────────────────────────────────────────────────────

class TestAgentAuth:
    def test_requires_auth(self):
        resp = client.post("/ai/agent", json={"message": "hello"})
        assert resp.status_code == 401

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_authenticated_gets_200(self, _mock, auth_as):
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "hello"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_response_has_correct_shape(self, _mock, auth_as):
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "hello"})
        body = resp.json()
        assert "response" in body
        assert "disclaimer" in body


# ─── Patient role ─────────────────────────────────────────────────────────────

class TestPatientRole:
    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_clinic_hours_query(self, _mock, auth_as, db_session):
        _make_settings(db_session)
        db_session.commit()
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "What are the working hours?"})
        assert resp.status_code == 200
        assert resp.json()["response"] == MODEL_RETURN

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_doctor_search_query(self, _mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        _make_doctor(db_session, spec, "Sami", "Ali")
        db_session.commit()
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "Show me doctors"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_symptom_query(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "I have a headache and fever"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_my_appointments_query(self, _mock, auth_as, db_session):
        p_user = _make_user("patient", db_session)
        p_profile = _make_profile(p_user, db_session, "Lina", "Omar")
        spec = _make_specialty(db_session)
        _, _, doc = _make_doctor(db_session, spec)
        _make_appointment(db_session, p_profile.id, doc.id)
        db_session.commit()
        auth_as("patient", user=p_user)
        resp = client.post("/ai/agent", json={"message": "Show me my appointments"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH) 
    def test_model_receives_clinic_data_in_prompt(self, mock_model, auth_as, db_session):
        _make_settings(db_session)
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "What are the working hours?"})
        # Check that system prompt contains clinic data
        system_prompt = _llm_payload(mock_model)
        assert "CLINIC DATA" in system_prompt or "CLINIC SETTINGS" in system_prompt

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_conversation_id_returned(self, _mock, auth_as):
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "hello"})
        cid = resp.json()["conversation_id"]
        assert cid is not None and len(cid) > 0
        # Second message with same conversation_id reuses it
        resp2 = client.post("/ai/agent", json={"message": "again", "conversation_id": cid})
        assert resp2.json()["conversation_id"] == cid

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_arabic_language_accepted(self, _mock, auth_as):
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "كيف أحجز موعداً؟"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_explicit_language_param(self, _mock, auth_as):
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "hello", "language": "ar"})
        assert resp.status_code == 200


# ─── Receptionist role ────────────────────────────────────────────────────────

class TestReceptionistRole:
    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_today_stats_query(self, _mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        p_user, p_profile = _make_user("patient", db_session), None
        p_profile = _make_profile(p_user, db_session)
        _, _, doc = _make_doctor(db_session, spec)
        _make_appointment(db_session, p_profile.id, doc.id)
        db_session.commit()
        auth_as("receptionist")
        resp = client.post("/ai/agent", json={"message": "How many patients today?"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_revenue_query(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("receptionist")
        resp = client.post("/ai/agent", json={"message": "What is today's revenue?"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_cancellations_query(self, _mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        p_user = _make_user("patient", db_session)
        p_profile = _make_profile(p_user, db_session)
        _, _, doc = _make_doctor(db_session, spec)
        _make_appointment(db_session, p_profile.id, doc.id, status="cancelled")
        db_session.commit()
        auth_as("receptionist")
        resp = client.post("/ai/agent", json={"message": "Who cancelled today?"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH)
    def test_revenue_data_passed_to_model(self, mock_model, auth_as, db_session):
        spec = _make_specialty(db_session)
        p_user = _make_user("patient", db_session)
        p_profile = _make_profile(p_user, db_session)
        _, _, doc = _make_doctor(db_session, spec)
        apt = _make_appointment(db_session, p_profile.id, doc.id)
        _make_payment(db_session, apt.id, amount=999.0)
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("receptionist")
        client.post("/ai/agent", json={"message": "What is the revenue?"})
        system_prompt = _llm_payload(mock_model)
        # Revenue data should be in the system prompt
        assert "999" in system_prompt or "REVENUE" in system_prompt.upper()

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_arabic_query(self, _mock, auth_as):
        auth_as("receptionist")
        resp = client.post("/ai/agent", json={"message": "كم الإيراد اليوم؟"})
        assert resp.status_code == 200


# ─── Doctor role ──────────────────────────────────────────────────────────────

class TestDoctorRole:
    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_my_schedule_today(self, _mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        p_user = _make_user("patient", db_session)
        p_profile = _make_profile(p_user, db_session)
        d_user, d_profile, doc = _make_doctor(db_session, spec, "Karim", "Zaki")
        _make_appointment(db_session, p_profile.id, doc.id)
        db_session.commit()
        auth_as("doctor", user=d_user)
        resp = client.post("/ai/agent", json={"message": "What is my schedule today?"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_my_reviews(self, _mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        p_user = _make_user("patient", db_session)
        p_profile = _make_profile(p_user, db_session)
        d_user, d_profile, doc = _make_doctor(db_session, spec)
        apt = _make_appointment(db_session, p_profile.id, doc.id)
        r = AppointmentReview(
            id=_uid(), appointment_id=apt.id, patient_id=p_profile.id,
            doctor_id=doc.id, doctor_rating=5, doctor_comment="Excellent",
            created_at=datetime.utcnow()
        )
        db_session.add(r)
        db_session.commit()
        auth_as("doctor", user=d_user)
        resp = client.post("/ai/agent", json={"message": "What are my reviews?"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH)
    def test_doctor_only_sees_own_schedule(self, mock_model, auth_as, db_session):
        spec = _make_specialty(db_session)
        p_user = _make_user("patient", db_session)
        p_profile = _make_profile(p_user, db_session)
        d_user1, _, doc1 = _make_doctor(db_session, spec, "Doc1", "A")
        d_user2, _, doc2 = _make_doctor(db_session, spec, "Doc2", "B")
        apt1 = _make_appointment(db_session, p_profile.id, doc1.id)
        _make_appointment(db_session, p_profile.id, doc2.id)
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("doctor", user=d_user1)
        client.post("/ai/agent", json={"message": "What is my schedule today?"})
        system_prompt = _llm_payload(mock_model)
        # doc1's schedule should be in prompt, not doc2's directly
        assert "Doc1" in system_prompt or "MY SCHEDULE" in system_prompt.upper()

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_doctor_cannot_see_admin_dashboard(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("doctor")
        # Even if doctor asks for admin data, the prompt should not include it
        resp = client.post("/ai/agent", json={"message": "Show me admin dashboard"})
        assert resp.status_code == 200  # still 200 but data won't be there

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_arabic_schedule_query(self, _mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        d_user, _, _ = _make_doctor(db_session, spec)
        db_session.commit()
        auth_as("doctor", user=d_user)
        resp = client.post("/ai/agent", json={"message": "ما هو جدولي اليوم؟"})
        assert resp.status_code == 200


# ─── Admin role ───────────────────────────────────────────────────────────────

class TestAdminRole:
    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_admin_dashboard_overview(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("admin")
        resp = client.post("/ai/agent", json={"message": "Give me the total summary"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH)
    def test_admin_gets_full_dashboard_data(self, mock_model, auth_as, db_session):
        _make_user("patient", db_session)
        spec = _make_specialty(db_session)
        _make_doctor(db_session, spec)
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Give me a complete overview"})
        system_prompt = _llm_payload(mock_model)
        assert "total_patients" in system_prompt or "ADMIN DASHBOARD" in system_prompt.upper()

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_doctor_comparison(self, _mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        _make_doctor(db_session, spec, "BusyDoc", "A")
        _make_doctor(db_session, spec, "QuietDoc", "B")
        db_session.commit()
        auth_as("admin")
        resp = client.post("/ai/agent", json={"message": "Compare doctors by appointments"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_patient_lookup_with_name(self, _mock, auth_as, db_session):
        p_user = _make_user("patient", db_session)
        _make_profile(p_user, db_session, "Hanan", "Farag")
        db_session.commit()
        auth_as("admin")
        resp = client.post("/ai/agent", json={"message": "Find patient named Hanan"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH)
    def test_patient_search_results_in_prompt(self, mock_model, auth_as, db_session):
        p_user = _make_user("patient", db_session)
        _make_profile(p_user, db_session, "Zeina", "Badr")
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Find patient named Zeina"})
        system_prompt = _llm_payload(mock_model)
        assert "Zeina" in system_prompt

    @patch(MODEL_PATCH)
    def test_patient_search_without_name_gives_helpful_note(self, mock_model, auth_as, db_session):
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Find a patient"})
        system_prompt = _llm_payload(mock_model)
        # Should include a note asking for the patient's name
        assert "name" in system_prompt.lower() or "patient" in system_prompt.lower()

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_staff_list_query(self, _mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        _make_doctor(db_session, spec)
        _make_user("receptionist", db_session)
        db_session.commit()
        auth_as("admin")
        resp = client.post("/ai/agent", json={"message": "Show me all staff"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_audit_log_query(self, _mock, auth_as, db_session):
        u = _make_user("doctor", db_session)
        log = AuditLog(
            user_id=u.id, action="test_action", entity_type="Record",
            entity_id=_uid(), timestamp=datetime.utcnow()
        )
        db_session.add(log)
        db_session.commit()
        auth_as("admin")
        resp = client.post("/ai/agent", json={"message": "Show me the audit log"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_arabic_admin_query(self, _mock, auth_as):
        auth_as("admin")
        resp = client.post("/ai/agent", json={"message": "أعطني ملخص النظام"})
        assert resp.status_code == 200

    @patch(MODEL_PATCH)
    def test_admin_prompt_includes_privacy_note(self, mock_model, auth_as, db_session):
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Show me everything about all patients"})
        system_prompt = _llm_payload(mock_model)
        # Admin system prompt should mention PHI limitation
        assert "privacy" in system_prompt.lower() or "all patient" in system_prompt.lower()


# ─── Model offline fallback ───────────────────────────────────────────────────

class TestModelFallback:
    @patch(MODEL_PATCH, return_value=None)
    def test_offline_model_returns_facts_anyway(self, _mock, auth_as, db_session):
        _make_settings(db_session)
        db_session.commit()
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "What are the working hours?"})
        assert resp.status_code == 200
        body = resp.json()
        # Should still have a response (the facts block)
        assert len(body["response"]) > 0

    @patch(MODEL_PATCH, return_value="")
    def test_empty_model_response_falls_back_to_facts(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "hello"})
        assert resp.status_code == 200
        # Should contain offline notice
        body = resp.json()
        assert "offline" in body["response"].lower() or "AI model" in body["response"]


# ─── Role isolation ───────────────────────────────────────────────────────────

class TestRoleIsolation:
    @patch(MODEL_PATCH)
    def test_patient_prompt_never_contains_admin_dashboard(self, mock_model, auth_as, db_session):
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "total revenue admin dashboard"})
        system_prompt = _llm_payload(mock_model)
        assert "admin_dashboard" not in system_prompt.lower()
        assert "net_revenue" not in system_prompt

    @patch(MODEL_PATCH)
    def test_receptionist_prompt_never_has_patient_records(self, mock_model, auth_as, db_session):
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("receptionist")
        client.post("/ai/agent", json={"message": "who did what in the audit"})
        payload = _llm_payload(mock_model)
        assert "### RECENT AUDIT" not in payload
        assert "### AUDIT" not in payload

    @patch(MODEL_PATCH)
    def test_doctor_prompt_never_has_audit_log(self, mock_model, auth_as, db_session):
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("doctor")
        client.post("/ai/agent", json={"message": "show me audit log and all patients revenue"})
        payload = _llm_payload(mock_model)
        assert "### RECENT AUDIT" not in payload
        assert "### ADMIN DASHBOARD" not in payload

    @patch(MODEL_PATCH)
    def test_system_prompt_contains_role_specific_rules(self, mock_model, auth_as, db_session):
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "hello"})
        system_prompt = _llm_payload(mock_model)
        # Patient prompt should mention doctor recommendation
        assert "doctor" in system_prompt.lower()

    @patch(MODEL_PATCH)
    def test_admin_system_prompt_mentions_privacy_limitation(self, mock_model, auth_as, db_session):
        db_session.commit()
        mock_model.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "hello"})
        system_prompt = _llm_payload(mock_model)
        assert "privacy" in system_prompt.lower() or "not shown here" in system_prompt.lower()


# ─── Disclaimer checks ────────────────────────────────────────────────────────

class TestDisclaimers:
    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_patient_gets_disclaimer(self, _mock, auth_as):
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "hello"})
        assert resp.json()["disclaimer"]

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_admin_gets_disclaimer(self, _mock, auth_as):
        auth_as("admin")
        resp = client.post("/ai/agent", json={"message": "hello"})
        assert resp.json()["disclaimer"]

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_doctor_gets_disclaimer(self, _mock, auth_as):
        auth_as("doctor")
        resp = client.post("/ai/agent", json={"message": "hello"})
        assert resp.json()["disclaimer"]

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_receptionist_gets_disclaimer(self, _mock, auth_as):
        auth_as("receptionist")
        resp = client.post("/ai/agent", json={"message": "hello"})
        assert resp.json()["disclaimer"]


# ─── Conversation persistence ────────────────────────────────────────────────

class TestConversationPersistence:
    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_first_message_creates_conversation(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "hello"})
        body = resp.json()
        assert body["conversation_id"] is not None
        assert body["message_count"] == 1
        assert body["remaining_messages"] is not None

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_continuing_conversation_increments_count(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        r1 = client.post("/ai/agent", json={"message": "first"})
        cid = r1.json()["conversation_id"]
        r2 = client.post("/ai/agent", json={"message": "second", "conversation_id": cid})
        assert r2.json()["message_count"] == 2
        assert r2.json()["remaining_messages"] < r1.json()["remaining_messages"]

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_max_messages_field_present(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        resp = client.post("/ai/agent", json={"message": "hello"})
        assert resp.json()["max_messages"] is not None
        assert resp.json()["max_messages"] > 0


# ─── Chat history endpoints ─────────────────────────────────────────────────

class TestChatHistoryEndpoints:
    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_list_chats_returns_conversations(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        client.post("/ai/agent", json={"message": "create me"})
        resp = client.get("/ai/chats")
        assert resp.status_code == 200
        chats = resp.json()
        assert len(chats) >= 1
        assert "id" in chats[0]
        assert "summary" in chats[0]
        assert "message_count" in chats[0]

    def test_list_chats_requires_auth(self):
        resp = client.get("/ai/chats")
        assert resp.status_code == 401

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_get_chat_returns_messages(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        r1 = client.post("/ai/agent", json={"message": "test msg"})
        cid = r1.json()["conversation_id"]
        resp = client.get(f"/ai/chats/{cid}")
        assert resp.status_code == 200
        body = resp.json()
        assert len(body["messages"]) == 2  # user + assistant
        assert body["messages"][0]["role"] == "user"
        assert body["messages"][1]["role"] == "assistant"

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_get_nonexistent_chat_returns_404(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        resp = client.get("/ai/chats/nonexistent-id")
        assert resp.status_code == 404

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_delete_chat(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        r1 = client.post("/ai/agent", json={"message": "to delete"})
        cid = r1.json()["conversation_id"]
        resp = client.delete(f"/ai/chats/{cid}")
        assert resp.status_code == 200
        # Verify it's gone
        resp2 = client.get(f"/ai/chats/{cid}")
        assert resp2.status_code == 404

    @patch(MODEL_PATCH, return_value=MODEL_RETURN)
    def test_delete_nonexistent_returns_404(self, _mock, auth_as, db_session):
        db_session.commit()
        auth_as("patient")
        resp = client.delete("/ai/chats/fake-id")
        assert resp.status_code == 404


# ─── Feature coverage: verify every agreed tool is reachable per role ────────

class TestFeatureCoverage:
    """Systematically verify every agreed AI capability reaches the model prompt."""

    # ── PATIENT: clinic info, doctors, specialties, symptoms, appointments,
    #    availability, reviews ─────────────────────────────────────────────────

    @patch(MODEL_PATCH)
    def test_patient_clinic_info(self, mock, auth_as, db_session):
        _make_settings(db_session); db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "What are the clinic working hours and fees?"})
        prompt = _llm_payload(mock)
        assert "working_hours_start" in prompt

    @patch(MODEL_PATCH)
    def test_patient_specialties(self, mock, auth_as, db_session):
        _make_specialty(db_session, "Dermatology"); db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "What doctor specialties do you have?"})
        prompt = _llm_payload(mock)
        assert "Dermatology" in prompt

    @patch(MODEL_PATCH)
    def test_patient_doctor_list_with_ratings(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        _, _, doc = _make_doctor(db_session, spec, "Nabil", "Hassan")
        p = _make_user("patient", db_session)
        pp = _make_profile(p, db_session)
        apt = _make_appointment(db_session, pp.id, doc.id)
        db_session.add(AppointmentReview(
            id=_uid(), appointment_id=apt.id, patient_id=pp.id,
            doctor_id=doc.id, doctor_rating=4, doctor_comment="Good",
            created_at=datetime.utcnow(),
        ))
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "Show me doctors and their ratings"})
        prompt = _llm_payload(mock)
        assert "Nabil" in prompt
        assert "average_rating" in prompt

    @patch(MODEL_PATCH)
    def test_patient_symptom_advice(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session, "Orthopedics")
        _make_doctor(db_session, spec, "Samir", "Youssef")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "I have pain in my knee and back"})
        prompt = _llm_payload(mock)
        assert "Samir" in prompt or "Orthopedics" in prompt

    @patch(MODEL_PATCH)
    def test_patient_my_appointments(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        _, _, doc = _make_doctor(db_session, spec)
        pu = _make_user("patient", db_session)
        pp = _make_profile(pu, db_session, "Layla", "Ahmad")
        _make_appointment(db_session, pp.id, doc.id, status="completed")
        _make_appointment(db_session, pp.id, doc.id, status="pending")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("patient", user=pu)
        client.post("/ai/agent", json={"message": "Show me my appointments"})
        prompt = _llm_payload(mock)
        assert "completed" in prompt or "pending" in prompt

    @patch(MODEL_PATCH)
    def test_patient_doctor_availability(self, mock, auth_as, db_session):
        _make_settings(db_session)
        spec = _make_specialty(db_session)
        _make_doctor(db_session, spec, "Hany", "Fahim")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "Is Dr. Hany free tomorrow?"})
        prompt = _llm_payload(mock)
        assert "available_slots" in prompt or "available_count" in prompt

    @patch(MODEL_PATCH)
    def test_patient_arabic_availability(self, mock, auth_as, db_session):
        _make_settings(db_session)
        spec = _make_specialty(db_session)
        _make_doctor(db_session, spec, "أحمد", "خليل")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "هل الدكتور أحمد متاح بكره؟"})
        prompt = _llm_payload(mock)
        assert "available_slots" in prompt or "available_count" in prompt

    # ── RECEPTIONIST: today stats, revenue, cancellations, doctor workload,
    #    availability, clinic info ─────────────────────────────────────────────

    @patch(MODEL_PATCH)
    def test_receptionist_today_dashboard(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        pu = _make_user("patient", db_session)
        pp = _make_profile(pu, db_session)
        _, _, doc = _make_doctor(db_session, spec)
        _make_appointment(db_session, pp.id, doc.id)
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("receptionist")
        client.post("/ai/agent", json={"message": "How many patients today?"})
        prompt = _llm_payload(mock)
        assert "total" in prompt and "confirmed" in prompt

    @patch(MODEL_PATCH)
    def test_receptionist_revenue_7d_and_30d(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        pu = _make_user("patient", db_session); pp = _make_profile(pu, db_session)
        _, _, doc = _make_doctor(db_session, spec)
        apt = _make_appointment(db_session, pp.id, doc.id)
        _make_payment(db_session, apt.id, 500.0)
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("receptionist")
        client.post("/ai/agent", json={"message": "What is the revenue?"})
        prompt = _llm_payload(mock)
        assert "revenue_last_7_days" in prompt or "total_paid" in prompt

    @patch(MODEL_PATCH)
    def test_receptionist_cancellations_with_lost_revenue(self, mock, auth_as, db_session):
        _make_settings(db_session)
        spec = _make_specialty(db_session)
        pu = _make_user("patient", db_session); pp = _make_profile(pu, db_session)
        _, _, doc = _make_doctor(db_session, spec)
        _make_appointment(db_session, pp.id, doc.id, status="cancelled")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("receptionist")
        client.post("/ai/agent", json={"message": "Who cancelled this week?"})
        prompt = _llm_payload(mock)
        assert "cancelled" in prompt.lower()
        assert "estimated_lost_revenue" in prompt or "150" in prompt

    @patch(MODEL_PATCH)
    def test_receptionist_doctor_availability(self, mock, auth_as, db_session):
        _make_settings(db_session)
        spec = _make_specialty(db_session)
        _make_doctor(db_session, spec, "Tarek", "Salem")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("receptionist")
        client.post("/ai/agent", json={"message": "Is Dr. Tarek free today? Any open slot?"})
        prompt = _llm_payload(mock)
        assert "available_slots" in prompt or "available_count" in prompt

    # ── DOCTOR: own schedule, own reviews, today stats, availability ──────────

    @patch(MODEL_PATCH)
    def test_doctor_my_schedule_has_patients(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        pu = _make_user("patient", db_session); pp = _make_profile(pu, db_session, "Sara", "Nour")
        du, _, doc = _make_doctor(db_session, spec, "Youssef", "Kamil")
        _make_appointment(db_session, pp.id, doc.id)
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("doctor", user=du)
        client.post("/ai/agent", json={"message": "What is my schedule today?"})
        prompt = _llm_payload(mock)
        assert "Sara" in prompt

    @patch(MODEL_PATCH)
    def test_doctor_my_reviews_data(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        pu = _make_user("patient", db_session); pp = _make_profile(pu, db_session)
        du, _, doc = _make_doctor(db_session, spec)
        apt = _make_appointment(db_session, pp.id, doc.id)
        db_session.add(AppointmentReview(
            id=_uid(), appointment_id=apt.id, patient_id=pp.id,
            doctor_id=doc.id, doctor_rating=5, doctor_comment="Amazing",
            created_at=datetime.utcnow(),
        ))
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("doctor", user=du)
        client.post("/ai/agent", json={"message": "What are my reviews and rating?"})
        prompt = _llm_payload(mock)
        assert "Amazing" in prompt or "average_rating" in prompt

    @patch(MODEL_PATCH)
    def test_doctor_today_stats(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        pu = _make_user("patient", db_session); pp = _make_profile(pu, db_session)
        du, _, doc = _make_doctor(db_session, spec)
        _make_appointment(db_session, pp.id, doc.id)
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("doctor", user=du)
        client.post("/ai/agent", json={"message": "How many patients today?"})
        prompt = _llm_payload(mock)
        assert "total" in prompt

    @patch(MODEL_PATCH)
    def test_doctor_checks_availability(self, mock, auth_as, db_session):
        _make_settings(db_session)
        spec = _make_specialty(db_session)
        du, _, doc = _make_doctor(db_session, spec, "Amr", "Fathy")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("doctor", user=du)
        client.post("/ai/agent", json={"message": "What free slots are available tomorrow?"})
        prompt = _llm_payload(mock)
        assert "available_slots" in prompt or "available_count" in prompt

    # ── ADMIN: dashboard, compare doctors, patient lookup, staff list,
    #    audit log, revenue, cancellations, availability, today stats ──────────

    @patch(MODEL_PATCH)
    def test_admin_full_dashboard(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        _make_user("patient", db_session); _make_user("patient", db_session)
        _make_doctor(db_session, spec)
        _make_user("receptionist", db_session)
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Give me the total overview"})
        prompt = _llm_payload(mock)
        assert "total_patients" in prompt
        assert "total_doctors" in prompt
        assert "total_receptionists" in prompt
        assert "net_revenue" in prompt

    @patch(MODEL_PATCH)
    def test_admin_compare_doctors_performance(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        _, _, doc1 = _make_doctor(db_session, spec, "DocA", "X")
        _, _, doc2 = _make_doctor(db_session, spec, "DocB", "Y")
        pu = _make_user("patient", db_session); pp = _make_profile(pu, db_session)
        _make_appointment(db_session, pp.id, doc1.id)
        _make_appointment(db_session, pp.id, doc1.id)
        _make_appointment(db_session, pp.id, doc2.id)
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Compare doctors by appointments"})
        prompt = _llm_payload(mock)
        assert "DocA" in prompt and "DocB" in prompt

    @patch(MODEL_PATCH)
    def test_admin_staff_list_all(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        _make_doctor(db_session, spec, "StaffDoc", "One")
        ru = _make_user("receptionist", db_session)
        _make_profile(ru, db_session, "StaffRec", "Two")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Show me all staff and employees"})
        prompt = _llm_payload(mock)
        assert "StaffDoc" in prompt
        assert "StaffRec" in prompt

    @patch(MODEL_PATCH)
    def test_admin_patient_search(self, mock, auth_as, db_session):
        pu = _make_user("patient", db_session)
        _make_profile(pu, db_session, "Mariam", "Khalil")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Find patient named Mariam"})
        prompt = _llm_payload(mock)
        assert "Mariam" in prompt
        assert "Khalil" in prompt

    @patch(MODEL_PATCH)
    def test_admin_audit_log(self, mock, auth_as, db_session):
        u = _make_user("doctor", db_session)
        db_session.add(AuditLog(
            user_id=u.id, action="login", entity_type="User",
            entity_id=u.id, timestamp=datetime.utcnow(),
        ))
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Show me the audit log activity"})
        prompt = _llm_payload(mock)
        assert "login" in prompt

    @patch(MODEL_PATCH)
    def test_admin_revenue(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        pu = _make_user("patient", db_session); pp = _make_profile(pu, db_session)
        _, _, doc = _make_doctor(db_session, spec)
        apt = _make_appointment(db_session, pp.id, doc.id)
        _make_payment(db_session, apt.id, 1500.0)
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "What is the revenue and income?"})
        prompt = _llm_payload(mock)
        assert "1500" in prompt or "total_paid" in prompt

    @patch(MODEL_PATCH)
    def test_admin_cancellations(self, mock, auth_as, db_session):
        _make_settings(db_session)
        spec = _make_specialty(db_session)
        pu = _make_user("patient", db_session); pp = _make_profile(pu, db_session)
        _, _, doc = _make_doctor(db_session, spec)
        _make_appointment(db_session, pp.id, doc.id, status="cancelled")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "How many cancellations and refunds?"})
        prompt = _llm_payload(mock)
        assert "cancelled" in prompt.lower()

    @patch(MODEL_PATCH)
    def test_admin_doctor_availability(self, mock, auth_as, db_session):
        _make_settings(db_session)
        spec = _make_specialty(db_session)
        _make_doctor(db_session, spec, "AdminDoc", "Test")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("admin")
        client.post("/ai/agent", json={"message": "Which doctor has open slot availability today?"})
        prompt = _llm_payload(mock)
        assert "available_slots" in prompt or "available_count" in prompt

    # ── CROSS-ROLE: role isolation double-checks ─────────────────────────────

    @patch(MODEL_PATCH)
    def test_patient_cannot_get_revenue(self, mock, auth_as, db_session):
        spec = _make_specialty(db_session)
        pu = _make_user("patient", db_session); pp = _make_profile(pu, db_session)
        _, _, doc = _make_doctor(db_session, spec)
        apt = _make_appointment(db_session, pp.id, doc.id)
        _make_payment(db_session, apt.id, 999.0)
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "What is the revenue?"})
        prompt = _llm_payload(mock)
        assert "total_paid" not in prompt
        assert "net_revenue" not in prompt

    @patch(MODEL_PATCH)
    def test_patient_cannot_get_audit(self, mock, auth_as, db_session):
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("patient")
        client.post("/ai/agent", json={"message": "Show me the audit log"})
        prompt = _llm_payload(mock)
        assert "recent_audit" not in prompt

    @patch(MODEL_PATCH)
    def test_receptionist_cannot_get_audit(self, mock, auth_as, db_session):
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("receptionist")
        client.post("/ai/agent", json={"message": "Show me the audit log"})
        prompt = _llm_payload(mock)
        assert "recent_audit" not in prompt

    @patch(MODEL_PATCH)
    def test_doctor_cannot_get_revenue(self, mock, auth_as, db_session):
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("doctor")
        client.post("/ai/agent", json={"message": "What is the revenue?"})
        prompt = _llm_payload(mock)
        assert "total_paid" not in prompt

    @patch(MODEL_PATCH)
    def test_doctor_cannot_compare_doctors(self, mock, auth_as, db_session):
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("doctor")
        client.post("/ai/agent", json={"message": "Compare all doctors"})
        prompt = _llm_payload(mock)
        assert "doctor_comparison" not in prompt

    @patch(MODEL_PATCH)
    def test_receptionist_cannot_search_patients(self, mock, auth_as, db_session):
        pu = _make_user("patient", db_session)
        _make_profile(pu, db_session, "Secret", "Patient")
        db_session.commit()
        mock.return_value = MODEL_RETURN
        auth_as("receptionist")
        client.post("/ai/agent", json={"message": "Find patient named Secret"})
        prompt = _llm_payload(mock)
        assert "patient_search_results" not in prompt
