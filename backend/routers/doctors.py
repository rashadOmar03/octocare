from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database import get_db
from models import User, Profile, Doctor, Specialty, AuditLog, MedicalRecord, Prescription, Appointment, DoctorTimeOff
from schemas import DoctorTimeOffCreate, DoctorTimeOffResponse
from auth import get_current_user, require_role
from audit_service import log_audit

router = APIRouter()


def _get_doctor_record(user: User, db: Session) -> tuple[Doctor, Profile]:
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor record not found")
    return doctor, profile


def _log_relates_to_patient(db: Session, log: AuditLog, patient_id: str) -> bool:
    if log.entity_type == "medical_record":
        rec = db.query(MedicalRecord).filter(MedicalRecord.id == log.entity_id).first()
        return rec is not None and rec.patient_id == patient_id
    if log.entity_type == "prescription":
        rx = db.query(Prescription).filter(Prescription.id == log.entity_id).first()
        if not rx:
            return False
        rec = db.query(MedicalRecord).filter(MedicalRecord.id == rx.medical_record_id).first()
        return rec is not None and rec.patient_id == patient_id
    if log.entity_type == "appointment":
        apt = db.query(Appointment).filter(Appointment.id == log.entity_id).first()
        return apt is not None and apt.patient_id == patient_id
    return False


@router.get("/me")
def get_my_doctor_profile(
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    doctor, profile = _get_doctor_record(current_user, db)
    specialty = db.query(Specialty).filter(Specialty.id == doctor.specialty_id).first()
    return {
        "profile_id": profile.id,
        "doctor_id": doctor.id,
        "first_name": profile.first_name,
        "middle_name": profile.middle_name,
        "last_name": profile.last_name,
        "phone": profile.phone or current_user.phone,
        "address": profile.address,
        "photo_url": profile.photo_url,
        "email": current_user.email,
        "qualifications": doctor.qualifications,
        "bio": doctor.bio,
        "specialty": specialty.name if specialty else None,
        "specialty_id": doctor.specialty_id,
    }


@router.put("/me")
def update_my_doctor_profile(
    data: dict,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    doctor, profile = _get_doctor_record(current_user, db)

    profile_fields = {"first_name", "middle_name", "last_name", "phone", "address", "photo_url"}
    doctor_fields = {"qualifications", "bio"}

    for field, value in data.items():
        if field in profile_fields:
            setattr(profile, field, value)
        elif field in doctor_fields:
            setattr(doctor, field, value)

    if profile.first_name and profile.last_name:
        profile.is_complete = True

    db.commit()
    db.refresh(profile)
    db.refresh(doctor)

    specialty = db.query(Specialty).filter(Specialty.id == doctor.specialty_id).first()
    return {
        "profile_id": profile.id,
        "doctor_id": doctor.id,
        "first_name": profile.first_name,
        "middle_name": profile.middle_name,
        "last_name": profile.last_name,
        "phone": profile.phone or current_user.phone,
        "address": profile.address,
        "photo_url": profile.photo_url,
        "email": current_user.email,
        "qualifications": doctor.qualifications,
        "bio": doctor.bio,
        "specialty": specialty.name if specialty else None,
        "specialty_id": doctor.specialty_id,
    }


@router.get("/me/activity-report")
def doctor_activity_report(
    patient_id: str | None = Query(None),
    date_from: date | None = Query(None),
    date_to: date | None = Query(None),
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    """Audit trail of all actions performed by the logged-in doctor."""
    doctor, profile = _get_doctor_record(current_user, db)
    query = db.query(AuditLog).filter(AuditLog.user_id == current_user.id)
    if date_from:
        query = query.filter(AuditLog.timestamp >= datetime.combine(date_from, datetime.min.time()))
    if date_to:
        query = query.filter(AuditLog.timestamp <= datetime.combine(date_to, datetime.max.time()))

    logs = query.order_by(AuditLog.timestamp.desc()).limit(500).all()
    entries = []
    for log in logs:
        if patient_id and not _log_relates_to_patient(db, log, patient_id):
            continue
        entries.append({
            "timestamp": log.timestamp.isoformat() if log.timestamp else None,
            "action": log.action,
            "entity_type": log.entity_type,
            "entity_id": log.entity_id,
            "details": log.details,
        })

    patient_name = None
    if patient_id:
        p = db.query(Profile).filter(Profile.id == patient_id).first()
        if p:
            patient_name = f"{p.first_name or ''} {p.last_name or ''}".strip()

    return {
        "doctor_id": doctor.id,
        "doctor_name": f"Dr. {profile.first_name or ''} {profile.last_name or ''}".strip(),
        "patient_id": patient_id,
        "patient_name": patient_name,
        "total": len(entries),
        "entries": entries,
    }


@router.get("/me/time-off", response_model=list[DoctorTimeOffResponse])
def list_my_time_off(
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    doctor, _ = _get_doctor_record(current_user, db)
    return (
        db.query(DoctorTimeOff)
        .filter(DoctorTimeOff.doctor_id == doctor.id)
        .order_by(DoctorTimeOff.start_date.desc())
        .all()
    )


@router.post("/me/time-off", response_model=DoctorTimeOffResponse, status_code=status.HTTP_201_CREATED)
def add_my_time_off(
    data: DoctorTimeOffCreate,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    doctor, profile = _get_doctor_record(current_user, db)
    if data.end_date < data.start_date:
        raise HTTPException(status_code=400, detail="End date must be on or after start date")

    row = DoctorTimeOff(
        doctor_id=doctor.id,
        start_date=data.start_date,
        end_date=data.end_date,
        reason=data.reason,
    )
    db.add(row)

    from vacation_helpers import notify_vacation_scheduled

    patient_notified = notify_vacation_scheduled(
        db,
        doctor.id,
        data.start_date,
        data.end_date,
        data.reason,
        scheduled_by="doctor",
        exclude_user_id=current_user.id,
    )
    log_audit(
        db,
        current_user.id,
        "add_doctor_time_off",
        "doctor",
        doctor.id,
        (
            f"Doctor scheduled time off {data.start_date}–{data.end_date} "
            f"({patient_notified} patients notified)"
        ),
    )
    db.commit()
    db.refresh(row)
    return row


@router.delete("/me/time-off/{time_off_id}")
def delete_my_time_off(
    time_off_id: str,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    doctor, _ = _get_doctor_record(current_user, db)
    row = (
        db.query(DoctorTimeOff)
        .filter(DoctorTimeOff.id == time_off_id, DoctorTimeOff.doctor_id == doctor.id)
        .first()
    )
    if not row:
        raise HTTPException(status_code=404, detail="Time off not found")
    start_date = row.start_date
    end_date = row.end_date
    db.delete(row)

    from vacation_helpers import notify_vacation_removed

    notify_vacation_removed(
        db,
        doctor.id,
        start_date=start_date,
        end_date=end_date,
        removed_by="doctor",
        exclude_user_id=current_user.id,
    )
    log_audit(
        db,
        current_user.id,
        "delete_doctor_time_off",
        "doctor",
        doctor.id,
        f"Doctor removed time off {start_date}–{end_date}",
    )
    db.commit()
    return {"message": "Time off removed"}

