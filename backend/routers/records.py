import json
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database import get_db
from models import User, Profile, Doctor, MedicalRecord, AuditLog, Prescription, PrescriptionItem, Appointment
from schemas import MedicalRecordCreate, MedicalRecordUpdate, MedicalRecordResponse, MedicalRecordActiveUpdate
from auth import get_current_user, require_role
from medical_extraction import normalize_extraction, structured_to_record_fields
from appointment_rules import require_paid_arrived_appointment, require_active_paid_visit_for_patient
from access_control import assert_record_read, assert_record_write

router = APIRouter()


def _get_doctor(user: User, db: Session) -> Doctor:
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if not profile:
        raise HTTPException(status_code=400, detail="Doctor profile not found")
    doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
    if not doctor:
        raise HTTPException(status_code=400, detail="Doctor record not found")
    return doctor


def _parse_structured(raw: str | None) -> dict | None:
    if not raw:
        return None
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None


def _doctor_display_name(db: Session, doctor_id: str) -> str | None:
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        return None
    profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
    if not profile:
        return None
    name = f"Dr. {profile.first_name or ''} {profile.last_name or ''}".strip()
    return name or None


def _record_response(record: MedicalRecord, db: Session) -> MedicalRecordResponse:
    return MedicalRecordResponse(
        id=record.id,
        appointment_id=record.appointment_id,
        patient_id=record.patient_id,
        doctor_id=record.doctor_id,
        doctor_name=_doctor_display_name(db, record.doctor_id),
        chief_complaint=record.chief_complaint,
        symptoms=record.symptoms,
        diagnosis=record.diagnosis,
        severity=record.severity,
        treatment_plan=record.treatment_plan,
        notes=record.notes,
        soap_subjective=record.soap_subjective,
        soap_objective=record.soap_objective,
        soap_assessment=record.soap_assessment,
        soap_plan=record.soap_plan,
        structured_data=_parse_structured(record.structured_data),
        is_active=getattr(record, "is_active", True),
        created_at=record.created_at,
    )


def _parse_active_until(raw) -> datetime | None:
    if not raw:
        return None
    if isinstance(raw, datetime):
        return raw
    text = str(raw).strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00").split("+")[0])
    except ValueError:
        return None


def _resolve_prescription_active_until(meds: list[dict], explicit: datetime | None = None) -> datetime | None:
    if explicit:
        return explicit
    for med in meds:
        if isinstance(med, dict):
            parsed = _parse_active_until(med.get("active_until"))
            if parsed:
                return parsed
    return None


def _create_prescription_from_list(
    db: Session,
    record_id: str,
    meds: list[dict],
    active_until: datetime | None = None,
) -> None:
    if not meds:
        return
    resolved_until = _resolve_prescription_active_until(meds, active_until)
    prescription = Prescription(
        id=str(uuid.uuid4()),
        medical_record_id=record_id,
        status="active",
        active_until=resolved_until,
    )
    db.add(prescription)
    for med in meds:
        if not isinstance(med, dict):
            continue
        name = (med.get("name") or med.get("medication_name") or "").strip()
        if not name:
            continue
        dosage = (med.get("dosage") or "").strip()
        frequency = (med.get("frequency") or "").strip()
        duration = (med.get("duration") or "").strip()
        db.add(PrescriptionItem(
            prescription_id=prescription.id,
            medication_name=name,
            dosage=dosage or "—",
            frequency=frequency or "—",
            duration=duration or "—",
            notes=med.get("notes") or med.get("route"),
        ))


def _replace_prescriptions_for_record(
    db: Session,
    record_id: str,
    meds: list[dict],
    active_until: datetime | None = None,
) -> None:
    existing = db.query(Prescription).filter(Prescription.medical_record_id == record_id).all()
    for rx in existing:
        db.query(PrescriptionItem).filter(PrescriptionItem.prescription_id == rx.id).delete()
        db.delete(rx)
    active_meds = [
        m for m in meds
        if isinstance(m, dict)
        and m.get("active", True) is not False
        and (m.get("name") or m.get("medication_name") or "").strip()
    ]
    if active_meds:
        _create_prescription_from_list(db, record_id, active_meds, active_until=active_until)


def sync_prescriptions_from_records(db: Session) -> int:
    """Backfill Prescription rows from structured_data when consultations saved meds without RX rows."""
    created = 0
    for record in db.query(MedicalRecord).all():
        if db.query(Prescription).filter(Prescription.medical_record_id == record.id).count() > 0:
            continue
        meds: list[dict] = []
        structured = _parse_structured(record.structured_data)
        if structured:
            raw = structured.get("prescription") or []
            if isinstance(raw, list):
                meds = [m for m in raw if isinstance(m, dict)]
        if meds:
            _create_prescription_from_list(db, record.id, meds)
            created += 1
    if created:
        db.commit()
    return created


def _prepare_record_fields(data: MedicalRecordCreate) -> dict:
    """Normalize create payload into DB field dict + prescription list."""
    structured_json = data.structured_data
    prescription_items = list(data.prescription or [])

    if structured_json and not structured_json.strip().startswith("{"):
        structured_json = None

    if structured_json:
        try:
            structured = normalize_extraction(json.loads(structured_json))
            fields = structured_to_record_fields(structured)
            if not prescription_items:
                prescription_items = structured.get("prescription") or []
            return {
                "chief_complaint": data.chief_complaint or fields["chief_complaint"],
                "symptoms": data.symptoms or fields["symptoms"],
                "diagnosis": data.diagnosis or fields["diagnosis"],
                "severity": data.severity or fields["severity"],
                "treatment_plan": data.treatment_plan or fields["treatment_plan"],
                "notes": data.notes or fields["notes"],
                "soap_subjective": data.soap_subjective or fields["soap_subjective"],
                "soap_objective": data.soap_objective or fields["soap_objective"],
                "soap_assessment": data.soap_assessment or fields["soap_assessment"],
                "soap_plan": data.soap_plan or fields["soap_plan"],
                "structured_data": fields["structured_data"],
                "prescription": prescription_items,
            }
        except (json.JSONDecodeError, TypeError):
            pass

    return {
        "chief_complaint": data.chief_complaint,
        "symptoms": data.symptoms,
        "diagnosis": data.diagnosis,
        "severity": data.severity,
        "treatment_plan": data.treatment_plan,
        "notes": data.notes,
        "soap_subjective": data.soap_subjective,
        "soap_objective": data.soap_objective,
        "soap_assessment": data.soap_assessment,
        "soap_plan": data.soap_plan,
        "structured_data": structured_json,
        "prescription": prescription_items,
    }


@router.post("/", response_model=MedicalRecordResponse, status_code=status.HTTP_201_CREATED)
def create_record(
    data: MedicalRecordCreate,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    doctor = _get_doctor(current_user, db)

    patient = db.query(Profile).filter(Profile.id == data.patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    fields = _prepare_record_fields(data)
    prescription_items = fields.pop("prescription", [])
    prescription_active_until = data.prescription_active_until
    if not prescription_active_until and data.structured_data:
        try:
            structured = json.loads(data.structured_data)
            prescription_active_until = _parse_active_until(structured.get("prescription_active_until"))
        except (json.JSONDecodeError, TypeError):
            pass

    existing = None
    if data.appointment_id:
        apt = db.query(Appointment).filter(Appointment.id == data.appointment_id).first()
        existing = (
            db.query(MedicalRecord)
            .filter(MedicalRecord.appointment_id == data.appointment_id)
            .first()
        )
        if apt and apt.status == "completed" and not existing:
            raise HTTPException(
                status_code=400,
                detail="This appointment is completed. A new consultation cannot be started.",
            )
        if not existing:
            require_paid_arrived_appointment(db, data.appointment_id, doctor_id=doctor.id)
    elif not existing:
        require_active_paid_visit_for_patient(db, data.patient_id, doctor_id=doctor.id)

    if existing:
        for key, value in fields.items():
            setattr(existing, key, value)
        record = existing
        action = "update"
        details = f"Updated medical record for appointment {data.appointment_id}"
    else:
        record = MedicalRecord(
            id=str(uuid.uuid4()),
            appointment_id=data.appointment_id,
            patient_id=data.patient_id,
            doctor_id=doctor.id,
            **fields,
        )
        db.add(record)
        action = "create"
        details = f"Created medical record for patient {data.patient_id}"

    db.flush()
    if prescription_items:
        if existing:
            _replace_prescriptions_for_record(
                db, record.id, prescription_items, active_until=prescription_active_until,
            )
        else:
            _create_prescription_from_list(
                db, record.id, prescription_items, active_until=prescription_active_until,
            )

    db.add(AuditLog(
        user_id=current_user.id,
        action=action,
        entity_type="medical_record",
        entity_id=record.id,
        details=details,
    ))

    db.commit()
    db.refresh(record)
    return _record_response(record, db)


@router.put("/{record_id}", response_model=MedicalRecordResponse)
def update_record(
    record_id: str,
    data: MedicalRecordUpdate,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    record = db.query(MedicalRecord).filter(MedicalRecord.id == record_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Medical record not found")
    assert_record_write(current_user, record, db)

    update_data = data.model_dump(exclude_unset=True)
    prescription_items = update_data.pop("prescription", None)
    prescription_active_until = update_data.pop("prescription_active_until", None)
    for field, value in update_data.items():
        setattr(record, field, value)

    if prescription_items is not None:
        resolved_until = prescription_active_until
        if resolved_until is None and record.structured_data:
            try:
                structured = json.loads(record.structured_data)
                resolved_until = _parse_active_until(structured.get("prescription_active_until"))
            except (json.JSONDecodeError, TypeError):
                pass
        if resolved_until is None:
            existing_rx = (
                db.query(Prescription)
                .filter(Prescription.medical_record_id == record.id)
                .order_by(Prescription.created_at.desc())
                .first()
            )
            if existing_rx:
                resolved_until = existing_rx.active_until
        _replace_prescriptions_for_record(
            db, record.id, prescription_items, active_until=resolved_until,
        )

    db.add(AuditLog(
        user_id=current_user.id,
        action="update",
        entity_type="medical_record",
        entity_id=record.id,
        details=f"Updated fields: {', '.join(update_data.keys())}",
    ))

    db.commit()
    db.refresh(record)
    return _record_response(record, db)


@router.put("/{record_id}/active", response_model=MedicalRecordResponse)
def set_record_active(
    record_id: str,
    data: MedicalRecordActiveUpdate,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    record = db.query(MedicalRecord).filter(MedicalRecord.id == record_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Medical record not found")
    assert_record_write(current_user, record, db)

    record.is_active = data.is_active
    action = "activate" if data.is_active else "deactivate"
    db.add(AuditLog(
        user_id=current_user.id,
        action=action,
        entity_type="medical_record",
        entity_id=record.id,
        details=f"Diagnosis/record {action}d: {record.diagnosis}",
    ))
    db.commit()
    db.refresh(record)
    return _record_response(record, db)


@router.delete("/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_record(
    record_id: str,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    record = db.query(MedicalRecord).filter(MedicalRecord.id == record_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Medical record not found")
    assert_record_write(current_user, record, db)

    diagnosis = record.diagnosis
    for rx in db.query(Prescription).filter(Prescription.medical_record_id == record.id).all():
        db.query(PrescriptionItem).filter(PrescriptionItem.prescription_id == rx.id).delete()
        db.delete(rx)

    db.add(AuditLog(
        user_id=current_user.id,
        action="delete",
        entity_type="medical_record",
        entity_id=record_id,
        details=f"Deleted medical record/diagnosis: {diagnosis}",
    ))
    db.delete(record)
    db.commit()
    return None


@router.get("/patient/me", response_model=list[MedicalRecordResponse])
def get_my_records(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get records for the currently logged-in patient"""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        return []
    records = (
        db.query(MedicalRecord)
        .filter(MedicalRecord.patient_id == profile.id, MedicalRecord.is_active == True)
        .order_by(MedicalRecord.created_at.desc())
        .all()
    )
    return [_record_response(r, db) for r in records]


@router.get("/patient/{patient_id}", response_model=list[MedicalRecordResponse])
def get_patient_records(
    patient_id: str,
    include_inactive: bool = Query(False),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role == "patient":
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile or profile.id != patient_id:
            raise HTTPException(status_code=403, detail="Access denied")
        include_inactive = False

    query = db.query(MedicalRecord).filter(MedicalRecord.patient_id == patient_id)
    if current_user.role == "doctor":
        doctor = _get_doctor(current_user, db)
        query = query.filter(MedicalRecord.doctor_id == doctor.id)
    if not include_inactive:
        query = query.filter(MedicalRecord.is_active == True)
    records = query.order_by(MedicalRecord.created_at.desc()).all()
    return [_record_response(r, db) for r in records]


@router.get("/by-appointment/{appointment_id}", response_model=MedicalRecordResponse)
def get_record_by_appointment(
    appointment_id: str,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    record = (
        db.query(MedicalRecord)
        .filter(MedicalRecord.appointment_id == appointment_id)
        .first()
    )
    if not record:
        raise HTTPException(status_code=404, detail="No consultation record for this appointment")
    doctor = _get_doctor(current_user, db)
    if record.doctor_id != doctor.id:
        raise HTTPException(status_code=403, detail="Access denied")
    return _record_response(record, db)


@router.get("/{record_id}", response_model=MedicalRecordResponse)
def get_record(
    record_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    record = db.query(MedicalRecord).filter(MedicalRecord.id == record_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Medical record not found")
    assert_record_read(current_user, record, db)
    return _record_response(record, db)
