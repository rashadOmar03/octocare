"""Doctor vacation / time-off notifications and affected-appointment helpers."""

from __future__ import annotations

from datetime import date

from sqlalchemy.orm import Session

from models import Appointment, Doctor, Profile
from notification_helpers import notify_doctor, notify_role_users, notify_user

_ACTIVE_APPOINTMENT_STATUSES = ("pending", "confirmed", "arrived")


def doctor_display_name(db: Session, doctor: Doctor) -> str:
    profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
    if profile:
        name = f"Dr. {profile.first_name or ''} {profile.last_name or ''}".strip()
        if name != "Dr.":
            return name
    return "Doctor"


def appointments_affected_by_vacation(
    db: Session,
    doctor_id: str,
    start_date: date,
    end_date: date,
) -> list[Appointment]:
    return (
        db.query(Appointment)
        .filter(
            Appointment.doctor_id == doctor_id,
            Appointment.date >= start_date,
            Appointment.date <= end_date,
            Appointment.status.in_(_ACTIVE_APPOINTMENT_STATUSES),
        )
        .order_by(Appointment.date.asc(), Appointment.time_slot.asc())
        .all()
    )


def notify_vacation_scheduled(
    db: Session,
    doctor_id: str,
    start_date: date,
    end_date: date,
    reason: str | None = None,
    *,
    scheduled_by: str = "admin",
    exclude_user_id: str | None = None,
) -> int:
    """
    Notify doctor, receptionists, admins (when doctor self-schedules), and affected patients.
    Returns count of patient notifications sent.
    """
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        return 0

    doc_name = doctor_display_name(db, doctor)
    reason_text = (reason or "vacation").strip() or "vacation"
    period = f"{start_date} to {end_date}"

    if scheduled_by == "admin":
        notify_doctor(
            db,
            doctor_id,
            "Time off scheduled",
            f"Admin scheduled time off ({period}): {reason_text}.",
        )
    else:
        notify_doctor(
            db,
            doctor_id,
            "Time off recorded",
            f"Your time off ({period}) was saved: {reason_text}.",
        )
        notify_role_users(
            db,
            "admin",
            "Doctor time off",
            f"{doc_name} scheduled time off ({period}): {reason_text}.",
            exclude_user_id=exclude_user_id,
        )

    notify_role_users(
        db,
        "receptionist",
        "Doctor unavailable",
        (
            f"{doc_name} is unavailable {period} ({reason_text}). "
            "Do not book appointments on these dates."
        ),
        exclude_user_id=exclude_user_id,
    )

    patient_count = 0
    for apt in appointments_affected_by_vacation(db, doctor_id, start_date, end_date):
        patient = db.query(Profile).filter(Profile.id == apt.patient_id).first()
        if not patient:
            continue
        notify_user(
            db,
            patient.user_id,
            "Doctor unavailable",
            (
                f"{doc_name} is not available on {apt.date}. "
                f"Please reschedule your appointment ({apt.time_slot})."
            ),
        )
        patient_count += 1

    return patient_count


def notify_vacation_removed(
    db: Session,
    doctor_id: str,
    *,
    start_date: date | None = None,
    end_date: date | None = None,
    removed_by: str = "admin",
    exclude_user_id: str | None = None,
) -> None:
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        return

    doc_name = doctor_display_name(db, doctor)
    if start_date and end_date:
        period = f"{start_date} to {end_date}"
        detail = f"Time off removed for {doc_name} ({period})."
    else:
        detail = f"Time off removed for {doc_name}."

    if removed_by == "admin":
        notify_doctor(db, doctor_id, "Time off removed", "Admin removed a scheduled time-off period.")
    else:
        notify_doctor(db, doctor_id, "Time off removed", "Your scheduled time-off period was removed.")

    notify_role_users(
        db,
        "receptionist",
        "Doctor schedule updated",
        detail + " Appointments may be booked again on those dates.",
        exclude_user_id=exclude_user_id,
    )
    if removed_by == "doctor":
        notify_role_users(
            db,
            "admin",
            "Doctor schedule updated",
            detail,
            exclude_user_id=exclude_user_id,
        )
