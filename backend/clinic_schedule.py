"""Clinic working days and doctor schedule helpers.

day_of_week uses Python date.weekday(): Monday=0 .. Sunday=6.
Default clinic week: Saturday through Thursday (Friday closed).
"""

from __future__ import annotations

from datetime import date

from sqlalchemy.orm import Session

from models import ClinicSettings, Doctor, DoctorSchedule

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
