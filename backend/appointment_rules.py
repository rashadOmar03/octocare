"""Patient booking rules and auto-cancel for missed appointments."""
from datetime import datetime, date, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from models import Appointment, ClinicSettings, Payment, AuditLog
from audit_service import log_audit
from clinic_time import clinic_now

ACTIVE_STATUSES = ("pending", "confirmed", "arrived")
NO_SHOW_STATUSES = ("confirmed", "arrived")
DOCTOR_BUSY_STATUSES = ("pending", "confirmed", "arrived")


def _slot_minutes(time_slot: str) -> int:
    parts = time_slot.split(":")
    return int(parts[0]) * 60 + int(parts[1])


def _appointment_start(apt_date: date, time_slot: str) -> datetime:
    parts = time_slot.split(":")
    return datetime.combine(apt_date, datetime.min.time().replace(hour=int(parts[0]), minute=int(parts[1])))


def _get_duration(db: Session) -> int:
    settings = db.query(ClinicSettings).first()
    return settings.appointment_duration if settings else 30


def _slots_overlap(slot_a: str, slot_b: str, duration_minutes: int) -> bool:
    start_a = _slot_minutes(slot_a)
    start_b = _slot_minutes(slot_b)
    return start_a < start_b + duration_minutes and start_b < start_a + duration_minutes


def validate_booking_date(apt_date: date, user_role: str = "patient", db: Session | None = None) -> None:
    if apt_date < date.today():
        raise HTTPException(status_code=400, detail="Cannot book an appointment in the past.")

    if user_role == "patient":
        earliest = date.today() + timedelta(days=1)
        if apt_date < earliest:
            raise HTTPException(
                status_code=400,
                detail=(
                    "Appointments must be booked at least one day in advance. "
                    "Please select tomorrow or a later date."
                ),
            )
        if db is not None:
            from clinic_schedule import is_clinic_open, working_days_label
            from models import ClinicSettings

            settings = db.query(ClinicSettings).first()
            if not is_clinic_open(apt_date, settings):
                label = working_days_label(settings.working_days if settings else None)
                raise HTTPException(
                    status_code=400,
                    detail=f"The clinic is closed on this day. Working days: {label}.",
                )


def slot_duration_minutes(db: Session) -> int:
    return _get_duration(db)


def ensure_doctor_slot_free(
    db: Session,
    doctor_id: str,
    apt_date: date,
    time_slot: str,
    exclude_appointment_id: str | None = None,
) -> None:
    duration = _get_duration(db)
    query = db.query(Appointment).filter(
        Appointment.doctor_id == doctor_id,
        Appointment.date == apt_date,
        Appointment.status.in_(DOCTOR_BUSY_STATUSES),
    )
    if exclude_appointment_id:
        query = query.filter(Appointment.id != exclude_appointment_id)

    for apt in query.all():
        if _slots_overlap(apt.time_slot, time_slot, duration):
            raise HTTPException(
                status_code=409,
                detail=(
                    f"This doctor already has a patient for this {duration}-minute appointment slot. "
                    "Please choose another time."
                ),
            )


def is_slot_available(
    db: Session,
    doctor_id: str,
    apt_date: date,
    candidate_slot: str,
) -> bool:
    duration = _get_duration(db)
    appointments = (
        db.query(Appointment)
        .filter(
            Appointment.doctor_id == doctor_id,
            Appointment.date == apt_date,
            Appointment.status.in_(DOCTOR_BUSY_STATUSES),
        )
        .all()
    )
    for apt in appointments:
        if _slots_overlap(apt.time_slot, candidate_slot, duration):
            return False
    return True


def _appointment_is_paid(db: Session, appointment_id: str) -> bool:
    payment = (
        db.query(Payment)
        .filter(Payment.appointment_id == appointment_id, Payment.payment_status == "paid")
        .first()
    )
    return payment is not None


def require_paid_arrived_appointment(
    db: Session,
    appointment_id: str,
    *,
    doctor_id: str | None = None,
) -> Appointment:
    """Consultation / visit actions require the patient to be paid and in today's queue."""
    apt = db.query(Appointment).filter(Appointment.id == appointment_id).first()
    if not apt:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if apt.status != "arrived":
        raise HTTPException(
            status_code=400,
            detail="Patient must be marked as arrived before consultation or vitals.",
        )
    if not _appointment_is_paid(db, appointment_id):
        raise HTTPException(
            status_code=400,
            detail="Patient must complete payment before consultation or vitals.",
        )
    if doctor_id and apt.doctor_id != doctor_id:
        raise HTTPException(status_code=403, detail="This appointment belongs to another doctor.")
    return apt


def require_active_paid_visit_for_patient(
    db: Session,
    patient_id: str,
    *,
    doctor_id: str | None = None,
) -> Appointment:
    """Vitals upload: patient must be in the waiting queue and paid."""
    query = db.query(Appointment).filter(
        Appointment.patient_id == patient_id,
        Appointment.status == "arrived",
    )
    if doctor_id:
        query = query.filter(Appointment.doctor_id == doctor_id)
    apt = query.order_by(Appointment.queue_number.asc()).first()
    if not apt:
        raise HTTPException(
            status_code=400,
            detail="Patient must be marked as arrived and paid before recording vitals.",
        )
    if not _appointment_is_paid(db, apt.id):
        raise HTTPException(
            status_code=400,
            detail="Patient must complete payment before recording vitals.",
        )
    return apt


def _paid_no_show_alert_sent(db: Session, appointment_id: str) -> bool:
    return (
        db.query(AuditLog)
        .filter(
            AuditLog.entity_type == "appointment",
            AuditLog.entity_id == appointment_id,
            AuditLog.action == "paid_no_show_alert",
        )
        .first()
        is not None
    )


def count_paid_no_show_action_required(db: Session) -> int:
    """Paid confirmed/arrived visits past appointment date — receptionist must refund or reschedule."""
    today = clinic_now().date()
    paid_ids = {
        row[0]
        for row in db.query(Payment.appointment_id)
        .filter(Payment.payment_status == "paid")
        .all()
    }
    if not paid_ids:
        return 0
    return (
        db.query(Appointment)
        .filter(
            Appointment.id.in_(paid_ids),
            Appointment.status.in_(NO_SHOW_STATUSES),
            Appointment.date < today,
        )
        .count()
    )


def list_paid_no_show_action_required(db: Session, limit: int = 50) -> list[Appointment]:
    today = clinic_now().date()
    paid_ids = {
        row[0]
        for row in db.query(Payment.appointment_id)
        .filter(Payment.payment_status == "paid")
        .all()
    }
    if not paid_ids:
        return []
    return (
        db.query(Appointment)
        .filter(
            Appointment.id.in_(paid_ids),
            Appointment.status.in_(NO_SHOW_STATUSES),
            Appointment.date < today,
        )
        .order_by(Appointment.date.desc(), Appointment.time_slot.desc())
        .limit(limit)
        .all()
    )


def auto_cancel_expired_appointments(db: Session) -> int:
    """
    - Pending: cancel after time slot ends (unconfirmed booking expired).
    - Confirmed/arrived unpaid: cancel if appointment day passed (no-show).
    - Confirmed/arrived paid: do NOT auto-cancel — alert receptionist to refund or reschedule.
    Same-day confirmed patients are kept until the day ends.
    """
    duration = _get_duration(db)
    now = clinic_now().replace(tzinfo=None)
    today = now.date()
    changed = 0

    pending = db.query(Appointment).filter(Appointment.status == "pending").all()
    for apt in pending:
        end = _appointment_start(apt.date, apt.time_slot) + timedelta(minutes=duration)
        if end <= now:
            apt.status = "cancelled"
            apt.queue_number = None
            log_audit(
                db,
                None,
                "auto_cancel_pending",
                "appointment",
                apt.id,
                f"Unconfirmed booking expired for {apt.date} {apt.time_slot}",
            )
            from models import Profile, Notification
            import uuid as _uuid
            profile = db.query(Profile).filter(Profile.id == apt.patient_id).first()
            if profile:
                db.add(Notification(
                    id=str(_uuid.uuid4()),
                    user_id=profile.user_id,
                    title="Booking Expired",
                    message=(
                        f"Your unconfirmed appointment on {apt.date} at {apt.time_slot} expired. "
                        "Please book again or contact the clinic."
                    ),
                ))
            changed += 1

    no_shows = (
        db.query(Appointment)
        .filter(
            Appointment.status.in_(NO_SHOW_STATUSES),
            Appointment.date < today,
        )
        .all()
    )
    for apt in no_shows:
        if _appointment_is_paid(db, apt.id):
            if not _paid_no_show_alert_sent(db, apt.id):
                from routers.appointments import _get_patient_name, _notify_staff
                patient_name = _get_patient_name(db, apt.patient_id)
                log_audit(
                    db,
                    None,
                    "paid_no_show_alert",
                    "appointment",
                    apt.id,
                    f"Paid no-show on {apt.date} {apt.time_slot} — refund or reschedule required",
                )
                _notify_staff(
                    db,
                    "Paid visit needs action",
                    (
                        f"{patient_name} missed their paid appointment on {apt.date} at {apt.time_slot}. "
                        "Refund the payment or reschedule — paid appointments cannot be auto-cancelled."
                    ),
                )
                changed += 1
            continue

        apt.status = "cancelled"
        apt.queue_number = None
        log_audit(
            db,
            None,
            "auto_cancel_no_show",
            "appointment",
            apt.id,
            f"Patient did not complete visit on {apt.date}",
        )
        changed += 1

    if changed:
        db.commit()
    return changed


def repair_wrongly_cancelled_appointments(db: Session) -> int:
    """Restore future paid appointments that were cancelled within the last 5 minutes
    (likely a system error) and have no refund."""
    today = date.today()
    cutoff = datetime.utcnow() - timedelta(minutes=5)
    changed = 0
    appointments = (
        db.query(Appointment)
        .filter(Appointment.status == "cancelled", Appointment.date >= today)
        .all()
    )
    for apt in appointments:
        if not _appointment_is_paid(db, apt.id):
            continue
        payment = db.query(Payment).filter(
            Payment.appointment_id == apt.id
        ).first()
        if payment and payment.payment_status == "refunded":
            continue
        if not hasattr(apt, 'created_at') or apt.created_at is None or apt.created_at >= cutoff:
            apt.status = "confirmed"
            apt.queue_number = None
            changed += 1

    if changed:
        db.commit()
    return changed


def validate_patient_booking(
    db: Session,
    patient_id: str,
    doctor_id: str,
    apt_date: date,
    time_slot: str,
    exclude_appointment_id: str | None = None,
) -> None:
    query = db.query(Appointment).filter(
        Appointment.patient_id == patient_id,
        Appointment.status.in_(ACTIVE_STATUSES),
    )
    if exclude_appointment_id:
        query = query.filter(Appointment.id != exclude_appointment_id)

    existing = query.all()
    if not existing:
        return

    new_hour = int(time_slot.split(":")[0])

    for apt in existing:
        if apt.doctor_id == doctor_id:
            raise HTTPException(
                status_code=409,
                detail=(
                    "You already have an active appointment with this doctor. "
                    "Attend or cancel it before booking again."
                ),
            )

        if apt.date == apt_date:
            existing_hour = int(apt.time_slot.split(":")[0])
            if existing_hour == new_hour:
                raise HTTPException(
                    status_code=409,
                    detail="You cannot book more than one appointment in the same hour.",
                )
            raise HTTPException(
                status_code=409,
                detail=(
                    "You can only book one appointment per day. "
                    "Cancel or complete your existing appointment first."
                ),
            )
