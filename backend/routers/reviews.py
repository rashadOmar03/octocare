import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func

from database import get_db
from models import (
    User, Profile, Doctor, Appointment, Payment, AppointmentReview,
)
from schemas import ReviewCreate, ReviewResponse, DoctorRatingSummary
from auth import get_current_user, require_role

router = APIRouter()


def _round_rating(value: float) -> float:
    return round(value * 10) / 10


def doctor_rating_stats(db: Session, doctor_id: str) -> dict:
    row = (
        db.query(
            func.count(AppointmentReview.id),
            func.avg(AppointmentReview.doctor_rating),
        )
        .filter(AppointmentReview.doctor_id == doctor_id)
        .first()
    )
    count = int(row[0] or 0)
    avg_raw = row[1]
    return {
        "average_rating": _round_rating(float(avg_raw)) if avg_raw is not None and count > 0 else None,
        "review_count": count,
    }


def receptionist_rating_stats(db: Session, receptionist_id: str) -> dict:
    row = (
        db.query(
            func.count(AppointmentReview.id),
            func.avg(AppointmentReview.receptionist_rating),
        )
        .filter(
            AppointmentReview.receptionist_id == receptionist_id,
            AppointmentReview.receptionist_rating.isnot(None),
        )
        .first()
    )
    count = int(row[0] or 0)
    avg_raw = row[1]
    return {
        "average_rating": _round_rating(float(avg_raw)) if avg_raw is not None and count > 0 else None,
        "review_count": count,
    }


def _enrich_review(review: AppointmentReview, db: Session) -> dict:
    patient_name = None
    patient = db.query(Profile).filter(Profile.id == review.patient_id).first()
    if patient:
        patient_name = f"{patient.first_name or ''} {patient.last_name or ''}".strip() or None
    return {
        "id": review.id,
        "appointment_id": review.appointment_id,
        "patient_id": review.patient_id,
        "doctor_id": review.doctor_id,
        "receptionist_id": review.receptionist_id,
        "doctor_rating": review.doctor_rating,
        "receptionist_rating": review.receptionist_rating,
        "doctor_comment": review.doctor_comment,
        "receptionist_comment": review.receptionist_comment,
        "patient_name": patient_name,
        "created_at": review.created_at,
    }


def _validate_rating(value: int, label: str) -> None:
    if value < 1 or value > 5:
        raise HTTPException(status_code=400, detail=f"{label} must be between 1 and 5")


@router.get("/pending", response_model=list)
def pending_reviews(
    current_user: User = Depends(require_role("patient")),
    db: Session = Depends(get_db),
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        return []

    reviewed_ids = {
        r.appointment_id
        for r in db.query(AppointmentReview.appointment_id)
        .filter(AppointmentReview.patient_id == profile.id)
        .all()
    }

    appointments = (
        db.query(Appointment)
        .filter(
            Appointment.patient_id == profile.id,
            Appointment.status == "completed",
        )
        .order_by(Appointment.date.desc(), Appointment.time_slot.desc())
        .all()
    )

    results = []
    for apt in appointments:
        if apt.id in reviewed_ids:
            continue
        doctor = db.query(Doctor).filter(Doctor.id == apt.doctor_id).first()
        doctor_name = "Doctor"
        if doctor:
            doc_profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
            if doc_profile:
                doctor_name = f"Dr. {doc_profile.first_name or ''} {doc_profile.last_name or ''}".strip()

        payment = db.query(Payment).filter(Payment.appointment_id == apt.id).first()
        receptionist_name = None
        receptionist_id = payment.receptionist_id if payment else None
        if receptionist_id:
            rec_profile = db.query(Profile).filter(Profile.id == receptionist_id).first()
            if rec_profile:
                receptionist_name = f"{rec_profile.first_name or ''} {rec_profile.last_name or ''}".strip()

        results.append({
            "appointment_id": apt.id,
            "date": apt.date.isoformat() if apt.date else None,
            "time_slot": apt.time_slot,
            "doctor_id": apt.doctor_id,
            "doctor_name": doctor_name,
            "receptionist_id": receptionist_id,
            "receptionist_name": receptionist_name,
        })
    return results


@router.post("/", response_model=ReviewResponse, status_code=status.HTTP_201_CREATED)
def submit_review(
    data: ReviewCreate,
    current_user: User = Depends(require_role("patient")),
    db: Session = Depends(get_db),
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=400, detail="Patient profile not found")

    apt = db.query(Appointment).filter(Appointment.id == data.appointment_id).first()
    if not apt:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if apt.patient_id != profile.id:
        raise HTTPException(status_code=403, detail="Not your appointment")
    if apt.status != "completed":
        raise HTTPException(status_code=400, detail="You can only review completed appointments")

    existing = db.query(AppointmentReview).filter(AppointmentReview.appointment_id == apt.id).first()
    if existing:
        raise HTTPException(status_code=400, detail="Review already submitted for this appointment")

    _validate_rating(data.doctor_rating, "Doctor rating")

    payment = db.query(Payment).filter(Payment.appointment_id == apt.id).first()
    receptionist_id = payment.receptionist_id if payment else None

    receptionist_rating = data.receptionist_rating
    if receptionist_id:
        if receptionist_rating is None:
            raise HTTPException(status_code=400, detail="Receptionist rating is required for this visit")
        _validate_rating(receptionist_rating, "Receptionist rating")
    else:
        receptionist_rating = None

    review = AppointmentReview(
        id=str(uuid.uuid4()),
        appointment_id=apt.id,
        patient_id=profile.id,
        doctor_id=apt.doctor_id,
        receptionist_id=receptionist_id,
        doctor_rating=data.doctor_rating,
        receptionist_rating=receptionist_rating,
        doctor_comment=(data.doctor_comment or "").strip() or None,
        receptionist_comment=(data.receptionist_comment or "").strip() or None,
    )
    db.add(review)
    db.commit()
    db.refresh(review)
    return _enrich_review(review, db)


@router.get("/doctor/{doctor_id}", response_model=DoctorRatingSummary)
def doctor_reviews(
    doctor_id: str,
    db: Session = Depends(get_db),
):
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")

    stats = doctor_rating_stats(db, doctor_id)
    recent = (
        db.query(AppointmentReview)
        .filter(AppointmentReview.doctor_id == doctor_id)
        .order_by(AppointmentReview.created_at.desc())
        .limit(20)
        .all()
    )
    return {
        **stats,
        "reviews": [_enrich_review(r, db) for r in recent],
    }
