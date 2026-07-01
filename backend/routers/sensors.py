from datetime import datetime, timedelta

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from database import get_db
from models import User, SensorData, Profile, Doctor, Appointment
from schemas import SensorDataResponse, SensorAlert
from auth import get_current_user
from appointment_rules import require_active_paid_visit_for_patient

router = APIRouter()

HEART_RATE_LOW = 50
HEART_RATE_HIGH = 120
TEMP_HIGH = 38.5


def _assert_doctor_can_read_patient_sensors(db: Session, patient_id: str, doctor_id: str) -> None:
    has_relationship = (
        db.query(Appointment.id)
        .filter(
            Appointment.patient_id == patient_id,
            Appointment.doctor_id == doctor_id,
        )
        .first()
    )
    if not has_relationship:
        raise HTTPException(
            status_code=403,
            detail="Not authorized to view this patient's sensor data",
        )


def _resolve_patient_id(
    patient_id: str,
    current_user: User,
    db: Session,
    *,
    for_upload: bool = False,
) -> str:
    if patient_id == "me":
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile:
            raise HTTPException(status_code=404, detail="Patient profile not found")
        return profile.id

    if current_user.role == "patient":
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile or profile.id != patient_id:
            raise HTTPException(status_code=403, detail="Not authorized to view this patient's data")
        return profile.id

    if current_user.role == "doctor":
        doctor = None
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if profile:
            doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
        if doctor:
            if for_upload:
                require_active_paid_visit_for_patient(db, patient_id, doctor_id=doctor.id)
            else:
                _assert_doctor_can_read_patient_sensors(db, patient_id, doctor.id)

    return patient_id


def _check_alerts(reading: SensorData) -> list[str]:
    alerts = []
    if reading.heart_rate < HEART_RATE_LOW:
        alerts.append(f"Low heart rate: {reading.heart_rate} bpm (< {HEART_RATE_LOW})")
    if reading.heart_rate > HEART_RATE_HIGH:
        alerts.append(f"High heart rate: {reading.heart_rate} bpm (> {HEART_RATE_HIGH})")
    if reading.temperature > TEMP_HIGH:
        alerts.append(f"High temperature: {reading.temperature}°C (> {TEMP_HIGH})")
    return alerts


@router.post("/upload", status_code=201)
def upload_sensor_data(
    request_body: dict = Body(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if "readings" in request_body:
        readings_data = request_body["readings"]
    else:
        readings_data = [request_body]

    if current_user.role == "doctor":
        doctor_id = None
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if profile:
            doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
            if doctor:
                doctor_id = doctor.id
        for reading_dict in readings_data:
            patient_id = reading_dict.get("patient_id")
            if not patient_id:
                raise HTTPException(status_code=400, detail="patient_id is required")
            require_active_paid_visit_for_patient(db, patient_id, doctor_id=doctor_id)
    elif current_user.role == "patient":
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile:
            raise HTTPException(status_code=404, detail="Patient profile not found")
        for reading_dict in readings_data:
            pid = reading_dict.get("patient_id")
            if pid and pid != profile.id:
                raise HTTPException(status_code=403, detail="Not authorized")
            reading_dict["patient_id"] = profile.id
    else:
        raise HTTPException(status_code=403, detail="Only doctors and patients can upload sensor data")

    results = []
    for reading_dict in readings_data:
        entry = SensorData(
            patient_id=reading_dict["patient_id"],
            heart_rate=reading_dict["heart_rate"],
            temperature=reading_dict["temperature"],
            ecg=float(reading_dict.get("ecg") or 0),
            emg=float(reading_dict.get("emg") or 0),
            gsr=float(reading_dict.get("gsr") or 0),
            waveforms=reading_dict.get("waveforms"),
        )
        db.add(entry)
        db.flush()
        results.append(entry)

    db.commit()
    for r in results:
        db.refresh(r)

    serialized = [
        {
            "id": r.id,
            "patient_id": r.patient_id,
            "heart_rate": r.heart_rate,
            "temperature": r.temperature,
            "ecg": r.ecg or 0,
            "emg": r.emg or 0,
            "gsr": r.gsr or 0,
            "waveforms": r.waveforms,
            "timestamp": r.timestamp.isoformat() if r.timestamp else None,
        }
        for r in results
    ]
    return serialized[0] if len(serialized) == 1 else serialized


@router.get("/latest/{patient_id}", response_model=SensorDataResponse)
def get_latest_reading(
    patient_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    pid = _resolve_patient_id(patient_id, current_user, db)
    reading = (
        db.query(SensorData)
        .filter(SensorData.patient_id == pid)
        .order_by(SensorData.timestamp.desc())
        .first()
    )
    if not reading:
        raise HTTPException(status_code=404, detail="No sensor data found")
    return reading


@router.get("/history/{patient_id}", response_model=list[SensorDataResponse])
def get_sensor_history(
    patient_id: str,
    period: str = Query("daily", regex="^(daily|weekly|monthly)$"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    pid = _resolve_patient_id(patient_id, current_user, db)
    now = datetime.utcnow()
    if period == "daily":
        since = now - timedelta(days=1)
    elif period == "weekly":
        since = now - timedelta(weeks=1)
    else:
        since = now - timedelta(days=30)

    readings = (
        db.query(SensorData)
        .filter(SensorData.patient_id == pid, SensorData.timestamp >= since)
        .order_by(SensorData.timestamp.desc())
        .all()
    )
    return readings


@router.get("/alerts/{patient_id}", response_model=list[SensorAlert])
def get_alerts(
    patient_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    pid = _resolve_patient_id(patient_id, current_user, db)
    readings = (
        db.query(SensorData)
        .filter(SensorData.patient_id == pid)
        .order_by(SensorData.timestamp.desc())
        .limit(100)
        .all()
    )

    alerts = []
    for reading in readings:
        reading_alerts = _check_alerts(reading)
        if reading_alerts:
            alerts.append(SensorAlert(
                reading_id=reading.id,
                patient_id=reading.patient_id,
                timestamp=reading.timestamp,
                alerts=reading_alerts,
                heart_rate=reading.heart_rate,
                temperature=reading.temperature,
            ))
    return alerts
