"""Shared authorization helpers for role-scoped resources."""
from fastapi import HTTPException
from sqlalchemy.orm import Session

from models import User, Profile, Doctor, Appointment, MedicalRecord, Prescription, Document


def get_profile(user: User, db: Session) -> Profile | None:
    return db.query(Profile).filter(Profile.user_id == user.id).first()


def get_doctor(user: User, db: Session) -> Doctor | None:
    profile = get_profile(user, db)
    if not profile:
        return None
    return db.query(Doctor).filter(Doctor.profile_id == profile.id).first()


def is_staff(user: User) -> bool:
    return user.role in ("receptionist", "admin")


def assert_patient_profile_access(user: User, patient_id: str, db: Session) -> None:
    if user.role in ("doctor", "receptionist", "admin"):
        return
    profile = get_profile(user, db)
    if not profile or profile.id != patient_id:
        raise HTTPException(status_code=403, detail="Access denied")


def assert_appointment_read(user: User, appointment: Appointment, db: Session) -> None:
    if is_staff(user):
        return
    profile = get_profile(user, db)
    if user.role == "patient":
        if not profile or appointment.patient_id != profile.id:
            raise HTTPException(status_code=403, detail="Access denied")
        return
    if user.role == "doctor":
        doctor = get_doctor(user, db)
        if not doctor or appointment.doctor_id != doctor.id:
            raise HTTPException(status_code=403, detail="Access denied")
        return
    raise HTTPException(status_code=403, detail="Access denied")


def assert_appointment_patient_action(user: User, appointment: Appointment, db: Session) -> None:
    profile = get_profile(user, db)
    if not profile or appointment.patient_id != profile.id:
        raise HTTPException(status_code=403, detail="Access denied")


def assert_appointment_doctor_action(user: User, appointment: Appointment, db: Session) -> Doctor:
    doctor = get_doctor(user, db)
    if not doctor or appointment.doctor_id != doctor.id:
        raise HTTPException(status_code=403, detail="This appointment belongs to another doctor")
    return doctor


def assert_record_read(user: User, record: MedicalRecord, db: Session) -> None:
    if is_staff(user):
        return
    profile = get_profile(user, db)
    if user.role == "patient":
        if not profile or record.patient_id != profile.id:
            raise HTTPException(status_code=403, detail="Access denied")
        if not getattr(record, "is_active", True):
            raise HTTPException(status_code=404, detail="Medical record not found")
        return
    if user.role == "doctor":
        doctor = get_doctor(user, db)
        if not doctor:
            raise HTTPException(status_code=403, detail="Access denied")
        return
    raise HTTPException(status_code=403, detail="Access denied")


def assert_record_write(user: User, record: MedicalRecord, db: Session) -> None:
    doctor = get_doctor(user, db)
    if not doctor or record.doctor_id != doctor.id:
        raise HTTPException(status_code=403, detail="You can only modify your own medical records")


def assert_prescription_read(user: User, prescription: Prescription, db: Session) -> None:
    record = (
        db.query(MedicalRecord)
        .filter(MedicalRecord.id == prescription.medical_record_id)
        .first()
    )
    if not record:
        raise HTTPException(status_code=404, detail="Prescription not found")
    if user.role == "patient":
        if prescription.status != "active":
            raise HTTPException(status_code=404, detail="Prescription not found")
        assert_record_read(user, record, db)
        return
    if user.role == "doctor":
        return
    if is_staff(user):
        return
    raise HTTPException(status_code=403, detail="Access denied")


def assert_prescription_write(user: User, prescription: Prescription, db: Session) -> None:
    record = (
        db.query(MedicalRecord)
        .filter(MedicalRecord.id == prescription.medical_record_id)
        .first()
    )
    if not record:
        raise HTTPException(status_code=404, detail="Prescription not found")
    assert_record_write(user, record, db)


def assert_document_access(user: User, doc: Document, db: Session, *, write: bool = False) -> None:
    if user.role in ("doctor", "receptionist", "admin"):
        return
    profile = get_profile(user, db)
    if not profile or doc.patient_id != profile.id:
        raise HTTPException(status_code=403, detail="Access denied")
    if write and doc.uploaded_by and doc.uploaded_by != user.id and user.role == "patient":
        raise HTTPException(status_code=403, detail="Access denied")
