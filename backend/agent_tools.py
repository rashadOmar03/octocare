"""
Agent tools — read-only DB queries for the AI agent.

Each function returns plain serialisable Python (dict / list).
No HTTP calls; no writes to the DB.
"""

from __future__ import annotations

import re
from datetime import date, datetime, timedelta
from typing import Optional

# Common Arabic↔English name mappings for fuzzy doctor matching
_AR_EN_NAMES: dict[str, list[str]] = {
    "احمد": ["ahmed", "ahmad"],
    "أحمد": ["ahmed", "ahmad"],
    "محمد": ["mohamed", "mohammed", "muhammad", "mohamad"],
    "علي": ["ali", "aly"],
    "عمر": ["omar", "omer"],
    "حسن": ["hassan", "hasan"],
    "حسين": ["hussein", "hussain", "hosein"],
    "خالد": ["khaled", "khalid"],
    "كريم": ["karim", "kareem"],
    "سامي": ["sami", "samy"],
    "طارق": ["tarek", "tareq", "tariq"],
    "يوسف": ["youssef", "yousef", "yosef", "joseph"],
    "ابراهيم": ["ibrahim", "ebrahim"],
    "إبراهيم": ["ibrahim", "ebrahim"],
    "مصطفى": ["mostafa", "mustafa"],
    "عبدالله": ["abdullah", "abdallah"],
    "سعيد": ["saeed", "said", "saeid"],
    "ياسر": ["yasser", "yaser"],
    "هاني": ["hany", "hani"],
    "عمرو": ["amr", "amro"],
    "نبيل": ["nabil", "nabeel"],
    "سمير": ["samir", "sameer"],
    "فاطمة": ["fatma", "fatima"],
    "سارة": ["sara", "sarah"],
    "مريم": ["mariam", "maryam"],
    "نور": ["nour", "noor", "nur"],
    "ليلى": ["layla", "leila", "laila"],
    "هنا": ["hana", "hanna"],
    "زينة": ["zeina", "zeinab"],
    "رشا": ["rasha"],
    "منى": ["mona", "muna"],
    "دينا": ["dina", "deena"],
    "رانيا": ["rania", "ranya"],
    "لينا": ["lina", "leena"],
}

def _build_reverse_map() -> dict[str, list[str]]:
    rev: dict[str, list[str]] = {}
    for ar, ens in _AR_EN_NAMES.items():
        for en in ens:
            rev.setdefault(en, []).append(ar)
    return rev

_EN_AR_NAMES = _build_reverse_map()


def _names_match(query: str, first_name: str, last_name: str, full_name: str) -> bool:
    """Fuzzy name matching that handles Arabic↔English transliteration."""
    q = query.lower().strip()
    first_l = first_name.lower().strip()
    last_l = last_name.lower().strip()
    full_l = full_name.lower().strip()

    if q in full_l or q == first_l or q == last_l:
        return True

    ar_variants = _AR_EN_NAMES.get(q, [])
    for v in ar_variants:
        if v in full_l or v == first_l or v == last_l:
            return True

    en_variants = _EN_AR_NAMES.get(q, [])
    for v in en_variants:
        if v in full_l or v == first_l or v == last_l:
            return True

    return False

from sqlalchemy import func
from sqlalchemy.orm import Session

from models import (
    AuditLog,
    Appointment,
    AppointmentReview,
    ClinicSettings,
    Doctor,
    DoctorSchedule,
    MedicalRecord,
    Payment,
    Prescription,
    Profile,
    Specialty,
    User,
)
from clinic_schedule import working_days_label, parse_working_days, DEFAULT_WORKING_DAYS


# ─── helpers ──────────────────────────────────────────────────────────────────

def _doc_name(profile: Optional[Profile]) -> str:
    if not profile:
        return "Unknown"
    return f"Dr. {profile.first_name or ''} {profile.last_name or ''}".strip()


def _person_name(profile: Optional[Profile]) -> str:
    if not profile:
        return "Unknown"
    return f"{profile.first_name or ''} {profile.last_name or ''}".strip()


def _enrich_apt(apt: Appointment, db: Session) -> dict:
    """Lightweight appointment enrichment (no circular import)."""
    patient = db.query(Profile).filter(Profile.id == apt.patient_id).first()
    doctor = db.query(Doctor).filter(Doctor.id == apt.doctor_id).first()
    doc_profile = (
        db.query(Profile).filter(Profile.id == doctor.profile_id).first()
        if doctor else None
    )
    specialty = (
        db.query(Specialty).filter(Specialty.id == doctor.specialty_id).first()
        if doctor else None
    )
    payment = db.query(Payment).filter(Payment.appointment_id == apt.id).first()
    return {
        "id": apt.id,
        "date": str(apt.date) if apt.date else None,
        "time_slot": apt.time_slot,
        "status": apt.status,
        "patient_name": _person_name(patient),
        "doctor_name": _doc_name(doc_profile),
        "specialty": specialty.name if specialty else None,
        "notes": apt.notes,
        "payment_status": payment.payment_status if payment else None,
        "is_paid": payment.payment_status == "paid" if payment else False,
    }


def _rating_stats(db: Session, doctor_id: str) -> dict:
    row = (
        db.query(
            func.count(AppointmentReview.id),
            func.avg(AppointmentReview.doctor_rating),
        )
        .filter(AppointmentReview.doctor_id == doctor_id)
        .first()
    )
    count = int(row[0] or 0)
    avg = row[1]
    return {
        "average_rating": round(float(avg) * 10) / 10 if avg and count > 0 else None,
        "review_count": count,
    }


# ─── Clinic info ──────────────────────────────────────────────────────────────

_WEEKDAY_NAMES_EN = (
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
)


def _closed_days_label(raw: str | None) -> str:
    open_days = parse_working_days(raw)
    closed = [_WEEKDAY_NAMES_EN[d] for d in range(7) if d not in open_days]
    return ", ".join(closed) if closed else "none"


def tool_clinic_settings(db: Session) -> dict:
    s = db.query(ClinicSettings).first()
    if not s:
        open_label = working_days_label(",".join(str(d) for d in DEFAULT_WORKING_DAYS))
        return {
            "clinic_name": "Octocare Clinic",
            "address": None,
            "phone": None,
            "email": None,
            "working_hours_start": "09:00",
            "working_hours_end": "17:00",
            "working_days_open": open_label,
            "closed_days": "Friday",
            "working_days_note": (
                "working_days_open lists days the clinic accepts bookings. "
                "Friday is closed by default."
            ),
            "default_fee": 100.0,
            "appointment_duration": 30,
        }
    open_label = working_days_label(s.working_days)
    return {
        "clinic_name": s.clinic_name,
        "address": s.address,
        "phone": s.phone,
        "email": s.email,
        "working_hours_start": s.working_hours_start,
        "working_hours_end": s.working_hours_end,
        "working_days_open": open_label,
        "closed_days": _closed_days_label(s.working_days),
        "working_days_note": (
            "working_days_open lists OPEN days only. closed_days lists CLOSED days. "
            "Patients can book on any working_days_open day."
        ),
        "default_fee": float(s.default_fee),
        "appointment_duration": s.appointment_duration,
    }


# ─── Specialties & doctors ────────────────────────────────────────────────────

def tool_list_specialties(db: Session) -> list[dict]:
    rows = db.query(Specialty).all()
    return [{"id": s.id, "name": s.name, "description": s.description} for s in rows]


def tool_list_doctors(db: Session) -> list[dict]:
    rows = db.query(Doctor).all()
    result = []
    for d in rows:
        profile = db.query(Profile).filter(Profile.id == d.profile_id).first()
        if not profile:
            continue
        user = db.query(User).filter(User.id == profile.user_id).first()
        if user and not user.is_active:
            continue
        specialty = db.query(Specialty).filter(Specialty.id == d.specialty_id).first()
        rating = _rating_stats(db, d.id)
        from clinic_schedule import get_doctor_consultation_fee
        result.append({
            "doctor_id": d.id,
            "name": _doc_name(profile),
            "specialty": specialty.name if specialty else "General",
            "qualifications": d.qualifications,
            "bio": d.bio,
            "consultation_fee": get_doctor_consultation_fee(db, d),
            "average_rating": rating["average_rating"],
            "review_count": rating["review_count"],
        })
    return result


def tool_get_doctor_reviews(db: Session, doctor_id: str, limit: int = 5) -> list[dict]:
    rows = (
        db.query(AppointmentReview)
        .filter(AppointmentReview.doctor_id == doctor_id)
        .order_by(AppointmentReview.created_at.desc())
        .limit(limit)
        .all()
    )
    result = []
    for r in rows:
        patient = db.query(Profile).filter(Profile.id == r.patient_id).first()
        result.append({
            "patient": _person_name(patient),
            "rating": r.doctor_rating,
            "comment": r.doctor_comment,
            "date": r.created_at.strftime("%Y-%m-%d") if r.created_at else None,
        })
    return result


# ─── Doctor availability ──────────────────────────────────────────────────────

def _generate_slots(start: str, end: str, duration: int) -> list[str]:
    """Generate time slots between start and end times."""
    slots = []
    try:
        sh, sm = map(int, start.split(":"))
        eh, em = map(int, end.split(":"))
        current = sh * 60 + sm
        end_min = eh * 60 + em
        while current + duration <= end_min:
            h, m = divmod(current, 60)
            slots.append(f"{h:02d}:{m:02d}")
            current += duration
    except (ValueError, AttributeError):
        pass
    return slots


def tool_doctor_availability(
    db: Session,
    doctor_name: Optional[str] = None,
    target_date: Optional[date] = None,
) -> list[dict]:
    """
    Check available time slots for doctor(s) on a specific date.
    If doctor_name is None, checks all doctors.
    If target_date is None, checks today.
    """
    if target_date is None:
        target_date = date.today()

    settings = db.query(ClinicSettings).first()
    default_start = settings.working_hours_start if settings else "09:00"
    default_end = settings.working_hours_end if settings else "17:00"
    duration = settings.appointment_duration if settings else 30

    from clinic_schedule import is_doctor_on_vacation, get_doctor_vacation_on_date, is_clinic_open

    if not is_clinic_open(target_date, settings):
        return [{
            "date": str(target_date),
            "day": target_date.strftime("%A"),
            "is_working": False,
            "note": "Clinic is closed on this day",
            "available_slots": [],
            "booked_slots": [],
        }]

    doctors_q = db.query(Doctor).all()
    results = []

    for d in doctors_q:
        profile = db.query(Profile).filter(Profile.id == d.profile_id).first()
        if not profile:
            continue
        user = db.query(User).filter(User.id == profile.user_id).first()
        if user and not user.is_active:
            continue

        doc_full_name = _doc_name(profile)

        if doctor_name:
            if not _names_match(
                doctor_name,
                profile.first_name or "",
                profile.last_name or "",
                doc_full_name,
            ):
                continue

        specialty = db.query(Specialty).filter(Specialty.id == d.specialty_id).first()

        if is_doctor_on_vacation(db, d.id, target_date):
            off = get_doctor_vacation_on_date(db, d.id, target_date)
            reason = off.reason if off and off.reason else "vacation"
            results.append({
                "doctor": doc_full_name,
                "specialty": specialty.name if specialty else "General",
                "date": str(target_date),
                "day": target_date.strftime("%A"),
                "is_working": False,
                "note": f"{doc_full_name} is on {reason} on {target_date.strftime('%A')}",
                "available_slots": [],
                "booked_slots": [],
            })
            continue

        dow = target_date.weekday()  # 0=Mon
        sched = (
            db.query(DoctorSchedule)
            .filter(
                DoctorSchedule.doctor_id == d.id,
                DoctorSchedule.day_of_week == dow,
                DoctorSchedule.is_available == True,
            )
            .first()
        )

        start_time = sched.start_time if sched else default_start
        end_time = sched.end_time if sched else default_end
        is_working = sched.is_available if sched else True

        if not is_working:
            results.append({
                "doctor": doc_full_name,
                "specialty": specialty.name if specialty else "General",
                "date": str(target_date),
                "day": target_date.strftime("%A"),
                "is_working": False,
                "note": f"{doc_full_name} is not working on {target_date.strftime('%A')}",
                "available_slots": [],
                "booked_slots": [],
            })
            continue

        all_slots = _generate_slots(start_time, end_time, duration)

        booked = (
            db.query(Appointment.time_slot)
            .filter(
                Appointment.doctor_id == d.id,
                Appointment.date == target_date,
                Appointment.status.in_(["pending", "confirmed", "arrived"]),
            )
            .all()
        )
        booked_set = {b[0] for b in booked}
        free_slots = [s for s in all_slots if s not in booked_set]

        results.append({
            "doctor": doc_full_name,
            "specialty": specialty.name if specialty else "General",
            "date": str(target_date),
            "day": target_date.strftime("%A"),
            "is_working": True,
            "working_hours": f"{start_time} - {end_time}",
            "total_slots": len(all_slots),
            "booked_count": len(booked_set),
            "available_count": len(free_slots),
            "available_slots": free_slots[:15],
            "booked_slots": sorted(booked_set),
        })

    return results


# ─── Live queue / who is with doctor ──────────────────────────────────────────

def tool_live_queue(db: Session, doctor_name: Optional[str] = None) -> dict:
    """
    Live clinic status: who is currently with each doctor (arrived + paid),
    who is waiting (arrived not yet called), and upcoming confirmed patients.
    """
    today = date.today()
    doctors = db.query(Doctor).all()
    result = {"date": str(today), "doctors": []}

    for d in doctors:
        profile = db.query(Profile).filter(Profile.id == d.profile_id).first()
        if not profile:
            continue
        user = db.query(User).filter(User.id == profile.user_id).first()
        if user and not user.is_active:
            continue

        doc_full_name = _doc_name(profile)

        if doctor_name and not _names_match(
            doctor_name,
            profile.first_name or "",
            profile.last_name or "",
            doc_full_name,
        ):
            continue

        specialty = db.query(Specialty).filter(Specialty.id == d.specialty_id).first()

        arrived = (
            db.query(Appointment)
            .filter(
                Appointment.doctor_id == d.id,
                Appointment.date == today,
                Appointment.status == "arrived",
            )
            .order_by(Appointment.queue_number.asc().nulls_last(), Appointment.time_slot)
            .all()
        )

        confirmed = (
            db.query(Appointment)
            .filter(
                Appointment.doctor_id == d.id,
                Appointment.date == today,
                Appointment.status == "confirmed",
            )
            .order_by(Appointment.time_slot)
            .all()
        )

        def _patient_info(apt: Appointment) -> dict:
            pat = db.query(Profile).filter(Profile.id == apt.patient_id).first()
            pay = db.query(Payment).filter(Payment.appointment_id == apt.id).first()
            return {
                "patient_name": _person_name(pat),
                "time_slot": apt.time_slot,
                "status": apt.status,
                "queue_number": apt.queue_number,
                "is_paid": pay.payment_status == "paid" if pay else False,
            }

        if arrived:
            currently_with = [_patient_info(arrived[0])]
            waiting = [_patient_info(a) for a in arrived[1:]]
        else:
            currently_with = []
            waiting = []

        upcoming = [_patient_info(a) for a in confirmed]

        result["doctors"].append({
            "doctor": doc_full_name,
            "specialty": specialty.name if specialty else "General",
            "currently_with": currently_with,
            "waiting_count": len(waiting),
            "waiting": waiting,
            "upcoming_confirmed": upcoming,
        })

    return result


# ─── Patient tools ────────────────────────────────────────────────────────────

def tool_my_appointments_patient(db: Session, patient_profile_id: str, limit: int = 10) -> list[dict]:
    rows = (
        db.query(Appointment)
        .filter(Appointment.patient_id == patient_profile_id)
        .order_by(Appointment.date.desc(), Appointment.time_slot.desc())
        .limit(limit)
        .all()
    )
    return [_enrich_apt(a, db) for a in rows]


# ─── Receptionist / shared staff stats ────────────────────────────────────────

def tool_today_dashboard(db: Session) -> dict:
    today = date.today()
    q = db.query(Appointment).filter(Appointment.date == today)

    revenue = float(
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .join(Appointment, Appointment.id == Payment.appointment_id)
        .filter(Appointment.date == today, Payment.payment_status == "paid")
        .scalar()
    )
    refunded = float(
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .join(Appointment, Appointment.id == Payment.appointment_id)
        .filter(Appointment.date == today, Payment.payment_status == "refunded")
        .scalar()
    )

    return {
        "date": str(today),
        "total": q.count(),
        "pending": q.filter(Appointment.status == "pending").count(),
        "confirmed": q.filter(Appointment.status == "confirmed").count(),
        "arrived": q.filter(Appointment.status == "arrived").count(),
        "completed": q.filter(Appointment.status == "completed").count(),
        "cancelled": q.filter(Appointment.status == "cancelled").count(),
        "revenue_today": revenue,
        "refunded_today": refunded,
    }


def tool_revenue_summary(db: Session, days: int = 30) -> dict:
    cutoff = datetime.combine(date.today() - timedelta(days=days), datetime.min.time())

    paid = float(
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .filter(Payment.payment_status == "paid", Payment.created_at >= cutoff)
        .scalar()
    )
    refunded = float(
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .filter(Payment.payment_status == "refunded", Payment.created_at >= cutoff)
        .scalar()
    )
    paid_count = db.query(Payment).filter(
        Payment.payment_status == "paid", Payment.created_at >= cutoff
    ).count()
    ref_count = db.query(Payment).filter(
        Payment.payment_status == "refunded", Payment.created_at >= cutoff
    ).count()

    return {
        "period_days": days,
        "total_paid": paid,
        "total_refunded": refunded,
        "net_revenue": paid - refunded,
        "paid_count": paid_count,
        "refund_count": ref_count,
    }


def tool_cancellations(db: Session, days: int = 7) -> list[dict]:
    cutoff = date.today() - timedelta(days=days)
    rows = (
        db.query(Appointment)
        .filter(Appointment.status == "cancelled", Appointment.date >= cutoff)
        .order_by(Appointment.date.desc())
        .limit(50)
        .all()
    )
    return [_enrich_apt(a, db) for a in rows]


def tool_doctor_workload(db: Session, target_date: Optional[date] = None) -> list[dict]:
    if target_date is None:
        target_date = date.today()
    doctors = db.query(Doctor).all()
    result = []
    for d in doctors:
        profile = db.query(Profile).filter(Profile.id == d.profile_id).first()
        specialty = db.query(Specialty).filter(Specialty.id == d.specialty_id).first()
        total = db.query(Appointment).filter(
            Appointment.doctor_id == d.id, Appointment.date == target_date
        ).count()
        completed = db.query(Appointment).filter(
            Appointment.doctor_id == d.id,
            Appointment.date == target_date,
            Appointment.status == "completed",
        ).count()
        result.append({
            "name": _doc_name(profile),
            "specialty": specialty.name if specialty else "",
            "total": total,
            "completed": completed,
        })
    result.sort(key=lambda x: x["total"], reverse=True)
    return result


# ─── Doctor tools ─────────────────────────────────────────────────────────────

def tool_doctor_schedule_today(db: Session, doctor_id: str) -> list[dict]:
    today = date.today()
    rows = (
        db.query(Appointment)
        .filter(Appointment.doctor_id == doctor_id, Appointment.date == today)
        .order_by(Appointment.time_slot)
        .all()
    )
    return [_enrich_apt(a, db) for a in rows]


def tool_doctor_stats_today(db: Session, doctor_id: str) -> dict:
    """Today's appointment counts for one doctor only."""
    today = date.today()
    q = db.query(Appointment).filter(Appointment.doctor_id == doctor_id, Appointment.date == today)
    return {
        "date": str(today),
        "my_total": q.count(),
        "my_pending": q.filter(Appointment.status == "pending").count(),
        "my_confirmed": q.filter(Appointment.status == "confirmed").count(),
        "my_arrived": q.filter(Appointment.status == "arrived").count(),
        "my_completed": q.filter(Appointment.status == "completed").count(),
        "my_cancelled": q.filter(Appointment.status == "cancelled").count(),
    }


def tool_doctor_reviews_summary(db: Session, doctor_id: str) -> dict:
    stats = _rating_stats(db, doctor_id)
    recent = tool_get_doctor_reviews(db, doctor_id, limit=5)
    return {
        "average_rating": stats["average_rating"],
        "review_count": stats["review_count"],
        "recent_reviews": recent,
    }


# ─── Admin tools ──────────────────────────────────────────────────────────────

def tool_admin_dashboard(db: Session) -> dict:
    paid_rev = float(
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .filter(Payment.payment_status == "paid")
        .scalar()
    )
    refunded_rev = float(
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .filter(Payment.payment_status == "refunded")
        .scalar()
    )
    return {
        "total_patients": db.query(User).filter(User.role == "patient").count(),
        "total_doctors": db.query(User).filter(User.role == "doctor").count(),
        "total_receptionists": db.query(User).filter(User.role == "receptionist").count(),
        "total_appointments": db.query(Appointment).count(),
        "pending": db.query(Appointment).filter(Appointment.status == "pending").count(),
        "confirmed": db.query(Appointment).filter(Appointment.status == "confirmed").count(),
        "completed": db.query(Appointment).filter(Appointment.status == "completed").count(),
        "cancelled": db.query(Appointment).filter(Appointment.status == "cancelled").count(),
        "total_paid_revenue": paid_rev,
        "total_refunded": refunded_rev,
        "net_revenue": paid_rev - refunded_rev,
    }


def tool_compare_doctors(db: Session, days: int = 30) -> list[dict]:
    cutoff = date.today() - timedelta(days=days)
    doctors = db.query(Doctor).all()
    result = []
    for d in doctors:
        profile = db.query(Profile).filter(Profile.id == d.profile_id).first()
        specialty = db.query(Specialty).filter(Specialty.id == d.specialty_id).first()
        rating = _rating_stats(db, d.id)
        total_apts = db.query(Appointment).filter(
            Appointment.doctor_id == d.id, Appointment.date >= cutoff
        ).count()
        completed_apts = db.query(Appointment).filter(
            Appointment.doctor_id == d.id,
            Appointment.date >= cutoff,
            Appointment.status == "completed",
        ).count()
        revenue = float(
            db.query(func.coalesce(func.sum(Payment.amount), 0.0))
            .join(Appointment, Appointment.id == Payment.appointment_id)
            .filter(
                Appointment.doctor_id == d.id,
                Appointment.date >= cutoff,
                Payment.payment_status == "paid",
            )
            .scalar()
        )
        result.append({
            "name": _doc_name(profile),
            "specialty": specialty.name if specialty else "",
            "total_appointments": total_apts,
            "completed_appointments": completed_apts,
            "revenue": revenue,
            "average_rating": rating["average_rating"],
            "review_count": rating["review_count"],
        })
    result.sort(key=lambda x: x["total_appointments"], reverse=True)
    return result


def tool_staff_list(db: Session, role: Optional[str] = None) -> list[dict]:
    query = db.query(User)
    if role:
        query = query.filter(User.role == role)
    else:
        query = query.filter(User.role.in_(["doctor", "receptionist"]))
    users = query.order_by(User.role, User.created_at).all()
    result = []
    for u in users:
        profile = db.query(Profile).filter(Profile.user_id == u.id).first()
        entry: dict = {
            "name": _person_name(profile) or u.email,
            "email": u.email,
            "role": u.role,
            "is_active": u.is_active,
            "joined": u.created_at.strftime("%Y-%m-%d") if u.created_at else None,
        }
        if u.role == "doctor" and profile:
            doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
            if doctor:
                specialty = db.query(Specialty).filter(Specialty.id == doctor.specialty_id).first()
                entry["specialty"] = specialty.name if specialty else ""
        result.append(entry)
    return result


def tool_search_patient(db: Session, query_text: str, limit: int = 5) -> list[dict]:
    """
    Search patients by name or email.
    Returns summary cards — NOT full medical records.
    Full PHI is available in the Admin patient detail screen.
    """
    like = f"%{query_text.strip()}%"
    rows = (
        db.query(Profile, User)
        .join(User, User.id == Profile.user_id)
        .filter(User.role == "patient")
        .filter(
            Profile.first_name.ilike(like)
            | Profile.last_name.ilike(like)
            | User.email.ilike(like)
        )
        .limit(limit)
        .all()
    )
    result = []
    for profile, user in rows:
        apt_count = db.query(Appointment).filter(Appointment.patient_id == profile.id).count()
        result.append({
            "user_id": user.id,
            "name": _person_name(profile),
            "email": user.email,
            "is_active": user.is_active,
            "blood_type": profile.blood_type,
            "allergies": profile.allergies,
            "chronic_diseases": profile.chronic_diseases,
            "total_appointments": apt_count,
        })
    return result


def tool_audit_summary(db: Session, days: int = 7, limit: int = 30) -> list[dict]:
    cutoff = datetime.combine(date.today() - timedelta(days=days), datetime.min.time())
    logs = (
        db.query(AuditLog)
        .filter(AuditLog.timestamp >= cutoff)
        .order_by(AuditLog.timestamp.desc())
        .limit(limit)
        .all()
    )
    result = []
    for log in logs:
        user = db.query(User).filter(User.id == log.user_id).first() if log.user_id else None
        profile = db.query(Profile).filter(Profile.user_id == log.user_id).first() if log.user_id else None
        name = _person_name(profile) if profile else (user.email if user else "System")
        result.append({
            "timestamp": log.timestamp.strftime("%Y-%m-%d %H:%M") if log.timestamp else None,
            "action": log.action,
            "by": name,
            "role": user.role if user else None,
            "entity": log.entity_type,
            "details": log.details,
        })
    return result
