import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database import get_db
from models import (
    User, Profile, Doctor, MedicalRecord,
    Prescription, PrescriptionItem, AuditLog,
)
from schemas import (
    PrescriptionCreate, PrescriptionResponse, PrescriptionStatusUpdate, PrescriptionUpdate,
)
from auth import get_current_user, require_role
from access_control import assert_prescription_read, assert_prescription_write, get_doctor
from routers.records import sync_prescriptions_from_records

router = APIRouter()


def expire_prescriptions(db: Session) -> int:
    """Auto-deactivate prescriptions past their active_until time."""
    now = datetime.utcnow()
    expired = (
        db.query(Prescription)
        .filter(
            Prescription.status == "active",
            Prescription.active_until.isnot(None),
            Prescription.active_until < now,
        )
        .all()
    )
    for rx in expired:
        rx.status = "cancelled"
    if expired:
        db.commit()
    return len(expired)


def _prescription_summary(prescription: Prescription) -> str:
    names = [i.medication_name for i in prescription.items if i.medication_name]
    return ", ".join(names[:5]) if names else prescription.id[:8]


def _enrich_prescription(prescription: Prescription, db: Session) -> dict:
    record = db.query(MedicalRecord).filter(MedicalRecord.id == prescription.medical_record_id).first()
    patient_name = None
    patient_id = None
    doctor_name = None
    if record:
        patient_id = record.patient_id
        patient = db.query(Profile).filter(Profile.id == record.patient_id).first()
        if patient:
            patient_name = f"{patient.first_name or ''} {patient.last_name or ''}".strip() or None
        doctor = db.query(Doctor).filter(Doctor.id == record.doctor_id).first()
        if doctor:
            doc_profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
            if doc_profile:
                doctor_name = f"Dr. {doc_profile.first_name or ''} {doc_profile.last_name or ''}".strip() or None
    return {
        "id": prescription.id,
        "medical_record_id": prescription.medical_record_id,
        "status": prescription.status,
        "active_until": prescription.active_until,
        "created_at": prescription.created_at,
        "patient_id": patient_id,
        "patient_name": patient_name,
        "doctor_name": doctor_name,
        "items": [
            {
                "id": item.id,
                "prescription_id": item.prescription_id,
                "medication_name": item.medication_name,
                "dosage": item.dosage,
                "frequency": item.frequency,
                "duration": item.duration,
                "notes": item.notes,
            }
            for item in (prescription.items or [])
        ],
    }


@router.post("/", response_model=PrescriptionResponse, status_code=status.HTTP_201_CREATED)
def create_prescription(
    data: PrescriptionCreate,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    doctor = get_doctor(current_user, db)
    if not doctor:
        raise HTTPException(status_code=400, detail="Doctor record not found")

    record = None
    if data.medical_record_id:
        record = db.query(MedicalRecord).filter(MedicalRecord.id == data.medical_record_id).first()
        if record and record.doctor_id != doctor.id:
            raise HTTPException(status_code=403, detail="Cannot attach prescription to another doctor's record")

    if not record:
        patient_id = data.patient_id or data.patient
        if patient_id:
            patient_id_str = str(patient_id)
            record = (
                db.query(MedicalRecord)
                .filter(MedicalRecord.patient_id == patient_id_str, MedicalRecord.doctor_id == doctor.id)
                .order_by(MedicalRecord.created_at.desc())
                .first()
            )

    if not record:
        raise HTTPException(status_code=404, detail="Medical record not found. Create a medical record first.")

    if data.active_until is not None and data.active_until <= datetime.utcnow():
        raise HTTPException(status_code=400, detail="active_until must be in the future")

    prescription = Prescription(
        id=str(uuid.uuid4()),
        medical_record_id=record.id,
        active_until=data.active_until,
    )
    db.add(prescription)
    db.flush()

    for item_data in data.items:
        item = PrescriptionItem(
            prescription_id=prescription.id,
            medication_name=item_data.medication_name,
            dosage=(item_data.dosage or "").strip() or "—",
            frequency=(item_data.frequency or "").strip() or "—",
            duration=(item_data.duration or "").strip() or "—",
            notes=item_data.notes,
        )
        db.add(item)

    db.add(AuditLog(
        user_id=current_user.id,
        action="create",
        entity_type="prescription",
        entity_id=prescription.id,
        details=f"Created prescription ({len(data.items)} items): {_prescription_summary(prescription)} for record {record.id}",
    ))

    db.commit()
    db.refresh(prescription)
    return prescription


@router.get("/", response_model=list[PrescriptionResponse])
def list_prescriptions(
    medical_record_id: str = Query(None),
    patient_id: str = Query(None),
    include_inactive: bool = Query(False),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    expire_prescriptions(db)
    query = db.query(Prescription)

    if medical_record_id:
        query = query.filter(Prescription.medical_record_id == medical_record_id)

    if patient_id:
        record_ids = [
            r.id for r in
            db.query(MedicalRecord.id).filter(MedicalRecord.patient_id == patient_id).all()
        ]
        query = query.filter(Prescription.medical_record_id.in_(record_ids))

    if current_user.role == "patient":
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if profile:
            record_ids = [
                r.id for r in
                db.query(MedicalRecord.id).filter(
                    MedicalRecord.patient_id == profile.id,
                    MedicalRecord.is_active == True,
                ).all()
            ]
            query = query.filter(Prescription.medical_record_id.in_(record_ids))
        else:
            return []
        query = query.filter(Prescription.status == "active")
    elif current_user.role == "doctor":
        doctor = get_doctor(current_user, db)
        if doctor:
            record_ids = [
                r.id for r in
                db.query(MedicalRecord.id).filter(MedicalRecord.doctor_id == doctor.id).all()
            ]
            query = query.filter(Prescription.medical_record_id.in_(record_ids))
        elif not include_inactive:
            query = query.filter(Prescription.status == "active")
    elif current_user.role in ("admin", "receptionist"):
        if current_user.role == "admin":
            sync_prescriptions_from_records(db)
        pass
    elif not include_inactive:
        query = query.filter(Prescription.status == "active")

    prescriptions = query.order_by(Prescription.created_at.desc()).all()
    if current_user.role in ("admin", "receptionist"):
        return [_enrich_prescription(p, db) for p in prescriptions]
    return prescriptions


@router.get("/{prescription_id}", response_model=PrescriptionResponse)
def get_prescription(
    prescription_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    prescription = db.query(Prescription).filter(Prescription.id == prescription_id).first()
    if not prescription:
        raise HTTPException(status_code=404, detail="Prescription not found")

    expire_prescriptions(db)
    assert_prescription_read(current_user, prescription, db)

    if current_user.role in ("admin", "receptionist"):
        return _enrich_prescription(prescription, db)
    return prescription


@router.put("/{prescription_id}", response_model=PrescriptionResponse)
def update_prescription(
    prescription_id: str,
    data: PrescriptionUpdate,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    prescription = db.query(Prescription).filter(Prescription.id == prescription_id).first()
    if not prescription:
        raise HTTPException(status_code=404, detail="Prescription not found")

    assert_prescription_write(current_user, prescription, db)

    old_summary = _prescription_summary(prescription)

    db.query(PrescriptionItem).filter(PrescriptionItem.prescription_id == prescription.id).delete()
    for item_data in data.items:
        db.add(PrescriptionItem(
            prescription_id=prescription.id,
            medication_name=item_data.medication_name,
            dosage=item_data.dosage,
            frequency=item_data.frequency,
            duration=item_data.duration,
            notes=item_data.notes,
        ))

    if data.status:
        prescription.status = data.status
    if data.active_until is not None:
        prescription.active_until = data.active_until

    db.flush()
    new_summary = _prescription_summary(prescription)

    db.add(AuditLog(
        user_id=current_user.id,
        action="update",
        entity_type="prescription",
        entity_id=prescription.id,
        details=f"Updated prescription from [{old_summary}] to [{new_summary}]",
    ))

    db.commit()
    db.refresh(prescription)
    return prescription


@router.put("/{prescription_id}/status", response_model=PrescriptionResponse)
def update_prescription_status(
    prescription_id: str,
    data: PrescriptionStatusUpdate,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    prescription = db.query(Prescription).filter(Prescription.id == prescription_id).first()
    if not prescription:
        raise HTTPException(status_code=404, detail="Prescription not found")

    assert_prescription_write(current_user, prescription, db)

    if data.status not in ("active", "completed", "cancelled"):
        raise HTTPException(status_code=400, detail="Invalid status")

    old_status = prescription.status
    prescription.status = data.status

    if data.status == "active":
        if data.active_until is not None:
            if data.active_until <= datetime.utcnow():
                raise HTTPException(status_code=400, detail="active_until must be in the future")
            prescription.active_until = data.active_until
    else:
        prescription.active_until = None

    action = "activate" if data.status == "active" else ("deactivate" if data.status == "cancelled" else "update_status")
    expiry_note = ""
    if prescription.active_until:
        expiry_note = f" until {prescription.active_until.isoformat()}Z"
    db.add(AuditLog(
        user_id=current_user.id,
        action=action,
        entity_type="prescription",
        entity_id=prescription.id,
        details=f"Prescription status changed from {old_status} to {data.status}{expiry_note}: {_prescription_summary(prescription)}",
    ))

    db.commit()
    db.refresh(prescription)
    return prescription


@router.delete("/{prescription_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_prescription(
    prescription_id: str,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    prescription = db.query(Prescription).filter(Prescription.id == prescription_id).first()
    if not prescription:
        raise HTTPException(status_code=404, detail="Prescription not found")

    assert_prescription_write(current_user, prescription, db)

    summary = _prescription_summary(prescription)
    db.query(PrescriptionItem).filter(PrescriptionItem.prescription_id == prescription.id).delete()

    db.add(AuditLog(
        user_id=current_user.id,
        action="delete",
        entity_type="prescription",
        entity_id=prescription_id,
        details=f"Deleted prescription: {summary}",
    ))

    db.delete(prescription)
    db.commit()
    return None
