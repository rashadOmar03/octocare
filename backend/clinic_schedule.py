"""Clinic working days and doctor schedule helpers.

day_of_week uses Python date.weekday(): Monday=0 .. Sunday=6.
Default clinic week: Saturday through Thursday (Friday closed).
"""

from __future__ import annotations

from datetime import date

from sqlalchemy.orm import Session

from models import ClinicSettings, Doctor, DoctorSchedule, DoctorTimeOff

# Sat(5), Sun(6), Mon(0), Tue(1), Wed(2), Thu(3) — Friday(4) off
DEFAULT_WORKING_DAYS: tuple[int, ...] = (5, 6, 0, 1, 2, 3)

DAY_LABELS_EN = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


def parse_working_days(raw: str | None) -> set[int]:
    if not raw or not str(raw).strip():
        return set(DEFAULT_WORKING_DAYS)
    out: set[int] = set()
    for part in str(raw).split(","):
        part = part.strip()
        if not part:
            continue
        try:
            day = int(part)
        except ValueError:
            continue
        if 0 <= day <= 6:
            out.add(day)
    return out or set(DEFAULT_WORKING_DAYS)


def working_days_label(raw: str | None, *, lang: str = "en") -> str:
    days = sorted(parse_working_days(raw))
    if lang == "ar":
        names = {
            0: "الإثنين",
            1: "الثلاثاء",
            2: "الأربعاء",
            3: "الخميس",
            4: "الجمعة",
            5: "السبت",
            6: "الأحد",
        }
        return "، ".join(names[d] for d in days)
    return ", ".join(DAY_LABELS_EN[d] for d in days)


def is_clinic_open(slot_date: date, settings: ClinicSettings | None) -> bool:
    raw = settings.working_days if settings else None
    return slot_date.weekday() in parse_working_days(raw)


# Legacy installs used Mon–Fri only (0–4) or text labels without Saturday.
_LEGACY_MON_FRI = frozenset({0, 1, 2, 3, 4})
_LEGACY_TEXT_WORKING_DAYS = frozenset({
    "Sun,Mon,Tue,Wed,Thu",
    "Mon,Tue,Wed,Thu,Fri",
    "0,1,2,3,4",
})


def ensure_clinic_working_days(db: Session) -> bool:
    """One-time upgrade for legacy Mon–Fri / text-label schedules only."""
    settings = db.query(ClinicSettings).first()
    if not settings:
        return False

    raw = (settings.working_days or "").strip()
    current = parse_working_days(raw)
    target = ",".join(str(d) for d in sorted(DEFAULT_WORKING_DAYS))

    if raw in _LEGACY_TEXT_WORKING_DAYS or current == _LEGACY_MON_FRI:
        settings.working_days = target
        db.commit()
        return True

    return False


def ensure_doctor_schedules(db: Session, doctor_ids: list[str] | None = None) -> int:
    """Ensure each doctor has schedule rows for current clinic working days."""
    settings = db.query(ClinicSettings).first()
    working = parse_working_days(settings.working_days if settings else None)
    if settings and settings.working_days != ",".join(str(d) for d in sorted(working)):
        settings.working_days = ",".join(str(d) for d in sorted(working))

    query = db.query(Doctor)
    if doctor_ids:
        query = query.filter(Doctor.id.in_(doctor_ids))
    doctors = query.all()
    changed = 0
    for doctor in doctors:
        existing = {
            row.day_of_week
            for row in db.query(DoctorSchedule).filter(DoctorSchedule.doctor_id == doctor.id).all()
        }
        start = "09:00"
        end = "17:00"
        if existing:
            sample = (
                db.query(DoctorSchedule)
                .filter(DoctorSchedule.doctor_id == doctor.id)
                .first()
            )
            if sample:
                start = sample.start_time
                end = sample.end_time
        for day in working:
            if day not in existing:
                db.add(
                    DoctorSchedule(
                        doctor_id=doctor.id,
                        day_of_week=day,
                        start_time=start,
                        end_time=end,
                        is_available=True,
                    )
                )
                changed += 1
        for day in list(existing):
            if day not in working:
                db.query(DoctorSchedule).filter(
                    DoctorSchedule.doctor_id == doctor.id,
                    DoctorSchedule.day_of_week == day,
                ).delete(synchronize_session=False)
                changed += 1
    if changed:
        db.commit()
    return changed


def get_doctor_consultation_fee(db: Session, doctor: Doctor) -> float:
    if doctor.consultation_fee is not None:
        return float(doctor.consultation_fee)
    settings = db.query(ClinicSettings).first()
    return float(settings.default_fee) if settings and settings.default_fee is not None else 0.0


def is_doctor_on_vacation(db: Session, doctor_id: str, check_date: date) -> bool:
    row = (
        db.query(DoctorTimeOff)
        .filter(
            DoctorTimeOff.doctor_id == doctor_id,
            DoctorTimeOff.start_date <= check_date,
            DoctorTimeOff.end_date >= check_date,
        )
        .first()
    )
    return row is not None


def get_doctor_vacation_on_date(db: Session, doctor_id: str, check_date: date) -> DoctorTimeOff | None:
    return (
        db.query(DoctorTimeOff)
        .filter(
            DoctorTimeOff.doctor_id == doctor_id,
            DoctorTimeOff.start_date <= check_date,
            DoctorTimeOff.end_date >= check_date,
        )
        .first()
    )


def sync_doctor_weekly_hours(
    db: Session,
    doctor_id: str,
    start_time: str,
    end_time: str,
) -> int:
    """Update start/end for all weekly schedule rows of a doctor."""
    rows = db.query(DoctorSchedule).filter(DoctorSchedule.doctor_id == doctor_id).all()
    changed = 0
    for row in rows:
        if row.start_time != start_time or row.end_time != end_time:
            row.start_time = start_time
            row.end_time = end_time
            changed += 1
    if changed:
        db.commit()
    return changed


def sync_all_doctors_hours_from_clinic(db: Session, settings: ClinicSettings) -> int:
    """Apply clinic default hours to every doctor schedule row."""
    if not settings:
        return 0
    changed = 0
    for doctor in db.query(Doctor).all():
        changed += sync_doctor_weekly_hours(
            db,
            doctor.id,
            settings.working_hours_start,
            settings.working_hours_end,
        )
    return changed


def normalize_time_hhmm(raw: str | None, *, default: str = "09:00") -> str:
    """Normalize HH:MM (also accepts H:MM)."""
    if not raw or not str(raw).strip():
        return default
    text = str(raw).strip().split()[0]
    parts = text.split(":")
    if len(parts) < 2:
        return default
    try:
        hour = int(parts[0])
        minute = int(parts[1])
    except ValueError:
        return default
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        return default
    return f"{hour:02d}:{minute:02d}"


def normalize_clinic_time_pair(
    start: str | None,
    end: str | None,
    *,
    default_start: str = "09:00",
    default_end: str = "17:00",
) -> tuple[str, str]:
    """
    Normalize clinic open/close times as 24-hour HH:MM.
    Fixes common admin input like end=4:30 meaning 4:30 PM when start=08:00.
    """
    start_norm = normalize_time_hhmm(start, default=default_start)
    end_norm = normalize_time_hhmm(end, default=default_end)
    sh, sm = map(int, start_norm.split(":"))
    eh, em = map(int, end_norm.split(":"))
    start_min = sh * 60 + sm
    end_min = eh * 60 + em
    if end_min <= start_min and eh < 12:
        eh += 12
        end_norm = f"{eh:02d}:{em:02d}"
        end_min = eh * 60 + em
    if end_min <= start_min:
        end_norm = default_end
    return start_norm, end_norm


def repair_invalid_clinic_hours(db: Session) -> int:
    """Fix clinic and doctor hours where end time is before start (e.g. 4:30 PM saved as 04:30)."""
    settings = db.query(ClinicSettings).first()
    changed = 0
    if settings:
        start, end = normalize_clinic_time_pair(
            settings.working_hours_start,
            settings.working_hours_end,
        )
        if settings.working_hours_start != start or settings.working_hours_end != end:
            settings.working_hours_start = start
            settings.working_hours_end = end
            changed += 1

    for row in db.query(DoctorSchedule).all():
        start, end = normalize_clinic_time_pair(row.start_time, row.end_time)
        if row.start_time != start or row.end_time != end:
            row.start_time = start
            row.end_time = end
            changed += 1

    if changed:
        db.commit()
    return changed


def repair_doctor_with_no_available_days(db: Session, doctor_id: str) -> bool:
    """If every clinic working day is off for a doctor, restore clinic default hours."""
    settings = db.query(ClinicSettings).first()
    working = parse_working_days(settings.working_days if settings else None)
    rows = (
        db.query(DoctorSchedule)
        .filter(
            DoctorSchedule.doctor_id == doctor_id,
            DoctorSchedule.day_of_week.in_(working),
        )
        .all()
    )
    if not rows or any(r.is_available for r in rows):
        return False
    start = normalize_time_hhmm(settings.working_hours_start if settings else None, default="09:00")
    end_default = normalize_time_hhmm(settings.working_hours_end if settings else None, default="17:00")
    start, end = normalize_clinic_time_pair(start, end_default)
    for row in rows:
        row.is_available = True
        row.start_time = start
        row.end_time = end
    db.commit()
    return True


def resolve_doctor_schedule_for_date(
    db: Session,
    doctor_id: str,
    slot_date: date,
    settings: ClinicSettings | None,
) -> tuple[DoctorSchedule | None, str | None]:
    """
    Resolve the doctor's schedule for a booking date.
    Returns (schedule, block_reason) where block_reason is one of:
    clinic_closed, vacation, doctor_day_off, or None when bookable.
    """
    if not is_clinic_open(slot_date, settings):
        return None, "clinic_closed"

    if is_doctor_on_vacation(db, doctor_id, slot_date):
        return None, "vacation"

    day = slot_date.weekday()
    row = (
        db.query(DoctorSchedule)
        .filter(
            DoctorSchedule.doctor_id == doctor_id,
            DoctorSchedule.day_of_week == day,
        )
        .first()
    )
    if row and row.is_available:
        row.start_time, row.end_time = normalize_clinic_time_pair(row.start_time, row.end_time)
        return row, None
    if row and not row.is_available:
        return None, "doctor_day_off"

    # No schedule row: treat as off-day (do not auto-create bookable hours).
    return None, "doctor_day_off"
