"""Shared profile completeness checks."""

from models import Profile


def _field_ok(value) -> bool:
    return value is not None and str(value).strip() not in ("", "N/A")


def field_ok(value) -> bool:
    """Public alias for profile field checks."""
    return _field_ok(value)


def profile_personal_info_complete(profile: Profile | None) -> bool:
    """True when core personal info is filled (receptionist or patient)."""
    if not profile:
        return False
    return all(
        [
            _field_ok(profile.first_name),
            _field_ok(profile.last_name),
            profile.dob is not None,
            _field_ok(profile.gender),
            _field_ok(profile.phone),
            _field_ok(profile.address),
        ]
    )
