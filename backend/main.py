import os
import re
import uuid
from datetime import date
from pathlib import Path

from dotenv import load_dotenv
load_dotenv()

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, HTMLResponse, Response
from sqlalchemy.orm import Session

from database import engine, SessionLocal, Base, get_db
from models import (
    User, Profile, Specialty, Doctor, DoctorSchedule, ClinicSettings,
)
from auth import hash_password

from routers.auth_router import router as auth_router
from routers.patients import router as patients_router
from routers.appointments import router as appointments_router
from routers.records import router as records_router
from routers.prescriptions import router as prescriptions_router
from routers.ai_router import router as ai_router
from routers.sensors import router as sensors_router
from routers.sensor_live import router as sensor_live_router
from routers.reports import router as reports_router
from routers.admin import router as admin_router
from routers.receptionist import router as receptionist_router
from routers.doctors import router as doctors_router
from routers.reviews import router as reviews_router

app = FastAPI(title="Smart Clinic Management System", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router, prefix="/auth", tags=["Authentication"])
app.include_router(patients_router, prefix="/patients", tags=["Patients"])
app.include_router(appointments_router, prefix="/appointments", tags=["Appointments"])
app.include_router(records_router, prefix="/records", tags=["Medical Records"])
app.include_router(prescriptions_router, prefix="/prescriptions", tags=["Prescriptions"])
app.include_router(ai_router, prefix="/ai", tags=["AI"])
app.include_router(sensors_router, prefix="/sensors", tags=["Sensors"])
app.include_router(sensor_live_router, prefix="/sensors", tags=["Sensors"])
app.include_router(reports_router, prefix="/reports", tags=["Reports"])
app.include_router(admin_router, prefix="/admin", tags=["Admin"])
app.include_router(receptionist_router, prefix="/receptionist", tags=["Receptionist"])
app.include_router(doctors_router, prefix="/doctors", tags=["Doctors"])
app.include_router(reviews_router, prefix="/reviews", tags=["Reviews"])


@app.on_event("startup")
def on_startup():
    _migrate_sensor_columns()
    _migrate_auth_columns()
    _migrate_payment_columns()
    _migrate_medical_record_columns()
    _migrate_prescription_columns()
    Base.metadata.create_all(bind=engine)
    seed_data()
    _sync_admin_account()
    _normalize_user_emails()
    _repair_appointments()
    _run_db_maintenance()
    _log_smtp_status()


def _run_db_maintenance():
    from db_maintenance import run_startup_maintenance

    db = SessionLocal()
    try:
        run_startup_maintenance(db)
    except Exception as exc:
        db.rollback()
        print(f"[Smart Clinic] DB maintenance warning: {exc}")
    finally:
        db.close()


def _repair_appointments():
    from appointment_rules import repair_wrongly_cancelled_appointments
    db = SessionLocal()
    try:
        n = repair_wrongly_cancelled_appointments(db)
        if n:
            print(f"[Smart Clinic] Restored {n} wrongly cancelled appointment(s)")
    except Exception:
        db.rollback()
    finally:
        db.close()


def _log_smtp_status():
    from email_service import email_provider_status

    status = email_provider_status()
    if status["configured"]:
        print(
            f"[Smart Clinic] Email ready via {status['provider']} "
            f"(from {status['from_email']})"
        )
    else:
        print("[Smart Clinic] WARNING: Email is NOT configured — OTP emails will NOT be sent.")
        print("[Smart Clinic] Add BREVO_API_KEY to Railway (recommended) or SMTP settings.")


def _normalize_user_emails():
    """Lowercase stored emails so OTP lookup always matches."""
    db: Session = SessionLocal()
    try:
        users = db.query(User).all()
        changed = False
        for user in users:
            normalized = user.email.lower().strip()
            if user.email != normalized:
                user.email = normalized
                changed = True
        if changed:
            db.commit()
    except Exception:
        db.rollback()
    finally:
        db.close()


ADMIN_EMAIL = "clinova.clinic@gmail.com"
ADMIN_PASSWORD = "admin1234"


def _sync_admin_account():
    """Keep main admin + clinic sender email in sync (also updates existing DBs).
    Does NOT overwrite the admin password — only sets it on first creation via seed_data().
    """
    db: Session = SessionLocal()
    try:
        admin = db.query(User).filter(User.role == "admin").first()
        if admin:
            admin.email = ADMIN_EMAIL
            admin.email_verified = True
            admin.is_active = True

        settings = db.query(ClinicSettings).first()
        if settings:
            settings.email = ADMIN_EMAIL
        db.commit()
    except Exception:
        db.rollback()
    finally:
        db.close()


def seed_data():
    db: Session = SessionLocal()
    try:
        user_count = db.query(User).count()
        if user_count > 0:
            return

        # --- Admin ---
        admin_id = str(uuid.uuid4())
        admin_user = User(
            id=admin_id,
            email=ADMIN_EMAIL,
            password_hash=hash_password(ADMIN_PASSWORD),
            role="admin",
            is_active=True,
            email_verified=True,
        )
        db.add(admin_user)

        admin_profile_id = str(uuid.uuid4())
        admin_profile = Profile(
            id=admin_profile_id,
            user_id=admin_id,
            first_name="System",
            last_name="Admin",
            dob=date(1990, 1, 1),
            gender="male",
            phone="0000000000",
            address="Clinic HQ",
            emergency_contact_name="N/A",
            emergency_contact_phone="N/A",
            blood_type="O+",
            is_complete=True,
        )
        db.add(admin_profile)

        # --- Specialties ---
        specialty_names = [
            ("Cardiology", "Heart and cardiovascular system"),
            ("Dermatology", "Skin, hair, and nail conditions"),
            ("Pediatrics", "Medical care for infants and children"),
            ("Orthopedics", "Musculoskeletal system"),
            ("Neurology", "Brain and nervous system disorders"),
            ("General Practice", "Primary and general healthcare"),
            ("Ophthalmology", "Eye and vision care"),
            ("ENT", "Ear, nose, and throat conditions"),
        ]
        specialty_map = {}
        for name, desc in specialty_names:
            s = Specialty(name=name, description=desc)
            db.add(s)
            db.flush()
            specialty_map[name] = s.id

        # --- Doctor 1 ---
        doc1_user_id = str(uuid.uuid4())
        doc1_user = User(
            id=doc1_user_id,
            email="dr.ahmed@clinic.com",
            password_hash=hash_password("doctor123"),
            role="doctor",
            is_active=True,
            email_verified=True,
        )
        db.add(doc1_user)

        doc1_profile_id = str(uuid.uuid4())
        doc1_profile = Profile(
            id=doc1_profile_id,
            user_id=doc1_user_id,
            first_name="Ahmed",
            last_name="Hassan",
            dob=date(1980, 5, 15),
            gender="male",
            phone="0501234567",
            address="Riyadh, Saudi Arabia",
            emergency_contact_name="Sara Hassan",
            emergency_contact_phone="0509876543",
            blood_type="A+",
            is_complete=True,
        )
        db.add(doc1_profile)

        doc1_id = str(uuid.uuid4())
        doc1 = Doctor(
            id=doc1_id,
            profile_id=doc1_profile_id,
            specialty_id=specialty_map["Cardiology"],
            qualifications="MD, FACC",
            bio="Senior Cardiologist with 15 years of experience",
        )
        db.add(doc1)

        for day in range(6):
            db.add(DoctorSchedule(
                doctor_id=doc1_id, day_of_week=day,
                start_time="09:00", end_time="17:00", is_available=True,
            ))

        # --- Doctor 2 ---
        doc2_user_id = str(uuid.uuid4())
        doc2_user = User(
            id=doc2_user_id,
            email="dr.fatima@clinic.com",
            password_hash=hash_password("doctor123"),
            role="doctor",
            is_active=True,
            email_verified=True,
        )
        db.add(doc2_user)

        doc2_profile_id = str(uuid.uuid4())
        doc2_profile = Profile(
            id=doc2_profile_id,
            user_id=doc2_user_id,
            first_name="Fatima",
            last_name="Al-Rashid",
            dob=date(1985, 8, 20),
            gender="female",
            phone="0507654321",
            address="Jeddah, Saudi Arabia",
            emergency_contact_name="Omar Al-Rashid",
            emergency_contact_phone="0501112233",
            blood_type="B+",
            is_complete=True,
        )
        db.add(doc2_profile)

        doc2_id = str(uuid.uuid4())
        doc2 = Doctor(
            id=doc2_id,
            profile_id=doc2_profile_id,
            specialty_id=specialty_map["Pediatrics"],
            qualifications="MD, Pediatrics Board Certified",
            bio="Pediatric specialist with 10 years of experience",
        )
        db.add(doc2)

        for day in range(6):
            db.add(DoctorSchedule(
                doctor_id=doc2_id, day_of_week=day,
                start_time="08:00", end_time="16:00", is_available=True,
            ))

        # --- Receptionist ---
        rec_user_id = str(uuid.uuid4())
        rec_user = User(
            id=rec_user_id,
            email="reception@clinic.com",
            password_hash=hash_password("reception123"),
            role="receptionist",
            is_active=True,
            email_verified=True,
        )
        db.add(rec_user)

        rec_profile_id = str(uuid.uuid4())
        rec_profile = Profile(
            id=rec_profile_id,
            user_id=rec_user_id,
            first_name="Nora",
            last_name="Ali",
            dob=date(1992, 3, 10),
            gender="female",
            phone="0551234567",
            address="Riyadh, Saudi Arabia",
            emergency_contact_name="Ali Mohammed",
            emergency_contact_phone="0559876543",
            blood_type="AB+",
            is_complete=True,
        )
        db.add(rec_profile)

        # --- Clinic Settings ---
        settings = ClinicSettings(
            id=1,
            clinic_name="Smart Clinic",
            address="123 Healthcare Ave, Riyadh",
            phone="+966-11-1234567",
            email=ADMIN_EMAIL,
            default_fee=100.0,
            working_hours_start="08:00",
            working_hours_end="17:00",
            working_days="0,1,2,3,4",
            appointment_duration=30,
        )
        db.add(settings)

        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _migrate_auth_columns():
    if not str(engine.url).startswith("sqlite"):
        return
    import sqlite3
    from pathlib import Path

    db_file = Path(__file__).parent / "clinic.db"
    if not db_file.exists():
        return
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(users)")
    cols = {row[1] for row in cur.fetchall()}
    if "email_verified" not in cols:
        cur.execute("ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT 1")
        cur.execute("UPDATE users SET email_verified = 1 WHERE email_verified IS NULL")
    conn.commit()
    conn.close()


def _migrate_sensor_columns():
    """Add ecg/emg/gsr/waveforms columns to existing SQLite DBs."""
    if not str(engine.url).startswith("sqlite"):
        return
    import sqlite3
    from pathlib import Path

    db_file = Path(__file__).parent / "clinic.db"
    if not db_file.exists():
        return
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(sensor_data)")
    cols = {row[1] for row in cur.fetchall()}
    for col, typ in [("ecg", "REAL"), ("emg", "REAL"), ("gsr", "REAL"), ("waveforms", "TEXT")]:
        if col not in cols:
            if typ == "REAL":
                cur.execute(f"ALTER TABLE sensor_data ADD COLUMN {col} {typ} DEFAULT 0")
            else:
                cur.execute(f"ALTER TABLE sensor_data ADD COLUMN {col} {typ}")
    conn.commit()
    conn.close()


def _migrate_payment_columns():
    if not str(engine.url).startswith("sqlite"):
        return
    import sqlite3
    from pathlib import Path

    db_file = Path(__file__).parent / "clinic.db"
    if not db_file.exists():
        return
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(payments)")
    cols = {row[1] for row in cur.fetchall()}
    if "proof_url" not in cols:
        cur.execute("ALTER TABLE payments ADD COLUMN proof_url VARCHAR")
    if "refunded_at" not in cols:
        cur.execute("ALTER TABLE payments ADD COLUMN refunded_at DATETIME")
    if "refunded_by" not in cols:
        cur.execute("ALTER TABLE payments ADD COLUMN refunded_by VARCHAR")
    if "refund_reason" not in cols:
        cur.execute("ALTER TABLE payments ADD COLUMN refund_reason VARCHAR")
    if "refund_proof_url" not in cols:
        cur.execute("ALTER TABLE payments ADD COLUMN refund_proof_url VARCHAR")
    conn.commit()
    conn.close()


def _migrate_medical_record_columns():
    if not str(engine.url).startswith("sqlite"):
        return
    import sqlite3
    from pathlib import Path

    db_file = Path(__file__).parent / "clinic.db"
    if not db_file.exists():
        return
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(medical_records)")
    cols = {row[1] for row in cur.fetchall()}
    if "structured_data" not in cols:
        cur.execute("ALTER TABLE medical_records ADD COLUMN structured_data TEXT")
    if "is_active" not in cols:
        cur.execute("ALTER TABLE medical_records ADD COLUMN is_active BOOLEAN DEFAULT 1")
    conn.commit()
    conn.close()


def _migrate_prescription_columns():
    if not str(engine.url).startswith("sqlite"):
        return
    import sqlite3
    from pathlib import Path

    db_file = Path(__file__).parent / "clinic.db"
    if not db_file.exists():
        return
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(prescriptions)")
    cols = {row[1] for row in cur.fetchall()}
    if "active_until" not in cols:
        cur.execute("ALTER TABLE prescriptions ADD COLUMN active_until DATETIME")
    conn.commit()
    conn.close()


WEB_BUILD = Path(__file__).parent / "web"
if not WEB_BUILD.exists():
    WEB_BUILD = Path(__file__).parent.parent / "smart_clinic" / "build" / "web"


def _web_build_id() -> str:
    """Changes whenever `flutter build web` produces a new main.dart.js."""
    main_js = WEB_BUILD / "main.dart.js"
    if main_js.is_file():
        return str(int(main_js.stat().st_mtime))
    return "0"


def _no_cache_headers() -> dict[str, str]:
    return {
        "Cache-Control": "no-cache, no-store, must-revalidate",
        "Pragma": "no-cache",
        "Expires": "0",
        "CDN-Cache-Control": "no-store",
    }


def _patch_flutter_bootstrap(source: str, build_id: str) -> str:
    """Disable Flutter service worker and cache-bust main.dart.js."""
    source = re.sub(
        r"_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{[^}]*\}\s*\}\);",
        "_flutter.loader.load({});",
        source,
        count=1,
    )
    return source.replace(
        '"mainJsPath":"main.dart.js"',
        f'"mainJsPath":"main.dart.js?v={build_id}"',
    )


def _patch_index_html(source: str, build_id: str) -> str:
    if "__BUILD_ID__" in source:
        return source.replace("__BUILD_ID__", build_id)
    source = re.sub(
        r"window\.__CLINOVA_BUILD__\s*=\s*'[^']*'",
        f"window.__CLINOVA_BUILD__ = '{build_id}'",
        source,
    )
    return re.sub(
        r"flutter_bootstrap\.js\?v=[^'\"]+",
        f"flutter_bootstrap.js?v={build_id}",
        source,
    )


UPLOADS_DIR = Path(__file__).parent / "uploads"
UPLOADS_DIR.mkdir(exist_ok=True)

from auth import get_current_user as _get_current_user

@app.get("/uploads/{filename}")
def serve_upload(
    filename: str,
    current_user=Depends(_get_current_user),
):
    """Authenticated file serving for uploads."""
    safe_name = Path(filename).name
    file_path = UPLOADS_DIR / safe_name
    if not file_path.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(str(file_path))

@app.get("/api")
def api_root():
    return {"message": "Smart Clinic API"}


@app.get("/api/email-status")
def email_status():
    from email_service import email_provider_status

    return email_provider_status()


@app.post("/api/test-email")
def test_email_send(db: Session = Depends(get_db)):
    """Send a test email to EMAIL_FROM — confirms Brevo/SMTP works."""
    from email_service import get_sender_info, send_email

    sender, clinic_name = get_sender_info(db)
    try:
        send_email(
            db,
            sender,
            f"{clinic_name} — test email",
            "If you received this, OTP email delivery is working.",
            html_body="<p>If you received this, <strong>OTP email delivery is working</strong>.</p>",
        )
        return {"ok": True, "sent_to": sender, "message": "Check the inbox for your sender email."}
    except Exception as exc:
        return {"ok": False, "sent_to": sender, "error": str(exc)}

if WEB_BUILD.exists():
    app.mount("/static", StaticFiles(directory=str(WEB_BUILD)), name="flutter_static")

    _NO_CACHE_FILES = {
        "index.html",
        "flutter_bootstrap.js",
        "flutter_service_worker.js",
        "main.dart.js",
        "AssetManifest.bin.json",
        "FontManifest.json",
        "version.json",
    }

    _API_PREFIXES = (
        "auth/", "patients/", "appointments/", "records/", "prescriptions/",
        "ai/", "sensors/", "reports/", "admin/", "receptionist/", "doctors/",
        "reviews/", "uploads/", "api/", "docs", "openapi.json", "redoc",
    )

    @app.get("/{full_path:path}")
    async def serve_flutter(request: Request, full_path: str):
        clean_path = full_path.split("?", 1)[0]
        if clean_path.startswith(_API_PREFIXES) or clean_path in ("docs", "openapi.json", "redoc"):
            raise HTTPException(status_code=404, detail="Not found")
        file_path = WEB_BUILD / clean_path
        is_fallback = not file_path.is_file()
        target = WEB_BUILD / "index.html" if is_fallback else file_path
        no_cache = (
            target.name in _NO_CACHE_FILES
            or target.suffix in {".js", ".json"}
            or is_fallback
        )
        headers = _no_cache_headers() if no_cache else {}
        build_id = _web_build_id()

        if target.name == "index.html":
            html = _patch_index_html(
                (WEB_BUILD / "index.html").read_text(encoding="utf-8"),
                build_id,
            )
            return HTMLResponse(html, headers=headers)

        if target.name == "flutter_bootstrap.js":
            body = _patch_flutter_bootstrap(
                target.read_text(encoding="utf-8"),
                build_id,
            )
            return Response(body, media_type="application/javascript", headers=headers)

        return FileResponse(str(target), headers=headers)
