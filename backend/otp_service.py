import random
import uuid
from datetime import datetime, timedelta

from fastapi import BackgroundTasks
from sqlalchemy.orm import Session

from auth import hash_password, verify_password
from email_service import send_otp_email_async
from models import EmailOTP


def _generate_code() -> str:
    return f"{random.randint(100000, 999999)}"


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

    send_otp_email_async(normalized, code, purpose)


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
