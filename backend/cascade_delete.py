"""Shared cascade deletion helpers for appointments and clinical data."""

from __future__ import annotations

from sqlalchemy import or_
from sqlalchemy.orm import Session

from models import (
    Appointment,
    Payment,
    MedicalRecord,
    Prescription,
    PrescriptionItem,
    AppointmentReview,
    AISuggestion,
)


def delete_appointments_cascade(db: Session, apt_ids: list[str]) -> dict[str, int]:
    """Delete appointments and every row that references them."""
    stats = {
        "prescription_items": 0,
        "prescriptions": 0,
        "medical_records": 0,
        "ai_suggestions": 0,
        "appointment_reviews": 0,
        "payments": 0,
        "appointments": 0,
    }
    if not apt_ids:
        return stats

    record_ids = [
        r[0]
        for r in db.query(MedicalRecord.id).filter(MedicalRecord.appointment_id.in_(apt_ids)).all()
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

    stats["ai_suggestions"] = (
        db.query(AISuggestion)
        .filter(AISuggestion.appointment_id.in_(apt_ids))
        .delete(synchronize_session=False)
    )
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
    db.query(MedicalRecord).filter(MedicalRecord.appointment_id.in_(apt_ids)).delete(
        synchronize_session=False
    )
    stats["appointments"] = (
        db.query(Appointment)
        .filter(Appointment.id.in_(apt_ids))
        .delete(synchronize_session=False)
    )
    db.flush()
    return stats
