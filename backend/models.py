import uuid
from datetime import datetime, date

from sqlalchemy import (
    Column, String, Integer, Float, Boolean, Date, DateTime, Text, JSON,
    ForeignKey, UniqueConstraint
)
from sqlalchemy.orm import relationship

from database import Base


def generate_uuid():
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=generate_uuid)
    email = Column(String, unique=True, index=True, nullable=False)
    phone = Column(String, unique=True, nullable=True)
    password_hash = Column(String, nullable=False)
    role = Column(String, nullable=False)  # patient/doctor/receptionist/admin
    google_id = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    must_change_password = Column(Boolean, default=False)
    email_verified = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    profile = relationship("Profile", back_populates="user", uselist=False)
    notifications = relationship("Notification", back_populates="user")
    ai_conversations = relationship("AIConversation", back_populates="user")


class Profile(Base):
    __tablename__ = "profiles"

    id = Column(String, primary_key=True, default=generate_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False)
    first_name = Column(String, nullable=True)
    middle_name = Column(String, nullable=True)
    last_name = Column(String, nullable=True)
    dob = Column(Date, nullable=True)
    gender = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    address = Column(String, nullable=True)
    emergency_contact_name = Column(String, nullable=True)
    emergency_contact_phone = Column(String, nullable=True)
    blood_type = Column(String, nullable=True)
    allergies = Column(String, nullable=True)
    chronic_diseases = Column(String, nullable=True)
    existing_conditions = Column(String, nullable=True)
    photo_url = Column(String, nullable=True)
    is_complete = Column(Boolean, default=False)

    user = relationship("User", back_populates="profile")
    doctor = relationship("Doctor", back_populates="profile", uselist=False)
    patient_appointments = relationship(
        "Appointment", back_populates="patient", foreign_keys="Appointment.patient_id"
    )
    patient_records = relationship(
        "MedicalRecord", back_populates="patient", foreign_keys="MedicalRecord.patient_id"
    )
    sensor_data = relationship("SensorData", back_populates="patient")
    documents = relationship("Document", back_populates="patient")
    update_requests = relationship(
        "ProfileUpdateRequest", back_populates="patient",
        foreign_keys="ProfileUpdateRequest.patient_id"
    )


class Specialty(Base):
    __tablename__ = "specialties"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String, unique=True, nullable=False)
    description = Column(String, nullable=True)

    doctors = relationship("Doctor", back_populates="specialty")


class Doctor(Base):
    __tablename__ = "doctors"

    id = Column(String, primary_key=True, default=generate_uuid)
    profile_id = Column(String, ForeignKey("profiles.id"), unique=True, nullable=False)
    specialty_id = Column(Integer, ForeignKey("specialties.id"), nullable=False)
    qualifications = Column(String, nullable=True)
    bio = Column(String, nullable=True)

    profile = relationship("Profile", back_populates="doctor")
    specialty = relationship("Specialty", back_populates="doctors")
    schedules = relationship("DoctorSchedule", back_populates="doctor")
    appointments = relationship("Appointment", back_populates="doctor")
    doctor_records = relationship(
        "MedicalRecord", back_populates="doctor", foreign_keys="MedicalRecord.doctor_id"
    )
    ai_suggestions = relationship(
        "AISuggestion", back_populates="doctor", foreign_keys="AISuggestion.doctor_id"
    )


class DoctorSchedule(Base):
    __tablename__ = "doctor_schedules"

    id = Column(Integer, primary_key=True, autoincrement=True)
    doctor_id = Column(String, ForeignKey("doctors.id"), nullable=False)
    day_of_week = Column(Integer, nullable=False)  # 0=Monday .. 6=Sunday
    start_time = Column(String, nullable=False)
    end_time = Column(String, nullable=False)
    is_available = Column(Boolean, default=True)

    doctor = relationship("Doctor", back_populates="schedules")


class Appointment(Base):
    __tablename__ = "appointments"
    __table_args__ = (
        UniqueConstraint('doctor_id', 'date', 'time_slot', name='uq_doctor_date_slot'),
    )

    id = Column(String, primary_key=True, default=generate_uuid)
    patient_id = Column(String, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False)
    doctor_id = Column(String, ForeignKey("doctors.id", ondelete="CASCADE"), nullable=False)
    date = Column(Date, nullable=False)
    time_slot = Column(String, nullable=False)
    status = Column(String, default="pending")  # pending/confirmed/completed/cancelled
    queue_number = Column(Integer, nullable=True)
    notes = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    patient = relationship("Profile", back_populates="patient_appointments")
    doctor = relationship("Doctor", back_populates="appointments")
    payment = relationship("Payment", back_populates="appointment", uselist=False)
    medical_record = relationship("MedicalRecord", back_populates="appointment", uselist=False)


class Payment(Base):
    __tablename__ = "payments"

    id = Column(String, primary_key=True, default=generate_uuid)
    appointment_id = Column(String, ForeignKey("appointments.id", ondelete="CASCADE"), unique=True, nullable=False)
    amount = Column(Float, nullable=False)
    payment_method = Column(String, nullable=True)  # cash/instapay
    payment_status = Column(String, default="unpaid")  # unpaid/paid/refunded
    proof_url = Column(String, nullable=True)
    receptionist_id = Column(String, ForeignKey("profiles.id"), nullable=True)
    refund_proof_url = Column(String, nullable=True)
    refunded_at = Column(DateTime, nullable=True)
    refunded_by = Column(String, ForeignKey("profiles.id"), nullable=True)
    refund_reason = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    appointment = relationship("Appointment", back_populates="payment")
    receptionist = relationship("Profile", foreign_keys=[receptionist_id])
    refund_staff = relationship("Profile", foreign_keys=[refunded_by])


class MedicalRecord(Base):
    __tablename__ = "medical_records"

    id = Column(String, primary_key=True, default=generate_uuid)
    appointment_id = Column(String, ForeignKey("appointments.id"), unique=True, nullable=True)
    patient_id = Column(String, ForeignKey("profiles.id"), nullable=False)
    doctor_id = Column(String, ForeignKey("doctors.id"), nullable=False)
    chief_complaint = Column(String, nullable=False)
    symptoms = Column(String, nullable=False)
    diagnosis = Column(String, nullable=False)
    severity = Column(String, nullable=False)  # mild/moderate/severe
    treatment_plan = Column(String, nullable=False)
    notes = Column(String, nullable=True)
    soap_subjective = Column(String, nullable=True)
    soap_objective = Column(String, nullable=True)
    soap_assessment = Column(String, nullable=True)
    soap_plan = Column(String, nullable=True)
    structured_data = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    appointment = relationship("Appointment", back_populates="medical_record")
    patient = relationship("Profile", back_populates="patient_records")
    doctor = relationship("Doctor", back_populates="doctor_records")
    prescriptions = relationship("Prescription", back_populates="medical_record")


class Prescription(Base):
    __tablename__ = "prescriptions"

    id = Column(String, primary_key=True, default=generate_uuid)
    medical_record_id = Column(String, ForeignKey("medical_records.id"), nullable=False)
    status = Column(String, default="active")  # active/completed/cancelled
    active_until = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    medical_record = relationship("MedicalRecord", back_populates="prescriptions")
    items = relationship("PrescriptionItem", back_populates="prescription")


class AppointmentReview(Base):
    __tablename__ = "appointment_reviews"

    id = Column(String, primary_key=True, default=generate_uuid)
    appointment_id = Column(String, ForeignKey("appointments.id", ondelete="CASCADE"), unique=True, nullable=False)
    patient_id = Column(String, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False)
    doctor_id = Column(String, ForeignKey("doctors.id", ondelete="CASCADE"), nullable=False)
    receptionist_id = Column(String, ForeignKey("profiles.id"), nullable=True)
    doctor_rating = Column(Integer, nullable=False)
    receptionist_rating = Column(Integer, nullable=True)
    doctor_comment = Column(Text, nullable=True)
    receptionist_comment = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    appointment = relationship("Appointment", backref="review")
    patient = relationship("Profile", foreign_keys=[patient_id])
    doctor = relationship("Doctor", foreign_keys=[doctor_id])
    receptionist = relationship("Profile", foreign_keys=[receptionist_id])


class PrescriptionItem(Base):
    __tablename__ = "prescription_items"

    id = Column(Integer, primary_key=True, autoincrement=True)
    prescription_id = Column(String, ForeignKey("prescriptions.id"), nullable=False)
    medication_name = Column(String, nullable=False)
    dosage = Column(String, nullable=False)
    frequency = Column(String, nullable=False)
    duration = Column(String, nullable=False)
    notes = Column(String, nullable=True)

    prescription = relationship("Prescription", back_populates="items")


class SensorData(Base):
    __tablename__ = "sensor_data"

    id = Column(Integer, primary_key=True, autoincrement=True)
    patient_id = Column(String, ForeignKey("profiles.id"), nullable=False)
    heart_rate = Column(Integer, nullable=False)
    temperature = Column(Float, nullable=False)
    ecg = Column(Float, nullable=True, default=0)
    emg = Column(Float, nullable=True, default=0)
    gsr = Column(Float, nullable=True, default=0)
    waveforms = Column(JSON, nullable=True)
    timestamp = Column(DateTime, default=datetime.utcnow)

    patient = relationship("Profile", back_populates="sensor_data")


class Document(Base):
    __tablename__ = "documents"

    id = Column(String, primary_key=True, default=generate_uuid)
    patient_id = Column(String, ForeignKey("profiles.id"), nullable=False)
    uploaded_by = Column(String, ForeignKey("users.id"), nullable=True)
    category = Column(String, nullable=False)  # lab_report/x_ray/mri/prescription/other
    file_name = Column(String, nullable=False)
    file_url = Column(String, nullable=False)
    upload_date = Column(DateTime, default=datetime.utcnow)

    patient = relationship("Profile", back_populates="documents")
    uploader = relationship("User", foreign_keys=[uploaded_by])


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(String, primary_key=True, default=generate_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    title = Column(String, nullable=False)
    message = Column(String, nullable=False)
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="notifications")


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=True)
    action = Column(String, nullable=False)
    entity_type = Column(String, nullable=False)
    entity_id = Column(String, nullable=False)
    details = Column(String, nullable=True)
    timestamp = Column(DateTime, default=datetime.utcnow)


class ProfileUpdateRequest(Base):
    __tablename__ = "profile_update_requests"

    id = Column(String, primary_key=True, default=generate_uuid)
    patient_id = Column(String, ForeignKey("profiles.id"), nullable=False)
    request_type = Column(String, nullable=False)
    old_value = Column(String, nullable=True)
    new_value = Column(String, nullable=False)
    status = Column(String, default="pending")  # pending/approved/rejected
    doctor_id = Column(String, ForeignKey("doctors.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    patient = relationship("Profile", back_populates="update_requests")
    doctor = relationship("Doctor", foreign_keys=[doctor_id])


class AIConversation(Base):
    __tablename__ = "ai_conversations"

    id = Column(String, primary_key=True, default=generate_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    role = Column(String, nullable=False)
    messages = Column(Text, nullable=False)  # JSON string
    summary = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", back_populates="ai_conversations")


class AISuggestion(Base):
    __tablename__ = "ai_suggestions"

    id = Column(String, primary_key=True, default=generate_uuid)
    doctor_id = Column(String, ForeignKey("doctors.id"), nullable=False)
    patient_id = Column(String, ForeignKey("profiles.id"), nullable=False)
    appointment_id = Column(String, ForeignKey("appointments.id"), nullable=True)
    transcript = Column(String, nullable=True)
    extracted_data = Column(Text, nullable=False)  # JSON string
    status = Column(String, default="pending")  # pending/draft/approved/rejected
    created_at = Column(DateTime, default=datetime.utcnow)

    doctor = relationship("Doctor", back_populates="ai_suggestions")
    patient = relationship("Profile", foreign_keys=[patient_id])
    appointment = relationship("Appointment", foreign_keys=[appointment_id])


class EmailOTP(Base):
    __tablename__ = "email_otps"

    id = Column(String, primary_key=True, default=generate_uuid)
    email = Column(String, nullable=False, index=True)
    code_hash = Column(String, nullable=False)
    purpose = Column(String, nullable=False)  # signup | password_reset
    expires_at = Column(DateTime, nullable=False)
    used = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class ClinicSettings(Base):
    __tablename__ = "clinic_settings"

    id = Column(Integer, primary_key=True, default=1)
    clinic_name = Column(String, nullable=False)
    address = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    email = Column(String, nullable=True)
    logo_url = Column(String, nullable=True)
    default_fee = Column(Float, default=100.0)
    working_hours_start = Column(String, default="08:00")
    working_hours_end = Column(String, default="17:00")
    working_days = Column(String, default="5,6,0,1,2,3")
    appointment_duration = Column(Integer, default=30)
