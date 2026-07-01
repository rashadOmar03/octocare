from datetime import datetime, date
from typing import Optional, List
import re
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic import AliasChoices


# ─── Auth ────────────────────────────────────────────────────────────────────

class UserCreate(BaseModel):
    email: str
    phone: Optional[str] = None
    password: str = Field(min_length=8)
    role: str = "patient"
    first_name: Optional[str] = None
    middle_name: Optional[str] = None
    last_name: Optional[str] = None

    @field_validator("email")
    @classmethod
    def _validate_email(cls, v: str) -> str:
        v = (v or "").lower().strip()
        if not re.match(r"^[\w.\+-]+@[\w.-]+\.\w{2,}$", v):
            raise ValueError("Invalid email address")
        return v


class UserLogin(BaseModel):
    email_or_phone: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: str
    role: str
    email: str | None = None
    must_change_password: bool = False
    first_name: str | None = None
    last_name: str | None = None
    full_name: str | None = None
    profile_complete: bool = False


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class ChangePasswordRequest(BaseModel):
    current_password: str | None = None
    old_password: str | None = None
    new_password: str = Field(min_length=8)

    @property
    def actual_old_password(self) -> str:
        return self.current_password or self.old_password or ""


class ForgotPasswordRequest(BaseModel):
    email: str


class ForgotPasswordResponse(BaseModel):
    message: str


class RegisterPendingResponse(BaseModel):
    message: str
    requires_verification: bool = True
    email: str


class VerifyEmailRequest(BaseModel):
    email: str
    otp: str


class ResendOtpRequest(BaseModel):
    email: str
    purpose: str  # signup | password_reset


class ResetPasswordRequest(BaseModel):
    email: str
    otp: str
    new_password: str = Field(min_length=8)


class MessageResponse(BaseModel):
    message: str


# ─── Profile ─────────────────────────────────────────────────────────────────

class ProfileCreate(BaseModel):
    first_name: str
    middle_name: Optional[str] = None
    last_name: str
    dob: date
    gender: str
    phone: str
    address: str
    emergency_contact_name: str
    emergency_contact_phone: str
    blood_type: str
    allergies: Optional[str] = None
    chronic_diseases: Optional[str] = None
    existing_conditions: Optional[str] = None
    photo_url: Optional[str] = None


class ProfileUpdate(BaseModel):
    first_name: Optional[str] = None
    middle_name: Optional[str] = None
    last_name: Optional[str] = None
    dob: Optional[date] = None
    gender: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    blood_type: Optional[str] = None
    allergies: Optional[str] = None
    chronic_diseases: Optional[str] = None
    existing_conditions: Optional[str] = None
    photo_url: Optional[str] = None


class ProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    first_name: Optional[str] = None
    middle_name: Optional[str] = None
    last_name: Optional[str] = None
    dob: Optional[date] = None
    gender: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    blood_type: Optional[str] = None
    allergies: Optional[str] = None
    chronic_diseases: Optional[str] = None
    existing_conditions: Optional[str] = None
    photo_url: Optional[str] = None
    is_complete: bool


# ─── Specialty ────────────────────────────────────────────────────────────────

class SpecialtyCreate(BaseModel):
    name: str
    description: Optional[str] = None


class SpecialtyResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    description: Optional[str] = None


# ─── Doctor ───────────────────────────────────────────────────────────────────

class DoctorCreate(BaseModel):
    email: str
    password: Optional[str] = None
    first_name: str
    last_name: str
    phone: str
    specialty_id: int
    qualifications: Optional[str] = None
    bio: Optional[str] = None
    dob: Optional[date] = None
    gender: Optional[str] = "Unknown"
    address: str = ""
    emergency_contact_name: str = ""
    emergency_contact_phone: str = ""
    blood_type: str = "Unknown"


class DoctorUpdate(BaseModel):
    specialty_id: Optional[int] = None
    qualifications: Optional[str] = None
    bio: Optional[str] = None


class DoctorScheduleCreate(BaseModel):
    day_of_week: int = Field(ge=0, le=6)
    start_time: str
    end_time: str
    is_available: bool = True


class DoctorScheduleResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    doctor_id: str
    day_of_week: int
    start_time: str
    end_time: str
    is_available: bool


class DoctorResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    profile_id: str
    specialty_id: int
    qualifications: Optional[str] = None
    bio: Optional[str] = None
    profile: Optional[ProfileResponse] = None
    specialty: Optional[SpecialtyResponse] = None
    schedules: Optional[List[DoctorScheduleResponse]] = None


# ─── Appointment ──────────────────────────────────────────────────────────────

class AppointmentCreate(BaseModel):
    doctor_id: str
    date: date
    time_slot: str


class AppointmentReschedule(BaseModel):
    date: date
    time_slot: str


class ReceptionistReschedule(BaseModel):
    date: date
    time_slot: str
    confirm: bool = True


class AppointmentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    patient_id: str
    doctor_id: str
    date: date
    time_slot: str
    status: str
    queue_number: Optional[int] = None
    notes: Optional[str] = None
    created_at: datetime


# ─── Payment ─────────────────────────────────────────────────────────────────

class PaymentCreate(BaseModel):
    appointment_id: Optional[str] = None
    appointment: Optional[str] = None
    amount: float
    payment_method: Optional[str] = None
    method: Optional[str] = None
    payment_status: str = "paid"

    @property
    def actual_appointment_id(self) -> str:
        aid = self.appointment_id or self.appointment
        return str(aid) if aid is not None else ""

    @property
    def actual_payment_method(self) -> str | None:
        return self.payment_method or self.method


class InstapayPaymentCreate(BaseModel):
    appointment_id: str
    proof_base64: str
    proof_filename: str = "instapay_proof.png"


class RefundPaymentCreate(BaseModel):
    reason: str = "Patient refund"
    proof_base64: str | None = None
    proof_filename: str = "refund_proof.png"


class PaymentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    appointment_id: str
    amount: float
    payment_method: Optional[str] = None
    payment_status: str
    proof_url: Optional[str] = None
    receptionist_id: Optional[str] = None
    created_at: datetime
    patient_name: Optional[str] = None
    doctor_name: Optional[str] = None
    appointment_date: Optional[str] = None
    time_slot: Optional[str] = None
    receptionist_name: Optional[str] = None
    invoice_ref: Optional[str] = None
    refund_reason: Optional[str] = None
    refunded_at: Optional[datetime] = None
    refunded_by: Optional[str] = None
    refund_proof_url: Optional[str] = None
    refund_staff_name: Optional[str] = None


# ─── Medical Record ──────────────────────────────────────────────────────────

class MedicalRecordCreate(BaseModel):
    appointment_id: Optional[str] = None
    patient_id: str
    chief_complaint: str
    symptoms: str
    diagnosis: str
    severity: str
    treatment_plan: str
    notes: Optional[str] = None
    soap_subjective: Optional[str] = None
    soap_objective: Optional[str] = None
    soap_assessment: Optional[str] = None
    soap_plan: Optional[str] = None
    structured_data: Optional[str] = None
    prescription: Optional[list[dict]] = None
    prescription_active_until: Optional[datetime] = None


class MedicalRecordUpdate(BaseModel):
    chief_complaint: Optional[str] = None
    symptoms: Optional[str] = None
    diagnosis: Optional[str] = None
    severity: Optional[str] = None
    treatment_plan: Optional[str] = None
    notes: Optional[str] = None
    soap_subjective: Optional[str] = None
    soap_objective: Optional[str] = None
    soap_assessment: Optional[str] = None
    soap_plan: Optional[str] = None
    structured_data: Optional[str] = None
    prescription: Optional[list[dict]] = None
    prescription_active_until: Optional[datetime] = None
    is_active: Optional[bool] = None


class MedicalRecordActiveUpdate(BaseModel):
    is_active: bool


class MedicalRecordResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    appointment_id: Optional[str] = None
    patient_id: str
    doctor_id: str
    doctor_name: Optional[str] = None
    chief_complaint: str
    symptoms: str
    diagnosis: str
    severity: str
    treatment_plan: str
    notes: Optional[str] = None
    soap_subjective: Optional[str] = None
    soap_objective: Optional[str] = None
    soap_assessment: Optional[str] = None
    soap_plan: Optional[str] = None
    structured_data: Optional[dict] = None
    is_active: bool = True
    created_at: datetime


# ─── Prescription ────────────────────────────────────────────────────────────

class PrescriptionItemCreate(BaseModel):
    medication_name: str
    dosage: str
    frequency: str
    duration: str
    notes: Optional[str] = None


class PrescriptionItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    prescription_id: str
    medication_name: str
    dosage: str
    frequency: str
    duration: str
    notes: Optional[str] = None


class PrescriptionCreate(BaseModel):
    medical_record_id: Optional[str] = None
    patient_id: Optional[str] = None
    patient: Optional[str] = None
    items: List[PrescriptionItemCreate]
    active_until: Optional[datetime] = None


class PrescriptionStatusUpdate(BaseModel):
    status: str
    active_until: Optional[datetime] = None


class PrescriptionUpdate(BaseModel):
    items: List[PrescriptionItemCreate]
    status: Optional[str] = None
    active_until: Optional[datetime] = None


class PrescriptionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    medical_record_id: str
    status: str
    active_until: Optional[datetime] = None
    created_at: datetime
    items: List[PrescriptionItemResponse] = []
    patient_id: Optional[str] = None
    patient_name: Optional[str] = None
    doctor_name: Optional[str] = None


# ─── Reviews ─────────────────────────────────────────────────────────────────

class ReviewCreate(BaseModel):
    appointment_id: str
    doctor_rating: int = Field(ge=1, le=5)
    receptionist_rating: Optional[int] = Field(default=None, ge=1, le=5)
    doctor_comment: Optional[str] = None
    receptionist_comment: Optional[str] = None


class ReviewResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    appointment_id: str
    patient_id: str
    doctor_id: str
    receptionist_id: Optional[str] = None
    doctor_rating: int
    receptionist_rating: Optional[int] = None
    doctor_comment: Optional[str] = None
    receptionist_comment: Optional[str] = None
    patient_name: Optional[str] = None
    created_at: datetime


class DoctorRatingSummary(BaseModel):
    average_rating: Optional[float] = None
    review_count: int = 0
    reviews: List[ReviewResponse] = []


# ─── Sensor Data ─────────────────────────────────────────────────────────────

class SensorDataCreate(BaseModel):
    patient_id: str
    heart_rate: int = Field(ge=20, le=300)
    temperature: float = Field(ge=30.0, le=45.0)
    ecg: float = 0
    emg: float = 0
    gsr: float = 0
    waveforms: Optional[dict] = None


class SensorDataBatchCreate(BaseModel):
    readings: List[SensorDataCreate]


class SensorDataResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    patient_id: str
    heart_rate: int
    temperature: float
    ecg: float = 0
    emg: float = 0
    gsr: float = 0
    waveforms: Optional[dict] = None
    timestamp: datetime


class SensorAlert(BaseModel):
    reading_id: int
    patient_id: str
    timestamp: datetime
    alerts: List[str]
    heart_rate: int
    temperature: float


# ─── Notification ────────────────────────────────────────────────────────────

class NotificationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    title: str
    message: str
    is_read: bool
    created_at: datetime


# ─── Documents ───────────────────────────────────────────────────────────────

class DocumentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    patient_id: str
    uploaded_by: Optional[str] = None
    category: str
    file_name: str
    file_url: str
    upload_date: datetime


# ─── Profile Update Request ──────────────────────────────────────────────────

class ProfileUpdateRequestCreate(BaseModel):
    request_type: str
    old_value: Optional[str] = None
    new_value: str


class ProfileUpdateRequestResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    patient_id: str
    request_type: str
    old_value: Optional[str] = None
    new_value: str
    status: str
    doctor_id: Optional[str] = None
    created_at: datetime


# ─── AI ──────────────────────────────────────────────────────────────────────

class AIChatRequest(BaseModel):
    message: str
    conversation_id: Optional[str] = None
    language: Optional[str] = None


class AIChatResponse(BaseModel):
    response: str
    conversation_id: Optional[str] = None
    disclaimer: str
    remaining_messages: Optional[int] = None
    message_count: Optional[int] = None
    max_messages: Optional[int] = None


class AIExtractRequest(BaseModel):
    transcript: Optional[str] = None
    text: Optional[str] = None
    patient_id: Optional[str] = None

    @property
    def actual_transcript(self) -> str:
        return self.transcript or self.text or ""


class AIExtractResponse(BaseModel):
    extracted_data: dict
    source: str  # "lm_studio" or "mock"


class AIReviewRequest(BaseModel):
    transcript: Optional[str] = None
    text: Optional[str] = None
    extracted_data: Optional[dict] = None
    structured: Optional[dict] = None
    prompt: Optional[str] = None
    question: Optional[str] = None

    @property
    def actual_transcript(self) -> str:
        return self.transcript or self.text or ""

    @property
    def actual_extracted(self) -> dict:
        return self.extracted_data or self.structured or {}

    @property
    def actual_prompt(self) -> str:
        return (self.prompt or self.question or "").strip()


class AIReviewSuggestion(BaseModel):
    category: str
    field: str
    suggested_value: str
    confidence: float
    explanation: str
    source_snippet: str = ""


class AIReviewResponse(BaseModel):
    answer: str = "partial"
    message: str = ""
    suggestions: List[AIReviewSuggestion]
    language_detected: Optional[str] = None
    review_count: int = 0


class AISuggestionCreate(BaseModel):
    patient_id: Optional[str] = None
    patient: Optional[str] = None
    appointment_id: Optional[str] = None
    appointment: Optional[str] = None
    transcript: Optional[str] = None
    notes: Optional[str] = None
    extracted_data: Optional[dict] = None
    symptoms: Optional[str] = None
    soap_subjective: Optional[str] = None
    soap_objective: Optional[str] = None
    soap_assessment: Optional[str] = None
    soap_plan: Optional[str] = None
    status: Optional[str] = None

    @property
    def actual_patient_id(self) -> str:
        pid = self.patient_id or self.patient
        return str(pid) if pid is not None else ""

    @property
    def actual_appointment_id(self) -> str | None:
        aid = self.appointment_id or self.appointment
        return str(aid) if aid is not None else None

    @property
    def actual_transcript(self) -> str | None:
        return self.transcript or self.notes

    @property
    def actual_extracted_data(self) -> dict:
        if self.extracted_data:
            return self.extracted_data
        result: dict = {}
        if self.symptoms:
            result["symptoms"] = self.symptoms
        if self.soap_subjective or self.soap_objective or self.soap_assessment or self.soap_plan:
            result["soap_note"] = {
                "subjective": self.soap_subjective or "",
                "objective": self.soap_objective or "",
                "assessment": self.soap_assessment or "",
                "plan": self.soap_plan or "",
            }
        return result if result else {"notes": self.notes or "Pending review"}


class AISuggestionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    doctor_id: str
    patient_id: str
    appointment_id: Optional[str] = None
    transcript: Optional[str] = None
    extracted_data: str
    status: str
    created_at: datetime


class AIConversationCreate(BaseModel):
    role: str
    messages: str  # JSON string
    summary: Optional[str] = None


class AIConversationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    role: str
    messages: str
    summary: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class VoiceTranscribeResponse(BaseModel):
    transcript: str
    language: str
    model: str


class VoiceSpeakRequest(BaseModel):
    text: str
    language: Optional[str] = "en"


class VoiceSpeakResponse(BaseModel):
    audio_base64: str
    content_type: str = "audio/mpeg"


# ─── Clinic Settings ─────────────────────────────────────────────────────────

class ClinicSettingsUpdate(BaseModel):
    clinic_name: Optional[str] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    logo_url: Optional[str] = None
    default_fee: Optional[float] = None
    working_hours_start: Optional[str] = None
    working_hours_end: Optional[str] = None
    working_days: Optional[str] = None
    appointment_duration: Optional[int] = None


class ClinicSettingsResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    clinic_name: str
    address: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    logo_url: Optional[str] = None
    default_fee: float
    working_hours_start: str
    working_hours_end: str
    working_days: str
    appointment_duration: int


# ─── Audit Log ───────────────────────────────────────────────────────────────

class AuditLogResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: Optional[str] = None
    action: str
    entity_type: str
    entity_id: str
    details: Optional[str] = None
    timestamp: datetime


# ─── Dashboard ───────────────────────────────────────────────────────────────

class AdminDashboard(BaseModel):
    total_patients: int
    total_doctors: int
    total_receptionists: int = 0
    total_appointments: int
    total_prescriptions: int = 0
    pending_appointments: int
    confirmed_appointments: int = 0
    arrived_appointments: int = 0
    completed_appointments: int
    cancelled_appointments: int = 0
    total_revenue: float
    revenue: float = 0
    paid_revenue: float = 0
    refunded_revenue: float = 0
    paid_payments_count: int = 0
    refunded_payments_count: int = 0
    chart_data: list[dict] = Field(default_factory=list)
    status_distribution: dict[str, int] = Field(default_factory=dict)


class ReceptionistDashboard(BaseModel):
    today_appointments: int
    pending_appointments: int
    confirmed_appointments: int
    completed_appointments: int
    arrived_appointments: int = 0
    today_revenue: float


class ReceptionistClinicInfo(BaseModel):
    default_fee: float
    appointment_duration: int


class ReceptionistBookAppointment(BaseModel):
    patient_id: str
    doctor_id: str
    date: date
    time_slot: str
    notes: Optional[str] = None


class ReceptionistPatientSearchResult(BaseModel):
    profile_id: str
    name: str
    email: Optional[str] = None
    phone: Optional[str] = None


# ─── Receptionist Patient Registration ────────────────────────────────────────

class ReceptionistPatientCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    email: str
    first_name: str
    last_name: str
    phone: str
    dob: date = Field(..., validation_alias=AliasChoices("dob", "date_of_birth"))
    gender: str
    middle_name: str = ""
    address: str = ""
    emergency_contact_name: str = ""
    emergency_contact_phone: str = ""
    blood_type: str = "Unknown"
    allergies: str = ""
    chronic_diseases: str = ""

    @field_validator("first_name", "last_name", "phone", "gender")
    @classmethod
    def _strip_required(cls, v: str) -> str:
        v = (v or "").strip()
        if not v:
            raise ValueError("This field is required")
        return v

    @field_validator("phone")
    @classmethod
    def _validate_phone(cls, v: str) -> str:
        v = (v or "").strip()
        digits = re.sub(r"\D", "", v)
        if len(digits) < 8:
            raise ValueError("Enter a valid phone number (at least 8 digits)")
        return v

    @field_validator("email", mode="before")
    @classmethod
    def _normalize_email(cls, v: str) -> str:
        email = (v or "").lower().strip()
        if not re.match(r"^[\w.\+-]+@[\w.-]+\.\w{2,}$", email):
            raise ValueError("Invalid email address")
        return email

    @field_validator("blood_type", mode="before")
    @classmethod
    def _default_blood_type(cls, v) -> str:
        if v is None or (isinstance(v, str) and not v.strip()):
            return "Unknown"
        return str(v).strip()


# ─── User Listing ────────────────────────────────────────────────────────────

class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    email: str
    phone: Optional[str] = None
    role: str
    is_active: bool
    must_change_password: bool
    created_at: datetime
    profile: Optional[ProfileResponse] = None


class AdminDoctorInfo(BaseModel):
    doctor_id: str
    specialty_id: Optional[int] = None
    specialty_name: Optional[str] = None
    qualifications: Optional[str] = None
    bio: Optional[str] = None


class AdminUserListItem(UserResponse):
    doctor_info: Optional[AdminDoctorInfo] = None


class AdminCreate(BaseModel):
    email: str
    password: Optional[str] = None
    first_name: str
    last_name: str
    phone: str
    dob: Optional[date] = None
    gender: Optional[str] = "Unknown"
    address: str = ""
    emergency_contact_name: str = ""
    emergency_contact_phone: str = ""
    blood_type: str = "Unknown"


class AdminPatientDetailResponse(BaseModel):
    user: UserResponse
    profile_id: str
    stats: dict
    appointments: list
    records: list
    prescriptions: list
    payments: list
    documents: list[DocumentResponse]


# ─── Chart Data ──────────────────────────────────────────────────────────────

class ChartDataPoint(BaseModel):
    label: str
    value: int


class ReceptionistCreate(BaseModel):
    email: str
    password: Optional[str] = None
    first_name: str
    last_name: str
    phone: str
    dob: Optional[date] = None
    gender: Optional[str] = "Unknown"
    address: str = ""
    emergency_contact_name: str = ""
    emergency_contact_phone: str = ""
    blood_type: str = "Unknown"


class ReceptionistUpdate(BaseModel):
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
