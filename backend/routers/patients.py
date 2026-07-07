import os
import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from sqlalchemy.orm import Session

from database import get_db
from models import User, Profile, Notification, ProfileUpdateRequest, Document
from models import (
    Appointment, Doctor, MedicalRecord, Prescription, PrescriptionItem,
    SensorData, Payment,
)
from schemas import (
    ProfileCreate, ProfileUpdate, ProfileResponse,
    NotificationResponse, ProfileUpdateRequestCreate, ProfileUpdateRequestResponse,
)
from auth import get_current_user, require_role
from access_control import assert_patient_profile_access, assert_document_access
from profile_utils import profile_personal_info_complete, field_ok

router = APIRouter()


def _sync_profile_from_user(profile: Profile, user: User) -> bool:
    """Copy account phone onto profile when profile has none or placeholder."""
    changed = False
    if not field_ok(profile.phone) and field_ok(user.phone):
        profile.phone = user.phone.strip()
        changed = True
    return changed


@router.get("/profile", response_model=ProfileResponse)
def get_profile(
    patient_id: str | None = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if patient_id:
        assert_patient_profile_access(current_user, patient_id, db)
        profile = db.query(Profile).filter(Profile.id == patient_id).first()
        if not profile:
            raise HTTPException(status_code=404, detail="Profile not found")
        user = db.query(User).filter(User.id == profile.user_id).first()
        if user and _sync_profile_from_user(profile, user):
            db.commit()
            db.refresh(profile)
        complete = profile_personal_info_complete(profile)
        if profile.is_complete != complete:
            profile.is_complete = complete
            db.commit()
            db.refresh(profile)
        return profile

    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        profile = Profile(
            id=str(uuid.uuid4()),
            user_id=current_user.id,
            first_name="",
            last_name="",
            is_complete=False,
        )
        db.add(profile)
        db.commit()
        db.refresh(profile)
    if _sync_profile_from_user(profile, current_user):
        db.commit()
        db.refresh(profile)
    complete = profile_personal_info_complete(profile)
    if profile.is_complete != complete:
        profile.is_complete = complete
        db.commit()
        db.refresh(profile)
    return profile


@router.put("/profile", response_model=ProfileResponse)
def update_profile(
    data: ProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()

    if not profile:
        profile = Profile(
            id=str(uuid.uuid4()),
            user_id=current_user.id,
            is_complete=False,
        )
        db.add(profile)

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(profile, field, value)

    if profile.first_name and profile.last_name:
        profile.is_complete = True

    db.commit()
    db.refresh(profile)
    return profile


@router.put("/profile/{patient_id}", response_model=ProfileResponse)
def update_patient_profile_by_id(
    patient_id: str,
    data: ProfileUpdate,
    current_user: User = Depends(require_role("doctor", "receptionist", "admin")),
    db: Session = Depends(get_db),
):
    assert_patient_profile_access(current_user, patient_id, db)
    profile = db.query(Profile).filter(Profile.id == patient_id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    update_data = data.model_dump(exclude_unset=True)
    if current_user.role == "doctor":
        allowed = {"blood_type", "allergies", "chronic_diseases", "existing_conditions"}
        update_data = {k: v for k, v in update_data.items() if k in allowed}

    for field, value in update_data.items():
        setattr(profile, field, value)

    db.commit()
    db.refresh(profile)
    return profile


@router.post("/complete-profile", response_model=ProfileResponse, status_code=status.HTTP_201_CREATED)
def complete_profile(
    data: ProfileCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    existing = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if existing and profile_personal_info_complete(existing):
        return existing

    def _pick(*values):
        for value in values:
            if field_ok(value):
                return str(value).strip()
        return ""

    first_name = _pick(data.first_name, existing.first_name if existing else None)
    last_name = _pick(data.last_name, existing.last_name if existing else None)
    phone = _pick(data.phone, existing.phone if existing else None, current_user.phone)
    middle_name = _pick(data.middle_name, existing.middle_name if existing else None) or None

    for label, value in [
        ("Date of birth", data.dob),
        ("Gender", data.gender),
        ("Address", data.address),
        ("Phone", phone),
        ("First name", first_name),
        ("Last name", last_name),
    ]:
        if value is None or str(value).strip() in ("", "N/A"):
            raise HTTPException(status_code=400, detail=f"{label} is required")

    if existing:
        existing.first_name = first_name
        existing.middle_name = middle_name
        existing.last_name = last_name
        existing.dob = data.dob
        existing.gender = data.gender
        existing.phone = phone
        existing.address = data.address
        existing.emergency_contact_name = (data.emergency_contact_name or "").strip() or None
        existing.emergency_contact_phone = (data.emergency_contact_phone or "").strip() or None
        existing.blood_type = (data.blood_type or "").strip() or "Unknown"
        existing.allergies = (data.allergies or "").strip() or None
        existing.chronic_diseases = (data.chronic_diseases or "").strip() or None
        existing.existing_conditions = (data.existing_conditions or "").strip() or None
        if data.photo_url:
            existing.photo_url = data.photo_url
        existing.is_complete = profile_personal_info_complete(existing)
        db.commit()
        db.refresh(existing)
        return existing

    profile = Profile(
        id=str(uuid.uuid4()),
        user_id=current_user.id,
        first_name=first_name,
        middle_name=middle_name,
        last_name=last_name,
        dob=data.dob,
        gender=data.gender,
        phone=phone,
        address=data.address,
        emergency_contact_name=(data.emergency_contact_name or "").strip() or None,
        emergency_contact_phone=(data.emergency_contact_phone or "").strip() or None,
        blood_type=(data.blood_type or "").strip() or "Unknown",
        allergies=(data.allergies or "").strip() or None,
        chronic_diseases=(data.chronic_diseases or "").strip() or None,
        existing_conditions=(data.existing_conditions or "").strip() or None,
        photo_url=data.photo_url,
        is_complete=False,
    )
    profile.is_complete = profile_personal_info_complete(profile)
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile


@router.get("/notifications", response_model=list[NotificationResponse])
def get_notifications(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    notifications = (
        db.query(Notification)
        .filter(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc())
        .all()
    )
    return notifications


@router.put("/notifications/{notification_id}/read")
def mark_notification_read(
    notification_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    notification = (
        db.query(Notification)
        .filter(Notification.id == notification_id, Notification.user_id == current_user.id)
        .first()
    )
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")

    notification.is_read = True
    db.commit()
    return {"message": "Notification marked as read"}


@router.delete("/notifications/{notification_id}")
def delete_notification(
    notification_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    notification = (
        db.query(Notification)
        .filter(Notification.id == notification_id, Notification.user_id == current_user.id)
        .first()
    )
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")

    db.delete(notification)
    db.commit()
    return {"message": "Notification deleted"}


@router.post("/update-request", response_model=ProfileUpdateRequestResponse, status_code=status.HTTP_201_CREATED)
def create_update_request(
    data: ProfileUpdateRequestCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    request = ProfileUpdateRequest(
        id=str(uuid.uuid4()),
        patient_id=profile.id,
        request_type=data.request_type,
        old_value=data.old_value,
        new_value=data.new_value,
    )
    db.add(request)
    db.commit()
    db.refresh(request)
    return request


@router.get("/update-requests", response_model=list[ProfileUpdateRequestResponse])
def get_update_requests(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    requests = (
        db.query(ProfileUpdateRequest)
        .filter(ProfileUpdateRequest.patient_id == profile.id)
        .order_by(ProfileUpdateRequest.created_at.desc())
        .all()
    )
    return requests


UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

ALLOWED_PHOTO_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
ALLOWED_DOC_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".pdf", ".doc", ".docx"}
MAX_PHOTO_SIZE = 5 * 1024 * 1024   # 5 MB
MAX_DOC_SIZE = 10 * 1024 * 1024    # 10 MB


def _normalize_photo_extension(filename: str | None, content_type: str | None = None) -> str:
    ext = os.path.splitext(filename or "")[1].lower()
    if ext in ALLOWED_PHOTO_EXTENSIONS:
        return ext
    if content_type:
        ct = content_type.lower()
        if "jpeg" in ct or "jpg" in ct:
            return ".jpg"
        if "png" in ct:
            return ".png"
        if "gif" in ct:
            return ".gif"
        if "webp" in ct:
            return ".webp"
    return ".jpg"


def _validate_upload(file: UploadFile, allowed_exts: set, max_size: int, content: bytes) -> None:
    ext = _normalize_photo_extension(file.filename, file.content_type) if allowed_exts == ALLOWED_PHOTO_EXTENSIONS else os.path.splitext(file.filename or "")[1].lower()
    if ext not in allowed_exts:
        raise HTTPException(
            status_code=400,
            detail=f"File type '{ext}' not allowed. Allowed: {', '.join(sorted(allowed_exts))}",
        )
    if len(content) > max_size:
        raise HTTPException(
            status_code=400,
            detail=f"File too large. Maximum size: {max_size // (1024 * 1024)} MB",
        )


@router.post("/profile/photo")
async def upload_profile_photo(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        profile = Profile(
            id=str(uuid.uuid4()),
            user_id=current_user.id,
            first_name="",
            last_name="",
            is_complete=False,
        )
        db.add(profile)
        db.commit()
        db.refresh(profile)

    content = await file.read()
    _validate_upload(file, ALLOWED_PHOTO_EXTENSIONS, MAX_PHOTO_SIZE, content)

    ext = _normalize_photo_extension(file.filename, file.content_type)
    safe_name = f"avatar_{current_user.id}{ext}"
    file_path = os.path.join(UPLOAD_DIR, safe_name)

    with open(file_path, "wb") as f:
        f.write(content)

    version = int(datetime.utcnow().timestamp())
    profile.photo_url = f"/uploads/{safe_name}?v={version}"
    db.commit()
    db.refresh(profile)

    return {"photo_url": profile.photo_url}


@router.post("/documents/upload")
async def upload_document(
    file: UploadFile = File(...),
    category: str = Form("other"),
    patient_id: str = Form(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if patient_id:
        if current_user.role == "patient":
            raise HTTPException(status_code=403, detail="Patients cannot upload for other accounts")
        assert_patient_profile_access(current_user, patient_id, db)
        pid = patient_id
    else:
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile:
            raise HTTPException(status_code=404, detail="Profile not found")
        pid = profile.id

    content = await file.read()
    _validate_upload(file, ALLOWED_DOC_EXTENSIONS, MAX_DOC_SIZE, content)

    ext = os.path.splitext(file.filename or "file")[1]
    safe_name = f"{uuid.uuid4()}{ext}"
    file_path = os.path.join(UPLOAD_DIR, safe_name)

    with open(file_path, "wb") as f:
        f.write(content)

    doc = Document(
        id=str(uuid.uuid4()),
        patient_id=pid,
        uploaded_by=current_user.id,
        category=category,
        file_name=file.filename or "file",
        file_url=f"/uploads/{safe_name}",
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)

    return {
        "id": doc.id,
        "file_name": doc.file_name,
        "category": doc.category,
        "file_url": doc.file_url,
        "upload_date": doc.upload_date.isoformat() if doc.upload_date else None,
    }


@router.get("/documents")
def get_documents(
    patient_id: str = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if patient_id:
        assert_patient_profile_access(current_user, patient_id, db)
        pid = patient_id
    else:
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile:
            return []
        pid = profile.id

    docs = (
        db.query(Document)
        .filter(Document.patient_id == pid)
        .order_by(Document.upload_date.desc())
        .all()
    )
    return [
        {
            "id": d.id,
            "file_name": d.file_name,
            "category": d.category,
            "file_url": d.file_url,
            "upload_date": d.upload_date.isoformat() if d.upload_date else None,
            "uploaded_by": d.uploaded_by,
        }
        for d in docs
    ]


@router.delete("/documents/{doc_id}")
def delete_document(
    doc_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    doc = db.query(Document).filter(Document.id == doc_id).first()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")

    assert_document_access(current_user, doc, db, write=True)

    file_path = os.path.join(UPLOAD_DIR, os.path.basename(doc.file_url))
    if os.path.exists(file_path):
        os.remove(file_path)

    db.delete(doc)
    db.commit()
    return {"message": "Document deleted"}


def _doctor_display_name(db: Session, doctor_id: str) -> str:
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if doctor:
        doc_profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
        if doc_profile:
            return f"Dr. {doc_profile.first_name or ''} {doc_profile.last_name or ''}".strip()
    return "Doctor"


def _profile_display_name(db: Session, profile_id: str) -> str:
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if profile:
        return f"{profile.first_name or ''} {profile.last_name or ''}".strip()
    return "Staff"


@router.get("/my-care-summary")
def my_care_summary(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role not in ("patient", "admin", "doctor"):
        raise HTTPException(status_code=403, detail="Not authorized")

    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    appointments = (
        db.query(Appointment)
        .filter(Appointment.patient_id == profile.id)
        .order_by(Appointment.date.desc(), Appointment.time_slot.desc())
        .all()
    )

    visit_count = sum(1 for a in appointments if a.status == "completed")

    consultation_rows = []
    for apt in appointments:
        payment = db.query(Payment).filter(Payment.appointment_id == apt.id).first()
        receptionist_name = (
            _profile_display_name(db, payment.receptionist_id)
            if payment and payment.receptionist_id
            else None
        )
        record = db.query(MedicalRecord).filter(MedicalRecord.appointment_id == apt.id).first()

        apt_sensors = []
        if apt.date:
            day_start = datetime.combine(apt.date, datetime.min.time())
            day_end = day_start + timedelta(days=1)
            apt_sensors = (
                db.query(SensorData)
                .filter(
                    SensorData.patient_id == profile.id,
                    SensorData.timestamp >= day_start,
                    SensorData.timestamp < day_end,
                )
                .order_by(SensorData.timestamp.desc())
                .all()
            )
        latest_sensor = apt_sensors[0] if apt_sensors else None

        consultation_rows.append({
            "appointment_id": apt.id,
            "date": apt.date.isoformat() if apt.date else None,
            "time_slot": apt.time_slot,
            "status": apt.status,
            "doctor_name": _doctor_display_name(db, apt.doctor_id),
            "receptionist_name": receptionist_name,
            "notes": apt.notes,
            "diagnosis": record.diagnosis if record else None,
            "record_notes": record.notes if record else None,
            "chief_complaint": record.chief_complaint if record else None,
            "payment_amount": payment.amount if payment else None,
            "payment_method": payment.payment_method if payment else None,
            "payment_status": payment.payment_status if payment else "unpaid",
            "sensor_heart_rate": latest_sensor.heart_rate if latest_sensor else None,
            "sensor_temperature": latest_sensor.temperature if latest_sensor else None,
            "sensor_ecg": latest_sensor.ecg if latest_sensor else None,
            "sensor_emg": latest_sensor.emg if latest_sensor else None,
            "sensor_gsr": latest_sensor.gsr if latest_sensor else None,
            "sensor_timestamp": latest_sensor.timestamp.isoformat() if latest_sensor and latest_sensor.timestamp else None,
        })

    records = (
        db.query(MedicalRecord)
        .filter(MedicalRecord.patient_id == profile.id, MedicalRecord.is_active == True)
        .order_by(MedicalRecord.created_at.desc())
        .all()
    )
    record_rows = []
    for r in records:
        prescriptions = db.query(Prescription).filter(
            Prescription.medical_record_id == r.id,
            Prescription.status == "active",
        ).all()
        meds = []
        for rx in prescriptions:
            items = db.query(PrescriptionItem).filter(PrescriptionItem.prescription_id == rx.id).all()
            for item in items:
                meds.append({
                    "name": item.medication_name,
                    "dosage": item.dosage,
                    "frequency": item.frequency,
                    "duration": item.duration,
                    "notes": item.notes,
                })
        record_rows.append({
            "id": r.id,
            "date": r.created_at.isoformat() if r.created_at else None,
            "doctor_name": _doctor_display_name(db, r.doctor_id),
            "diagnosis": r.diagnosis,
            "chief_complaint": r.chief_complaint,
            "treatment_plan": r.treatment_plan,
            "notes": r.notes,
            "severity": r.severity,
            "medications": meds,
        })

    sensors = (
        db.query(SensorData)
        .filter(SensorData.patient_id == profile.id)
        .order_by(SensorData.timestamp.desc())
        .limit(50)
        .all()
    )
    sensor_rows = [
        {
            "id": s.id,
            "heart_rate": s.heart_rate,
            "temperature": s.temperature,
            "ecg": s.ecg or 0,
            "emg": s.emg or 0,
            "gsr": s.gsr or 0,
            "waveforms": s.waveforms,
            "timestamp": s.timestamp.isoformat() if s.timestamp else None,
        }
        for s in sensors
    ]

    active_meds = []
    active_rxs = (
        db.query(Prescription)
        .join(MedicalRecord, Prescription.medical_record_id == MedicalRecord.id)
        .filter(MedicalRecord.patient_id == profile.id, Prescription.status == "active")
        .all()
    )
    for rx in active_rxs:
        items = db.query(PrescriptionItem).filter(PrescriptionItem.prescription_id == rx.id).all()
        for item in items:
            active_meds.append(item.medication_name)

    return {
        "patient_name": f"{profile.first_name or ''} {profile.last_name or ''}".strip(),
        "visit_count": visit_count,
        "self_reported_conditions": profile.existing_conditions,
        "medications_on_file": active_meds if active_meds else None,
        "allergies": profile.allergies,
        "chronic_diseases": profile.chronic_diseases,
        "consultations": consultation_rows,
        "medical_records": record_rows,
        "sensor_readings": sensor_rows,
    }
