"""
Remove all patient accounts and every record tied to them.
Staff (admin, doctor, receptionist), specialties, and clinic settings are kept.
"""

from __future__ import annotations

from sqlalchemy import or_
from sqlalchemy.orm import Session

from models import (
    User,
    Profile,
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


def purge_all_patients(db: Session) -> dict[str, int]:
    """Delete every patient user and all related clinical/booking data."""
    patient_profiles = (
        db.query(Profile)
        .join(User, User.id == Profile.user_id)
        .filter(User.role == "patient")
        .all()
    )
    if not patient_profiles:
        return {"patients_deleted": 0}

    patient_profile_ids = [p.id for p in patient_profiles]
    patient_user_ids = [p.user_id for p in patient_profiles]
    patient_emails = [
        u.email.lower()
        for u in db.query(User).filter(User.id.in_(patient_user_ids)).all()
        if u.email
    ]

    apt_ids = [
        a[0]
        for a in db.query(Appointment.id)
        .filter(Appointment.patient_id.in_(patient_profile_ids))
        .all()
    ]

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
        "notifications": 0,
        "ai_conversations": 0,
        "email_otps": 0,
        "patients_deleted": len(patient_profiles),
    }

    try:
        record_ids = [
            r[0]
            for r in db.query(MedicalRecord.id)
            .filter(MedicalRecord.patient_id.in_(patient_profile_ids))
            .all()
        ]
        if record_ids:
            prescription_ids = [
                p[0]
                for p in db.query(Prescription.id)
                .filter(Prescription.medical_record_id.in_(record_ids))
                .all()
            ]
            if prescription_ids:
                stats["prescription_items"] = (
                    db.query(PrescriptionItem)
                    .filter(PrescriptionItem.prescription_id.in_(prescription_ids))
                    .delete(synchronize_session=False)
                )
                stats["prescriptions"] = (
                    db.query(Prescription)
                    .filter(Prescription.id.in_(prescription_ids))
                    .delete(synchronize_session=False)
                )
            stats["medical_records"] = (
                db.query(MedicalRecord)
                .filter(MedicalRecord.id.in_(record_ids))
                .delete(synchronize_session=False)
            )
            db.flush()

        ai_filters = [AISuggestion.patient_id.in_(patient_profile_ids)]
        if apt_ids:
            ai_filters.append(AISuggestion.appointment_id.in_(apt_ids))
        stats["ai_suggestions"] = (
            db.query(AISuggestion).filter(or_(*ai_filters)).delete(synchronize_session=False)
        )
        db.flush()

        if apt_ids:
            stats["appointment_reviews"] = (
                db.query(AppointmentReview)
                .filter(AppointmentReview.appointment_id.in_(apt_ids))
                .delete(synchronize_session=False)
            )
            stats["payments"] = (
                db.query(Payment)
                .filter(Payment.appointment_id.in_(apt_ids))
                .delete(synchronize_session=False)
            )
            # Safety: remove any records still pointing at these appointments.
            db.query(MedicalRecord).filter(MedicalRecord.appointment_id.in_(apt_ids)).delete(
                synchronize_session=False
            )
            stats["appointments"] = (
                db.query(Appointment)
                .filter(Appointment.id.in_(apt_ids))
                .delete(synchronize_session=False)
            )
            db.flush()

        stats["profile_update_requests"] = (
            db.query(ProfileUpdateRequest)
            .filter(ProfileUpdateRequest.patient_id.in_(patient_profile_ids))
            .delete(synchronize_session=False)
        )
        stats["sensor_readings"] = (
            db.query(SensorData)
            .filter(SensorData.patient_id.in_(patient_profile_ids))
            .delete(synchronize_session=False)
        )
        stats["documents"] = (
            db.query(Document)
            .filter(Document.patient_id.in_(patient_profile_ids))
            .delete(synchronize_session=False)
        )

        if patient_user_ids:
            stats["notifications"] = (
                db.query(Notification)
                .filter(Notification.user_id.in_(patient_user_ids))
                .delete(synchronize_session=False)
            )
            stats["ai_conversations"] = (
                db.query(AIConversation)
                .filter(AIConversation.user_id.in_(patient_user_ids))
                .delete(synchronize_session=False)
            )

        if patient_emails:
            stats["email_otps"] = (
                db.query(EmailOTP)
                .filter(EmailOTP.email.in_(patient_emails))
                .delete(synchronize_session=False)
            )

        for profile in patient_profiles:
            db.delete(profile)
        for user in db.query(User).filter(User.id.in_(patient_user_ids)).all():
            db.delete(user)

        db.commit()
    except Exception:
        db.rollback()
        raise

    return stats
