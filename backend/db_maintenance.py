"""Database maintenance: drop deprecated columns and clean invalid legacy rows."""
from __future__ import annotations

import sqlite3
from pathlib import Path

from sqlalchemy.orm import Session

from models import Appointment, Payment, MedicalRecord, Prescription, PrescriptionItem


def _sqlite_db_path() -> Path | None:
    from database import engine

    if not str(engine.url).startswith("sqlite"):
        return None
    path = str(engine.url).replace("sqlite:///", "")
    db_file = Path(path)
    if not db_file.is_absolute():
        db_file = Path(__file__).parent / path
    return db_file if db_file.exists() else None


def drop_spo2_column() -> bool:
    """Rebuild sensor_data without spo2 (SQLite). Returns True if migration ran."""
    db_file = _sqlite_db_path()
    if not db_file:
        return False

    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(sensor_data)")
    cols = {row[1] for row in cur.fetchall()}
    if "spo2" not in cols:
        conn.close()
        return False

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS sensor_data_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            patient_id VARCHAR NOT NULL,
            heart_rate INTEGER NOT NULL,
            temperature REAL NOT NULL,
            ecg REAL DEFAULT 0,
            emg REAL DEFAULT 0,
            gsr REAL DEFAULT 0,
            waveforms TEXT,
            timestamp DATETIME
        )
        """
    )
    cur.execute(
        """
        INSERT INTO sensor_data_new (id, patient_id, heart_rate, temperature, ecg, emg, gsr, waveforms, timestamp)
        SELECT id, patient_id, heart_rate, temperature,
               COALESCE(ecg, 0), COALESCE(emg, 0), COALESCE(gsr, 0), waveforms, timestamp
        FROM sensor_data
        """
    )
    cur.execute("DROP TABLE sensor_data")
    cur.execute("ALTER TABLE sensor_data_new RENAME TO sensor_data")
    conn.commit()
    conn.close()
    print("[Octocare Clinic] Removed spo2 column from sensor_data")
    return True


def _appointment_is_paid(db: Session, appointment_id: str) -> bool:
    payment = (
        db.query(Payment)
        .filter(Payment.appointment_id == appointment_id, Payment.payment_status == "paid")
        .first()
    )
    return payment is not None


def clean_legacy_invalid_data(db: Session) -> dict[str, int]:
    """
    Remove invalid legacy workflow state:
    - Completed visits without payment -> cancelled + records removed
    - Completed visits without medical record -> cancelled
    - Arrived without payment -> confirmed, queue cleared
    - Inactive orphaned AI suggestions left as-is
    """
    stats = {
        "completed_unpaid_cancelled": 0,
        "completed_no_record_cancelled": 0,
        "arrived_unpaid_reset": 0,
        "records_deleted": 0,
    }

    completed = db.query(Appointment).filter(Appointment.status == "completed").all()
    for apt in completed:
        paid = _appointment_is_paid(db, apt.id)
        record = db.query(MedicalRecord).filter(MedicalRecord.appointment_id == apt.id).first()
        if not paid:
            if record:
                for rx in db.query(Prescription).filter(Prescription.medical_record_id == record.id).all():
                    db.query(PrescriptionItem).filter(PrescriptionItem.prescription_id == rx.id).delete()
                    db.delete(rx)
                db.delete(record)
                stats["records_deleted"] += 1
            apt.status = "cancelled"
            apt.queue_number = None
            note = "[Legacy cleaned: completed without payment]"
            apt.notes = f"{apt.notes}\n{note}" if apt.notes else note
            stats["completed_unpaid_cancelled"] += 1
        elif not record:
            apt.status = "cancelled"
            apt.queue_number = None
            note = "[Legacy cleaned: completed without consultation record]"
            apt.notes = f"{apt.notes}\n{note}" if apt.notes else note
            stats["completed_no_record_cancelled"] += 1

    arrived = db.query(Appointment).filter(Appointment.status == "arrived").all()
    for apt in arrived:
        if not _appointment_is_paid(db, apt.id):
            apt.status = "confirmed"
            apt.queue_number = None
            note = "[Legacy cleaned: arrived without payment]"
            apt.notes = f"{apt.notes}\n{note}" if apt.notes else note
            stats["arrived_unpaid_reset"] += 1

    db.commit()
    total = sum(stats.values())
    if total:
        print(f"[Octocare Clinic] Legacy cleanup: {stats}")
    return stats


def run_startup_maintenance(db: Session) -> None:
    drop_spo2_column()
    clean_legacy_invalid_data(db)
    from clinic_schedule import ensure_clinic_working_days, ensure_doctor_schedules

    try:
        if ensure_clinic_working_days(db):
            print("[Octocare Clinic] Clinic working days updated to Sat–Thu")
    except Exception as exc:
        db.rollback()
        print(f"[Octocare Clinic] Working days sync warning: {exc}")

    try:
        changed = ensure_doctor_schedules(db)
        if changed:
            print(f"[Octocare Clinic] Doctor schedules synced ({changed} rows)")
    except Exception as exc:
        db.rollback()
        print(f"[Octocare Clinic] Schedule sync warning: {exc}")
    from routers.records import sync_prescriptions_from_records
    from routers.prescriptions import expire_prescriptions

    try:
        sync_prescriptions_from_records(db)
        expire_prescriptions(db)
    except Exception as exc:
        db.rollback()
        print(f"[Octocare Clinic] Prescription sync warning: {exc}")
