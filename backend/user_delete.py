"""Delete a single user account and all data tied to that role."""

from __future__ import annotations

from sqlalchemy import or_
from sqlalchemy.orm import Session

from cascade_delete import delete_appointments_cascade
from models import (
    User,
    Profile,
    Doctor,
    DoctorSchedule,
    DoctorTimeOff,
    Appointment,
    Payment,
    MedicalRecord,
    Prescription,
    PrescriptionItem,
    AppointmentReview,
    AISuggestion,
    SensorData,
    Document,
    ProfileUpdateRequest,
    Notification,
    AIConversation,
    EmailOTP,
)


def _clear_profile_staff_references(db: Session, profile_id: str) -> None:
    db.query(Payment).filter(Payment.receptionist_id == profile_id).update(
        {Payment.receptionist_id: None}, synchronize_session=False
    )
    db.query(Payment).filter(Payment.refunded_by == profile_id).update(
        {Payment.refunded_by: None}, synchronize_session=False
    )
    db.query(AppointmentReview).filter(AppointmentReview.receptionist_id == profile_id).update(
        {AppointmentReview.receptionist_id: None}, synchronize_session=False
    )


def _delete_patient_data(db: Session, profile: Profile, user: User) -> dict[str, int]:
    stats = {
        "prescription_items": 0,
        "prescriptions": 0,
        "medical_records": 0,
        "ai_suggestions": 0,
        "appointment_reviews": 0,
        "payments": 0,
        "appointments": 0,
        "profile_update_requests": 0,
        "sensor_readings": 0,
        "documents": 0,
    }

    apt_ids = [
        a[0]
        for a in db.query(Appointment.id).filter(Appointment.patient_id == profile.id).all()
    ]
    apt_stats = delete_appointments_cascade(db, apt_ids)
    for key, value in apt_stats.items():
        stats[key] = stats.get(key, 0) + value

    record_ids = [
        r[0]
        for r in db.query(MedicalRecord.id).filter(MedicalRecord.patient_id == profile.id).all()
    ]
    if record_ids:
        prescription_ids = [
            p[0]
            for p in db.query(Prescription.id)
            .filter(Prescription.medical_record_id.in_(record_ids))
            .all()
        ]
        if prescription_ids:
            stats["prescription_items"] += (
                db.query(PrescriptionItem)
                .filter(PrescriptionItem.prescription_id.in_(prescription_ids))
                .delete(synchronize_session=False)
            )
            stats["prescriptions"] += (
                db.query(Prescription)
                .filter(Prescription.id.in_(prescription_ids))
                .delete(synchronize_session=False)
            )
        stats["medical_records"] += (
            db.query(MedicalRecord)
            .filter(MedicalRecord.id.in_(record_ids))
            .delete(synchronize_session=False)
        )
        db.flush()

    ai_filters = [AISuggestion.patient_id == profile.id]
    if apt_ids:
        ai_filters.append(AISuggestion.appointment_id.in_(apt_ids))
    stats["ai_suggestions"] += (
        db.query(AISuggestion).filter(or_(*ai_filters)).delete(synchronize_session=False)
    )
    stats["profile_update_requests"] = (
        db.query(ProfileUpdateRequest)
        .filter(ProfileUpdateRequest.patient_id == profile.id)
        .delete(synchronize_session=False)
    )
    stats["sensor_readings"] = (
        db.query(SensorData)
        .filter(SensorData.patient_id == profile.id)
        .delete(synchronize_session=False)
    )
    stats["documents"] = (
        db.query(Document)
        .filter(Document.patient_id == profile.id)
        .delete(synchronize_session=False)
    )
    db.flush()
    return stats


def _delete_doctor_data(db: Session, profile: Profile) -> dict[str, int]:
    stats = {
        "prescription_items": 0,
        "prescriptions": 0,
        "medical_records": 0,
        "ai_suggestions": 0,
        "appointment_reviews": 0,
        "payments": 0,
        "appointments": 0,
        "doctor_schedules": 0,
        "doctor_time_off": 0,
    }

    doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
    if not doctor:
        return stats

    apt_ids = [
        a[0]
        for a in db.query(Appointment.id).filter(Appointment.doctor_id == doctor.id).all()
    ]
    apt_stats = delete_appointments_cascade(db, apt_ids)
    for key, value in apt_stats.items():
        stats[key] = stats.get(key, 0) + value

    record_ids = [
        r[0]
        for r in db.query(MedicalRecord.id).filter(MedicalRecord.doctor_id == doctor.id).all()
    ]
    if record_ids:
        prescription_ids = [
            p[0]
            for p in db.query(Prescription.id)
            .filter(Prescription.medical_record_id.in_(record_ids))
            .all()
        ]
        if prescription_ids:
            stats["prescription_items"] += (
                db.query(PrescriptionItem)
                .filter(PrescriptionItem.prescription_id.in_(prescription_ids))
                .delete(synchronize_session=False)
            )
            stats["prescriptions"] += (
                db.query(Prescription)
                .filter(Prescription.id.in_(prescription_ids))
                .delete(synchronize_session=False)
            )
        stats["medical_records"] += (
            db.query(MedicalRecord)
            .filter(MedicalRecord.id.in_(record_ids))
            .delete(synchronize_session=False)
        )
        db.flush()

    stats["ai_suggestions"] += (
        db.query(AISuggestion)
        .filter(AISuggestion.doctor_id == doctor.id)
        .delete(synchronize_session=False)
    )
    db.query(ProfileUpdateRequest).filter(ProfileUpdateRequest.doctor_id == doctor.id).delete(
        synchronize_session=False
    )
    stats["doctor_schedules"] = (
        db.query(DoctorSchedule)
        .filter(DoctorSchedule.doctor_id == doctor.id)
        .delete(synchronize_session=False)
    )
    stats["doctor_time_off"] = (
        db.query(DoctorTimeOff)
        .filter(DoctorTimeOff.doctor_id == doctor.id)
        .delete(synchronize_session=False)
    )
    db.delete(doctor)
    db.flush()
    return stats


def delete_user_account(db: Session, user: User) -> dict[str, int]:
    """Permanently delete one user and all related rows."""
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    stats: dict[str, int] = {"notifications": 0, "ai_conversations": 0, "email_otps": 0}

    try:
        if user.role == "patient" and profile:
            role_stats = _delete_patient_data(db, profile, user)
            stats.update(role_stats)
        elif user.role == "doctor" and profile:
            role_stats = _delete_doctor_data(db, profile)
            stats.update(role_stats)
        elif profile:
            _clear_profile_staff_references(db, profile.id)

        db.query(Document).filter(Document.uploaded_by == user.id).update(
            {Document.uploaded_by: None}, synchronize_session=False
        )
        stats["notifications"] = (
            db.query(Notification)
            .filter(Notification.user_id == user.id)
            .delete(synchronize_session=False)
        )
        stats["ai_conversations"] = (
            db.query(AIConversation)
            .filter(AIConversation.user_id == user.id)
            .delete(synchronize_session=False)
        )
        if user.email:
            stats["email_otps"] = (
                db.query(EmailOTP)
                .filter(EmailOTP.email == user.email.lower())
                .delete(synchronize_session=False)
            )

        if profile:
            db.delete(profile)
        db.delete(user)
    except Exception:
        db.rollback()
        raise

    return stats
