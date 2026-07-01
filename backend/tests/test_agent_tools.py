"""
Unit tests for agent_tools.py — every tool is tested with an in-memory SQLite DB.
Tests cover: data returned, empty-DB behaviour, role-scoped access, edge cases.
"""

from __future__ import annotations

import sys
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from database import Base
from models import (
    Appointment, AppointmentReview, AuditLog, ClinicSettings, Doctor,
    Payment, Profile, Specialty, User,
)
from agent_tools import (
    _names_match,
    tool_admin_dashboard,
    tool_audit_summary,
    tool_cancellations,
    tool_clinic_settings,
    tool_compare_doctors,
    tool_doctor_availability,
    tool_doctor_reviews_summary,
    tool_doctor_schedule_today,
    tool_doctor_workload,
    tool_get_doctor_reviews,
    tool_list_doctors,
    tool_list_specialties,
    tool_my_appointments_patient,
    tool_revenue_summary,
    tool_search_patient,
    tool_staff_list,
    tool_today_dashboard,
)


# ─── fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture()
def db():
    global _slot_counter
    _slot_counter = 0
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


def _uid() -> str:
    return str(uuid.uuid4())


def _make_specialty(db, name: str = "Cardiology") -> Specialty:
    s = Specialty(name=name, description=f"{name} dept")
    db.add(s)
    db.flush()
    return s


def _make_user_and_profile(db, role: str = "patient", first: str = "Ali", last: str = "Hassan") -> tuple[User, Profile]:
    uid = _uid()
    user = User(id=uid, email=f"{uid[:8]}@test.com", password_hash="x", role=role, is_active=True)
    db.add(user)
    db.flush()
    profile = Profile(id=_uid(), user_id=uid, first_name=first, last_name=last, dob=date(1990, 1, 1), gender="Male")
    db.add(profile)
    db.flush()
    return user, profile


def _make_doctor(db, specialty: Specialty, first: str = "Ahmed", last: str = "Nour") -> tuple[User, Profile, Doctor]:
    user, profile = _make_user_and_profile(db, "doctor", first, last)
    doc = Doctor(id=_uid(), profile_id=profile.id, specialty_id=specialty.id, qualifications="MD", bio="Expert")
    db.add(doc)
    db.flush()
    return user, profile, doc


_slot_counter = 0

def _make_appointment(db, patient_profile_id: str, doctor_id: str, apt_date=None, status: str = "confirmed", time_slot: str | None = None) -> Appointment:
    global _slot_counter
    if time_slot is None:
        _slot_counter += 1
        h, m = divmod(_slot_counter, 2)
        time_slot = f"{8 + h:02d}:{m * 30:02d}"
    apt = Appointment(
        id=_uid(),
        patient_id=patient_profile_id,
        doctor_id=doctor_id,
        date=apt_date or date.today(),
        time_slot=time_slot,
        status=status,
    )
    db.add(apt)
    db.flush()
    return apt


def _make_payment(db, appointment_id: str, amount: float = 200.0, pstatus: str = "paid") -> Payment:
    p = Payment(
        id=_uid(),
        appointment_id=appointment_id,
        amount=amount,
        payment_status=pstatus,
        payment_method="cash",
    )
    db.add(p)
    db.flush()
    return p


def _make_settings(db) -> ClinicSettings:
    s = ClinicSettings(
        clinic_name="Clinova",
        working_hours_start="08:00",
        working_hours_end="20:00",
        working_days="Sun,Mon,Tue,Wed,Thu",
        default_fee=150.0,
        appointment_duration=20,
        address="123 Health St",
        phone="0100000000",
        email="clinic@test.com",
    )
    db.add(s)
    db.flush()
    return s


def _make_review(db, appointment_id: str, patient_id: str, doctor_id: str, rating: int = 5) -> AppointmentReview:
    r = AppointmentReview(
        id=_uid(),
        appointment_id=appointment_id,
        patient_id=patient_id,
        doctor_id=doctor_id,
        doctor_rating=rating,
        doctor_comment=f"Rating {rating} stars",
        created_at=datetime.utcnow(),
    )
    db.add(r)
    db.flush()
    return r


# ─── tool_clinic_settings ─────────────────────────────────────────────────────

class TestClinicSettings:
    def test_returns_defaults_when_empty(self, db):
        result = tool_clinic_settings(db)
        assert result["clinic_name"] == "Smart Clinic"
        assert result["default_fee"] == 100.0
        assert "working_hours_start" in result

    def test_returns_stored_settings(self, db):
        _make_settings(db)
        result = tool_clinic_settings(db)
        assert result["clinic_name"] == "Clinova"
        assert result["default_fee"] == 150.0
        assert result["working_hours_start"] == "08:00"
        assert result["address"] == "123 Health St"
        assert result["phone"] == "0100000000"


# ─── tool_list_specialties ────────────────────────────────────────────────────

class TestListSpecialties:
    def test_empty_returns_empty_list(self, db):
        assert tool_list_specialties(db) == []

    def test_returns_all_specialties(self, db):
        _make_specialty(db, "Cardiology")
        _make_specialty(db, "Dermatology")
        result = tool_list_specialties(db)
        assert len(result) == 2
        names = [r["name"] for r in result]
        assert "Cardiology" in names
        assert "Dermatology" in names

    def test_specialty_has_required_fields(self, db):
        _make_specialty(db, "Neurology")
        result = tool_list_specialties(db)
        assert "id" in result[0]
        assert "name" in result[0]
        assert "description" in result[0]


# ─── tool_list_doctors ────────────────────────────────────────────────────────

class TestListDoctors:
    def test_empty_returns_empty_list(self, db):
        assert tool_list_doctors(db) == []

    def test_returns_active_doctors(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "Sami", "Ali")
        result = tool_list_doctors(db)
        assert len(result) == 1
        assert result[0]["name"] == "Dr. Sami Ali"
        assert result[0]["specialty"] == "Cardiology"

    def test_excludes_inactive_doctors(self, db):
        spec = _make_specialty(db)
        user, profile, doc = _make_doctor(db, spec)
        user.is_active = False
        db.flush()
        assert tool_list_doctors(db) == []

    def test_doctor_has_rating_fields(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec)
        result = tool_list_doctors(db)
        assert "average_rating" in result[0]
        assert "review_count" in result[0]

    def test_multiple_doctors(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "Omar", "Said")
        _make_doctor(db, spec, "Sara", "Nabil")
        result = tool_list_doctors(db)
        assert len(result) == 2

    def test_doctor_has_qualifications_and_bio(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec)
        result = tool_list_doctors(db)
        assert result[0]["qualifications"] == "MD"
        assert result[0]["bio"] == "Expert"


# ─── tool_get_doctor_reviews ──────────────────────────────────────────────────

class TestGetDoctorReviews:
    def test_no_reviews_returns_empty(self, db):
        spec = _make_specialty(db)
        _, _, doc = _make_doctor(db, spec)
        assert tool_get_doctor_reviews(db, doc.id) == []

    def test_returns_reviews_with_fields(self, db):
        spec = _make_specialty(db)
        p_user, p_profile = _make_user_and_profile(db, "patient", "Mona", "Khalil")
        d_user, d_profile, doc = _make_doctor(db, spec)
        apt = _make_appointment(db, p_profile.id, doc.id)
        _make_review(db, apt.id, p_profile.id, doc.id, rating=4)
        result = tool_get_doctor_reviews(db, doc.id)
        assert len(result) == 1
        assert result[0]["rating"] == 4
        assert "Mona" in result[0]["patient"]
        assert "comment" in result[0]

    def test_limit_is_respected(self, db):
        spec = _make_specialty(db)
        p_user, p_profile = _make_user_and_profile(db, "patient")
        d_user, d_profile, doc = _make_doctor(db, spec)
        for _ in range(10):
            apt = _make_appointment(db, p_profile.id, doc.id)
            _make_review(db, apt.id, p_profile.id, doc.id, rating=5)
        result = tool_get_doctor_reviews(db, doc.id, limit=3)
        assert len(result) == 3


# ─── tool_my_appointments_patient ────────────────────────────────────────────

class TestMyAppointmentsPatient:
    def test_no_appointments_returns_empty(self, db):
        _, p_profile = _make_user_and_profile(db, "patient")
        assert tool_my_appointments_patient(db, p_profile.id) == []

    def test_returns_patient_appointments_only(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient", "Lina", "Omar")
        _, _, doc = _make_doctor(db, spec)
        _, other_profile = _make_user_and_profile(db, "patient", "Nadia", "Saleh")

        _make_appointment(db, p_profile.id, doc.id)
        _make_appointment(db, other_profile.id, doc.id)

        result = tool_my_appointments_patient(db, p_profile.id)
        assert len(result) == 1
        assert result[0]["patient_name"] == "Lina Omar"

    def test_appointment_has_required_fields(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        _make_appointment(db, p_profile.id, doc.id)
        result = tool_my_appointments_patient(db, p_profile.id)
        apt = result[0]
        for field in ("id", "date", "time_slot", "status", "doctor_name", "specialty"):
            assert field in apt


# ─── tool_today_dashboard ─────────────────────────────────────────────────────

class TestTodayDashboard:
    def test_empty_db_returns_zeros(self, db):
        result = tool_today_dashboard(db)
        assert result["total"] == 0
        assert result["revenue_today"] == 0.0
        assert result["refunded_today"] == 0.0

    def test_counts_todays_appointments(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        _make_appointment(db, p_profile.id, doc.id, status="confirmed")
        _make_appointment(db, p_profile.id, doc.id, status="completed")
        _make_appointment(db, p_profile.id, doc.id, status="cancelled")

        result = tool_today_dashboard(db)
        assert result["total"] == 3
        assert result["confirmed"] == 1
        assert result["completed"] == 1
        assert result["cancelled"] == 1

    def test_excludes_other_day_appointments(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        yesterday = date.today() - timedelta(days=1)
        _make_appointment(db, p_profile.id, doc.id, apt_date=yesterday)
        result = tool_today_dashboard(db)
        assert result["total"] == 0

    def test_revenue_sums_paid_payments(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        apt = _make_appointment(db, p_profile.id, doc.id)
        _make_payment(db, apt.id, amount=300.0)
        result = tool_today_dashboard(db)
        assert result["revenue_today"] == 300.0

    def test_refunded_tracked_separately(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        apt = _make_appointment(db, p_profile.id, doc.id)
        _make_payment(db, apt.id, amount=150.0, pstatus="refunded")
        result = tool_today_dashboard(db)
        assert result["refunded_today"] == 150.0
        assert result["revenue_today"] == 0.0

    def test_date_field_present(self, db):
        result = tool_today_dashboard(db)
        assert result["date"] == str(date.today())


# ─── tool_revenue_summary ─────────────────────────────────────────────────────

class TestRevenueSummary:
    def test_empty_db(self, db):
        result = tool_revenue_summary(db, 30)
        assert result["total_paid"] == 0.0
        assert result["net_revenue"] == 0.0
        assert result["period_days"] == 30

    def test_sums_paid_in_period(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        apt = _make_appointment(db, p_profile.id, doc.id)
        _make_payment(db, apt.id, amount=500.0)
        result = tool_revenue_summary(db, 30)
        assert result["total_paid"] == 500.0
        assert result["paid_count"] == 1

    def test_net_revenue_subtracts_refunds(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        apt1 = _make_appointment(db, p_profile.id, doc.id)
        apt2 = _make_appointment(db, p_profile.id, doc.id)
        _make_payment(db, apt1.id, amount=600.0, pstatus="paid")
        _make_payment(db, apt2.id, amount=100.0, pstatus="refunded")
        result = tool_revenue_summary(db, 30)
        assert result["net_revenue"] == 500.0
        assert result["refund_count"] == 1


# ─── tool_cancellations ───────────────────────────────────────────────────────

class TestCancellations:
    def test_no_cancellations_returns_empty(self, db):
        assert tool_cancellations(db, 7) == []

    def test_returns_cancelled_in_period(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        _make_appointment(db, p_profile.id, doc.id, status="cancelled")
        _make_appointment(db, p_profile.id, doc.id, status="confirmed")
        result = tool_cancellations(db, 7)
        assert len(result) == 1
        assert result[0]["status"] == "cancelled"

    def test_excludes_cancellations_outside_period(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        old_date = date.today() - timedelta(days=30)
        _make_appointment(db, p_profile.id, doc.id, apt_date=old_date, status="cancelled")
        result = tool_cancellations(db, 7)
        assert result == []

    def test_cancellation_includes_patient_name(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient", "Ziad", "Farouk")
        _, _, doc = _make_doctor(db, spec)
        _make_appointment(db, p_profile.id, doc.id, status="cancelled")
        result = tool_cancellations(db, 7)
        assert "Ziad" in result[0]["patient_name"]


# ─── tool_doctor_workload ─────────────────────────────────────────────────────

class TestDoctorWorkload:
    def test_empty_db_returns_empty(self, db):
        assert tool_doctor_workload(db) == []

    def test_counts_appointments_per_doctor(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc1 = _make_doctor(db, spec, "Ahmad", "Ali")
        _, _, doc2 = _make_doctor(db, spec, "Hana", "Said")
        _make_appointment(db, p_profile.id, doc1.id)
        _make_appointment(db, p_profile.id, doc1.id)
        _make_appointment(db, p_profile.id, doc2.id)

        result = tool_doctor_workload(db)
        totals = {r["name"]: r["total"] for r in result}
        assert totals["Dr. Ahmad Ali"] == 2
        assert totals["Dr. Hana Said"] == 1

    def test_sorted_by_busiest(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc1 = _make_doctor(db, spec, "Dr1", "X")
        _, _, doc2 = _make_doctor(db, spec, "Dr2", "X")
        _make_appointment(db, p_profile.id, doc2.id)  # doc2 has 1
        # doc1 has 0
        result = tool_doctor_workload(db)
        assert result[0]["name"] == "Dr. Dr2 X"


# ─── tool_doctor_schedule_today ───────────────────────────────────────────────

class TestDoctorScheduleToday:
    def test_no_appointments_returns_empty(self, db):
        spec = _make_specialty(db)
        _, _, doc = _make_doctor(db, spec)
        assert tool_doctor_schedule_today(db, doc.id) == []

    def test_returns_only_today_for_that_doctor(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc1 = _make_doctor(db, spec, "Dr1", "A")
        _, _, doc2 = _make_doctor(db, spec, "Dr2", "B")
        _make_appointment(db, p_profile.id, doc1.id)
        _make_appointment(db, p_profile.id, doc2.id)

        result = tool_doctor_schedule_today(db, doc1.id)
        assert len(result) == 1
        assert result[0]["doctor_name"] == "Dr. Dr1 A"

    def test_excludes_other_days(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        _make_appointment(db, p_profile.id, doc.id, apt_date=date.today() - timedelta(days=1))
        assert tool_doctor_schedule_today(db, doc.id) == []


# ─── tool_doctor_reviews_summary ─────────────────────────────────────────────

class TestDoctorReviewsSummary:
    def test_no_reviews(self, db):
        spec = _make_specialty(db)
        _, _, doc = _make_doctor(db, spec)
        result = tool_doctor_reviews_summary(db, doc.id)
        assert result["review_count"] == 0
        assert result["average_rating"] is None
        assert result["recent_reviews"] == []

    def test_averages_ratings(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        apt1 = _make_appointment(db, p_profile.id, doc.id)
        apt2 = _make_appointment(db, p_profile.id, doc.id)
        _make_review(db, apt1.id, p_profile.id, doc.id, rating=4)
        _make_review(db, apt2.id, p_profile.id, doc.id, rating=5)
        result = tool_doctor_reviews_summary(db, doc.id)
        assert result["review_count"] == 2
        assert result["average_rating"] == 4.5


# ─── tool_admin_dashboard ─────────────────────────────────────────────────────

class TestAdminDashboard:
    def test_empty_db_zeros(self, db):
        result = tool_admin_dashboard(db)
        assert result["total_patients"] == 0
        assert result["total_doctors"] == 0
        assert result["net_revenue"] == 0.0

    def test_counts_by_role(self, db):
        _make_user_and_profile(db, "patient")
        _make_user_and_profile(db, "patient")
        spec = _make_specialty(db)
        _make_doctor(db, spec)
        result = tool_admin_dashboard(db)
        assert result["total_patients"] == 2
        assert result["total_doctors"] == 1

    def test_all_required_fields_present(self, db):
        result = tool_admin_dashboard(db)
        for field in (
            "total_patients", "total_doctors", "total_receptionists",
            "total_appointments", "pending", "confirmed", "completed",
            "cancelled", "total_paid_revenue", "total_refunded", "net_revenue",
        ):
            assert field in result, f"Missing field: {field}"

    def test_revenue_calculated_correctly(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc = _make_doctor(db, spec)
        apt1 = _make_appointment(db, p_profile.id, doc.id)
        apt2 = _make_appointment(db, p_profile.id, doc.id)
        _make_payment(db, apt1.id, amount=1000.0, pstatus="paid")
        _make_payment(db, apt2.id, amount=200.0, pstatus="refunded")
        result = tool_admin_dashboard(db)
        assert result["total_paid_revenue"] == 1000.0
        assert result["total_refunded"] == 200.0
        assert result["net_revenue"] == 800.0


# ─── tool_compare_doctors ────────────────────────────────────────────────────

class TestCompareDoctors:
    def test_empty_returns_empty(self, db):
        assert tool_compare_doctors(db) == []

    def test_sorted_by_appointments(self, db):
        spec = _make_specialty(db)
        _, p_profile = _make_user_and_profile(db, "patient")
        _, _, doc1 = _make_doctor(db, spec, "Busy", "Doc")
        _, _, doc2 = _make_doctor(db, spec, "Quiet", "Doc")
        _make_appointment(db, p_profile.id, doc1.id)
        _make_appointment(db, p_profile.id, doc1.id)
        _make_appointment(db, p_profile.id, doc2.id)
        result = tool_compare_doctors(db)
        assert result[0]["name"] == "Dr. Busy Doc"
        assert result[0]["total_appointments"] == 2

    def test_includes_revenue_and_rating(self, db):
        spec = _make_specialty(db)
        _, _, doc = _make_doctor(db, spec)
        result = tool_compare_doctors(db)
        assert "revenue" in result[0]
        assert "average_rating" in result[0]
        assert "review_count" in result[0]


# ─── tool_staff_list ─────────────────────────────────────────────────────────

class TestStaffList:
    def test_empty_db(self, db):
        assert tool_staff_list(db) == []

    def test_returns_doctors_and_receptionists(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "DrA", "X")
        _make_user_and_profile(db, "receptionist", "Rec", "Y")
        result = tool_staff_list(db)
        roles = [r["role"] for r in result]
        assert "doctor" in roles
        assert "receptionist" in roles

    def test_does_not_return_patients_or_admins(self, db):
        _make_user_and_profile(db, "patient")
        _make_user_and_profile(db, "admin")
        result = tool_staff_list(db)
        assert all(r["role"] not in ("patient", "admin") for r in result)

    def test_filter_by_role(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec)
        _make_user_and_profile(db, "receptionist")
        result = tool_staff_list(db, role="doctor")
        assert all(r["role"] == "doctor" for r in result)

    def test_doctor_entry_includes_specialty(self, db):
        spec = _make_specialty(db, "Orthopedics")
        _make_doctor(db, spec, "Karim", "Zaki")
        result = tool_staff_list(db, role="doctor")
        assert result[0]["specialty"] == "Orthopedics"


# ─── tool_search_patient ─────────────────────────────────────────────────────

class TestSearchPatient:
    def test_no_match_returns_empty(self, db):
        assert tool_search_patient(db, "Nonexistent") == []

    def test_finds_by_first_name(self, db):
        _make_user_and_profile(db, "patient", "Yasmin", "Adel")
        result = tool_search_patient(db, "Yasmin")
        assert len(result) == 1
        assert "Yasmin" in result[0]["name"]

    def test_finds_by_last_name(self, db):
        _make_user_and_profile(db, "patient", "Omar", "Fathy")
        result = tool_search_patient(db, "Fathy")
        assert len(result) == 1

    def test_does_not_return_doctors(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "DoctorMatch", "X")
        result = tool_search_patient(db, "DoctorMatch")
        assert result == []

    def test_includes_medical_summary_fields(self, db):
        _make_user_and_profile(db, "patient", "Heba", "Nour")
        result = tool_search_patient(db, "Heba")
        entry = result[0]
        assert "blood_type" in entry
        assert "allergies" in entry
        assert "chronic_diseases" in entry
        assert "total_appointments" in entry

    def test_limit_is_respected(self, db):
        for i in range(10):
            _make_user_and_profile(db, "patient", "TestPatient", f"No{i}")
        result = tool_search_patient(db, "TestPatient", limit=5)
        assert len(result) <= 5

    def test_does_not_return_full_medical_records(self, db):
        _make_user_and_profile(db, "patient", "Privacy", "Check")
        result = tool_search_patient(db, "Privacy")
        # Should NOT contain full records, prescriptions, or documents
        entry = result[0]
        assert "records" not in entry
        assert "prescriptions" not in entry
        assert "documents" not in entry


# ─── tool_audit_summary ──────────────────────────────────────────────────────

class TestAuditSummary:
    def test_empty_db_returns_empty(self, db):
        assert tool_audit_summary(db, 7) == []

    def test_returns_recent_logs(self, db):
        user, _ = _make_user_and_profile(db, "doctor", "Audit", "User")
        log = AuditLog(
            user_id=user.id,
            action="record_created",
            entity_type="MedicalRecord",
            entity_id=_uid(),
            details="Created record",
            timestamp=datetime.utcnow(),
        )
        db.add(log)
        db.flush()
        result = tool_audit_summary(db, 7)
        assert len(result) == 1
        assert result[0]["action"] == "record_created"
        assert result[0]["role"] == "doctor"

    def test_excludes_old_logs(self, db):
        user, _ = _make_user_and_profile(db, "doctor")
        log = AuditLog(
            user_id=user.id,
            action="old_action",
            entity_type="X",
            entity_id=_uid(),
            timestamp=datetime.utcnow() - timedelta(days=30),
        )
        db.add(log)
        db.flush()
        result = tool_audit_summary(db, 7)
        assert result == []

    def test_log_has_required_fields(self, db):
        user, _ = _make_user_and_profile(db, "receptionist", "Staff", "One")
        log = AuditLog(
            user_id=user.id,
            action="payment_recorded",
            entity_type="Payment",
            entity_id=_uid(),
            timestamp=datetime.utcnow(),
        )
        db.add(log)
        db.flush()
        result = tool_audit_summary(db, 7)
        entry = result[0]
        for field in ("timestamp", "action", "by", "role", "entity"):
            assert field in entry


# ─── Arabic↔English name matching ─────────────────────────────────────────

class TestNamesMatch:
    def test_exact_english(self):
        assert _names_match("Ahmed", "Ahmed", "Hassan", "Dr. Ahmed Hassan")

    def test_exact_arabic(self):
        assert _names_match("أحمد", "أحمد", "حسن", "Dr. أحمد حسن")

    def test_arabic_query_english_db(self):
        assert _names_match("احمد", "Ahmed", "Hassan", "Dr. Ahmed Hassan")

    def test_arabic_query_english_db_variant(self):
        assert _names_match("أحمد", "Ahmad", "Salem", "Dr. Ahmad Salem")

    def test_english_query_arabic_db(self):
        assert _names_match("ahmed", "أحمد", "حسن", "Dr. أحمد حسن")

    def test_mohamed_arabic_to_english(self):
        assert _names_match("محمد", "Mohamed", "Ali", "Dr. Mohamed Ali")

    def test_khaled_arabic_to_english(self):
        assert _names_match("خالد", "Khaled", "Omar", "Dr. Khaled Omar")

    def test_no_match(self):
        assert not _names_match("سامي", "Ahmed", "Hassan", "Dr. Ahmed Hassan")

    def test_partial_match_in_full_name(self):
        assert _names_match("ahmed", "X", "Y", "something ahmed something")

    def test_case_insensitive(self):
        assert _names_match("AHMED", "ahmed", "hassan", "dr. ahmed hassan")


# ─── Doctor Availability ──────────────────────────────────────────────────

class TestDoctorAvailability:
    def test_returns_all_doctors_when_no_name(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "Ali", "Zaki")
        _make_doctor(db, spec, "Sara", "Nour")
        _make_settings(db)
        result = tool_doctor_availability(db)
        assert len(result) == 2
        names = {r["doctor"] for r in result}
        assert "Dr. Ali Zaki" in names
        assert "Dr. Sara Nour" in names

    def test_filters_by_english_name(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "Ali", "Zaki")
        _make_doctor(db, spec, "Sara", "Nour")
        _make_settings(db)
        result = tool_doctor_availability(db, doctor_name="Ali")
        assert len(result) == 1
        assert result[0]["doctor"] == "Dr. Ali Zaki"

    def test_filters_by_arabic_name_matching_english_db(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "Ahmed", "Hassan")
        _make_doctor(db, spec, "Sara", "Nour")
        _make_settings(db)
        result = tool_doctor_availability(db, doctor_name="احمد")
        assert len(result) == 1
        assert result[0]["doctor"] == "Dr. Ahmed Hassan"

    def test_has_available_slots(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "Ali", "Zaki")
        _make_settings(db)
        result = tool_doctor_availability(db, doctor_name="Ali")
        assert len(result) == 1
        assert result[0]["is_working"] is True
        assert "available_slots" in result[0]
        assert len(result[0]["available_slots"]) > 0

    def test_booked_slots_reduce_available(self, db):
        spec = _make_specialty(db)
        _, _, doc = _make_doctor(db, spec, "Ali", "Zaki")
        _make_settings(db)
        patient_user, patient_profile = _make_user_and_profile(db, "patient")
        apt = Appointment(
            id=_uid(), patient_id=patient_profile.id, doctor_id=doc.id,
            date=date.today(), time_slot="10:00", status="confirmed",
        )
        db.add(apt)
        db.flush()
        result = tool_doctor_availability(db, doctor_name="Ali", target_date=date.today())
        assert result[0]["booked_count"] == 1
        assert "10:00" not in result[0]["available_slots"]
        assert "10:00" in result[0]["booked_slots"]

    def test_tomorrow_date(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "Ali", "Zaki")
        _make_settings(db)
        tomorrow = date.today() + timedelta(days=1)
        result = tool_doctor_availability(db, target_date=tomorrow)
        assert result[0]["date"] == str(tomorrow)

    def test_no_match_returns_empty(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "Ali", "Zaki")
        _make_settings(db)
        result = tool_doctor_availability(db, doctor_name="NonExistent")
        assert result == []

    def test_result_has_all_fields(self, db):
        spec = _make_specialty(db)
        _make_doctor(db, spec, "Ali", "Zaki")
        _make_settings(db)
        result = tool_doctor_availability(db, doctor_name="Ali")
        entry = result[0]
        for field in ("doctor", "specialty", "date", "day", "is_working",
                       "working_hours", "total_slots", "booked_count",
                       "available_count", "available_slots", "booked_slots"):
            assert field in entry, f"Missing field: {field}"
