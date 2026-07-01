import random
import uuid
from datetime import datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from auth import hash_password, verify_password
from email_service import send_otp_email
from models import EmailOTP


def _generate_code() -> str:
    return f"{random.randint(100000, 999999)}"


def create_and_send_otp(db: Session, email: str, purpose: str) -> None:
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

    print(
        f"\n[Smart Clinic OTP] purpose={purpose} email={normalized} code={code} "
        f"(this is the actual code, also sent by email)\n",
        flush=True,
    )

    try:
        send_otp_email(db, normalized, code, purpose)
    except Exception as exc:
        db.commit()
        print(
            f"[Smart Clinic OTP] WARNING: email send failed but OTP is still valid. "
            f"User can enter code {code} for {normalized}. Error: {exc}",
            flush=True,
        )
        return

    db.commit()


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
