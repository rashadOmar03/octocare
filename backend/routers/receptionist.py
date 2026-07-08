import uuid
import string
import random
import os
import base64
from datetime import datetime, date, timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status, UploadFile, File, Form, Request
from sqlalchemy.orm import Session
from sqlalchemy import func, or_

from database import get_db
from models import User, Profile, Appointment, Payment, Doctor, ClinicSettings, DoctorSchedule, Notification
from schemas import (
    ReceptionistDashboard, ReceptionistPatientCreate, ReceptionistClinicInfo,
    ReceptionistBookAppointment, ReceptionistPatientSearchResult,
    PaymentCreate, PaymentResponse, InstapayPaymentCreate, RefundPaymentCreate,
    ReceptionistRevenueSummary,
)
from auth import hash_password, require_role
from otp_service import create_and_send_otp
from appointment_rules import (
    auto_cancel_expired_appointments,
    is_slot_available,
    validate_patient_booking,
    validate_booking_date,
    ensure_doctor_slot_free,
    count_paid_no_show_action_required,
    list_paid_no_show_action_required,
    resolve_stale_appointment_states,
    slot_duration_minutes,
    NO_SHOW_STATUSES,
    _visit_has_passed,
)
from routers.appointments import (
    _enrich_appointment,
    _generate_slots,
    _empty_slots_response,
    _get_patient_name,
    _get_doctor_name,
    _notify_staff,
    _renumber_doctor_queue,
)

from audit_service import log_audit
from otp_service import create_and_send_otp
from email_service import send_patient_welcome_email
from profile_utils import profile_personal_info_complete
from clinic_time import clinic_today, clinic_now, upcoming_from_date
from clinic_schedule import resolve_doctor_schedule_for_date, get_doctor_vacation_on_date, working_days_label

router = APIRouter()

UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads")
ALLOWED_PAYMENT_METHODS = ("cash", "instapay")
PAYABLE_STATUSES = ("pending", "confirmed", "arrived")


def _assert_payable_appointment(appointment: Appointment) -> None:
    if appointment.status not in PAYABLE_STATUSES:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot record payment for a {appointment.status} appointment",
        )


def _generate_temp_password(length: int = 8) -> str:
    chars = string.ascii_letters + string.digits
    return "".join(random.choices(chars, k=length))


def _default_fee(db: Session, doctor_id: str | None = None) -> float:
    if doctor_id:
        doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
        if doctor:
            from clinic_schedule import get_doctor_consultation_fee
            return get_doctor_consultation_fee(db, doctor)
    settings = db.query(ClinicSettings).first()
    return float(settings.default_fee if settings else 100.0)


def _enrich_payment(payment: Payment, db: Session) -> dict:
    apt = (
        payment.appointment
        or db.query(Appointment).filter(Appointment.id == payment.appointment_id).first()
    )
    patient_name = None
    doctor_name = None
    appointment_date = None
    time_slot = None
    if apt:
        appointment_date = str(apt.date)
        time_slot = apt.time_slot
        patient = db.query(Profile).filter(Profile.id == apt.patient_id).first()
        if patient:
            patient_name = f"{patient.first_name or ''} {patient.last_name or ''}".strip()
        doctor = db.query(Doctor).filter(Doctor.id == apt.doctor_id).first()
        if doctor:
            doc_profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
            if doc_profile:
                doctor_name = f"Dr. {doc_profile.first_name or ''} {doc_profile.last_name or ''}".strip()

    receptionist_name = None
    if payment.receptionist_id:
        rec = db.query(Profile).filter(Profile.id == payment.receptionist_id).first()
        if rec:
            receptionist_name = f"{rec.first_name or ''} {rec.last_name or ''}".strip()

    refund_staff_name = None
    if payment.refunded_by:
        ref = db.query(Profile).filter(Profile.id == payment.refunded_by).first()
        if ref:
            refund_staff_name = f"{ref.first_name or ''} {ref.last_name or ''}".strip()

    return {
        "id": payment.id,
        "appointment_id": payment.appointment_id,
        "amount": payment.amount,
        "payment_method": payment.payment_method,
        "payment_status": payment.payment_status,
        "proof_url": payment.proof_url,
        "refund_proof_url": payment.refund_proof_url,
        "receptionist_id": payment.receptionist_id,
        "created_at": payment.created_at,
        "refunded_at": payment.refunded_at,
        "refunded_by": payment.refunded_by,
        "refund_reason": payment.refund_reason,
        "refund_staff_name": refund_staff_name,
        "patient_name": patient_name,
        "doctor_name": doctor_name,
        "appointment_date": appointment_date,
        "time_slot": time_slot,
        "receptionist_name": receptionist_name,
        "invoice_ref": f"INV-{payment.id[:8].upper()}",
    }


async def _read_upload_bytes(proof) -> bytes:
    if proof is None:
        return b""
    if hasattr(proof, "read"):
        content = await proof.read()
        return content or b""
    if isinstance(proof, (bytes, bytearray)):
        return bytes(proof)
    return b""


async def _extract_proof_from_form(form) -> object | None:
    for key in ("proof", "file", "screenshot", "image"):
        candidate = form.get(key)
        if candidate is not None and hasattr(candidate, "read"):
            return candidate
    for _key, value in form.multi_items():
        if hasattr(value, "read"):
            return value
    return None


def _reactivate_payment_after_refund(
    payment: Payment,
    amount: float,
    method: str,
    proof_url: str | None,
    rec_profile: Profile | None,
) -> None:
    """Allow collecting payment again on the same appointment after a refund."""
    payment.amount = amount
    payment.payment_method = method
    payment.payment_status = "paid"
    payment.proof_url = proof_url or payment.proof_url
    payment.refunded_at = None
    payment.refunded_by = None
    payment.refund_reason = None
    payment.refund_proof_url = None
    if rec_profile:
        payment.receptionist_id = rec_profile.id


def _save_payment_record(
    db: Session,
    current_user: User,
    appointment_id: str,
    method: str,
    proof_url: str | None,
) -> dict:
    apt = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not apt:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if apt.status == "pending":
        apt.status = "confirmed"
    amount = _default_fee(db, apt.doctor_id)
    rec_profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()

    existing = db.query(Payment).filter(Payment.appointment_id == appointment_id).first()
    if existing:
        if existing.payment_status == "paid":
            raise HTTPException(status_code=400, detail="This appointment is already paid")
        if existing.payment_status == "refunded":
            _reactivate_payment_after_refund(existing, amount, method, proof_url, rec_profile)
            db.commit()
            db.refresh(existing)
            log_audit(
                db,
                current_user.id,
                "record_payment",
                "payment",
                existing.id,
                f"Re-collected {amount} EGP via {method} after refund for appointment {appointment_id}",
            )
            db.commit()
            return _enrich_payment(existing, db)
        existing.amount = amount
        existing.payment_method = method
        existing.payment_status = "paid"
        existing.proof_url = proof_url or existing.proof_url
        if rec_profile:
            existing.receptionist_id = rec_profile.id
        db.commit()
        db.refresh(existing)
        log_audit(
            db,
            current_user.id,
            "record_payment",
            "payment",
            existing.id,
            f"Updated payment to {amount} EGP via {method} for appointment {appointment_id}",
        )
        db.commit()
        return _enrich_payment(existing, db)

    payment = Payment(
        id=str(uuid.uuid4()),
        appointment_id=appointment_id,
        amount=amount,
        payment_method=method,
        payment_status="paid",
        proof_url=proof_url,
        receptionist_id=rec_profile.id if rec_profile else None,
    )
    db.add(payment)
    db.commit()
    db.refresh(payment)
    log_audit(
        db,
        current_user.id,
        "record_payment",
        "payment",
        payment.id,
        f"Recorded {amount} EGP via {method} for appointment {appointment_id}",
    )
    db.commit()
    return _enrich_payment(payment, db)


async def _save_proof_bytes(content: bytes, filename: str | None) -> str:
    ext = os.path.splitext(filename or "proof.jpg")[1] or ".jpg"
    safe_name = f"payment_{uuid.uuid4()}{ext}"
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    file_path = os.path.join(UPLOAD_DIR, safe_name)
    with open(file_path, "wb") as f:
        f.write(content)
    return f"/uploads/{safe_name}"


async def _save_proof(proof: UploadFile) -> str:
    content = await _read_upload_bytes(proof)
    return await _save_proof_bytes(content, proof.filename)


@router.get("/dashboard", response_model=ReceptionistDashboard)
def receptionist_dashboard(
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    auto_cancel_expired_appointments(db)
    resolve_stale_appointment_states(db)
    today = clinic_today()
    today_q = db.query(Appointment).filter(Appointment.date == today)

    today_count = today_q.filter(
        Appointment.status.in_(["pending", "confirmed", "arrived"])
    ).count()
    pending = (
        db.query(Appointment)
        .filter(Appointment.status == "pending", Appointment.date >= today)
        .count()
    )
    confirmed = (
        db.query(Appointment)
        .filter(Appointment.status == "confirmed", Appointment.date >= today)
        .count()
    )
    completed = today_q.filter(Appointment.status == "completed").count()
    arrived = today_q.filter(Appointment.status == "arrived").count()

    today_revenue = (
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .join(Appointment, Appointment.id == Payment.appointment_id)
        .filter(Appointment.date == today, Payment.payment_status == "paid")
        .scalar()
    )

    action_required = count_paid_no_show_action_required(db)

    return ReceptionistDashboard(
        today_appointments=today_count,
        pending_appointments=pending,
        confirmed_appointments=confirmed,
        completed_appointments=completed,
        arrived_appointments=arrived,
        today_revenue=float(today_revenue),
        action_required_appointments=action_required,
    )


@router.get("/action-required-appointments")
def action_required_appointments(
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    auto_cancel_expired_appointments(db)
    resolve_stale_appointment_states(db)
    rows = list_paid_no_show_action_required(db)
    return [_enrich_appointment(a, db) for a in rows]


@router.get("/revenue-summary", response_model=ReceptionistRevenueSummary)
def revenue_summary(
    date_filter: date = Query(None, alias="date"),
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    paid_query = db.query(func.coalesce(func.sum(Payment.amount), 0.0)).filter(
        Payment.payment_status == "paid"
    )
    refunded_query = db.query(func.coalesce(func.sum(Payment.amount), 0.0)).filter(
        Payment.payment_status == "refunded"
    )
    if date_filter:
        paid_query = paid_query.join(Appointment, Appointment.id == Payment.appointment_id).filter(
            Appointment.date == date_filter
        )
        refunded_query = refunded_query.join(Appointment, Appointment.id == Payment.appointment_id).filter(
            Appointment.date == date_filter
        )
    paid_total = float(paid_query.scalar())
    refunded_total = float(refunded_query.scalar())
    return ReceptionistRevenueSummary(
        net_revenue=paid_total - refunded_total,
        paid_total=paid_total,
        refunded_total=refunded_total,
    )


@router.get("/clinic-info", response_model=ReceptionistClinicInfo)
def clinic_info(
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    settings = db.query(ClinicSettings).first()
    return ReceptionistClinicInfo(
        default_fee=float(settings.default_fee if settings else 100.0),
        appointment_duration=settings.appointment_duration if settings else 30,
    )


@router.get("/patients", response_model=list[ReceptionistPatientSearchResult])
def list_patients(
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=100),
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    """List all patients (paginated)."""
    offset = (page - 1) * limit
    rows = (
        db.query(Profile, User)
        .join(User, User.id == Profile.user_id)
        .filter(User.role == "patient", User.is_active == True)
        .order_by(Profile.first_name.asc(), Profile.last_name.asc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return [
        ReceptionistPatientSearchResult(
            profile_id=profile.id,
            name=f"{profile.first_name or ''} {profile.last_name or ''}".strip() or "Patient",
            email=user.email,
            phone=profile.phone or user.phone,
            photo_url=profile.photo_url,
        )
        for profile, user in rows
    ]


@router.get("/patients/search", response_model=list[ReceptionistPatientSearchResult])
def search_patients(
    q: str = Query("", alias="q"),
    limit: int = Query(25, ge=1, le=50),
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    term = q.strip()
    if not term:
        return []
    like = f"%{term}%"
    rows = (
        db.query(Profile, User)
        .join(User, User.id == Profile.user_id)
        .filter(User.role == "patient", User.is_active == True)
        .filter(
            or_(
                Profile.first_name.ilike(like),
                Profile.last_name.ilike(like),
                User.email.ilike(like),
                User.phone.ilike(like),
                Profile.phone.ilike(like),
            )
        )
        .order_by(Profile.first_name.asc(), Profile.last_name.asc())
        .limit(limit)
        .all()
    )
    return [
        ReceptionistPatientSearchResult(
            profile_id=profile.id,
            name=f"{profile.first_name or ''} {profile.last_name or ''}".strip() or "Patient",
            email=user.email,
            phone=profile.phone or user.phone,
            photo_url=profile.photo_url,
        )
        for profile, user in rows
    ]


@router.get("/appointments", response_model=list)
def list_receptionist_appointments(
    date_filter: date = Query(None, alias="date"),
    status_filter: str = Query(None, alias="status"),
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    """List appointments visible to receptionist (upcoming by default)."""
    auto_cancel_expired_appointments(db)
    query = db.query(Appointment)
    if date_filter:
        query = query.filter(Appointment.date == date_filter)
    else:
        query = query.filter(Appointment.date >= upcoming_from_date())
    if status_filter:
        query = query.filter(Appointment.status == status_filter)
    appointments = query.order_by(Appointment.date.asc(), Appointment.time_slot.asc()).all()
    return [_enrich_appointment(apt, db) for apt in appointments]


@router.post("/appointments", status_code=status.HTTP_201_CREATED)
def book_appointment_for_patient(
    data: ReceptionistBookAppointment,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    auto_cancel_expired_appointments(db)

    patient = db.query(Profile).filter(Profile.id == data.patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    doctor = db.query(Doctor).filter(Doctor.id == data.doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")

    validate_booking_date(data.date, "receptionist", db)

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
    validate_patient_booking(db, patient.id, data.doctor_id, data.date, data.time_slot)

    appointment = Appointment(
        id=str(uuid.uuid4()),
        patient_id=patient.id,
        doctor_id=data.doctor_id,
        date=data.date,
        time_slot=data.time_slot,
        notes=data.notes,
        status="confirmed",
    )
    db.add(appointment)

    patient_name = _get_patient_name(db, patient.id)
    doctor_name = _get_doctor_name(db, data.doctor_id)

    log_audit(
        db,
        current_user.id,
        "book_appointment",
        "appointment",
        appointment.id,
        f"Reception booked {patient_name} with {doctor_name} on {data.date} {data.time_slot}",
    )

    _notify_staff(
        db,
        "Appointment Booked by Reception",
        f"{patient_name} was booked with {doctor_name} on {data.date} at {data.time_slot}",
    )

    doc_user = db.query(User).join(Profile).filter(Profile.id == doctor.profile_id).first()
    if doc_user:
        db.add(Notification(
            id=str(uuid.uuid4()),
            user_id=doc_user.id,
            title="New Appointment",
            message=f"Reception booked {patient_name} on {data.date} at {data.time_slot}.",
        ))

    db.commit()
    db.refresh(appointment)
    return _enrich_appointment(appointment, db)


@router.get("/queue", response_model=list)
def get_queue(
    doctor_id: str = Query(None),
    queue_date: date = Query(None, alias="date"),
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    target_date = queue_date or clinic_today()
    query = (
        db.query(Appointment)
        .filter(
            Appointment.status == "arrived",
            Appointment.date == target_date,
        )
    )
    if doctor_id:
        query = query.filter(Appointment.doctor_id == doctor_id)

    appointments = (
        query.order_by(
            Appointment.queue_number.asc().nullslast(),
            Appointment.time_slot.asc(),
        )
        .all()
    )
    return [_enrich_appointment(apt, db) for apt in appointments]


@router.get("/available-slots")
def receptionist_available_slots(
    doctor_id: str = Query(...),
    slot_date: date = Query(..., alias="date"),
    exclude_appointment_id: str | None = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("receptionist", "admin")),
):
    if slot_date < date.today():
        settings = db.query(ClinicSettings).first()
        return _empty_slots_response(db, settings, reason="too_soon")

    settings = db.query(ClinicSettings).first()
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
        s
        for s in all_slots
        if is_slot_available(db, doctor_id, slot_date, s, exclude_appointment_id=exclude_appointment_id)
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


@router.get("/payable-appointments", response_model=list)
def list_payable_appointments(
    days_ahead: int = Query(30, ge=1, le=90),
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    """Appointments that can still be marked as paid (no paid record yet)."""
    auto_cancel_expired_appointments(db)
    today = clinic_today()
    max_date = today + timedelta(days=days_ahead)
    appointments = (
        db.query(Appointment)
        .outerjoin(Payment, Appointment.id == Payment.appointment_id)
        .filter(
            Appointment.date >= today,
            Appointment.date <= max_date,
            Appointment.status.in_(PAYABLE_STATUSES),
            or_(Payment.id.is_(None), Payment.payment_status != "paid"),
        )
        .order_by(Appointment.date.asc(), Appointment.time_slot.asc())
        .all()
    )
    return [_enrich_appointment(apt, db) for apt in appointments]


@router.post("/patients", status_code=status.HTTP_201_CREATED)
def register_patient(
    data: ReceptionistPatientCreate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    email = data.email.lower().strip()
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    if data.phone:
        phone_exists = db.query(User).filter(User.phone == data.phone).first()
        if phone_exists:
            raise HTTPException(status_code=400, detail="Phone number already registered")

    temp_password = _generate_temp_password()

    user_id = str(uuid.uuid4())
    user = User(
        id=user_id,
        email=email,
        phone=data.phone,
        password_hash=hash_password(temp_password),
        role="patient",
        must_change_password=True,
        email_verified=False,
    )
    db.add(user)

    profile = Profile(
        id=str(uuid.uuid4()),
        user_id=user_id,
        first_name=data.first_name,
        middle_name=data.middle_name or None,
        last_name=data.last_name,
        dob=data.dob,
        gender=data.gender,
        phone=data.phone,
        address=data.address,
        emergency_contact_name=data.emergency_contact_name,
        emergency_contact_phone=data.emergency_contact_phone,
        blood_type=data.blood_type,
        allergies=data.allergies or None,
        chronic_diseases=data.chronic_diseases or None,
        is_complete=False,
    )
    profile.is_complete = profile_personal_info_complete(profile)
    db.add(profile)
    db.commit()

    welcome_sent = False
    try:
        send_patient_welcome_email(db, email, temp_password, data.first_name)
        welcome_sent = True
    except Exception:
        welcome_sent = False

    otp_sent = create_and_send_otp(db, email, "signup", background_tasks)

    db.add(Notification(
        id=str(uuid.uuid4()),
        user_id=user_id,
        title="Account created",
        message=(
            f"Welcome {data.first_name}! A 6-digit verification code was sent to {email}. "
            f"Temporary password: {temp_password}. "
            "Sign in with your email and temporary password, then enter the code to verify your email before accessing your account."
        ),
    ))
    _notify_staff(
        db,
        "Patient registered",
        f"Patient {data.first_name} {data.last_name} ({email}) was registered.",
        exclude_user_id=current_user.id,
    )

    log_audit(
        db,
        current_user.id,
        "register_patient",
        "user",
        user_id,
        f"Registered patient {data.first_name} {data.last_name} ({email})",
    )
    db.commit()

    return {
        "message": (
            "Patient registered. A verification code was sent to their email. "
            "They must verify before signing in."
            if otp_sent
            else "Patient registered but verification email could not be sent. Use Resend code from login."
        ),
        "user_id": user_id,
        "profile_id": profile.id,
        "patient_name": f"{profile.first_name or ''} {profile.last_name or ''}".strip(),
        "email": email,
        "temp_password": temp_password,
        "temporary_password": temp_password,
        "otp_sent": otp_sent,
        "welcome_email_sent": welcome_sent,
        "login_blocked_until_verified": True,
    }


@router.get("/payments", response_model=list[PaymentResponse])
def list_payments(
    date_filter: date = Query(None, alias="date"),
    payment_status: str = Query(None, alias="status"),
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    query = db.query(Payment)

    if date_filter:
        query = (
            query.join(Appointment, Appointment.id == Payment.appointment_id)
            .filter(Appointment.date == date_filter)
        )

    if payment_status:
        query = query.filter(Payment.payment_status == payment_status)

    payments = query.order_by(Payment.created_at.desc()).all()
    return [_enrich_payment(p, db) for p in payments]


@router.get("/doctors", response_model=list)
def list_doctors(
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    """Doctors list for receptionist screens (queue filter, etc.)."""
    from routers.appointments import get_doctors_public
    return get_doctors_public(db=db)


@router.post("/payments", response_model=PaymentResponse, status_code=status.HTTP_201_CREATED)
async def record_payment(
    request: Request,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    content_type = request.headers.get("content-type", "")

    appointment_id: str | None = None
    payment_method: str | None = None
    proof: UploadFile | None = None

    if "multipart/form-data" in content_type:
        form = await request.form()
        appointment_id = str(form.get("appointment_id") or form.get("appointment") or "")
        payment_method = str(form.get("payment_method") or form.get("method") or "")
        proof = await _extract_proof_from_form(form)
    elif "application/json" in content_type:
        body = await request.json()
        appointment_id = str(body.get("appointment_id") or body.get("appointment") or "")
        payment_method = str(body.get("payment_method") or body.get("method") or "cash")
    else:
        raise HTTPException(status_code=415, detail="Use multipart/form-data or application/json")

    if not appointment_id:
        raise HTTPException(status_code=400, detail="appointment_id is required")

    method = payment_method.strip().lower()
    if method not in ALLOWED_PAYMENT_METHODS:
        raise HTTPException(
            status_code=400,
            detail="Payment method must be cash or instapay",
        )

    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    _assert_payable_appointment(appointment)

    proof_url = None
    if method == "instapay":
        proof_bytes = await _read_upload_bytes(proof)
        if not proof_bytes:
            raise HTTPException(
                status_code=400,
                detail="InstaPay payment requires a screenshot before saving",
            )
        filename = getattr(proof, "filename", None) if proof else None
        proof_url = await _save_proof_bytes(proof_bytes, filename)

    return _save_payment_record(db, current_user, appointment_id, method, proof_url)


@router.post("/payments/instapay", response_model=PaymentResponse, status_code=status.HTTP_201_CREATED)
async def record_instapay_payment(
    data: InstapayPaymentCreate,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    """JSON + base64 screenshot — reliable on Flutter web."""
    appointment_id = data.appointment_id.strip()
    if not appointment_id:
        raise HTTPException(status_code=400, detail="appointment_id is required")

    appointment = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    _assert_payable_appointment(appointment)

    raw = data.proof_base64.strip()
    if "," in raw and raw.startswith("data:"):
        raw = raw.split(",", 1)[1]
    try:
        proof_bytes = base64.b64decode(raw, validate=False)
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid screenshot image data") from exc

    if not proof_bytes:
        raise HTTPException(
            status_code=400,
            detail="InstaPay payment requires a screenshot before saving",
        )

    proof_url = await _save_proof_bytes(proof_bytes, data.proof_filename)
    return _save_payment_record(db, current_user, appointment_id, "instapay", proof_url)


@router.post("/payments/json", response_model=PaymentResponse, status_code=status.HTTP_201_CREATED)
def record_payment_json(
    data: PaymentCreate,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    """Legacy JSON endpoint — amount is always clinic default fee."""
    method = (data.actual_payment_method or "").strip().lower()
    if method not in ALLOWED_PAYMENT_METHODS:
        raise HTTPException(status_code=400, detail="Payment method must be cash or instapay")
    if method == "instapay":
        raise HTTPException(
            status_code=400,
            detail="InstaPay payments must include a screenshot via multipart upload",
        )

    apt_id = data.actual_appointment_id
    appointment = db.query(Appointment).filter(Appointment.id == apt_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    _assert_payable_appointment(appointment)

    return _save_payment_record(db, current_user, apt_id, method, None)


@router.post("/payments/{payment_id}/refund", response_model=PaymentResponse)
async def refund_payment(
    payment_id: str,
    data: RefundPaymentCreate,
    current_user: User = Depends(require_role("receptionist", "admin")),
    db: Session = Depends(get_db),
):
    payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    if payment.payment_status != "paid":
        raise HTTPException(status_code=400, detail="Only paid payments can be refunded")

    refund_proof_url = None
    if data.proof_base64:
        raw = data.proof_base64.strip()
        if "," in raw and raw.startswith("data:"):
            raw = raw.split(",", 1)[1]
        try:
            proof_bytes = base64.b64decode(raw, validate=False)
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Invalid refund proof image") from exc
        if proof_bytes:
            refund_proof_url = await _save_proof_bytes(proof_bytes, data.proof_filename)

    rec_profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    payment.payment_status = "refunded"
    payment.refunded_at = datetime.utcnow()
    payment.refunded_by = rec_profile.id if rec_profile else None
    payment.refund_reason = data.reason.strip() or "Patient refund"
    payment.refund_proof_url = refund_proof_url

    apt = db.query(Appointment).filter(Appointment.id == payment.appointment_id).first()
    if apt and apt.notes:
        apt.notes = f"{apt.notes}\n[REFUNDED — collect payment again before visit]"
    elif apt:
        apt.notes = "[REFUNDED — collect payment again before visit]"
    if apt:
        duration = slot_duration_minutes(db)
        now = clinic_now().replace(tzinfo=None)
        visit_passed = _visit_has_passed(apt, duration, now)
        if visit_passed and apt.status in NO_SHOW_STATUSES:
            apt.status = "cancelled"
            apt.queue_number = None
            log_audit(
                db,
                current_user.id,
                "cancel_after_refund_no_show",
                "appointment",
                apt.id,
                f"Cancelled missed paid visit on {apt.date} {apt.time_slot} after refund",
            )
        elif apt.status == "arrived":
            apt.status = "confirmed"
            apt.queue_number = None
            _renumber_doctor_queue(db, apt.date, apt.doctor_id, notify_patients=True)
            doctor = db.query(Doctor).filter(Doctor.id == apt.doctor_id).first()
            if doctor:
                doc_profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
                if doc_profile:
                    doc_user = db.query(User).filter(User.id == doc_profile.user_id).first()
                    if doc_user:
                        p = db.query(Profile).filter(Profile.id == apt.patient_id).first()
                        patient_name = f"{p.first_name or ''} {p.last_name or ''}".strip() if p else "Patient"
                        db.add(Notification(
                            id=str(uuid.uuid4()),
                            user_id=doc_user.id,
                            title="Patient Removed from Queue (Refund)",
                            message=f"{patient_name} was removed from the queue after payment refund. Re-collect payment before arrival.",
                        ))
    patient_name = "Patient"
    if apt:
        patient = db.query(Profile).filter(Profile.id == apt.patient_id).first()
        if patient:
            patient_name = f"{patient.first_name or ''} {patient.last_name or ''}".strip()

    log_audit(
        db,
        current_user.id,
        "refund_payment",
        "payment",
        payment.id,
        f"Refunded {payment.amount} EGP to {patient_name} — {payment.refund_reason}",
    )
    db.commit()
    db.refresh(payment)
    return _enrich_payment(payment, db)
