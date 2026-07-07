"""In-app notification helpers (all roles including admin)."""

from __future__ import annotations

import uuid

from sqlalchemy.orm import Session

from models import Doctor, Notification, Profile, User


def notify_user(db: Session, user_id: str, title: str, message: str) -> None:
    if not user_id:
        return
    db.add(
        Notification(
            id=str(uuid.uuid4()),
            user_id=user_id,
            title=title,
            message=message,
        )
    )


def notify_doctor(db: Session, doctor_id: str, title: str, message: str) -> None:
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        return
    profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
    if not profile:
        return
    notify_user(db, profile.user_id, title, message)


def notify_role_users(
    db: Session,
    role: str,
    title: str,
    message: str,
    *,
    exclude_user_id: str | None = None,
) -> None:
    query = db.query(User).filter(User.role == role, User.is_active == True)
    if exclude_user_id:
        query = query.filter(User.id != exclude_user_id)
    for user in query.all():
        notify_user(db, user.id, title, message)
