import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import or_

from database import get_db
from models import User, Profile, EmailOTP, Notification, AIConversation
from schemas import (
    UserCreate, UserLogin, TokenResponse, RefreshTokenRequest,
    ChangePasswordRequest, ForgotPasswordRequest, ForgotPasswordResponse,
    RegisterPendingResponse, VerifyEmailRequest, ResendOtpRequest,
    ResetPasswordRequest, MessageResponse,
)
from auth import (
    hash_password, verify_password, create_access_token,
    create_refresh_token, verify_token, get_current_user,
)
from otp_service import create_and_send_otp, verify_otp
from email_service import send_password_changed_email
from profile_utils import profile_personal_info_complete

router = APIRouter()


def _norm_email(email: str) -> str:
    return email.lower().strip()


def _find_user_by_email(db: Session, email: str) -> User | None:
    normalized = _norm_email(email)
    return db.query(User).filter(User.email == normalized).first()


def _purge_unverified_account(db: Session, user: User) -> None:
    """Remove a never-verified signup so email/phone can be reused."""
    if user.email_verified:
        return
    old_email = user.email
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    db.query(EmailOTP).filter(EmailOTP.email == old_email).delete(synchronize_session=False)
    db.query(Notification).filter(Notification.user_id == user.id).delete(synchronize_session=False)
    db.query(AIConversation).filter(AIConversation.user_id == user.id).delete(synchronize_session=False)
    if profile:
        db.delete(profile)
    db.delete(user)
    db.flush()


def _upsert_signup_profile(db: Session, user: User, data: UserCreate) -> None:
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if not profile and not (data.first_name or data.last_name):
        return
    if not profile:
        profile = Profile(
            id=str(uuid.uuid4()),
            user_id=user.id,
            first_name=data.first_name or "",
            middle_name=data.middle_name,
            last_name=data.last_name or "",
            phone=data.phone,
            is_complete=False,
        )
        db.add(profile)
    else:
        if data.first_name:
            profile.first_name = data.first_name
        profile.middle_name = data.middle_name
        if data.last_name:
            profile.last_name = data.last_name
        profile.phone = data.phone


def _pending_register_response(
    db: Session,
    email: str,
    background_tasks: BackgroundTasks,
    *,
    created: bool,
    email_sent: bool | None = None,
) -> RegisterPendingResponse:
    if email_sent is None:
        email_sent = create_and_send_otp(db, email, "signup", background_tasks)
    if created:
        message = (
            "Account created. Enter the verification code sent to your email."
            if email_sent
            else "Account created but email delivery failed. Tap Resend code or check Railway logs."
        )
    else:
        message = (
            "Verification code sent to your email."
            if email_sent
            else "Account updated but email could not be sent. Use Resend code or contact support."
        )
    return RegisterPendingResponse(message=message, email=email, email_sent=email_sent)


def _token_response(user: User, profile: Profile | None = None) -> TokenResponse:
    access_token = create_access_token({"sub": user.id, "role": user.role})
    refresh_token = create_refresh_token({"sub": user.id, "role": user.role})
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        role=user.role,
        email=user.email,
        must_change_password=user.must_change_password,
        first_name=profile.first_name if profile else None,
        last_name=profile.last_name if profile else None,
        full_name=(
            f"{profile.first_name} {profile.last_name}".strip()
            if profile
            else user.email
        ),
        profile_complete=profile_personal_info_complete(profile),
        photo_url=profile.photo_url if profile else None,
    )


@router.post("/register", response_model=RegisterPendingResponse, status_code=status.HTTP_201_CREATED)
def register(data: UserCreate, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    email = _norm_email(data.email)
    existing = _find_user_by_email(db, email)
    if existing:
        if not existing.email_verified:
            if data.phone:
                phone_conflict = db.query(User).filter(User.phone == data.phone).first()
                if phone_conflict and phone_conflict.id != existing.id:
                    if phone_conflict.email_verified:
                        raise HTTPException(status_code=400, detail="Phone number already registered")
                    _purge_unverified_account(db, phone_conflict)
                existing.phone = data.phone
            existing.password_hash = hash_password(data.password)
            _upsert_signup_profile(db, existing, data)
            db.commit()
            return _pending_register_response(db, email, background_tasks, created=False)
        raise HTTPException(status_code=400, detail="Email already registered")

    phone_user: User | None = None
    if data.phone:
        phone_user = db.query(User).filter(User.phone == data.phone).first()
        if phone_user:
            if phone_user.email_verified:
                raise HTTPException(status_code=400, detail="Phone number already registered")
            email_conflict = _find_user_by_email(db, email)
            if email_conflict and email_conflict.id != phone_user.id:
                if email_conflict.email_verified:
                    raise HTTPException(status_code=400, detail="Email already registered")
                _purge_unverified_account(db, email_conflict)
            # Unverified signup with wrong email — update account instead of blocking the phone
            phone_user.email = email
            phone_user.password_hash = hash_password(data.password)
            _upsert_signup_profile(db, phone_user, data)
            db.commit()
            return _pending_register_response(db, email, background_tasks, created=False)

    user = User(
        id=str(uuid.uuid4()),
        email=email,
        phone=data.phone,
        password_hash=hash_password(data.password),
        role="patient",
        email_verified=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    _upsert_signup_profile(db, user, data)
    db.commit()

    return _pending_register_response(db, email, background_tasks, created=True)


@router.post("/verify-email", response_model=TokenResponse)
def verify_email(data: VerifyEmailRequest, db: Session = Depends(get_db)):
    email = _norm_email(data.email)
    user = _find_user_by_email(db, email)
    if not user:
        raise HTTPException(status_code=404, detail="Account not found")

    if not verify_otp(db, email, "signup", data.otp):
        raise HTTPException(status_code=400, detail="Invalid or expired verification code")

    user.email_verified = True
    db.commit()
    db.refresh(user)
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    return _token_response(user, profile)


@router.post("/resend-otp", response_model=MessageResponse)
def resend_otp(data: ResendOtpRequest, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    if data.purpose not in ("signup", "password_reset"):
        raise HTTPException(status_code=400, detail="Invalid purpose")

    email = _norm_email(data.email)
    user = _find_user_by_email(db, email)
    if not user:
        return MessageResponse(message="If this email is registered, a new code has been sent.")

    if data.purpose == "signup" and user.email_verified:
        raise HTTPException(status_code=400, detail="Email is already verified")

    email_sent = create_and_send_otp(db, email, data.purpose, background_tasks)
    return MessageResponse(
        message=(
            "A new verification code has been sent to your email. Check your Spam or Junk folder if you do not see it within a few minutes."
            if email_sent
            else "Could not send email. Verify Brevo sender is confirmed, then try again."
        ),
    )


@router.post("/login", response_model=TokenResponse)
def login(data: UserLogin, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    identifier = data.email_or_phone.strip()
    if "@" in identifier:
        identifier = _norm_email(identifier)

    user = db.query(User).filter(
        or_(User.email == identifier, User.phone == identifier)
    ).first()

    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is deactivated")

    if user.role == "patient" and not user.email_verified:
        create_and_send_otp(db, user.email, "signup", background_tasks)
        raise HTTPException(
            status_code=403,
            detail="Please verify your email first. Check your inbox (and spam) for the 6-digit code. A new code has been sent.",
        )

    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    return _token_response(user, profile)


@router.post("/refresh", response_model=TokenResponse)
def refresh_token(data: RefreshTokenRequest, db: Session = Depends(get_db)):
    payload = verify_token(data.refresh_token, expected_type="refresh")
    user_id = payload.get("sub")

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is deactivated")

    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    return _token_response(user, profile)


@router.post("/change-password")
def change_password(
    data: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not verify_password(data.actual_old_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    current_user.password_hash = hash_password(data.new_password)
    current_user.must_change_password = False
    db.commit()

    if current_user.email:
        try:
            send_password_changed_email(db, current_user.email)
        except Exception:
            pass

    return {"message": "Password changed successfully. A confirmation email has been sent."}


@router.post("/forgot-password", response_model=ForgotPasswordResponse)
def forgot_password(data: ForgotPasswordRequest, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    email = _norm_email(data.email)
    user = _find_user_by_email(db, email)
    if not user:
        raise HTTPException(
            status_code=404,
            detail="This email is not registered with us. Please sign up first.",
        )
    create_and_send_otp(db, email, "password_reset", background_tasks)
    return ForgotPasswordResponse(
        message="A reset code has been sent to your email. Check your Spam or Junk folder if you do not see it within a few minutes.",
    )


@router.post("/reset-password", response_model=MessageResponse)
def reset_password(data: ResetPasswordRequest, db: Session = Depends(get_db)):
    email = _norm_email(data.email)
    user = _find_user_by_email(db, email)
    if not user:
        raise HTTPException(status_code=400, detail="Invalid or expired reset code")

    if not verify_otp(db, email, "password_reset", data.otp):
        raise HTTPException(status_code=400, detail="Invalid or expired reset code")

    if len(data.new_password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")

    user.password_hash = hash_password(data.new_password)
    user.must_change_password = False
    db.commit()

    try:
        send_password_changed_email(db, user.email)
    except Exception:
        pass

    return MessageResponse(message="Password reset successfully. You can now sign in.")
