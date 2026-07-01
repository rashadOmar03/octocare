"""Central audit logging for traceability."""
from sqlalchemy.orm import Session

from models import AuditLog, User, Profile


def log_audit(
    db: Session,
    user_id: str | None,
    action: str,
    entity_type: str,
    entity_id: str,
    details: str | None = None,
) -> None:
    db.add(
        AuditLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            details=details,
        )
    )


def staff_display_name(db: Session, user_id: str | None) -> str:
    if not user_id:
        return "System"
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        return user_id[:8]
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if profile:
        name = f"{profile.first_name or ''} {profile.last_name or ''}".strip()
        if name:
            return f"{name} ({user.role})"
    return f"{user.email} ({user.role})"
