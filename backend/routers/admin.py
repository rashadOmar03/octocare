import uuid
from datetime import datetime, date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy import func

from database import get_db
from models import (
    User, Profile, Doctor, DoctorSchedule, DoctorTimeOff, Specialty,
    Appointment, Payment, ClinicSettings, Prescription, PrescriptionItem,
    Notification, SensorData, Document, AIConversation, MedicalRecord,
)
from routers.appointments import _notify_staff, _enrich_appointment
from routers.records import _record_response, sync_prescriptions_from_records
from routers.prescriptions import _enrich_prescription, expire_prescriptions
from routers.receptionist import _generate_temp_password, _enrich_payment
from schemas import (
    AdminDashboard, DoctorCreate, DoctorUpdate, DoctorResponse,
    SpecialtyCreate, SpecialtyResponse, ClinicSettingsUpdate, ClinicSettingsResponse,
    UserResponse, AdminUserListItem, AdminDoctorInfo, AdminCreate, AdminPatientDetailResponse,
    ChartDataPoint, ReceptionistCreate, ReceptionistUpdate, DocumentResponse, PurgePatientsRequest,
    DoctorAdminDetailResponse, DoctorSchedulesUpdate, DoctorTimeOffCreate, DoctorTimeOffResponse,
    DoctorFeeUpdate, DoctorScheduleResponse,
)
from notification_helpers import notify_doctor, notify_user, notify_role_users
from audit_service import log_audit
from patient_purge import purge_all_patients
from auth import hash_password, require_role, get_current_user

router = APIRouter()


def _display_name(profile: Profile | None, email: str) -> str:
    if profile:
        name = f"{profile.first_name or ''} {profile.last_name or ''}".strip()
        if name:
            return name
    return email


def _notify_new_user(db: Session, user_id: str, title: str, message: str) -> None:
    db.add(Notification(
        id=str(uuid.uuid4()),
        user_id=user_id,
        title=title,
        message=message,
    ))


@router.get("/dashboard", response_model=AdminDashboard)
def admin_dashboard(
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    total_patients = db.query(User).filter(User.role == "patient").count()
    total_doctors = db.query(User).filter(User.role == "doctor").count()
    total_receptionists = db.query(User).filter(User.role == "receptionist").count()
    total_appointments = db.query(Appointment).count()
    sync_prescriptions_from_records(db)
    expire_prescriptions(db)
    total_prescriptions = db.query(Prescription).count()
    total_prescription_items = db.query(PrescriptionItem).count()
    if total_prescriptions == 0 and total_prescription_items > 0:
        total_prescriptions = total_prescription_items
    pending = db.query(Appointment).filter(Appointment.status == "pending").count()
    confirmed = db.query(Appointment).filter(Appointment.status == "confirmed").count()
    arrived = db.query(Appointment).filter(Appointment.status == "arrived").count()
    completed = db.query(Appointment).filter(Appointment.status == "completed").count()
    cancelled = db.query(Appointment).filter(Appointment.status == "cancelled").count()

    paid_revenue = db.query(func.coalesce(func.sum(Payment.amount), 0.0)).filter(
        Payment.payment_status == "paid"
    ).scalar()
    refunded_revenue = db.query(func.coalesce(func.sum(Payment.amount), 0.0)).filter(
        Payment.payment_status == "refunded"
    ).scalar()
    paid_revenue_val = float(paid_revenue)
    refunded_revenue_val = float(refunded_revenue)
    revenue_val = paid_revenue_val - refunded_revenue_val
    paid_payments_count = db.query(Payment).filter(Payment.payment_status == "paid").count()
    refunded_payments_count = db.query(Payment).filter(Payment.payment_status == "refunded").count()

    chart_data = []
    today = date.today()
    for i in range(6, -1, -1):
        d = today - timedelta(days=i)
        completed_day = db.query(Appointment).filter(
            Appointment.date == d, Appointment.status == "completed"
        ).count()
        total_day = db.query(Appointment).filter(Appointment.date == d).count()
        chart_data.append({
            "label": d.strftime("%a"),
            "count": completed_day,
            "total": total_day,
        })

    status_distribution = {
        "Pending": pending,
        "Confirmed": confirmed,
        "Arrived": arrived,
        "Completed": completed,
        "Cancelled": cancelled,
    }

    return AdminDashboard(
        total_patients=total_patients,
        total_doctors=total_doctors,
        total_receptionists=total_receptionists,
        total_appointments=total_appointments,
        total_prescriptions=total_prescriptions,
        pending_appointments=pending,
        confirmed_appointments=confirmed,
        arrived_appointments=arrived,
        completed_appointments=completed,
        cancelled_appointments=cancelled,
        total_revenue=revenue_val,
        revenue=revenue_val,
        paid_revenue=paid_revenue_val,
        refunded_revenue=refunded_revenue_val,
        paid_payments_count=paid_payments_count,
        refunded_payments_count=refunded_payments_count,
        chart_data=chart_data,
        status_distribution=status_distribution,
    )


@router.post("/doctors", status_code=status.HTTP_201_CREATED)
def create_doctor(
    data: DoctorCreate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    existing = db.query(User).filter(User.email == data.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    specialty = db.query(Specialty).filter(Specialty.id == data.specialty_id).first()
    if not specialty:
        raise HTTPException(status_code=404, detail="Specialty not found")

    temp_password = data.password or _generate_temp_password()
    user_id = str(uuid.uuid4())
    user = User(
        id=user_id,
        email=data.email.lower().strip(),
        phone=data.phone,
        password_hash=hash_password(temp_password),
        role="doctor",
        must_change_password=True,
        email_verified=True,
    )
    db.add(user)

    profile_id = str(uuid.uuid4())
    profile = Profile(
        id=profile_id,
        user_id=user_id,
        first_name=data.first_name,
        last_name=data.last_name,
        dob=data.dob or date(1990, 1, 1),
        gender=data.gender or "Unknown",
        phone=data.phone,
        address=data.address,
        emergency_contact_name=data.emergency_contact_name,
        emergency_contact_phone=data.emergency_contact_phone,
        blood_type=data.blood_type,
        is_complete=True,
    )
    db.add(profile)

    doctor_id = str(uuid.uuid4())
    doctor = Doctor(
        id=doctor_id,
        profile_id=profile_id,
        specialty_id=data.specialty_id,
        qualifications=data.qualifications,
        bio=data.bio,
    )
    db.add(doctor)

    from clinic_schedule import DEFAULT_WORKING_DAYS

    for day in DEFAULT_WORKING_DAYS:
        db.add(DoctorSchedule(
            doctor_id=doctor_id, day_of_week=day,
            start_time="09:00", end_time="17:00", is_available=True,
        ))

    name = _display_name(profile, user.email)
    _notify_new_user(
        db,
        user_id,
        "Account created",
        f"Welcome Dr. {name}. Your temporary password is: {temp_password}. Please change it after your first login.",
    )
    _notify_staff(
        db,
        "Doctor created",
        f"Dr. {name} was created by admin.",
        exclude_user_id=current_user.id,
    )

    db.commit()
    db.refresh(doctor)
    return {
        "message": "Doctor created successfully. Temporary password was sent via notification.",
        "id": doctor.id,
        "email": user.email,
    }


@router.put("/doctors/{doctor_id}", response_model=DoctorResponse)
def update_doctor(
    doctor_id: str,
    data: DoctorUpdate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(doctor, field, value)

    db.commit()
    db.refresh(doctor)
    return doctor


def _doctor_display_name(db: Session, doctor: Doctor) -> str:
    profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
    if profile:
        name = f"{profile.first_name or ''} {profile.last_name or ''}".strip()
        if name:
            return f"Dr. {name}"
    return "Doctor"


@router.get("/doctors/{doctor_id}/manage", response_model=DoctorAdminDetailResponse)
def get_doctor_manage(
    doctor_id: str,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")

    settings = db.query(ClinicSettings).first()
    specialty = db.query(Specialty).filter(Specialty.id == doctor.specialty_id).first()
    schedules = (
        db.query(DoctorSchedule)
        .filter(DoctorSchedule.doctor_id == doctor_id)
        .order_by(DoctorSchedule.day_of_week)
        .all()
    )
    time_off = (
        db.query(DoctorTimeOff)
        .filter(DoctorTimeOff.doctor_id == doctor_id)
        .order_by(DoctorTimeOff.start_date.desc())
        .all()
    )
    return DoctorAdminDetailResponse(
        doctor_id=doctor.id,
        name=_doctor_display_name(db, doctor),
        specialty_name=specialty.name if specialty else None,
        consultation_fee=doctor.consultation_fee,
        default_fee=float(settings.default_fee) if settings else 100.0,
        schedules=schedules,
        time_off=time_off,
    )


@router.put("/doctors/{doctor_id}/schedule", response_model=DoctorAdminDetailResponse)
def update_doctor_schedule(
    doctor_id: str,
    data: DoctorSchedulesUpdate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")

    from clinic_schedule import sync_doctor_weekly_hours, normalize_clinic_time_pair, repair_doctor_with_no_available_days

    if data.working_hours_start and data.working_hours_end:
        start, end = normalize_clinic_time_pair(data.working_hours_start, data.working_hours_end)
        sync_doctor_weekly_hours(db, doctor_id, start, end)

    for item in data.schedules:
        start, end = normalize_clinic_time_pair(item.start_time, item.end_time)
        row = (
            db.query(DoctorSchedule)
            .filter(
                DoctorSchedule.doctor_id == doctor_id,
                DoctorSchedule.day_of_week == item.day_of_week,
            )
            .first()
        )
        if row:
            row.start_time = start
            row.end_time = end
            row.is_available = item.is_available
        else:
            db.add(
                DoctorSchedule(
                    doctor_id=doctor_id,
                    day_of_week=item.day_of_week,
                    start_time=start,
                    end_time=end,
                    is_available=item.is_available,
                )
            )

    repair_doctor_with_no_available_days(db, doctor_id)

    doc_name = _doctor_display_name(db, doctor)
    notify_doctor(
        db,
        doctor_id,
        "Schedule updated",
        f"Your working schedule was updated by admin.",
    )
    log_audit(
        db,
        current_user.id,
        "update_doctor_schedule",
        "doctor",
        doctor_id,
        f"Updated schedule for {doc_name}",
    )
    db.commit()
    return get_doctor_manage(doctor_id, current_user, db)


@router.post("/doctors/{doctor_id}/time-off", response_model=DoctorTimeOffResponse, status_code=status.HTTP_201_CREATED)
def add_doctor_time_off(
    doctor_id: str,
    data: DoctorTimeOffCreate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")
    if data.end_date < data.start_date:
        raise HTTPException(status_code=400, detail="End date must be on or after start date")

    row = DoctorTimeOff(
        doctor_id=doctor_id,
        start_date=data.start_date,
        end_date=data.end_date,
        reason=data.reason,
    )
    db.add(row)

    doc_name = _doctor_display_name(db, doctor)
    reason = data.reason or "vacation"
    notify_doctor(
        db,
        doctor_id,
        "Time off scheduled",
        f"Admin scheduled time off ({data.start_date} to {data.end_date}): {reason}.",
    )

    affected = (
        db.query(Appointment)
        .filter(
            Appointment.doctor_id == doctor_id,
            Appointment.date >= data.start_date,
            Appointment.date <= data.end_date,
            Appointment.status.in_(["pending", "confirmed", "arrived"]),
        )
        .all()
    )
    for apt in affected:
        patient = db.query(Profile).filter(Profile.id == apt.patient_id).first()
        if patient:
            notify_user(
                db,
                patient.user_id,
                "Doctor unavailable",
                (
                    f"{doc_name} is not available on {apt.date}. "
                    f"Please reschedule your appointment ({apt.time_slot})."
                ),
            )

    log_audit(
        db,
        current_user.id,
        "add_doctor_time_off",
        "doctor",
        doctor_id,
        f"Time off {data.start_date}–{data.end_date} for {doc_name}",
    )
    db.commit()
    db.refresh(row)
    return row


@router.delete("/doctors/{doctor_id}/time-off/{time_off_id}")
def delete_doctor_time_off(
    doctor_id: str,
    time_off_id: str,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    row = (
        db.query(DoctorTimeOff)
        .filter(DoctorTimeOff.id == time_off_id, DoctorTimeOff.doctor_id == doctor_id)
        .first()
    )
    if not row:
        raise HTTPException(status_code=404, detail="Time off not found")
    db.delete(row)
    notify_doctor(db, doctor_id, "Time off removed", "Admin removed a scheduled time-off period.")
    db.commit()
    return {"message": "Time off removed"}


@router.put("/doctors/{doctor_id}/fee", response_model=DoctorAdminDetailResponse)
def update_doctor_fee(
    doctor_id: str,
    data: DoctorFeeUpdate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")
    doctor.consultation_fee = data.consultation_fee
    fee_label = f"{data.consultation_fee} EGP" if data.consultation_fee is not None else "clinic default"
    notify_doctor(
        db,
        doctor_id,
        "Consultation fee updated",
        f"Your consultation fee was set to {fee_label} by admin.",
    )
    log_audit(
        db,
        current_user.id,
        "update_doctor_fee",
        "doctor",
        doctor_id,
        f"Fee set to {fee_label} for {_doctor_display_name(db, doctor)}",
    )
    db.commit()
    return get_doctor_manage(doctor_id, current_user, db)


@router.put("/doctors/{doctor_id}/deactivate")
def deactivate_doctor(
    doctor_id: str,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        raise HTTPException(status_code=404, detail="Doctor not found")

    profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
    if profile:
        user = db.query(User).filter(User.id == profile.user_id).first()
        if user:
            user.is_active = False
            name = _display_name(profile, user.email)
            _notify_staff(
                db,
                "Doctor deactivated",
                f"Dr. {name} was deactivated by admin.",
                exclude_user_id=current_user.id,
            )
            db.commit()
    return {"message": "Doctor deactivated"}


@router.post("/receptionists", status_code=status.HTTP_201_CREATED)
def create_receptionist(
    data: ReceptionistCreate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    existing = db.query(User).filter(User.email == data.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    temp_password = data.password or _generate_temp_password()
    user_id = str(uuid.uuid4())
    user = User(
        id=user_id,
        email=data.email.lower().strip(),
        phone=data.phone,
        password_hash=hash_password(temp_password),
        role="receptionist",
        must_change_password=True,
        email_verified=True,
    )
    db.add(user)

    profile = Profile(
        id=str(uuid.uuid4()),
        user_id=user_id,
        first_name=data.first_name,
        last_name=data.last_name,
        dob=data.dob or date(1990, 1, 1),
        gender=data.gender or "Unknown",
        phone=data.phone,
        address=data.address,
        emergency_contact_name=data.emergency_contact_name,
        emergency_contact_phone=data.emergency_contact_phone,
        blood_type=data.blood_type,
        is_complete=True,
    )
    db.add(profile)

    name = _display_name(profile, user.email)
    _notify_new_user(
        db,
        user_id,
        "Account created",
        f"Welcome {name}. Your temporary password is: {temp_password}. Please change it after your first login.",
    )
    _notify_staff(
        db,
        "Receptionist created",
        f"{name} was created as receptionist by admin.",
        exclude_user_id=current_user.id,
    )

    db.commit()

    return {
        "message": "Receptionist created successfully. Temporary password was sent via notification.",
        "user_id": user_id,
        "email": user.email,
    }


@router.post("/admins", status_code=status.HTTP_201_CREATED)
def create_admin(
    data: AdminCreate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    existing = db.query(User).filter(User.email == data.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    temp_password = data.password or _generate_temp_password()
    user_id = str(uuid.uuid4())
    user = User(
        id=user_id,
        email=data.email.lower().strip(),
        phone=data.phone,
        password_hash=hash_password(temp_password),
        role="admin",
        must_change_password=True,
        email_verified=True,
    )
    db.add(user)

    profile = Profile(
        id=str(uuid.uuid4()),
        user_id=user_id,
        first_name=data.first_name,
        last_name=data.last_name,
        dob=data.dob or date(1990, 1, 1),
        gender=data.gender or "Unknown",
        phone=data.phone,
        address=data.address,
        emergency_contact_name=data.emergency_contact_name,
        emergency_contact_phone=data.emergency_contact_phone,
        blood_type=data.blood_type,
        is_complete=True,
    )
    db.add(profile)

    name = _display_name(profile, user.email)
    _notify_new_user(
        db,
        user_id,
        "Admin account created",
        f"Welcome {name}. Your temporary password is: {temp_password}. Please change it after your first login.",
    )
    _notify_staff(
        db,
        "Admin created",
        f"{name} was created as admin by {current_user.email}.",
        exclude_user_id=current_user.id,
    )

    db.commit()

    return {
        "message": "Admin created successfully. Temporary password was sent via notification.",
        "user_id": user_id,
        "email": user.email,
    }


@router.put("/receptionists/{user_id}")
def update_receptionist(
    user_id: str,
    data: ReceptionistUpdate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id, User.role == "receptionist").first()
    if not user:
        raise HTTPException(status_code=404, detail="Receptionist not found")

    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(profile, field, value)

    db.commit()
    return {"message": "Receptionist updated"}


@router.get("/users", response_model=list[AdminUserListItem])
def list_users(
    role: str = Query(None),
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    query = db.query(User)
    if role:
        query = query.filter(User.role == role)
    users = query.order_by(User.created_at.desc()).all()

    result = []
    for u in users:
        profile = db.query(Profile).filter(Profile.user_id == u.id).first()
        doctor_info = None
        if u.role == "doctor" and profile:
            doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
            if doctor:
                specialty = db.query(Specialty).filter(Specialty.id == doctor.specialty_id).first()
                doctor_info = AdminDoctorInfo(
                    doctor_id=doctor.id,
                    specialty_id=doctor.specialty_id,
                    specialty_name=specialty.name if specialty else None,
                    qualifications=doctor.qualifications,
                    bio=doctor.bio,
                )
        result.append(AdminUserListItem(
            id=u.id,
            email=u.email,
            phone=u.phone,
            role=u.role,
            is_active=u.is_active,
            must_change_password=u.must_change_password,
            created_at=u.created_at,
            profile=profile,
            doctor_info=doctor_info,
        ))
    return result


@router.get("/users/{user_id}", response_model=UserResponse)
def get_user(
    user_id: str,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    return UserResponse(
        id=user.id,
        email=user.email,
        phone=user.phone,
        role=user.role,
        is_active=user.is_active,
        must_change_password=user.must_change_password,
        created_at=user.created_at,
        profile=profile,
    )


@router.get("/patients/{user_id}/detail", response_model=AdminPatientDetailResponse)
def get_patient_detail(
    user_id: str,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id, User.role == "patient").first()
    if not user:
        raise HTTPException(status_code=404, detail="Patient not found")

    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Patient profile not found")

    sync_prescriptions_from_records(db)
    expire_prescriptions(db)

    appointments = (
        db.query(Appointment)
        .filter(Appointment.patient_id == profile.id)
        .order_by(Appointment.date.desc(), Appointment.time_slot.desc())
        .all()
    )
    appointment_payload = [_enrich_appointment(a, db) for a in appointments]

    records = (
        db.query(MedicalRecord)
        .filter(MedicalRecord.patient_id == profile.id)
        .order_by(MedicalRecord.created_at.desc())
        .all()
    )
    record_payload = [_record_response(r, db) for r in records]
    record_ids = [r.id for r in records]

    prescriptions = []
    if record_ids:
        rx_list = (
            db.query(Prescription)
            .filter(Prescription.medical_record_id.in_(record_ids))
            .order_by(Prescription.created_at.desc())
            .all()
        )
        prescriptions = [_enrich_prescription(p, db) for p in rx_list]

    apt_ids = [a.id for a in appointments]
    payments = []
    if apt_ids:
        payment_rows = (
            db.query(Payment)
            .filter(Payment.appointment_id.in_(apt_ids))
            .order_by(Payment.created_at.desc())
            .all()
        )
        payments = [_enrich_payment(p, db) for p in payment_rows]

    documents = (
        db.query(Document)
        .filter(Document.patient_id == profile.id)
        .order_by(Document.upload_date.desc())
        .all()
    )

    status_counts = {}
    for apt in appointments:
        status_counts[apt.status] = status_counts.get(apt.status, 0) + 1

    stats = {
        "total_appointments": len(appointments),
        "appointments_by_status": status_counts,
        "total_records": len(records),
        "active_records": sum(1 for r in records if getattr(r, "is_active", True)),
        "total_prescriptions": len(prescriptions),
        "active_prescriptions": sum(1 for p in prescriptions if p.get("status") == "active"),
        "total_payments": len(payments),
        "total_documents": len(documents),
    }

    return AdminPatientDetailResponse(
        user=UserResponse(
            id=user.id,
            email=user.email,
            phone=user.phone,
            role=user.role,
            is_active=user.is_active,
            must_change_password=user.must_change_password,
            created_at=user.created_at,
            profile=profile,
        ),
        profile_id=profile.id,
        stats=stats,
        appointments=appointment_payload,
        records=record_payload,
        prescriptions=prescriptions,
        payments=payments,
        documents=[DocumentResponse.model_validate(d) for d in documents],
    )


@router.put("/users/{user_id}")
def update_user(
    user_id: str,
    data: dict,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    name = _display_name(profile, user.email)

    if "is_active" in data:
        old_active = user.is_active
        user.is_active = data["is_active"]
        if old_active != user.is_active:
            action = "reactivated" if user.is_active else "deactivated"
            _notify_staff(
                db,
                f"User {action}",
                f"{name} ({user.role}) was {action} by admin.",
                exclude_user_id=current_user.id,
            )
    VALID_ROLES = {"patient", "doctor", "receptionist", "admin"}
    if "role" in data:
        if data["role"] not in VALID_ROLES:
            raise HTTPException(status_code=400, detail=f"Invalid role. Must be one of: {', '.join(sorted(VALID_ROLES))}")
        user.role = data["role"]

    db.commit()
    return {"message": "User updated"}


@router.delete("/users/{user_id}")
def delete_user(
    user_id: str,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot delete your own account")

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.role == "admin":
        raise HTTPException(status_code=400, detail="Cannot delete admin accounts")

    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    name = _display_name(profile, user.email)
    role = user.role

    if user.role == "doctor" and profile:
        doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
        if doctor:
            apt_count = db.query(Appointment).filter(Appointment.doctor_id == doctor.id).count()
            if apt_count > 0:
                raise HTTPException(
                    status_code=400,
                    detail=f"Cannot delete: doctor has {apt_count} appointment(s). Deactivate instead.",
                )
            db.query(DoctorSchedule).filter(DoctorSchedule.doctor_id == doctor.id).delete()
            db.delete(doctor)

    if user.role == "patient" and profile:
        apt_count = db.query(Appointment).filter(Appointment.patient_id == profile.id).count()
        if apt_count > 0:
            raise HTTPException(
                status_code=400,
                detail=f"Cannot delete: patient has {apt_count} appointment(s). Deactivate instead.",
            )
        db.query(SensorData).filter(SensorData.patient_id == profile.id).delete()
        db.query(Document).filter(Document.patient_id == profile.id).delete()

    db.query(Notification).filter(Notification.user_id == user_id).delete()
    db.query(AIConversation).filter(AIConversation.user_id == user_id).delete()

    if profile:
        db.delete(profile)
    db.delete(user)

    _notify_staff(
        db,
        "User deleted",
        f"{name} ({role}) was permanently deleted by admin.",
        exclude_user_id=current_user.id,
    )
    db.commit()
    return {"message": "User deleted"}


@router.post("/purge-patients")
def purge_patients(
    data: PurgePatientsRequest,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    """Permanently delete ALL patient accounts and related data. Staff accounts are kept."""
    if data.confirm != "DELETE_ALL_PATIENTS":
        raise HTTPException(
            status_code=400,
            detail='Send {"confirm": "DELETE_ALL_PATIENTS"} to proceed.',
        )
    try:
        stats = purge_all_patients(db)
        log_audit(
            db,
            current_user.id,
            "purge_all_patients",
            "system",
            "patients",
            f"Admin purged all patients: {stats}",
        )
        db.commit()
        try:
            _notify_staff(
                db,
                "Patient data reset",
                f"All patient accounts were removed by admin ({stats.get('patients_deleted', 0)} patients).",
                exclude_user_id=current_user.id,
            )
            db.commit()
        except Exception:
            db.rollback()
        return {"message": "All patients and related data deleted.", "stats": stats}
    except HTTPException:
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Patient purge failed: {exc}") from exc


@router.post("/specialties", response_model=SpecialtyResponse, status_code=status.HTTP_201_CREATED)
def create_specialty(
    data: SpecialtyCreate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    existing = db.query(Specialty).filter(Specialty.name == data.name).first()
    if existing:
        raise HTTPException(status_code=400, detail="Specialty already exists")

    specialty = Specialty(name=data.name, description=data.description)
    db.add(specialty)
    db.commit()
    db.refresh(specialty)
    return specialty


@router.put("/specialties/{specialty_id}", response_model=SpecialtyResponse)
def update_specialty(
    specialty_id: int,
    data: SpecialtyCreate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    specialty = db.query(Specialty).filter(Specialty.id == specialty_id).first()
    if not specialty:
        raise HTTPException(status_code=404, detail="Specialty not found")

    specialty.name = data.name
    specialty.description = data.description
    db.commit()
    db.refresh(specialty)
    return specialty


@router.delete("/specialties/{specialty_id}")
def delete_specialty(
    specialty_id: int,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    specialty = db.query(Specialty).filter(Specialty.id == specialty_id).first()
    if not specialty:
        raise HTTPException(status_code=404, detail="Specialty not found")

    doctors_count = db.query(Doctor).filter(Doctor.specialty_id == specialty_id).count()
    if doctors_count > 0:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot delete: {doctors_count} doctor(s) assigned to this specialty",
        )

    db.delete(specialty)
    db.commit()
    return {"message": "Specialty deleted"}


@router.get("/specialties", response_model=list[SpecialtyResponse])
def list_specialties(
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    return db.query(Specialty).order_by(Specialty.name).all()


@router.get("/settings", response_model=ClinicSettingsResponse)
def get_settings(
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    settings = db.query(ClinicSettings).first()
    if not settings:
        raise HTTPException(status_code=404, detail="Settings not configured")
    return settings


@router.put("/settings", response_model=ClinicSettingsResponse)
def update_settings(
    data: ClinicSettingsUpdate,
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    from clinic_schedule import ensure_doctor_schedules, sync_all_doctors_hours_from_clinic, normalize_clinic_time_pair

    settings = db.query(ClinicSettings).first()
    if not settings:
        raise HTTPException(status_code=404, detail="Settings not configured")

    old_hours = (settings.working_hours_start, settings.working_hours_end)
    old_days = settings.working_days

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(settings, field, value)

    if "working_hours_start" in update_data or "working_hours_end" in update_data:
        start, end = normalize_clinic_time_pair(
            settings.working_hours_start,
            settings.working_hours_end,
        )
        settings.working_hours_start = start
        settings.working_hours_end = end

    if "working_days" in update_data:
        ensure_doctor_schedules(db)
    if "working_hours_start" in update_data or "working_hours_end" in update_data:
        sync_all_doctors_hours_from_clinic(db, settings)

    hours_changed = (
        settings.working_hours_start,
        settings.working_hours_end,
    ) != old_hours
    days_changed = settings.working_days != old_days

    if hours_changed or days_changed or "appointment_duration" in update_data or "default_fee" in update_data:
        notify_role_users(
            db,
            "doctor",
            "Clinic settings updated",
            "Clinic working hours or fees were updated by admin. Please review your schedule.",
            exclude_user_id=current_user.id,
        )
        notify_role_users(
            db,
            "receptionist",
            "Clinic settings updated",
            "Clinic settings were updated by admin.",
            exclude_user_id=current_user.id,
        )
        notify_role_users(
            db,
            "admin",
            "Clinic settings updated",
            f"Clinic settings were updated by {current_user.email}.",
            exclude_user_id=current_user.id,
        )

    log_audit(
        db,
        current_user.id,
        "update_clinic_settings",
        "clinic_settings",
        str(settings.id),
        "Clinic settings updated",
    )

    db.commit()
    db.refresh(settings)
    return settings


@router.get("/charts/appointments-per-day", response_model=list[ChartDataPoint])
def appointments_per_day(
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    today = date.today()
    start = today - timedelta(days=29)
    results = []
    for i in range(30):
        d = start + timedelta(days=i)
        count = db.query(Appointment).filter(Appointment.date == d).count()
        results.append(ChartDataPoint(label=str(d), value=count))
    return results


@router.get("/charts/patients-per-month", response_model=list[ChartDataPoint])
def patients_per_month(
    current_user: User = Depends(require_role("admin")),
    db: Session = Depends(get_db),
):
    results = []
    today = date.today()
    for i in range(11, -1, -1):
        month_start = date(today.year, today.month, 1) - timedelta(days=i * 30)
        month_end = month_start + timedelta(days=30)
        count = (
            db.query(User)
            .filter(
                User.role == "patient",
                User.created_at >= datetime.combine(month_start, datetime.min.time()),
                User.created_at < datetime.combine(month_end, datetime.min.time()),
            )
            .count()
        )
        results.append(ChartDataPoint(label=month_start.strftime("%Y-%m"), value=count))
    return results
