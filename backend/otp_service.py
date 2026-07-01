import random
import uuid
from datetime import datetime, timedelta

from fastapi import BackgroundTasks, HTTPException
from sqlalchemy.orm import Session

from auth import hash_password, verify_password
from database import SessionLocal
from email_service import send_otp_email
from models import EmailOTP


def _generate_code() -> str:
    return f"{random.randint(100000, 999999)}"


def _send_otp_email_task(email: str, code: str, purpose: str) -> None:
    db = SessionLocal()
    try:
        send_otp_email(db, email, code, purpose)
    except Exception as exc:
        print(
            f"[Smart Clinic OTP] WARNING: email send failed but OTP is still valid. "
            f"User can enter code {code} for {email}. Error: {exc}",
            flush=True,
        )
    finally:
        db.close()


def create_and_send_otp(
    db: Session,
    email: str,
    purpose: str,
    background_tasks: BackgroundTasks | None = None,
) -> None:
    normalized = email.lower().strip()
    db.query(EmailOTP).filter(
        EmailOTP.email == normalized,
        EmailOTP.purpose == purpose,
        EmailOTP.used.is_(False),
    ).update({"used": True})

    code = _generate_code()
    otp = EmailOTP(
        id=str(uuid.uuid4()),
        email=normalized,
        code_hash=hash_password(code),
        purpose=purpose,
        expires_at=datetime.utcnow() + timedelta(minutes=10),
        used=False,
    )
    db.add(otp)
    db.commit()

    print(
        f"\n[Smart Clinic OTP] purpose={purpose} email={normalized} code={code} "
        f"(this is the actual code, also sent by email)\n",
        flush=True,
    )

    if background_tasks is not None:
        background_tasks.add_task(_send_otp_email_task, normalized, code, purpose)
        return

    try:
        send_otp_email(db, normalized, code, purpose)
    except Exception as exc:
        print(
            f"[Smart Clinic OTP] WARNING: email send failed but OTP is still valid. "
            f"User can enter code {code} for {normalized}. Error: {exc}",
            flush=True,
        )


def verify_otp(db: Session, email: str, purpose: str, code: str) -> bool:
    otp = (
        db.query(EmailOTP)
        .filter(
            EmailOTP.email == email.lower().strip(),
            EmailOTP.purpose == purpose,
            EmailOTP.used.is_(False),
            EmailOTP.expires_at > datetime.utcnow(),
        )
        .order_by(EmailOTP.created_at.desc())
        .first()
    )
    if not otp or not verify_password(code.strip(), otp.code_hash):
        return False
    otp.used = True
    db.commit()
    return True
