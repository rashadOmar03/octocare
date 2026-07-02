"""Clinic-local calendar helpers (default: Africa/Cairo for Egyptian clinics)."""

from __future__ import annotations

import os
from datetime import date, datetime
from zoneinfo import ZoneInfo

DEFAULT_CLINIC_TZ = "Africa/Cairo"


def clinic_timezone() -> ZoneInfo:
    name = os.getenv("CLINIC_TIMEZONE", DEFAULT_CLINIC_TZ).strip() or DEFAULT_CLINIC_TZ
    try:
        return ZoneInfo(name)
    except Exception:
        return ZoneInfo(DEFAULT_CLINIC_TZ)


def clinic_today() -> date:
    return datetime.now(clinic_timezone()).date()


def clinic_now() -> datetime:
    return datetime.now(clinic_timezone())
