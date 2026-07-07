import uuid
from datetime import datetime, date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy import func, or_

from database import get_db
from models import (
    User, Profile, Doctor, DoctorSchedule, Appointment,
    Notification, ClinicSettings, Specialty, Payment, MedicalRecord,
)
from schemas import AppointmentCreate, AppointmentReschedule, ReceptionistReschedule, AppointmentResponse
from auth import get_current_user, require_role
from appointment_rules import (
    auto_cancel_expired_appointments,
    validate_patient_booking,
    validate_booking_date,
    ensure_doctor_slot_free,
    is_slot_available,
    _appointment_is_paid,
    require_paid_arrived_appointment,
)
from audit_service import log_audit
from clinic_time import clinic_today, upcoming_from_date
from clinic_schedule import (
    is_clinic_open,
    parse_working_days,
    working_days_label,
    resolve_doctor_schedule_for_date,
    get_doctor_vacation_on_date,
    normalize_time_hhmm,
)
from access_control import (
    assert_appointment_read,
    assert_appointment_patient_action,
    assert_appointment_doctor_action,
    get_profile,
    get_doctor,
    is_staff,
)

router = APIRouter()


def _get_doctor_id_for_user(user: User, db: Session) -> str | None:
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if not profile:
        return None
    doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
    return doctor.id if doctor else None


def _notify_staff(db: Session, title: str, message: str, exclude_user_id: str | None = None):
    staff = db.query(User).filter(
        User.role.in_(["receptionist", "admin"]),
        User.is_active == True,
    ).all()
    for s in staff:
        if s.id == exclude_user_id:
            continue
        db.add(Notification(
            id=str(uuid.uuid4()),
            user_id=s.id,
            title=title,
            message=message,
        ))


def _get_patient_name(db: Session, patient_id: str) -> str:
    profile = db.query(Profile).filter(Profile.id == patient_id).first()
    if profile:
        return f"{profile.first_name or ''} {profile.last_name or ''}".strip() or "Patient"
    return "Patient"


def _get_doctor_name(db: Session, doctor_id: str) -> str:
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if doctor:
        doc_profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
        if doc_profile:
            return f"Dr. {doc_profile.first_name or ''} {doc_profile.last_name or ''}".strip()
    return "Doctor"


def _notify_patient_queue(db: Session, appointment: Appointment, queue_number: int, *, updated: bool = False) -> None:
    """Notify patient of their queue number only — no other patients shown."""
    profile = db.query(Profile).filter(Profile.id == appointment.patient_id).first()
    if not profile:
        return
    doctor_name = _get_doctor_name(db, appointment.doctor_id)
    if updated:
        title = "Queue update"
        message = (
            f"Your queue number with {doctor_name} is now #{queue_number}. "
            "Please stay nearby — you will be called when it is your turn."
        )
    else:
        title = "You are in the queue"
        message = (
            f"You have been checked in for {doctor_name}. "
            f"Your queue number is #{queue_number}. "
            "Other patients' positions are not shown for privacy."
        )
    db.add(Notification(
        id=str(uuid.uuid4()),
        user_id=profile.user_id,
        title=title,
        message=message,
    ))


def _renumber_doctor_queue(db: Session, apt_date: date, doctor_id: str, *, notify_patients: bool = False) -> None:
    arrived = (
        db.query(Appointment)
        .filter(
            Appointment.date == apt_date,
            Appointment.doctor_id == doctor_id,
            Appointment.status == "arrived",
            Appointment.queue_number.isnot(None),
        )
        .order_by(Appointment.queue_number.asc().nullslast(), Appointment.time_slot.asc())
        .all()
    )
    for index, apt in enumerate(arrived, start=1):
        old = apt.queue_number
        apt.queue_number = index
        if notify_patients and old != index:
            _notify_patient_queue(db, apt, index, updated=True)


@router.get("/my-queue")
def my_queue_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Patient: see own queue number.
    Doctor: see patients queued for them today.
    Staff: returns empty (use /receptionist/queue instead).
    """
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        return {"in_queue": False}

    today = clinic_today()

    if current_user.role == "doctor":
        doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
        if not doctor:
            return {"in_queue": False, "queue": []}
        arrived = (
            db.query(Appointment)
            .filter(
                Appointment.doctor_id == doctor.id,
                Appointment.date == today,
                Appointment.status == "arrived",
                Appointment.queue_number.isnot(None),
            )
            .order_by(Appointment.queue_number.asc())
            .all()
        )
        queue_list = []
        for apt in arrived:
            patient_name = _get_patient_name(db, apt.patient_id)
            queue_list.append({
                "queue_number": apt.queue_number,
                "patient_name": patient_name,
                "appointment_id": apt.id,
                "time_slot": apt.time_slot,
            })
        return {"in_queue": len(queue_list) > 0, "queue": queue_list, "total": len(queue_list)}

    appointment = (
        db.query(Appointment)
        .filter(
            Appointment.patient_id == profile.id,
            Appointment.date == today,
            Appointment.status == "arrived",
            Appointment.queue_number.isnot(None),
        )
        .order_by(Appointment.queue_number.asc())
        .first()
    )
    if not appointment:
        return {"in_queue": False}

    return {
        "in_queue": True,
        "queue_number": appointment.queue_number,
        "doctor_name": _get_doctor_name(db, appointment.doctor_id),
        "appointment_id": appointment.id,
        "time_slot": appointment.time_slot,
        "date": str(appointment.date),
    }


@router.get("/my-patients")
def doctor_my_patients(
    q: str = Query("", alias="q"),
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    """All unique patients this doctor has seen (from appointments), with optional search."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        return []
    doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
    if not doctor:
        return []

    rows = (
        db.query(Appointment.patient_id)
        .filter(Appointment.doctor_id == doctor.id)
        .distinct()
        .all()
    )
    patient_ids = [r[0] for r in rows if r[0]]
    if not patient_ids:
        return []

    query = db.query(Profile, User).join(User, User.id == Profile.user_id).filter(Profile.id.in_(patient_ids))
    term = q.strip().lower()
    if term:
        like = f"%{term}%"
        query = query.filter(
            or_(
                Profile.first_name.ilike(like),
                Profile.last_name.ilike(like),
                User.email.ilike(like),
                User.phone.ilike(like),
                Profile.phone.ilike(like),
            )
        )

    results = []
    for prof, user in query.order_by(Profile.first_name.asc(), Profile.last_name.asc()).limit(100).all():
        results.append({
            "profile_id": prof.id,
            "id": prof.id,
            "first_name": prof.first_name,
            "last_name": prof.last_name,
            "name": f"{prof.first_name or ''} {prof.last_name or ''}".strip() or "Patient",
            "email": user.email,
            "phone": prof.phone or user.phone,
            "photo_url": prof.photo_url,
        })
    return results


@router.get("/booking-info")
def booking_info(db: Session = Depends(get_db)):
    """Working days and booking rules for the patient calendar."""
    settings = db.query(ClinicSettings).first()
    days = sorted(parse_working_days(settings.working_days if settings else None))
    return {
        "working_days": days,
        "working_days_label": working_days_label(settings.working_days if settings else None),
        "min_booking_days_ahead": 1,
    }


@router.get("/specialties", response_model=list)
def get_specialties_public(db: Session = Depends(get_db)):
    """Public endpoint for patients to see available specialties"""
    specialties = db.query(Specialty).all()
    return [{"id": s.id, "name": s.name, "description": s.description} for s in specialties]


@router.get("/doctors", response_model=list)
def get_doctors_public(
    specialty_id: int = None,
    db: Session = Depends(get_db),
):
    """Public endpoint to list doctors, optionally filtered by specialty"""
    query = db.query(Doctor).join(Profile, Doctor.profile_id == Profile.id)
    if specialty_id:
        query = query.filter(Doctor.specialty_id == specialty_id)
    doctors = query.all()
    from clinic_schedule import get_doctor_consultation_fee, is_doctor_on_vacation
    from datetime import date as date_cls

    today = date_cls.today()
    result = []
    for d in doctors:
        profile = db.query(Profile).filter(Profile.id == d.profile_id).first()
        specialty = db.query(Specialty).filter(Specialty.id == d.specialty_id).first()
        from routers.reviews import doctor_rating_stats
        rating = doctor_rating_stats(db, d.id)
        on_vacation = is_doctor_on_vacation(db, d.id, today)
        result.append({
            "id": d.id,
            "name": f"{profile.first_name} {profile.last_name}" if profile else "Unknown",
            "specialty": specialty.name if specialty else "",
            "specialty_id": d.specialty_id,
            "qualifications": d.qualifications,
            "bio": d.bio,
            "profile_photo": profile.photo_url if profile else None,
            "consultation_fee": get_doctor_consultation_fee(db, d),
            "on_vacation_today": on_vacation,
            "average_rating": rating["average_rating"],
            "review_count": rating["review_count"],
        })
    return result


def _generate_slots(start: str, end: str, duration: int) -> list[str]:
    from clinic_schedule import normalize_clinic_time_pair

    slots = []
    start, end = normalize_clinic_time_pair(start, end)
    sh, sm = map(int, start.split(":"))
    eh, em = map(int, end.split(":"))
    current = sh * 60 + sm
    end_min = eh * 60 + em
    if end_min <= current:
        return slots
    while current + duration <= end_min:
        h, m = divmod(current, 60)
        slots.append(f"{h:02d}:{m:02d}")
        current += duration
    return slots


@router.post("/", status_code=status.HTTP_201_CREATED)
def book_appointment(
    data: AppointmentCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    auto_cancel_expired_appointments(db)

    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        import uuid as _uuid
        profile = Profile(
            id=str(_uuid.uuid4()),
            user_id=current_user.id,
            first_name=current_user.email.split('@')[0] if current_user.email else "Patient",
            last_name="",
            is_complete=False,
        )
        db.add(profile)
        db.flush()

    doctor = db.query(Doctor).filter(Doctor.id == data.doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")

    validate_booking_date(data.date, current_user.role, db)

    settings = db.query(ClinicSettings).first()
    schedule, block_reason = resolve_doctor_schedule_for_date(db, data.doctor_id, data.date, settings)
    if block_reason == "vacation":
        raise HTTPException(status_code=400, detail="Doctor is on vacation on the selected date")
    if block_reason or not schedule:
        raise HTTPException(status_code=400, detail="Doctor is not available on this day")

    duration = settings.appointment_duration if settings else 30
    available = _generate_slots(schedule.start_time, schedule.end_time, duration)
    if data.time_slot not in available:
        raise HTTPException(status_code=400, detail="Invalid time slot")

    ensure_doctor_slot_free(db, data.doctor_id, data.date, data.time_slot)

    validate_patient_booking(db, profile.id, data.doctor_id, data.date, data.time_slot)

    appointment = Appointment(
        id=str(uuid.uuid4()),
        patient_id=profile.id,
        doctor_id=data.doctor_id,
        date=data.date,
        time_slot=data.time_slot,
    )
    db.add(appointment)

    patient_name = _get_patient_name(db, profile.id)
    doctor_name = _get_doctor_name(db, data.doctor_id)

    doctor_user = db.query(User).join(Profile).filter(Profile.id == doctor.profile_id).first()
    if doctor_user:
        db.add(Notification(
            id=str(uuid.uuid4()),
            user_id=doctor_user.id,
            title="New Appointment",
            message=f"New appointment with {patient_name} on {data.date} at {data.time_slot}",
        ))

    _notify_staff(
        db,
        "New Appointment Booked",
        f"{patient_name} booked an appointment with {doctor_name} on {data.date} at {data.time_slot}",
    )

    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)


def _enrich_appointment(apt: Appointment, db: Session) -> dict:
    """Add patient_name, doctor_name, specialty_name to appointment data."""
    result = {
        "id": apt.id,
        "patient_id": apt.patient_id,
        "doctor_id": apt.doctor_id,
        "date": apt.date,
        "time_slot": apt.time_slot,
        "status": apt.status,
        "queue_number": apt.queue_number,
        "notes": apt.notes,
        "created_at": apt.created_at,
    }
    patient = db.query(Profile).filter(Profile.id == apt.patient_id).first()
    if patient:
        result["patient_name"] = f"{patient.first_name or ''} {patient.last_name or ''}".strip()
        result["patient_photo_url"] = patient.photo_url
    doctor = db.query(Doctor).filter(Doctor.id == apt.doctor_id).first()
    if doctor:
        doc_profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
        if doc_profile:
            result["doctor_name"] = f"Dr. {doc_profile.first_name or ''} {doc_profile.last_name or ''}".strip()
        spec = db.query(Specialty).filter(Specialty.id == doctor.specialty_id).first()
        if spec:
            result["specialty_name"] = spec.name
    payment = db.query(Payment).filter(Payment.appointment_id == apt.id).first()
    if payment:
        result["payment_status"] = payment.payment_status
        result["is_paid"] = payment.payment_status == "paid"
        result["needs_payment"] = payment.payment_status == "refunded"
    else:
        result["payment_status"] = None
        result["is_paid"] = False
        result["needs_payment"] = False
    record = db.query(MedicalRecord).filter(MedicalRecord.appointment_id == apt.id).first()
    result["medical_record_id"] = record.id if record else None
    result["has_consultation"] = record is not None
    return result


@router.get("/", response_model=list)
def list_appointments(
    status_filter: str = Query(None, alias="status"),
    date_from: date = Query(None),
    date_to: date = Query(None),
    single_date: date = Query(None, alias="date"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    auto_cancel_expired_appointments(db)

    query = db.query(Appointment)

    if current_user.role == "patient":
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile:
            return []
        query = query.filter(Appointment.patient_id == profile.id)
    elif current_user.role == "doctor":
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first() if profile else None
        if not doctor:
            return []
        query = query.filter(Appointment.doctor_id == doctor.id)
    elif current_user.role in ("receptionist", "admin"):
        pass  # clinic-wide list for staff

    if status_filter:
        query = query.filter(Appointment.status == status_filter)
    if single_date:
        query = query.filter(Appointment.date == single_date)
    else:
        if date_from:
            query = query.filter(Appointment.date >= date_from)
        elif current_user.role in ("receptionist", "admin"):
            # Staff worklists default to today + future unless a specific day is requested.
            query = query.filter(Appointment.date >= upcoming_from_date())
        if date_to:
            query = query.filter(Appointment.date <= date_to)

    if current_user.role in ("receptionist", "admin") and not single_date:
        appointments = query.order_by(Appointment.date.asc(), Appointment.time_slot.asc()).all()
    else:
        appointments = query.order_by(Appointment.date.desc(), Appointment.time_slot.desc()).all()
    return [_enrich_appointment(apt, db) for apt in appointments]


def _empty_slots_response(
    db: Session,
    settings: ClinicSettings | None,
    *,
    reason: str | None = None,
    vacation_reason: str | None = None,
) -> dict:
    label = working_days_label(settings.working_days if settings else None)
    return {
        "slots": [],
        "doctor_on_vacation": reason == "vacation",
        "clinic_closed": reason == "clinic_closed",
        "doctor_day_off": reason == "doctor_day_off",
        "all_slots_booked": reason == "all_slots_booked",
        "reason": reason,
        "vacation_reason": vacation_reason,
        "working_days_label": label,
    }


@router.get("/available-slots")
def available_slots(
    doctor_id: str = Query(...),
    slot_date: date = Query(..., alias="date"),
    db: Session = Depends(get_db),
):
    auto_cancel_expired_appointments(db)

    tomorrow = date.today() + timedelta(days=1)
    settings = db.query(ClinicSettings).first()
    if slot_date < tomorrow:
        return _empty_slots_response(db, settings, reason="too_soon")

    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")

    schedule, block_reason = resolve_doctor_schedule_for_date(db, doctor_id, slot_date, settings)
    if block_reason == "vacation":
        off = get_doctor_vacation_on_date(db, doctor_id, slot_date)
        return _empty_slots_response(
            db,
            settings,
            reason="vacation",
            vacation_reason=off.reason if off else None,
        )
    if block_reason or not schedule:
        return _empty_slots_response(db, settings, reason=block_reason or "doctor_day_off")

    duration = settings.appointment_duration if settings else 30
    all_slots = _generate_slots(schedule.start_time, schedule.end_time, duration)
    if not all_slots:
        return _empty_slots_response(db, settings, reason="no_schedule_hours")

    free = [
        s for s in all_slots
        if is_slot_available(db, doctor_id, slot_date, s)
    ]
    if not free and all_slots:
        return _empty_slots_response(db, settings, reason="all_slots_booked")

    label = working_days_label(settings.working_days if settings else None)
    return {
        "slots": free,
        "doctor_on_vacation": False,
        "clinic_closed": False,
        "doctor_day_off": False,
        "all_slots_booked": False,
        "reason": None,
        "working_days_label": label,
    }


@router.get("/{appointment_id}")
def get_appointment(
    appointment_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    assert_appointment_read(current_user, appointment, db)
    return _enrich_appointment(appointment, db)


@router.put("/{appointment_id}/cancel")
def cancel_appointment(
    appointment_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if current_user.role == "patient":
        assert_appointment_patient_action(current_user, appointment, db)
    if current_user.role == "doctor":
        doc_id = _get_doctor_id_for_user(current_user, db)
        if not doc_id or appointment.doctor_id != doc_id:
            raise HTTPException(status_code=403, detail="You can only cancel your own appointments")
    if appointment.status in ("completed", "cancelled"):
        raise HTTPException(status_code=400, detail=f"Cannot cancel a {appointment.status} appointment")

    if _appointment_is_paid(db, appointment_id):
        payment = db.query(Payment).filter(Payment.appointment_id == appointment_id).first()
        if payment and payment.payment_status == "paid":
            if current_user.role in ("receptionist", "admin"):
                raise HTTPException(
                    status_code=400,
                    detail="This appointment is paid. Refund the payment from Payments first, then cancel.",
                )
            raise HTTPException(
                status_code=400,
                detail="This appointment has been paid and cannot be cancelled. Contact admin for a refund.",
            )

    if appointment.status in ("confirmed", "arrived") and current_user.role == "patient":
        raise HTTPException(
            status_code=403,
            detail="This appointment can only be cancelled by the receptionist",
        )

    was_arrived = appointment.status == "arrived"
    appointment.status = "cancelled"
    appointment.queue_number = None
    if was_arrived:
        _renumber_doctor_queue(db, appointment.date, appointment.doctor_id, notify_patients=True)

    patient_name = _get_patient_name(db, appointment.patient_id)
    doctor_name = _get_doctor_name(db, appointment.doctor_id)

    log_audit(
        db,
        current_user.id,
        "cancel_appointment",
        "appointment",
        appointment_id,
        f"Cancelled {patient_name} with {doctor_name} on {appointment.date} {appointment.time_slot}",
    )

    _notify_staff(
        db,
        "Appointment Cancelled",
        f"{patient_name}'s appointment with {doctor_name} on {appointment.date} at {appointment.time_slot} was cancelled.",
        exclude_user_id=current_user.id,
    )

    patient_profile = db.query(Profile).filter(Profile.id == appointment.patient_id).first()
    if patient_profile and patient_profile.user_id != current_user.id:
        db.add(Notification(
            id=str(uuid.uuid4()),
            user_id=patient_profile.user_id,
            title="Appointment Cancelled",
            message=f"Your appointment with {doctor_name} on {appointment.date} at {appointment.time_slot} has been cancelled.",
        ))

    doctor = db.query(Doctor).filter(Doctor.id == appointment.doctor_id).first()
    if doctor:
        doc_user = db.query(User).join(Profile).filter(Profile.id == doctor.profile_id).first()
        if doc_user and doc_user.id != current_user.id:
            db.add(Notification(
                id=str(uuid.uuid4()),
                user_id=doc_user.id,
                title="Appointment Cancelled",
                message=f"{patient_name}'s appointment on {appointment.date} at {appointment.time_slot} was cancelled.",
            ))

    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)


@router.put("/{appointment_id}/confirm")
def confirm_appointment(
    appointment_id: str,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if appointment.status != "pending":
        raise HTTPException(status_code=400, detail="Only pending appointments can be confirmed")

    appointment.status = "confirmed"

    patient_name = _get_patient_name(db, appointment.patient_id)
    doctor_name = _get_doctor_name(db, appointment.doctor_id)

    log_audit(
        db,
        current_user.id,
        "confirm_appointment",
        "appointment",
        appointment_id,
        f"Confirmed {patient_name} with {doctor_name} on {appointment.date} {appointment.time_slot}",
    )

    patient_profile = db.query(Profile).filter(Profile.id == appointment.patient_id).first()
    if patient_profile:
        db.add(Notification(
            id=str(uuid.uuid4()),
            user_id=patient_profile.user_id,
            title="Appointment Confirmed",
            message=f"Your appointment with {doctor_name} on {appointment.date} at {appointment.time_slot} has been confirmed.",
        ))

    doctor = db.query(Doctor).filter(Doctor.id == appointment.doctor_id).first()
    if doctor:
        doc_user = db.query(User).join(Profile).filter(Profile.id == doctor.profile_id).first()
        if doc_user:
            db.add(Notification(
                id=str(uuid.uuid4()),
                user_id=doc_user.id,
                title="Appointment Confirmed",
                message=f"Appointment with {patient_name} on {appointment.date} at {appointment.time_slot} has been confirmed.",
            ))

    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)


@router.put("/{appointment_id}/reschedule")
def reschedule_appointment(
    appointment_id: str,
    data: AppointmentReschedule,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")

    if current_user.role == "patient":
        assert_appointment_patient_action(current_user, appointment, db)
        if appointment.status != "pending":
            raise HTTPException(
                status_code=403,
                detail="Only pending appointments can be rescheduled by the patient. Contact the clinic for confirmed visits.",
            )

    if current_user.role == "doctor":
        doc_id = _get_doctor_id_for_user(current_user, db)
        if not doc_id or appointment.doctor_id != doc_id:
            raise HTTPException(status_code=403, detail="You can only reschedule your own appointments")

    if appointment.status in ("completed", "cancelled"):
        raise HTTPException(status_code=400, detail=f"Cannot reschedule a {appointment.status} appointment")

    validate_booking_date(data.date, current_user.role, db)

    validate_patient_booking(
        db,
        appointment.patient_id,
        appointment.doctor_id,
        data.date,
        data.time_slot,
        exclude_appointment_id=appointment_id,
    )

    ensure_doctor_slot_free(
        db,
        appointment.doctor_id,
        data.date,
        data.time_slot,
        exclude_appointment_id=appointment_id,
    )

    was_arrived = appointment.status == "arrived"
    appointment.date = data.date
    appointment.time_slot = data.time_slot
    if was_arrived:
        appointment.queue_number = None
        appointment.status = "pending"
    if current_user.role == "patient":
        appointment.status = "pending"
        patient_profile = db.query(Profile).filter(Profile.id == appointment.patient_id).first()
        doctor_name = _get_doctor_name(db, appointment.doctor_id)
        if patient_profile:
            db.add(Notification(
                id=str(uuid.uuid4()),
                user_id=patient_profile.user_id,
                title="Appointment Reschedule Requested",
                message=(
                    f"Your reschedule request for {doctor_name} on {data.date} at {data.time_slot} "
                    "is pending receptionist confirmation."
                ),
            ))
        _notify_staff(
            db,
            "Patient Reschedule Request",
            f"A patient requested to move an appointment with {doctor_name} to {data.date} at {data.time_slot}.",
        )
    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)


@router.put("/{appointment_id}/complete")
def complete_appointment(
    appointment_id: str,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")

    assert_appointment_doctor_action(current_user, appointment, db)

    if appointment.status != "arrived":
        raise HTTPException(
            status_code=400,
            detail="Only patients in the waiting queue can be marked completed.",
        )
    if not _appointment_is_paid(db, appointment_id):
        raise HTTPException(
            status_code=400,
            detail="Patient must complete payment before marking the visit completed.",
        )

    record = db.query(MedicalRecord).filter(MedicalRecord.appointment_id == appointment_id).first()
    if not record:
        raise HTTPException(
            status_code=400,
            detail="Save the consultation record before marking the visit completed.",
        )

    appointment.status = "completed"
    was_arrived = appointment.queue_number is not None
    appointment.queue_number = None
    if was_arrived:
        _renumber_doctor_queue(db, appointment.date, appointment.doctor_id, notify_patients=True)

    patient_name = _get_patient_name(db, appointment.patient_id)
    doctor_name = _get_doctor_name(db, appointment.doctor_id)

    patient_profile = db.query(Profile).filter(Profile.id == appointment.patient_id).first()
    if patient_profile:
        db.add(Notification(
            id=str(uuid.uuid4()),
            user_id=patient_profile.user_id,
            title="Appointment Completed",
            message=f"Your appointment with {doctor_name} has been completed. Check your medical records for details.",
        ))

    _notify_staff(
        db,
        "Appointment Completed",
        f"{patient_name}'s appointment with {doctor_name} has been completed.",
    )

    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)


def _apply_arrived_status(
    db: Session,
    appointment: Appointment,
    *,
    actor_user_id: str,
    audit_action: str = "mark_arrived",
    notify_doctor: bool = True,
) -> None:
    """Move a paid appointment into today's waiting queue."""
    if appointment.status == "arrived":
        return

    if appointment.status == "pending":
        appointment.status = "confirmed"

    if appointment.status != "confirmed":
        raise HTTPException(
            status_code=400,
            detail="Only confirmed appointments can be added to the waiting queue",
        )

    if not _appointment_is_paid(db, appointment.id):
        raise HTTPException(
            status_code=400,
            detail="Patient must complete payment before marking as arrived.",
        )

    today = clinic_today()
    if appointment.date != today:
        ensure_doctor_slot_free(db, appointment.doctor_id, today, appointment.time_slot)
        original = appointment.date
        note = f"[Checked in on {today}; originally scheduled {original}]"
        appointment.notes = f"{appointment.notes}\n{note}".strip() if appointment.notes else note
        appointment.date = today

    visit_date = appointment.date
    max_queue = (
        db.query(func.max(Appointment.queue_number))
        .filter(
            Appointment.date == visit_date,
            Appointment.doctor_id == appointment.doctor_id,
            Appointment.queue_number.isnot(None),
        )
        .scalar()
    ) or 0

    appointment.queue_number = max_queue + 1
    appointment.status = "arrived"

    patient_name = _get_patient_name(db, appointment.patient_id)
    log_audit(
        db,
        actor_user_id,
        audit_action,
        "appointment",
        appointment.id,
        f"{patient_name} arrived — queue #{appointment.queue_number} on {appointment.date} {appointment.time_slot}",
    )

    if notify_doctor:
        doctor = db.query(Doctor).filter(Doctor.id == appointment.doctor_id).first()
        if doctor:
            doc_user = db.query(User).join(Profile).filter(Profile.id == doctor.profile_id).first()
            if doc_user:
                db.add(Notification(
                    id=str(uuid.uuid4()),
                    user_id=doc_user.id,
                    title="Patient Arrived",
                    message=(
                        f"{patient_name} has arrived (Queue #{appointment.queue_number}). "
                        f"Appointment at {appointment.time_slot}."
                    ),
                ))

    _notify_patient_queue(db, appointment, appointment.queue_number)


@router.put("/{appointment_id}/arrive")
def mark_arrived(
    appointment_id: str,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")

    _apply_arrived_status(
        db,
        appointment,
        actor_user_id=current_user.id,
        audit_action="mark_arrived",
        notify_doctor=True,
    )

    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)


@router.put("/{appointment_id}/start-consultation")
def start_consultation(
    appointment_id: str,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    """Doctor starts consultation: auto check-in paid patients if not already arrived."""
    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")

    assert_appointment_doctor_action(current_user, appointment, db)

    if appointment.status in ("completed", "cancelled"):
        raise HTTPException(
            status_code=400,
            detail=f"Cannot start consultation for a {appointment.status} appointment.",
        )

    if appointment.status == "arrived":
        if not _appointment_is_paid(db, appointment_id):
            raise HTTPException(
                status_code=400,
                detail="Patient must complete payment before consultation.",
            )
    else:
        _apply_arrived_status(
            db,
            appointment,
            actor_user_id=current_user.id,
            audit_action="start_consultation",
            notify_doctor=False,
        )

    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)


@router.put("/{appointment_id}/leave-queue")
def leave_queue(
    appointment_id: str,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    """Remove patient from waiting queue and return them to confirmed status."""
    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if appointment.status != "arrived":
        raise HTTPException(status_code=400, detail="Only arrived patients can be removed from the queue")

    appointment.status = "confirmed"
    appointment.queue_number = None
    _renumber_doctor_queue(db, appointment.date, appointment.doctor_id, notify_patients=True)

    patient_name = _get_patient_name(db, appointment.patient_id)
    log_audit(
        db,
        current_user.id,
        "leave_queue",
        "appointment",
        appointment_id,
        f"{patient_name} removed from queue — returned to confirmed on {appointment.date} {appointment.time_slot}",
    )

    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)


@router.put("/{appointment_id}/receptionist-reschedule")
def receptionist_reschedule(
    appointment_id: str,
    data: ReceptionistReschedule,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if appointment.status == "completed":
        raise HTTPException(status_code=400, detail="Cannot reschedule a completed appointment")

    was_cancelled = appointment.status == "cancelled"
    was_arrived = appointment.status == "arrived"

    if data.date < date.today():
        raise HTTPException(status_code=400, detail="Cannot reschedule to a past date")

    day_of_week = data.date.weekday()
    schedule = (
        db.query(DoctorSchedule)
        .filter(
            DoctorSchedule.doctor_id == appointment.doctor_id,
            DoctorSchedule.day_of_week == day_of_week,
            DoctorSchedule.is_available == True,
        )
        .first()
    )
    if not schedule:
        raise HTTPException(status_code=400, detail="Doctor is not available on this day")

    from clinic_schedule import is_doctor_on_vacation

    if is_doctor_on_vacation(db, appointment.doctor_id, data.date):
        raise HTTPException(status_code=400, detail="Doctor is on vacation on the selected date")

    settings = db.query(ClinicSettings).first()
    duration = settings.appointment_duration if settings else 30
    available = _generate_slots(schedule.start_time, schedule.end_time, duration)
    if data.time_slot not in available:
        raise HTTPException(status_code=400, detail="Invalid time slot")

    ensure_doctor_slot_free(
        db,
        appointment.doctor_id,
        data.date,
        data.time_slot,
        exclude_appointment_id=appointment_id,
    )

    validate_patient_booking(
        db,
        appointment.patient_id,
        appointment.doctor_id,
        data.date,
        data.time_slot,
        exclude_appointment_id=appointment_id,
    )

    was_arrived = appointment.status == "arrived"
    old_date = appointment.date
    old_doctor_id = appointment.doctor_id

    appointment.date = data.date
    appointment.time_slot = data.time_slot
    appointment.queue_number = None
    if data.confirm or was_cancelled:
        appointment.status = "confirmed"
    elif was_arrived:
        appointment.status = "confirmed"
    else:
        appointment.status = "pending"

    if was_arrived:
        _renumber_doctor_queue(db, old_date, old_doctor_id, notify_patients=True)

    patient_name = _get_patient_name(db, appointment.patient_id)
    doctor_name = _get_doctor_name(db, appointment.doctor_id)

    action = "reactivate_appointment" if was_cancelled else "reschedule_appointment"
    log_audit(
        db,
        current_user.id,
        action,
        "appointment",
        appointment_id,
        (
            f"{'Reactivated' if was_cancelled else 'Rescheduled'} {patient_name} with {doctor_name} "
            f"to {data.date} {data.time_slot} — status {appointment.status}"
        ),
    )

    patient_profile = db.query(Profile).filter(Profile.id == appointment.patient_id).first()
    if patient_profile:
        db.add(Notification(
            id=str(uuid.uuid4()),
            user_id=patient_profile.user_id,
            title="Appointment Rescheduled",
            message=(
                f"Your appointment with {doctor_name} has been moved to "
                f"{data.date} at {data.time_slot}."
            ),
        ))

    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)
