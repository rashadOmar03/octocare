import os
import re
import uuid
import json
import base64
from datetime import date, datetime, timedelta

from openai import OpenAI
from json_repair import repair_json
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from sqlalchemy.orm import Session

from database import get_db
from models import (
    User, Profile, Doctor, MedicalRecord, Appointment,
    AIConversation, AISuggestion, AuditLog,
    Prescription, PrescriptionItem,
    ClinicSettings,
)
from schemas import (
    AIChatRequest, AIChatResponse, AIExtractRequest, AIExtractResponse,
    AIReviewRequest, AIReviewResponse,
    AISuggestionCreate, AISuggestionResponse,
    AIConversationCreate, AIConversationResponse,
    VoiceTranscribeResponse, VoiceSpeakRequest, VoiceSpeakResponse,
)
from auth import get_current_user, require_role
from voice_service import transcribe_bytes, synthesize_speech_sync, whisper_is_available
from extraction_review import run_extraction_review
from medical_extraction import (
    EXTRACTION_SYSTEM_PROMPT,
    EXTRACTION_USER_PREFIX,
    MOCK_EXTRACTION,
    mock_extraction_for_language,
    detect_input_language,
    build_api_response,
    normalize_extraction,
    structured_to_record_fields,
)
from agent_tools import (
    tool_clinic_settings,
    tool_list_specialties,
    tool_list_doctors,
    tool_get_doctor_reviews,
    tool_doctor_availability,
    tool_my_appointments_patient,
    tool_today_dashboard,
    tool_revenue_summary,
    tool_cancellations,
    tool_doctor_workload,
    tool_doctor_schedule_today,
    tool_doctor_reviews_summary,
    tool_admin_dashboard,
    tool_compare_doctors,
    tool_staff_list,
    tool_search_patient,
    tool_audit_summary,
    tool_live_queue,
)
from agent_intent import detect_intent, detect_language as _agent_detect_lang
from agent_router import (
    baseline_intents_for_role,
    classify_intents_semantic,
    merge_intent_results,
)

router = APIRouter()

LM_STUDIO_URL = os.getenv("LM_STUDIO_URL", "http://127.0.0.1:1234/v1")
LM_STUDIO_MODEL = os.getenv("LM_STUDIO_MODEL", "gemma-4-E2B-it-Q4_K_M")
LM_API_KEY = os.getenv("LM_API_KEY", "lm-studio")

ARABIC_RE = re.compile(r"[\u0600-\u06FF]")


def _detect_language(text: str) -> str:
    if ARABIC_RE.search(text):
        return "ar"
    return "en"


def _get_client() -> OpenAI:
    return OpenAI(base_url=LM_STUDIO_URL, api_key=LM_API_KEY)


def _call_model(
    system_prompt: str,
    user_message: str,
    temperature: float = 0.3,
    max_tokens: int = 2048,
    history: list[dict] | None = None,
    json_mode: bool = False,
) -> str | None:
    import logging
    logger = logging.getLogger("ai_router")
    try:
        client = _get_client()
        messages = [{"role": "system", "content": system_prompt}]
        if history:
            messages.extend(history)
        messages.append({"role": "user", "content": user_message})
        kwargs: dict = {
            "model": LM_STUDIO_MODEL,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if json_mode:
            kwargs["response_format"] = {"type": "json_object"}
        response = client.chat.completions.create(**kwargs)
        content = response.choices[0].message.content
        return content if content else None
    except Exception as e:
        logger.error(f"LLM call failed: {e}")
        return None


def _clean_json(text: str) -> dict:
    text = re.sub(r"```json", "", text)
    text = re.sub(r"```", "", text)
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("No JSON found")
    text = text[start:end + 1]
    repaired = repair_json(text)
    return json.loads(repaired)


CHAT_PROMPTS = {
    "patient": {
        "en": (
            "You are a helpful, empathetic medical assistant for patients at Octocare Clinic.\n"
            "You provide general health guidance, help patients understand symptoms, "
            "and guide them on when to see a doctor.\n\n"
            "RULES:\n"
            "- NEVER diagnose or prescribe medications\n"
            "- Always recommend consulting a doctor for medical concerns\n"
            "- Be warm, caring, and clear in your responses\n"
            "- Keep responses concise but helpful\n"
            "- You can help with: understanding symptoms, which specialty to visit, "
            "appointment booking guidance, general wellness tips\n"
            "- Reply in English"
        ),
        "ar": (
            "أنت مساعد طبي ذكي ومتعاطف للمرضى في عيادة ذكية.\n"
            "تقدم إرشادات صحية عامة، وتساعد المرضى على فهم أعراضهم، "
            "وتوجههم متى يجب زيارة الطبيب.\n\n"
            "القواعد:\n"
            "- لا تشخص أبداً ولا تصف أدوية\n"
            "- دائماً أوصِ باستشارة الطبيب للمخاوف الطبية\n"
            "- كن دافئاً ومهتماً وواضحاً في ردودك\n"
            "- اجعل الردود مختصرة لكن مفيدة\n"
            "- يمكنك المساعدة في: فهم الأعراض، التخصص المناسب، "
            "حجز المواعيد، نصائح صحية عامة\n"
            "- أجب بالعربية فقط"
        ),
    },
    "doctor": {
        "en": (
            "You are a clinical decision support assistant for doctors at Octocare Clinic.\n"
            "You help doctors with evidence-based suggestions, structuring SOAP notes, "
            "differential diagnoses, and treatment considerations.\n\n"
            "RULES:\n"
            "- Provide evidence-based medical information\n"
            "- Help structure clinical notes and visit summaries\n"
            "- Suggest differential diagnoses when asked\n"
            "- All clinical decisions remain with the doctor\n"
            "- Be professional and concise\n"
            "- Reply in English"
        ),
        "ar": (
            "أنت مساعد دعم قرار سريري للأطباء في عيادة ذكية.\n"
            "تساعد الأطباء في اقتراحات مبنية على الأدلة، تنظيم ملاحظات SOAP، "
            "التشخيص التفريقي، واعتبارات العلاج.\n\n"
            "القواعد:\n"
            "- قدم معلومات طبية مبنية على الأدلة\n"
            "- ساعد في تنظيم الملاحظات السريرية وملخصات الزيارات\n"
            "- اقترح تشخيصات تفريقية عند السؤال\n"
            "- جميع القرارات السريرية تبقى مع الطبيب\n"
            "- كن محترفاً ومختصراً\n"
            "- أجب بالعربية فقط"
        ),
    },
    "receptionist": {
        "en": (
            "You are an assistant for clinic receptionists.\n"
            "Help with scheduling, queue management, patient registration, "
            "and payment processing questions.\n"
            "Be professional and helpful. Reply in English."
        ),
        "ar": (
            "أنت مساعد لموظفي الاستقبال في العيادة.\n"
            "ساعد في الجدولة، إدارة قائمة الانتظار، تسجيل المرضى، "
            "ومعالجة المدفوعات.\n"
            "كن محترفاً ومفيداً. أجب بالعربية فقط."
        ),
    },
    "admin": {
        "en": (
            "You are a clinic management assistant for administrators.\n"
            "Help with system analytics, user management, clinic configuration, "
            "staff scheduling, and operational optimization.\n"
            "Be professional and data-driven. Reply in English."
        ),
        "ar": (
            "أنت مساعد إدارة عيادة للمسؤولين.\n"
            "ساعد في تحليلات النظام، إدارة المستخدمين، تكوين العيادة، "
            "جدولة الموظفين، وتحسين العمليات.\n"
            "كن محترفاً ومعتمداً على البيانات. أجب بالعربية فقط."
        ),
    },
}

DISCLAIMERS = {
    "patient": "This assistant provides general guidance only. Always consult a doctor for medical advice.",
    "doctor": "These are AI-generated suggestions. Clinical decisions are yours.",
    "receptionist": "AI assistant for receptionist support.",
    "admin": "AI assistant for administrative support.",
}


# ─── Chat ────────────────────────────────────────────────────────────────────

@router.post("/chat", response_model=AIChatResponse)
async def ai_chat(
    data: AIChatRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    lang = data.language if data.language in ("ar", "en") else _detect_language(data.message)
    role = current_user.role if current_user.role in CHAT_PROMPTS else "patient"
    system_prompt = CHAT_PROMPTS[role].get(lang, CHAT_PROMPTS[role]["en"])
    disclaimer = DISCLAIMERS.get(role, "AI-generated response.")

    response_text = _call_model(system_prompt, data.message, temperature=0.7, max_tokens=1024)

    if not response_text:
        if lang == "ar":
            response_text = (
                "عذراً، نموذج الذكاء الاصطناعي غير متصل حالياً.\n\n"
                "لتفعيل المساعد الذكي:\n"
                "1. افتح برنامج LM Studio\n"
                "2. حمّل نموذج Gemma\n"
                "3. شغّل السيرفر المحلي\n\n"
                "في الوقت الحالي، يمكنك استخدام باقي ميزات التطبيق بشكل طبيعي."
            )
        else:
            response_text = (
                "Sorry, the AI model is not connected right now.\n\n"
                "To enable the AI assistant:\n"
                "1. Open LM Studio\n"
                "2. Load the Gemma model\n"
                "3. Start the local server\n\n"
                "In the meantime, you can use all other app features normally."
            )

    return AIChatResponse(
        response=response_text,
        conversation_id=data.conversation_id,
        disclaimer=disclaimer,
    )


# ─── Agent ────────────────────────────────────────────────────────────────────

MAX_MESSAGES_PER_CHAT = 50

_FORMAT_RULES = (
    "\n\nFORMATTING RULES (very important):\n"
    "- NEVER use markdown asterisks (* or **) for bold or bullets\n"
    "- Use numbered lists (1. 2. 3.) for steps\n"
    "- Use dashes (-) for simple bullet points\n"
    "- Write clean plain text, well-organized with line breaks\n"
    "- Separate sections with a blank line\n"
    "- Be conversational and friendly, like a helpful human assistant\n"
    "- Keep answers focused and concise\n"
    "\n\nGROUNDING RULES (MANDATORY — breaking these = critical system failure):\n"
    "- You MUST answer ONLY using data from the CLINIC DATA section below\n"
    "- Every number you state MUST come directly from CLINIC DATA\n"
    "- If CLINIC DATA says total_patients: 5, you say 5 — not 5000, not 50\n"
    "- NEVER add percentages, breakdowns, or details not explicitly in the data\n"
    "- If the data says 0 results, empty list, or NOT FOUND — say exactly that\n"
    "- NEVER invent patient names, doctor names, appointments, or numbers\n"
    "- If you don't have data to answer a question, say 'I don't have that information'\n"
    "- DO NOT hallucinate or make up any data under any circumstances\n"
)

_LANG_RULE = (
    "\n\nLANGUAGE RULE (critical):\n"
    "Reply in the SAME language and dialect the user writes in.\n"
    "- If they write in Egyptian Arabic (عامية مصرية), reply in Egyptian Arabic\n"
    "- If they write in formal/standard Arabic (فصحى), reply in formal Arabic\n"
    "- If they write in English, reply in English\n"
    "- If they mix languages, match whatever they use most\n"
    "- NEVER switch language unless the user does\n"
    "- When replying in Arabic, TRANSLATE English data terms to Arabic.\n"
    "  Examples: Cardiology = أمراض القلب, Dermatology = الأمراض الجلدية,\n"
    "  Pediatrics = طب الأطفال, Orthopedics = العظام, Neurology = الأعصاب,\n"
    "  General Medicine = طب عام, Internal Medicine = الباطنة,\n"
    "  Ophthalmology = طب العيون, ENT = الأنف والأذن والحنجرة,\n"
    "  Surgery = الجراحة, Dentistry = طب الأسنان, Psychiatry = الطب النفسي,\n"
    "  Urology = المسالك البولية, Gynecology = أمراض النساء والتوليد\n"
    "- Keep doctor names as-is (don't translate names)\n"
    "- Translate status words: pending = في الانتظار, confirmed = مؤكد,\n"
    "  completed = مكتمل, cancelled = ملغي, paid = مدفوع, refunded = مسترد\n"
)

_AGENT_SYSTEM: dict[str, str] = {
    "patient": (
        "You are a helpful assistant for patients at Octocare Clinic.\n"
        "You have access to REAL clinic data provided in the CLINIC DATA section below.\n"
        "Use ONLY that data when quoting names, ratings, hours, or fees. Never invent facts.\n\n"
        "RULES:\n"
        "- Never diagnose or prescribe, that is for doctors only\n"
        "- Always recommend seeing a doctor for medical concerns\n"
        "- Guide patients through the booking process step by step\n"
        "- Be warm, caring, and clear\n"
        "- When listing doctors, show their name, specialty, and rating clearly\n"
        "- IMPORTANT: When DOCTOR AVAILABILITY data is provided, you MUST show the actual\n"
        "  available time slots from the data. List them clearly (e.g. 09:00, 09:30, 10:00).\n"
        "  Never say 'I cannot determine appointments' when availability data exists.\n"
        "- If the user asks about a specific doctor's schedule or availability,\n"
        "  show the exact slots, date, and working hours from the data.\n"
        "- When MY APPOINTMENTS data is provided, answer from that list first.\n"
        "  If the list is empty, say the patient has no appointments on record — do NOT\n"
        "  claim you lack access to their bookings.\n"
        "- If they also ask how to book, explain the in-app booking steps after listing\n"
        "  their appointments (or after confirming they have none)."
        + _FORMAT_RULES + _LANG_RULE
    ),
    "receptionist": (
        "You are a clinic operations assistant for receptionists at Octocare Clinic.\n"
        "You have access to REAL clinic data in the CLINIC DATA section below.\n"
        "Use ONLY facts from that section. NEVER invent names, numbers, or details.\n\n"
        "RULES:\n"
        "- Give clear operational insights from the provided numbers\n"
        "- Highlight urgent items (pending payments, long queues, cancellations)\n"
        "- Suggest practical action plans based on the actual data\n"
        "- When DOCTOR AVAILABILITY data is provided, show the actual time slots clearly\n"
        "- When LIVE QUEUE data is provided, clearly state:\n"
        "  * Who is CURRENTLY with each doctor (the patient being seen right now)\n"
        "  * How many patients are WAITING and their names\n"
        "  * Who has upcoming confirmed appointments\n"
        "  Use patient names from the data. Never say you don't have access to patient names.\n"
        "- Be concise and professional"
        + _FORMAT_RULES + _LANG_RULE
    ),
    "doctor": (
        "You are a personal clinic assistant for the LOGGED-IN doctor at Octocare Clinic.\n"
        "You have access to REAL clinic data in the CLINIC DATA section below.\n"
        "Use ONLY facts from that section. NEVER invent names, numbers, or details.\n\n"
        "RULES:\n"
        "- When asked about 'my schedule' or 'my patients', only show THIS doctor's data\n"
        "- Do NOT show other doctors' schedules unless explicitly asked\n"
        "- Help with schedule, queue, and operational questions\n"
        "- Summarise patient reviews honestly from the data\n"
        "- General clinical info is for reference only, all decisions are yours\n"
        "- Do NOT replace the SOAP extraction or prescription tools\n"
        "- When DOCTOR AVAILABILITY data is provided, show the actual time slots clearly\n"
        "- Be professional and concise"
        + _FORMAT_RULES + _LANG_RULE
    ),
    "admin": (
        "You are a clinic management assistant for administrators at Octocare Clinic.\n"
        "You have access to REAL clinic data in the CLINIC DATA section below.\n\n"
        "ABSOLUTE RULES (violation = system failure):\n"
        "- ONLY use numbers, names, and facts from the CLINIC DATA section below\n"
        "- If CLINIC DATA says total_patients: 12, you say 12. NEVER invent different numbers\n"
        "- If CLINIC DATA has no info on a topic, say 'I don't have that data'\n"
        "- NEVER make up statistics, percentages, or breakdowns not in the data\n"
        "- You can search for specific patients by name when asked\n"
        "- You will NOT dump all patient records at once (privacy)\n"
        "- You can compare doctors, analyse revenue, review audit logs\n"
        "- You cannot modify any data through this chat\n"
        "- If patient search returns empty, say 'patient not found' — do NOT invent a match"
        + _FORMAT_RULES + _LANG_RULE
    ),
}


def _facts_to_prompt(facts: dict) -> str:
    """Serialise fetched DB facts to a readable text block for the system prompt."""
    if not facts:
        return "(No clinic data fetched for this query)"
    lines = []
    for key, value in facts.items():
        lines.append(f"### {key.replace('_', ' ').upper()}")
        if isinstance(value, list):
            if not value:
                lines.append("  (none)")
            else:
                for item in value[:20]:          # cap list length in prompt
                    if isinstance(item, dict):
                        row = ", ".join(
                            f"{k}: {v}"
                            for k, v in item.items()
                            if v is not None and v != ""
                        )
                        lines.append(f"  - {row}")
                    else:
                        lines.append(f"  - {item}")
        elif isinstance(value, dict):
            for k, v in value.items():
                if v is not None:
                    lines.append(f"  {k}: {v}")
        else:
            lines.append(f"  {value}")
        lines.append("")
    return "\n".join(lines)


def _extract_search_term(message: str) -> str | None:
    """Try to pull a patient name from an admin search query."""
    patterns = [
        r"patient\s+(?:named?|called)\s+([A-Za-z\u0600-\u06FF]+(?:\s+[A-Za-z\u0600-\u06FF]+)?)",
        r"(?:مريض|مريضة)\s+(?:اسمه|اسمها|يسمى)?\s*([A-Za-z\u0600-\u06FF]+(?:\s+[A-Za-z\u0600-\u06FF]+)?)",
        r"find\s+(?:patient\s+)?([A-Za-z\u0600-\u06FF]+(?:\s+[A-Za-z\u0600-\u06FF]+)?)",
        r"tell\s+me\s+about\s+(?:patient\s+)?([A-Za-z\u0600-\u06FF]+(?:\s+[A-Za-z\u0600-\u06FF]+)?)",
    ]
    for p in patterns:
        m = re.search(p, message, re.IGNORECASE)
        if m:
            return m.group(1).strip()
    return None


def _get_doctor_id(user: User, db: Session) -> str | None:
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if not profile:
        return None
    doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first()
    return doctor.id if doctor else None


def _extract_doctor_name(message: str) -> str | None:
    _STOP_WORDS = {
        "the", "a", "an", "my", "is", "for", "on", "at", "tomorrow", "today",
        "available", "free", "when", "any", "all", "am", "i", "are", "what",
        "who", "how", "do", "does", "can", "will", "be", "been", "being",
        "have", "has", "had", "there", "they", "slots", "slot",
        "في", "من", "على", "إلى", "هل", "ما", "لا", "أي", "كل", "هو", "هي",
    }
    patterns = [
        r"(?:dr\.?|doctor|دكتور|طبيب)\s+([A-Za-z\u0600-\u06FF]+)",
        r"with\s+([A-Za-z]+)\s+(?:tomorrow|today|next|available)",
        r"([A-Za-z\u0600-\u06FF]+)\s+(?:available|متاح|فاضي)",
    ]
    for p in patterns:
        m = re.search(p, message, re.IGNORECASE)
        if m:
            name = m.group(1).strip()
            if name.lower() not in _STOP_WORDS:
                return name
    return None


def _extract_target_date(message: str) -> date | None:
    msg = message.lower()
    today = date.today()
    if any(w in msg for w in (
        "after tomorrow", "بعد بكرا", "بعد بكره", "بعد بكرة", "بعد غد", "بعد غدا",
    )):
        return today + timedelta(days=2)
    if any(w in msg for w in (
        "tomorrow", "بكرا", "بكره", "بكرة", "غدا", "غداً",
    )):
        return today + timedelta(days=1)
    if any(w in msg for w in (
        "today", "اليوم", "النهارده", "النهاردة", "النهارده", "دلوقتي", "دلوقت",
    )):
        return today
    # Try specific date patterns: "july 5", "5/7", "2026-07-05"
    m = re.search(r"(\d{4})-(\d{1,2})-(\d{1,2})", msg)
    if m:
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            pass
    m = re.search(r"(\d{1,2})/(\d{1,2})", msg)
    if m:
        try:
            return date(today.year, int(m.group(2)), int(m.group(1)))
        except ValueError:
            pass
    return None


def _fetch_agent_facts(
    intents: list[str],
    role: str,
    current_user: User,
    message: str,
    db: Session,
) -> dict:
    """Run the tools indicated by intents and merge the results."""
    facts: dict = {}

    # ── Clinic info / specialties / doctors ───────────────────────────────────
    if "clinic_info" in intents:
        facts["clinic_settings"] = tool_clinic_settings(db)

    if "clinic_info" in intents or "doctor_search" in intents or "symptom_advice" in intents:
        facts["specialties"] = tool_list_specialties(db)

    if "doctor_search" in intents or "symptom_advice" in intents:
        doctors = tool_list_doctors(db)
        facts["doctors"] = doctors
        # Include reviews for top-rated doctors (up to 3)
        top = sorted(
            [d for d in doctors if d["review_count"] > 0],
            key=lambda x: x["average_rating"] or 0,
            reverse=True,
        )[:3]
        if top:
            facts["sample_reviews"] = {
                d["name"]: tool_get_doctor_reviews(db, d["doctor_id"], limit=2)
                for d in top
            }

    # ── Doctor availability (all roles can ask) ────────────────────────────────
    if "doctor_availability" in intents:
        doc_name = _extract_doctor_name(message)
        target = _extract_target_date(message)
        avail = tool_doctor_availability(db, doctor_name=doc_name, target_date=target)
        if avail:
            facts["doctor_availability"] = avail
        elif doc_name:
            all_avail = tool_doctor_availability(db, doctor_name=None, target_date=target)
            if all_avail:
                facts["doctor_availability"] = all_avail
                facts["doctor_availability_note"] = (
                    f"No exact match for '{doc_name}'. "
                    "Showing all doctors' availability so you can help the user."
                )
            else:
                facts["doctor_availability_note"] = "No doctors available on this date."
        else:
            all_avail = tool_doctor_availability(db, doctor_name=None, target_date=target)
            facts["doctor_availability"] = all_avail

    # ── Patient appointments ───────────────────────────────────────────────────
    if "my_appointments" in intents and role == "patient":
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if profile:
            facts["my_appointments"] = tool_my_appointments_patient(db, profile.id)

    # ── Live queue (who is currently with doctor) ──────────────────────────────
    if "live_queue" in intents and role in ("receptionist", "admin"):
        doc_name = _extract_doctor_name(message)
        facts["live_queue"] = tool_live_queue(db, doctor_name=doc_name)

    # ── Receptionist / admin / doctor ops ─────────────────────────────────────
    if "today_stats" in intents and role in ("receptionist", "admin", "doctor"):
        facts["today"] = tool_today_dashboard(db)
        if role in ("receptionist", "admin"):
            facts["doctor_workload_today"] = tool_doctor_workload(db)

    if "doctor_workload" in intents and role in ("receptionist", "admin"):
        facts["doctor_workload_today"] = tool_doctor_workload(db)

    if "revenue" in intents and role in ("receptionist", "admin"):
        facts["revenue_last_7_days"] = tool_revenue_summary(db, 7)
        facts["revenue_last_30_days"] = tool_revenue_summary(db, 30)

    if "cancellations" in intents and role in ("receptionist", "admin"):
        cancelled = tool_cancellations(db, 7)
        facts["cancellations_last_7_days"] = cancelled
        settings = db.query(ClinicSettings).first()
        default_fee = float(settings.default_fee) if settings else 100.0
        facts["estimated_lost_revenue_7d"] = len(cancelled) * default_fee
        facts["note_on_estimate"] = (
            "The estimated lost revenue is calculated as: "
            "number of cancellations × default appointment fee. "
            "It is an approximation, not an exact figure."
        )

    # ── Doctor ops ────────────────────────────────────────────────────────────
    if "my_schedule" in intents and role == "doctor":
        doc_id = _get_doctor_id(current_user, db)
        if doc_id:
            facts["my_schedule_today"] = tool_doctor_schedule_today(db, doc_id)
            facts["my_reviews"] = tool_doctor_reviews_summary(db, doc_id)

    if "my_reviews" in intents and role == "doctor":
        doc_id = _get_doctor_id(current_user, db)
        if doc_id:
            facts["my_reviews"] = tool_doctor_reviews_summary(db, doc_id)

    # ── Admin ─────────────────────────────────────────────────────────────────
    if role == "admin":
        if "admin_overview" in intents:
            facts["admin_dashboard"] = tool_admin_dashboard(db)

        if "doctor_compare" in intents:
            facts["doctor_comparison_30d"] = tool_compare_doctors(db, 30)

        if "staff_list" in intents:
            facts["staff"] = tool_staff_list(db)

        if "patient_lookup" in intents:
            term = _extract_search_term(message)
            if term:
                try:
                    results = tool_search_patient(db, term)
                except Exception:
                    results = []
                facts["patient_search_results"] = results
                if not results:
                    facts["patient_search_note"] = (
                        f"NO PATIENTS FOUND matching '{term}'. "
                        "This patient does NOT exist in the system. "
                        "Do NOT invent or hallucinate patient data. Tell the user no match was found."
                    )
                else:
                    facts["patient_search_note"] = (
                        f"Showing summary cards for patients matching '{term}'. "
                        "Full medical records, prescriptions, and documents are available "
                        "in the Admin → Patient detail screen — not shown here for privacy."
                    )
            else:
                facts["patient_search_note"] = (
                    "Please include the patient's name in your query, "
                    "e.g. 'find patient Ahmed' or 'tell me about patient Sara'."
                )

    # ── Receptionist patient lookup ──────────────────────────────────────────
    if "patient_lookup" in intents and role == "receptionist":
        if "patient_search_results" not in facts:
            term = _extract_search_term(message)
            if term:
                try:
                    results = tool_search_patient(db, term)
                except Exception:
                    results = []
                facts["patient_search_results"] = results
                if not results:
                    facts["patient_search_note"] = (
                        f"NO PATIENTS FOUND matching '{term}'. "
                        "This patient does NOT exist in the system. Do NOT invent patient data."
                    )
            else:
                facts["patient_search_note"] = (
                    "Please include the patient's name in your query."
                )

    if role == "admin":
        if "audit" in intents:
            facts["recent_audit_7d"] = tool_audit_summary(db, 7)

        if not facts:
            facts["admin_dashboard"] = tool_admin_dashboard(db)

    return facts


@router.post("/agent", response_model=AIChatResponse)
async def agent_chat(
    data: AIChatRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Grounded AI agent — always fetches real DB data before calling Gemma.
    Persists conversation history so the AI remembers context.
    """
    lang = data.language if data.language in ("ar", "en") else _agent_detect_lang(data.message)
    role = current_user.role if current_user.role in _AGENT_SYSTEM else "patient"

    # 1. Load or create conversation
    conv: AIConversation | None = None
    history: list[dict] = []
    if data.conversation_id:
        conv = db.query(AIConversation).filter(
            AIConversation.id == data.conversation_id,
            AIConversation.user_id == current_user.id,
        ).first()
        if conv:
            try:
                history = json.loads(conv.messages) if conv.messages else []
            except (json.JSONDecodeError, TypeError):
                history = []
    if not conv:
        conv = AIConversation(
            user_id=current_user.id,
            role=role,
            messages="[]",
            summary=data.message[:80],
        )
        db.add(conv)
        db.flush()

    if len(history) >= MAX_MESSAGES_PER_CHAT * 2:
        raise HTTPException(
            status_code=429,
            detail="Chat message limit reached. Please start a new conversation.",
        )

    # 2. Route message → DB tools (LLM understands Arabic/English; keywords are fallback)
    keyword_intents = detect_intent(data.message, role)
    semantic_intents = None
    if os.getenv("AGENT_SEMANTIC_ROUTER", "true").lower() not in ("0", "false", "no", "off"):
        semantic_intents = classify_intents_semantic(
            data.message,
            role,
            lambda sys, msg: _call_model(
                sys, msg, temperature=0, max_tokens=256, json_mode=True,
            ),
        )
    intents = merge_intent_results(semantic_intents, keyword_intents, role)
    for baseline in baseline_intents_for_role(role):
        if baseline not in intents:
            intents.append(baseline)

    # 3. Fetch live DB facts
    try:
        facts = _fetch_agent_facts(intents, role, current_user, data.message, db)
    except Exception:
        facts = {"error": "Failed to fetch some data. Answer based on available information."}

    # 4. Build system prompt (no per-language split; language rule is in the prompt)
    base_prompt = _AGENT_SYSTEM.get(role, _AGENT_SYSTEM["patient"])
    facts_block = _facts_to_prompt(facts)
    system_prompt = base_prompt

    # Inject facts into user message for stronger grounding (LLMs follow user context better)
    augmented_message = (
        f"[SYSTEM DATABASE QUERY RESULTS - THIS IS THE ONLY TRUTH]:\n"
        f"{facts_block}\n"
        f"[END DATABASE RESULTS]\n\n"
        f"IMPORTANT: Answer the following question using ONLY the database results above. "
        f"Do NOT make up any numbers or facts. If the data shows total_patients: 12, say 12.\n\n"
        f"User question: {data.message}"
    )

    # 5. Trim history to last 10 message pairs (20 messages) to fit context window
    trimmed = history[-20:] if len(history) > 20 else history

    # 6. Call LLM with history
    response_text = _call_model(
        system_prompt, augmented_message,
        temperature=0.2, max_tokens=1024,
        history=trimmed,
    )

    # 7. Fallback if model offline
    if not response_text:
        if _agent_detect_lang(data.message) == "ar":
            response_text = (
                "نموذج الذكاء الاصطناعي غير متصل حالياً. إليك البيانات الفعلية من النظام:\n\n"
                + facts_block
            )
        else:
            response_text = (
                "AI model is currently offline. Here is the real data from the system:\n\n"
                + facts_block
            )

    # 8. Save to conversation history
    history.append({"role": "user", "content": data.message})
    history.append({"role": "assistant", "content": response_text})

    msg_count = len(history)
    remaining = max(0, MAX_MESSAGES_PER_CHAT * 2 - msg_count)

    if not conv.summary or conv.summary == "[]":
        conv.summary = data.message[:80]
    conv.messages = json.dumps(history, ensure_ascii=False)
    conv.updated_at = datetime.utcnow()
    db.commit()

    disclaimer = DISCLAIMERS.get(role, "AI-generated response based on clinic data.")
    return AIChatResponse(
        response=response_text,
        conversation_id=conv.id,
        disclaimer=disclaimer,
        remaining_messages=remaining // 2,
        message_count=msg_count // 2,
        max_messages=MAX_MESSAGES_PER_CHAT,
    )


# ─── Chat history endpoints ──────────────────────────────────────────────────

@router.get("/chats")
async def list_chats(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = (
        db.query(AIConversation)
        .filter(AIConversation.user_id == current_user.id)
        .order_by(AIConversation.updated_at.desc())
        .limit(50)
        .all()
    )
    result = []
    for c in rows:
        try:
            msgs = json.loads(c.messages) if c.messages else []
        except (json.JSONDecodeError, TypeError):
            msgs = []
        msg_count = len(msgs) // 2
        result.append({
            "id": c.id,
            "summary": c.summary or (msgs[0]["content"][:60] if msgs else "New chat"),
            "message_count": msg_count,
            "remaining_messages": max(0, MAX_MESSAGES_PER_CHAT - msg_count),
            "max_messages": MAX_MESSAGES_PER_CHAT,
            "updated_at": c.updated_at.isoformat() if c.updated_at else None,
            "created_at": c.created_at.isoformat() if c.created_at else None,
        })
    return result


@router.get("/chats/{chat_id}")
async def get_chat(
    chat_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv = db.query(AIConversation).filter(
        AIConversation.id == chat_id,
        AIConversation.user_id == current_user.id,
    ).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Chat not found")
    try:
        msgs = json.loads(conv.messages) if conv.messages else []
    except (json.JSONDecodeError, TypeError):
        msgs = []
    msg_count = len(msgs) // 2
    return {
        "id": conv.id,
        "summary": conv.summary,
        "messages": msgs,
        "message_count": msg_count,
        "remaining_messages": max(0, MAX_MESSAGES_PER_CHAT - msg_count),
        "max_messages": MAX_MESSAGES_PER_CHAT,
        "updated_at": conv.updated_at.isoformat() if conv.updated_at else None,
    }


@router.delete("/chats/{chat_id}")
async def delete_chat(
    chat_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conv = db.query(AIConversation).filter(
        AIConversation.id == chat_id,
        AIConversation.user_id == current_user.id,
    ).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Chat not found")
    db.delete(conv)
    db.commit()
    return {"ok": True}


# ─── Extract ─────────────────────────────────────────────────────────────────

@router.post("/extract")
async def extract_medical_info(
    data: AIExtractRequest,
    current_user: User = Depends(require_role("doctor", "admin")),
    db: Session = Depends(get_db),
):
    transcript = data.actual_transcript
    lang = detect_input_language(transcript)
    prefix = EXTRACTION_USER_PREFIX.get(lang, EXTRACTION_USER_PREFIX["en"])
    user_message = prefix + transcript
    raw = _call_model(EXTRACTION_SYSTEM_PROMPT, user_message, temperature=0, max_tokens=4096, json_mode=True)

    extracted = None
    source = "mock"

    if raw:
        try:
            extracted = _clean_json(raw)
            source = "lm_studio"
        except Exception:
            pass

    if extracted is None:
        extracted = mock_extraction_for_language("ar" if lang in ("ar", "mixed") else "en")

    response = build_api_response(extracted, source, source_text=transcript)
    if source == "mock":
        response["source"] = "mock"
        response["warning"] = "AI model offline — this is placeholder data, not real analysis"
    return response


@router.post("/extract/review", response_model=AIReviewResponse)
async def review_extraction(
    data: AIReviewRequest,
    current_user: User = Depends(require_role("doctor", "admin")),
    db: Session = Depends(get_db),
):
    transcript = data.actual_transcript.strip()
    if not transcript:
        raise HTTPException(status_code=400, detail="Transcript is required")
    extracted = data.actual_extracted
    if not extracted:
        raise HTTPException(status_code=400, detail="Extracted data is required for review")
    if not data.actual_prompt:
        raise HTTPException(status_code=400, detail="Please enter a question for AI Review")

    def _call(system: str, user: str) -> str | None:
        return _call_model(system, user, temperature=0.1, max_tokens=2048)

    result = run_extraction_review(
        transcript,
        extracted,
        doctor_prompt=data.actual_prompt,
        call_model=_call,
    )
    return result


# ─── Suggestions ─────────────────────────────────────────────────────────────

@router.post("/suggestions", response_model=AISuggestionResponse, status_code=status.HTTP_201_CREATED)
def save_suggestion(
    data: AISuggestionCreate,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first() if profile else None
    if not doctor:
        raise HTTPException(status_code=400, detail="Doctor record not found")

    suggestion = AISuggestion(
        id=str(uuid.uuid4()),
        doctor_id=doctor.id,
        patient_id=data.actual_patient_id,
        appointment_id=data.actual_appointment_id,
        transcript=data.actual_transcript,
        extracted_data=json.dumps(data.actual_extracted_data),
    )
    db.add(suggestion)
    db.commit()
    db.refresh(suggestion)
    return suggestion


@router.get("/suggestions")
def get_suggestions(
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    doctor = db.query(Doctor).filter(Doctor.profile_id == profile.id).first() if profile else None
    if not doctor:
        return []

    suggestions = (
        db.query(AISuggestion)
        .filter(AISuggestion.doctor_id == doctor.id, AISuggestion.status == "pending")
        .order_by(AISuggestion.created_at.desc())
        .all()
    )

    results = []
    for s in suggestions:
        patient = db.query(Profile).filter(Profile.id == s.patient_id).first()
        patient_name = f"{patient.first_name or ''} {patient.last_name or ''}".strip() if patient else "Unknown"

        try:
            extracted = json.loads(s.extracted_data) if s.extracted_data else {}
        except (json.JSONDecodeError, TypeError):
            extracted = {}

        results.append({
            "id": s.id,
            "doctor_id": s.doctor_id,
            "patient_id": s.patient_id,
            "patient_name": patient_name,
            "appointment_id": s.appointment_id,
            "transcript": s.transcript,
            "extracted_data": extracted,
            "status": s.status,
            "created_at": s.created_at.isoformat() if s.created_at else None,
            "chief_complaint": extracted.get("chief_complaint"),
            "diagnosis": extracted.get("diagnosis"),
            "symptoms": extracted.get("symptoms"),
            "severity": extracted.get("severity"),
            "treatment_plan": extracted.get("treatment_plan"),
            "medications": extracted.get("medications", []),
            "soap_note": extracted.get("soap_note", {}),
        })
    return results


@router.put("/suggestions/{suggestion_id}/approve", response_model=AISuggestionResponse)
def approve_suggestion(
    suggestion_id: str,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    suggestion = db.query(AISuggestion).filter(AISuggestion.id == suggestion_id).first()
    if not suggestion:
        raise HTTPException(status_code=404, detail="Suggestion not found")

    doctor_profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    doctor = db.query(Doctor).filter(Doctor.profile_id == doctor_profile.id).first() if doctor_profile else None
    if not doctor or suggestion.doctor_id != doctor.id:
        raise HTTPException(status_code=403, detail="Access denied")

    if suggestion.appointment_id:
        from appointment_rules import require_paid_arrived_appointment
        require_paid_arrived_appointment(db, suggestion.appointment_id, doctor_id=doctor.id)

    suggestion.status = "approved"

    try:
        extracted = json.loads(suggestion.extracted_data)
    except json.JSONDecodeError:
        extracted = {}

    extracted = normalize_extraction(extracted)
    fields = structured_to_record_fields(extracted)

    existing = None
    if suggestion.appointment_id:
        existing = (
            db.query(MedicalRecord)
            .filter(MedicalRecord.appointment_id == suggestion.appointment_id)
            .first()
        )

    if existing:
        for key, value in fields.items():
            setattr(existing, key, value)
        record = existing
    else:
        record = MedicalRecord(
            id=str(uuid.uuid4()),
            appointment_id=suggestion.appointment_id,
            patient_id=suggestion.patient_id,
            doctor_id=suggestion.doctor_id,
            chief_complaint=fields["chief_complaint"],
            symptoms=fields["symptoms"],
            diagnosis=fields["diagnosis"],
            severity=fields["severity"],
            treatment_plan=fields["treatment_plan"],
            notes=fields["notes"],
            soap_subjective=fields["soap_subjective"],
            soap_objective=fields["soap_objective"],
            soap_assessment=fields["soap_assessment"],
            soap_plan=fields["soap_plan"],
            structured_data=fields["structured_data"],
        )
        db.add(record)
    db.flush()

    prescription_items = extracted.get("prescription") or []
    if prescription_items:
        prescription = Prescription(
            id=str(uuid.uuid4()),
            medical_record_id=record.id,
            status="active",
        )
        db.add(prescription)
        for med in prescription_items:
            if not isinstance(med, dict):
                continue
            name = (med.get("name") or "").strip()
            if not name:
                continue
            db.add(PrescriptionItem(
                prescription_id=prescription.id,
                medication_name=name,
                dosage=(med.get("dosage") or "—").strip() or "—",
                frequency=(med.get("frequency") or "—").strip() or "—",
                duration=(med.get("duration") or "—").strip() or "—",
                notes=med.get("notes") or med.get("route"),
            ))

    db.add(AuditLog(
        user_id=current_user.id,
        action="approve_ai_suggestion",
        entity_type="ai_suggestion",
        entity_id=suggestion_id,
        details=f"Approved and created medical record {record.id}",
    ))

    db.commit()
    db.refresh(suggestion)
    return suggestion


@router.put("/suggestions/{suggestion_id}/reject", response_model=AISuggestionResponse)
def reject_suggestion(
    suggestion_id: str,
    current_user: User = Depends(require_role("doctor")),
    db: Session = Depends(get_db),
):
    suggestion = db.query(AISuggestion).filter(AISuggestion.id == suggestion_id).first()
    if not suggestion:
        raise HTTPException(status_code=404, detail="Suggestion not found")

    doctor_profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    doctor = db.query(Doctor).filter(Doctor.profile_id == doctor_profile.id).first() if doctor_profile else None
    if not doctor or suggestion.doctor_id != doctor.id:
        raise HTTPException(status_code=403, detail="Access denied")

    suggestion.status = "rejected"
    db.commit()
    db.refresh(suggestion)
    return suggestion


# ─── Conversations ───────────────────────────────────────────────────────────

@router.get("/conversations", response_model=list[AIConversationResponse])
def get_conversations(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return (
        db.query(AIConversation)
        .filter(AIConversation.user_id == current_user.id)
        .order_by(AIConversation.updated_at.desc())
        .all()
    )


@router.post("/conversations", response_model=AIConversationResponse, status_code=status.HTTP_201_CREATED)
def save_conversation(
    data: AIConversationCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conversation = AIConversation(
        id=str(uuid.uuid4()),
        user_id=current_user.id,
        role=data.role,
        messages=data.messages,
        summary=data.summary,
    )
    db.add(conversation)
    db.commit()
    db.refresh(conversation)
    return conversation


@router.get("/voice/status")
def voice_status(current_user: User = Depends(get_current_user)):
    from voice_service import _groq_whisper_available
    return {
        "whisper_available": whisper_is_available(),
        "groq_whisper": _groq_whisper_available(),
        "doctor_model": "medium",
        "other_roles_model": "small",
    }


@router.post("/transcribe", response_model=VoiceTranscribeResponse)
async def transcribe_voice(
    file: UploadFile = File(...),
    language: str | None = Form(None),
    current_user: User = Depends(get_current_user),
):
    if not whisper_is_available():
        raise HTTPException(
            status_code=503,
            detail="Voice input is not configured. Set GROQ_API_KEY or install faster-whisper.",
        )
    audio_bytes = await file.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Empty audio file")

    suffix = ".webm"
    if file.filename and "." in file.filename:
        suffix = "." + file.filename.rsplit(".", 1)[-1].lower()

    try:
        result = transcribe_bytes(
            audio_bytes,
            suffix=suffix,
            role=current_user.role or "patient",
            language=language if language in ("ar", "en") else None,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {exc}") from exc

    if not result.get("transcript"):
        raise HTTPException(status_code=422, detail="Could not detect speech. Please try again or type your message.")

    return VoiceTranscribeResponse(**result)


@router.post("/speak", response_model=VoiceSpeakResponse)
def speak_text(
    data: VoiceSpeakRequest,
    current_user: User = Depends(get_current_user),
):
    text = (data.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Text is required")
    if len(text) > 4000:
        text = text[:4000]

    lang = data.language or "en"
    try:
        audio = synthesize_speech_sync(text, lang)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Speech synthesis failed: {exc}") from exc

    return VoiceSpeakResponse(
        audio_base64=base64.b64encode(audio).decode("ascii"),
        content_type="audio/mpeg",
    )
