"""EHR-style medical extraction: prompt, normalization, and SOAP formatting."""

from __future__ import annotations

import json
import re
from typing import Any, Callable

EXTRACTION_SYSTEM_PROMPT = """You are an expert clinical documentation specialist and medical NLP system.

Extract ALL clinically relevant information from doctor-patient conversations or clinical documents.
The text may be English, Arabic, or mixed.

Return ONE valid JSON object ONLY. No markdown. No explanations.

RULES:
- Do NOT copy long paragraphs into SOAP sections. Summarize professionally like a hospital EHR.
- Extract EVERY POSITIVE symptom explicitly mentioned or clearly paraphrased from the source — not guessed.
- CRITICAL — OMISSION OVER GUESSING: If audio/text is messy, unclear, or something was not clearly said, LEAVE THE FIELD EMPTY. Never invent symptoms, diagnoses, medications, or findings to fill gaps.
- CRITICAL — NEGATION HANDLING: Words like "no", "denies", "negative", "without", "absent", "ruled out", "لا", "مفيش", "بدون" NEGATE the symptom that follows. NEVER add negated symptoms to the symptoms array.
- Do NOT infer diagnoses from symptoms, medications, tests ordered, or family history. Only include diagnoses explicitly documented by the clinician (including suspected/possible/rule-out with certainty preserved).
- Tag family history separately in medical_history.family_history — never as patient diagnoses or symptoms.
- Mark old/previous records and prior medication lists as historical — do not place them in current medications.
- Do NOT extract vital signs from the note text into vital_signs (vitals come from clinic sensors).
- Separate medications into prescription (new/current orders) vs plan (non-drug actions).
- Plan must NOT contain medications — put all drugs in prescription array OR medications_current based on context.
- Use null or [] for missing fields.
- For each symptom, diagnosis, and medication include source_evidence: a short phrase copied or closely paraphrased from the source. If you cannot tie an item to the source, omit it.

MEDICATION EXTRACTION (CRITICAL):
- Understand medications from full context — NOT keyword matching. Works for Arabic, English, mixed, formal notes, dialogue, and messy text.
- For EVERY medication, infer and populate:
  • name (normalized generic name when possible)
  • action: one of START | CONTINUE | HOLD | STOP | ONE_TIME | CONDITIONAL | UNKNOWN
  • If action is unclear, use UNKNOWN — never assume Continue.
  • dosage, frequency, route, duration, notes/instructions when available
- Classify automatically:
  • medications_current = home/chronic meds patient already takes (action usually Continue)
  • prescription = newly prescribed, dose changed (Start/Increase/Decrease), continued inpatient orders, or Administered during visit
  • medications_discontinued = stopped or held meds (Stop/Hold) as plain strings
- Do NOT mix chronic home meds with new prescriptions.
- Egyptian/colloquial examples: "ضغط من زمان" → chronic HTN med in PMH not necessarily a drug name; "هنزودلك..." / "هكتبلك" → new prescription Start; "وقف" / "بلاش" → Stop.

MEDICAL HISTORY:
- Extract PMH, FHx, social history, smoking, alcohol, allergies, and previous_surgeries into medical_history.
- NEVER place PMH/FHx/social/allergies/surgeries inside subjective or chief_complaint.

SUBJECTIVE:
- One concise physician-style paragraph of patient-reported complaints ONLY.
- Do NOT concatenate bullet lists. Write flowing clinical prose.
- Exclude PMH, FHx, exam, labs, imaging.

OBJECTIVE:
- Populate structured subsections: vitals, physical_exam, laboratory_results, ecg, imaging, echo.
- Each finding in exactly ONE subsection. Show all available categories.

CLINICAL SUMMARY:
- One natural professional paragraph: presentation, main symptoms, key objective findings, primary diagnoses, immediate management.
- Do NOT concatenate field values.

DEDUPLICATION:
- Each fact appears once in its correct section only.

JSON SCHEMA (exact keys):
{
  "patient_info": {
    "name": str|null,
    "age": int|null,
    "date_of_birth": str|null,
    "gender": str|null,
    "phone": str|null
  },
  "medical_history": {
    "past_medical_history": [str],
    "family_history": [str],
    "social_history": [str],
    "previous_surgeries": [str],
    "smoking": str|null,
    "alcohol": str|null,
    "allergies": [str]
  },
  "symptoms": [{"name": str, "duration": str|null, "severity": str|null, "location": str|null}],
  "chief_complaint": str|null,
  "diagnoses": [str],
  "severity": "mild"|"moderate"|"severe"|"critical"|"unknown"|null,
  "clinical_summary": str|null,
  "clinical_findings": [str],
  "follow_up_items": [str],
  "procedures": [str],
  "vital_signs": {"blood_pressure": str|null, "heart_rate": str|null, "temperature": str|null, "respiratory_rate": str|null, "weight": str|null},
  "laboratory_results": [str],
  "imaging": [str],
  "ecg": [str],
  "echocardiogram": [str],
  "doctor_notes": [str],
  "follow_up": str|null,
  "medications_current": [{"name": str, "action": str|null, "dosage": str|null, "frequency": str|null, "route": str|null, "duration": str|null, "notes": str|null, "temporality": str|null, "source_evidence": str|null}],
  "medications_discontinued": [str],
  "prescription": [{"name": str, "action": str|null, "dosage": str|null, "frequency": str|null, "route": str|null, "duration": str|null, "notes": str|null, "temporality": str|null, "source_evidence": str|null}],
  "soap_note": {
    "subjective": str,
    "objective": {
      "vitals": [str],
      "physical_exam": [str],
      "ecg": [str],
      "laboratory_results": [str],
      "imaging": [str],
      "echo": [str]
    },
    "assessment": [str],
    "plan": [str]
  },
  "language_detected": "en"|"ar"|"mixed"
}

SOAP QUALITY:
- subjective: ONLY patient-reported information (chief complaint, symptom narrative, duration, pain quality, functional limitations, direct patient quotes summarized). NEVER include past medical history, family history, social history, smoking, alcohol, or allergies in subjective.
- medical_history: all historical/contextual data (PMH, FHx, social, smoking, alcohol, allergies).
- objective: structured categories only — each finding in exactly ONE correct subsection. No mixing categories.
- assessment: numbered-priority clinical diagnoses (strings), most important first. Do NOT repeat assessment items in plan.
- plan: concise non-drug action items (admit, consults, monitoring orders, lifestyle) — NO drug names, NO duplicated diagnoses, NO follow-up items (use follow_up_items).
- follow_up_items: follow-up appointments, repeat testing, monitoring instructions, lifestyle recommendations.
- clinical_summary: one professional paragraph synthesizing context, presentation, key diagnoses, status, and immediate management. Do NOT concatenate lists.
- clinical_findings: critical abnormal findings only (e.g. reduced EF, elevated troponin) — NOT a diagnosis list.
- severity: infer from clinical data (mild/moderate/severe/critical/unknown). Never leave null.

PRESCRIPTION:
- New or changed medication orders only (not chronic home meds unless explicitly re-prescribed today).

CURRENT MEDICATIONS:
- Ongoing home/chronic medications the patient already uses.

SYMPTOM EXTRACTION:
- Include explicit AND clinically implied symptoms (e.g. "can't breathe lying flat" → orthopnea).
- Recognize abbreviations: SOB, CP, PND, DOE, etc.
- No duplicates.

LANGUAGE (CRITICAL — follow exactly):
- Detect the PRIMARY language of the source transcript.
- Write ALL string values in the JSON in that SAME primary language. Never translate Arabic input into English.
- If the transcript is mainly Arabic (including Egyptian colloquial Arabic), set language_detected to "ar" and write everything in Arabic suitable for a hospital EHR (formal/clinical Arabic).
- If the transcript is mainly English, set language_detected to "en" and write everything in English.
- If mixed but Arabic dominates, use Arabic. If English dominates, use English.
- Understand Egyptian Arabic dialect and map to proper clinical Arabic, e.g.:
  • "نفسي بيقف / مش قادر أتنفس" → ضيق نفس / عسر تنفس
  • "مخنوق / محتاج أكثر من مخدة" → orthopnea / اضطراب تنفس ليلي
  • "وجع في الصدر / الكتف" → ألم صدري
  • "دوخة" → دوخة
  • "تورم الرجلين / الجزمة ضيقة" → وذمة طرفية
  • "ضغط" → ارتفاع ضغط الدم
  • "سكر" → داء السكري
  • "نزلة برد" → upper respiratory symptoms as clinically appropriate
- Keep JSON keys in English exactly as in the schema; only VALUES follow the detected language.
- Medication names may use generic Arabic names or internationally recognized names as used locally, but narrative text must stay Arabic when input is Arabic."""

ARABIC_RE = re.compile(r"[\u0600-\u06FF]")
LATIN_RE = re.compile(r"[A-Za-z]")


def detect_input_language(text: str) -> str:
    """Detect primary transcript language: ar, en, or mixed."""
    if not (text or "").strip():
        return "en"
    arabic = len(ARABIC_RE.findall(text))
    latin = len(LATIN_RE.findall(text))
    if arabic == 0:
        return "en"
    if latin == 0 or arabic >= max(latin * 0.25, 8):
        return "ar"
    if arabic >= latin:
        return "ar"
    return "mixed"


def _resolve_output_language(data: dict[str, Any], source_text: str | None = None) -> str:
    detected = (data.get("language_detected") or "").strip().lower()
    if detected == "ar":
        return "ar"
    if detected == "en":
        return "en"
    if detected == "mixed":
        if source_text:
            primary = detect_input_language(source_text)
            return "ar" if primary in ("ar", "mixed") else "en"
        return "ar"
    if source_text:
        primary = detect_input_language(source_text)
        return "ar" if primary in ("ar", "mixed") else "en"
    blob = json.dumps(data, ensure_ascii=False)
    arabic = len(ARABIC_RE.findall(blob))
    latin = len(LATIN_RE.findall(blob))
    if arabic > 0 and arabic >= latin:
        return "ar"
    return "en"


def _output_lang(data: dict[str, Any]) -> str:
    lang = (data.get("language_detected") or "en").strip().lower()
    if lang == "mixed":
        return "ar"
    return lang if lang in ("ar", "en") else "en"


def _localized(lang: str, en: str, ar: str) -> str:
    return ar if lang == "ar" else en


EXTRACTION_USER_PREFIX = {
    "ar": (
        "IMPORTANT: The transcript below is primarily Arabic (Egyptian dialect may be used). "
        "Return ALL JSON string VALUES in Arabic (clinical/formal Arabic). "
        'Set language_detected to "ar". Do NOT translate to English.\n\n'
    ),
    "en": (
        "IMPORTANT: Return ALL JSON string VALUES in English. "
        'Set language_detected to "en".\n\n'
    ),
    "mixed": (
        "IMPORTANT: The transcript is mixed Arabic/English. Use the dominant language for ALL JSON string VALUES. "
        "If Arabic dominates, write in Arabic and set language_detected to \"ar\".\n\n"
    ),
}


def mock_extraction_for_language(lang: str) -> dict[str, Any]:
    if lang == "ar":
        return {
            "patient_info": {"name": None, "age": None, "date_of_birth": None, "gender": None, "phone": None},
            "medical_history": {
                "past_medical_history": [],
                "family_history": [],
                "social_history": [],
                "smoking": None,
                "alcohol": None,
                "allergies": [],
            },
            "symptoms": [{"name": "كما ورد في المحادثة", "duration": None, "severity": None, "location": None}],
            "chief_complaint": "استشارة عامة",
            "diagnoses": ["بانتظار مراجعة الطبيب"],
            "severity": "moderate",
            "clinical_summary": None,
            "clinical_findings": [],
            "follow_up_items": [],
            "procedures": [],
            "vital_signs": {},
            "laboratory_results": [],
            "imaging": [],
            "ecg": [],
            "echocardiogram": [],
            "doctor_notes": ["نموذج الذكاء الاصطناعي غير متاح — استخراج تجريبي"],
            "follow_up": None,
            "medications_current": [],
            "medications_discontinued": [],
            "prescription": [],
            "soap_note": {
                "subjective": "عرض المريض كما ورد في المحادثة. بانتظار المراجعة التفصيلية.",
                "objective": {
                    "vitals": [],
                    "physical_exam": ["بانتظار الفحص"],
                    "ecg": [],
                    "laboratory_results": [],
                    "imaging": [],
                    "echo": [],
                },
                "assessment": ["بانتظار التقييم السريري"],
                "plan": ["إكمال مراجعة الطبيب"],
            },
            "language_detected": "ar",
        }
    return dict(MOCK_EXTRACTION_EN)


MOCK_EXTRACTION_EN: dict[str, Any] = {
    "patient_info": {"name": None, "age": None, "date_of_birth": None, "gender": None, "phone": None},
    "medical_history": {
        "past_medical_history": [],
        "family_history": [],
        "social_history": [],
        "smoking": None,
        "alcohol": None,
        "allergies": [],
    },
    "symptoms": [{"name": "As described in transcript", "duration": None, "severity": None, "location": None}],
    "chief_complaint": "General consultation",
    "diagnoses": ["Pending physician review"],
    "severity": "moderate",
    "clinical_summary": None,
    "clinical_findings": [],
    "follow_up_items": [],
    "procedures": [],
    "vital_signs": {},
    "laboratory_results": [],
    "imaging": [],
    "ecg": [],
    "echocardiogram": [],
    "doctor_notes": ["AI model unavailable — mock extraction"],
    "follow_up": None,
    "medications_current": [],
    "medications_discontinued": [],
    "prescription": [],
    "soap_note": {
        "subjective": "Patient presentation as documented in transcript. Pending detailed review.",
        "objective": {
            "vitals": [],
            "physical_exam": ["Pending examination"],
            "ecg": [],
            "laboratory_results": [],
            "imaging": [],
            "echo": [],
        },
        "assessment": ["Pending clinical assessment"],
        "plan": ["Complete physician review"],
    },
    "language_detected": "en",
}

MOCK_EXTRACTION = MOCK_EXTRACTION_EN

_DIAGNOSIS_ALIASES = {
    "hf": "Heart failure",
    "chf": "Congestive heart failure",
    "heart failure": "Heart failure",
    "congestive heart failure": "Congestive heart failure",
    "htn": "Hypertension",
    "hypertension": "Hypertension",
    "dm": "Diabetes mellitus",
    "t2dm": "Type 2 diabetes mellitus",
    "type 2 diabetes": "Type 2 diabetes mellitus",
}


def _norm_key(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").strip().lower())


def _dedupe_strings(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for item in items:
        key = _norm_key(item)
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(item.strip())
    return out


_MED_ACTION_MAP = {
    "start": "Start", "new": "Start", "begin": "Start", "prescribe": "Start", "prescribed": "Start",
    "بدء": "Start", "ابدأ": "Start", "وصف": "Start", "هكتبلك": "Start", "صرف": "Start",
    "continue": "Continue", "continued": "Continue", "maintain": "Continue", "ongoing": "Continue",
    "استمر": "Continue", "مستمر": "Continue", "استمرار": "Continue",
    "stop": "Stop", "discontinue": "Stop", "discontinued": "Stop", "cease": "Stop",
    "إيقاف": "Stop", "وقف": "Stop", "توقف": "Stop", "بلاش": "Stop",
    "hold": "Hold", "withhold": "Hold", "تعليق": "Hold",
    "increase": "Increase", "increased": "Increase", "up titrate": "Increase", "raise": "Increase",
    "زيادة": "Increase", "هنزود": "Increase", "زاد": "Increase",
    "decrease": "Decrease", "reduced": "Decrease", "lower": "Decrease", "down titrate": "Decrease",
    "تقليل": "Decrease", "قلل": "Decrease", "نقص": "Decrease",
    "administered": "Administered", "given": "Administered", "administer": "Administered",
    "أعطى": "Administered", "تم إعطاء": "Administered",
}

_NEW_RX_ACTIONS = {"Start", "Increase", "Decrease", "Administered"}
_STOP_ACTIONS = {"Stop", "Hold"}


def _normalize_med_action(raw: Any) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    key = _norm_key(text)
    if key in _MED_ACTION_MAP:
        return _MED_ACTION_MAP[key]
    for token, action in _MED_ACTION_MAP.items():
        if token in key or key in token:
            return action
    title = text.title()
    if title in _NEW_RX_ACTIONS | _STOP_ACTIONS | {"Continue"}:
        return title
    return None


def _normalize_medication_item(item: Any, default_action: str = "UNKNOWN") -> dict[str, Any] | None:
    if isinstance(item, str):
        name = item.strip()
        if not name:
            return None
        return {
            "name": name,
            "action": default_action,
            "dosage": None,
            "frequency": None,
            "route": None,
            "duration": None,
            "notes": None,
        }
    if not isinstance(item, dict):
        return None
    name = (item.get("name") or item.get("medication_name") or "").strip()
    if not name:
        return None
    action = _normalize_med_action(item.get("action"))
    if action is None:
        action = default_action if default_action != "UNKNOWN" else "UNKNOWN"
    else:
        # Map legacy actions to canonical uppercase
        from extraction_schema import canonical_med_action
        action = canonical_med_action(action).value
    return {
        "name": name,
        "action": action,
        "dosage": (item.get("dosage") or item.get("dose") or None),
        "frequency": item.get("frequency"),
        "route": item.get("route"),
        "duration": item.get("duration"),
        "notes": item.get("notes") or item.get("instructions"),
    }


def _normalize_medications_list(raw: Any, default_action: str = "UNKNOWN") -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        return []
    out: list[dict[str, Any]] = []
    for item in raw:
        med = _normalize_medication_item(item, default_action=default_action)
        if med:
            out.append(med)
    return out


def _medication_signature(med: dict[str, Any]) -> str:
    return _norm_key(med.get("name") or "")


def _split_and_classify_medications(data: dict[str, Any]) -> dict[str, Any]:
    """Route medications to current vs prescription vs discontinued by semantic action."""
    from extraction_schema import MedAction, canonical_med_action

    current_raw = _normalize_medications_list(data.get("medications_current"), default_action="UNKNOWN")
    rx_raw = _normalize_medications_list(data.get("prescription"), default_action="UNKNOWN")
    discontinued = _dedupe_strings([str(x).strip() for x in _as_str_list(data.get("medications_discontinued"))])

    merged: list[tuple[dict[str, Any], str]] = []
    for med in current_raw:
        merged.append((med, "current"))
    for med in rx_raw:
        merged.append((med, "rx"))

    current: list[dict[str, Any]] = []
    prescription: list[dict[str, Any]] = []
    stop_names: list[str] = list(discontinued)

    for med, source in merged:
        action = canonical_med_action(med.get("action"))
        med = {**med, "action": action.value}
        if action in (MedAction.STOP, MedAction.HOLD):
            stop_names.append(med["name"])
            continue
        if action in (MedAction.START, MedAction.ONE_TIME, MedAction.CONDITIONAL):
            prescription.append(med)
        elif action == MedAction.CONTINUE:
            if source == "rx":
                prescription.append(med)
            else:
                current.append(med)
        else:
            current.append(med)

    rx_keys = {_medication_signature(m) for m in prescription}
    current = [
        m for m in current
        if _medication_signature(m) not in rx_keys or canonical_med_action(m.get("action")) == MedAction.CONTINUE
    ]

    data["medications_current"] = current
    data["prescription"] = prescription
    data["medications_discontinued"] = _dedupe_strings(stop_names)
    return data


def _collect_text_blobs(data: dict[str, Any]) -> set[str]:
    keys: set[str] = set()

    def add_text(val: Any) -> None:
        if val is None:
            return
        if isinstance(val, str):
            k = _norm_key(val)
            if len(k) > 3:
                keys.add(k)
        elif isinstance(val, list):
            for x in val:
                add_text(x if isinstance(x, str) else (x.get("name") if isinstance(x, dict) else str(x)))
        elif isinstance(val, dict):
            for v in val.values():
                add_text(v)

    add_text(data.get("chief_complaint"))
    add_text(data.get("diagnoses"))
    add_text(data.get("clinical_findings"))
    add_text(data.get("follow_up_items"))
    add_text(data.get("doctor_notes"))
    add_text(data.get("medications_discontinued"))
    soap = data.get("soap_note") or {}
    add_text(soap.get("subjective"))
    add_text(soap.get("assessment"))
    add_text(soap.get("plan"))
    obj = soap.get("objective")
    if isinstance(obj, dict):
        for v in obj.values():
            add_text(v)
    return keys


def _dedupe_cross_sections(data: dict[str, Any]) -> dict[str, Any]:
    """Remove duplicate facts across plan, notes, follow-up, assessment."""
    lang = _output_lang(data)
    known = _collect_text_blobs(data)
    diagnosis_keys = {_norm_key(str(d)) for d in data.get("diagnoses") or []}
    soap = data.get("soap_note") or {}

    def is_duplicate(item: str) -> bool:
        key = _norm_key(item)
        if not key:
            return True
        if key in diagnosis_keys:
            return True
        for dx in diagnosis_keys:
            if dx and (dx in key or key in dx):
                return True
        return False

    plan = [p for p in _as_str_list(soap.get("plan")) if not is_duplicate(p)]
    notes = [n for n in _as_str_list(data.get("doctor_notes")) if _norm_key(n) not in {_norm_key(p) for p in plan}]
    follow = _dedupe_strings(_as_str_list(data.get("follow_up_items")))

    soap["plan"] = _dedupe_strings(plan)
    data["soap_note"] = soap
    data["doctor_notes"] = _dedupe_strings(notes)
    data["follow_up_items"] = follow
    data["follow_up"] = "; ".join(follow) if follow else None

    # Remove PMH-like sentences accidentally left in subjective
    data = _clean_subjective_section(data)
    return data


def _objective_highlights(data: dict[str, Any]) -> list[str]:
    soap = data.get("soap_note") or {}
    obj = soap.get("objective") if isinstance(soap.get("objective"), dict) else {}
    highlights: list[str] = []
    for key in ("vitals", "physical_exam", "laboratory_results", "ecg", "imaging", "echo"):
        for item in _as_str_list(obj.get(key)):
            if item not in highlights:
                highlights.append(item)
    for item in data.get("clinical_findings") or []:
        if item not in highlights:
            highlights.append(str(item))
    return highlights[:4]


def _normalize_diagnosis(name: str, lang: str = "en") -> str:
    if lang == "ar":
        return name.strip()
    key = _norm_key(name)
    return _DIAGNOSIS_ALIASES.get(key, name.strip())


def normalize_symptoms(raw: Any) -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        return []
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for item in raw:
        if isinstance(item, str):
            name = item.strip()
            if not name:
                continue
            key = _norm_key(name)
            if key in seen:
                continue
            seen.add(key)
            out.append({"name": name, "duration": None, "severity": None, "location": None})
        elif isinstance(item, dict):
            name = (item.get("name") or "").strip()
            if not name:
                continue
            key = _norm_key(name)
            if key in seen:
                continue
            seen.add(key)
            out.append({
                "name": name,
                "duration": item.get("duration"),
                "severity": item.get("severity"),
                "location": item.get("location"),
            })
    return out


def _objective_dict_to_text(obj: dict[str, Any], lang: str = "en") -> str:
    if not isinstance(obj, dict):
        return str(obj or "")
    sections = [
        (_localized(lang, "Vitals", "العلامات الحيوية"), obj.get("vitals") or []),
        (_localized(lang, "Physical Examination", "الفحص السريري"), obj.get("physical_exam") or []),
        (_localized(lang, "ECG", "تخطيط القلب"), obj.get("ecg") or []),
        (_localized(lang, "Laboratory Results", "نتائج المختبر"), obj.get("laboratory_results") or []),
        (_localized(lang, "Imaging", "التصوير"), obj.get("imaging") or []),
        (_localized(lang, "Echocardiogram", "إيكو القلب"), obj.get("echo") or []),
    ]
    lines: list[str] = []
    for title, items in sections:
        if not items:
            continue
        lines.append(f"{title}:")
        for it in items:
            lines.append(f"  • {it}")
        lines.append("")
    return "\n".join(lines).strip()


def _list_to_bullets(items: Any) -> str:
    if not items:
        return ""
    if isinstance(items, str):
        return items.strip()
    if isinstance(items, list):
        return "\n".join(f"• {str(x).strip()}" for x in items if str(x).strip())
    return str(items)


def _numbered_list(items: Any) -> str:
    if not items:
        return ""
    if isinstance(items, str):
        return items.strip()
    if isinstance(items, list):
        return "\n".join(f"{i + 1}. {str(x).strip()}" for i, x in enumerate(items) if str(x).strip())
    return str(items)


def symptoms_to_string(symptoms: list[dict[str, Any]]) -> str:
    return "\n".join(f"• {s['name']}" for s in symptoms if s.get("name"))


def _subjective_contains_history(text: str) -> bool:
    t = (text or "").lower()
    markers = (
        "pmh:", "past medical", "family history", "fhx", "social history",
        "smoking:", "smoker", "allergies:", "allergy:", "former smoker",
        "alcohol:", "medical history", "surgical history",
        "تاريخ مرضي", "تاريخ عائلي", "تاريخ اجتماعي", "حساسية", "تدخين", "كحول",
        "عملية", "جراح", "ضغط من", "سكر من", "years ago", "من زمان",
    )
    return any(m in t for m in markers)


def _compose_patient_subjective(data: dict[str, Any]) -> str:
    """Build concise physician-style subjective paragraph — patient complaints only."""
    lang = _output_lang(data)
    cc = (data.get("chief_complaint") or "").strip().rstrip(".")

    symptom_parts: list[str] = []
    for s in data.get("symptoms") or []:
        if not isinstance(s, dict):
            continue
        name = (s.get("name") or "").strip()
        if not name:
            continue
        duration = (s.get("duration") or "").strip() if s.get("duration") else ""
        severity = (s.get("severity") or "").strip() if s.get("severity") else ""
        location = (s.get("location") or "").strip() if s.get("location") else ""
        fragment = name
        details = [x for x in (duration, severity, location) if x]
        if details:
            if lang == "ar":
                fragment = f"{name} ({'، '.join(details)})"
            else:
                fragment = f"{name} ({', '.join(details)})"
        symptom_parts.append(fragment)

    if lang == "ar":
        if cc and symptom_parts:
            extra = [s for s in symptom_parts if _norm_key(s.split("(")[0]) not in _norm_key(cc)]
            if extra:
                body = f"يشكو المريض من {cc}، مع {('، '.join(extra) if len(extra) > 1 else extra[0])}."
            else:
                body = f"يشكو المريض من {cc}."
        elif cc:
            body = f"يشكو المريض من {cc}."
        elif symptom_parts:
            body = f"يشكو المريض من {'، '.join(symptom_parts)}."
        else:
            body = _localized(lang, "Patient-reported symptoms as documented.", "أعراض أبلغ عنها المريض كما وردت في المحادثة.")
        return body

    if cc and symptom_parts:
        extra = [s for s in symptom_parts if _norm_key(s.split("(")[0]) not in _norm_key(cc)]
        if extra:
            joined = ", ".join(extra)
            body = f"The patient reports {cc}, associated with {joined}."
        else:
            body = f"The patient reports {cc}."
    elif cc:
        body = f"The patient reports {cc}."
    elif symptom_parts:
        body = f"The patient reports {', '.join(symptom_parts)}."
    else:
        body = _localized(lang, "Patient-reported symptoms as documented.", "أعراض أبلغ عنها المريض كما وردت في المحادثة.")
    return body


def _strip_history_from_subjective(text: str) -> str:
    """Remove sentences containing historical/social data from subjective."""
    if not text:
        return text
    sentences = re.split(r"(?<=[.!?])\s+", text)
    kept: list[str] = []
    for sent in sentences:
        if _subjective_contains_history(sent):
            continue
        kept.append(sent.strip())
    return " ".join(kept).strip()


def _ensure_medical_history(data: dict[str, Any]) -> dict[str, Any]:
    lang = _output_lang(data)
    mh = data.get("medical_history")
    if not isinstance(mh, dict):
        mh = {}
    for key in ("past_medical_history", "family_history", "social_history", "allergies", "previous_surgeries"):
        mh[key] = _as_str_list(mh.get(key))
    if mh.get("smoking") and not any("smok" in _norm_key(s) or "تدخ" in s for s in mh["social_history"]):
        smoking_label = _localized(lang, "Smoking", "التدخين")
        mh["social_history"] = _dedupe_strings(mh["social_history"] + [f"{smoking_label}: {mh['smoking']}"])
    if mh.get("alcohol") and not any("alcohol" in _norm_key(s) or "كح" in s for s in mh["social_history"]):
        alcohol_label = _localized(lang, "Alcohol", "الكحول")
        mh["social_history"] = _dedupe_strings(mh["social_history"] + [f"{alcohol_label}: {mh['alcohol']}"])
    if not mh.get("allergies"):
        mh["allergies"] = [_localized(lang, "None known", "لا يوجد معروف")]
    data["medical_history"] = mh
    return data


def _rebucket_objective_key(text: str, default: str = "physical_exam") -> str:
    t = text.lower()
    if re.search(r"\b(bp|blood pressure|hr|heart rate|temp|temperature|rr|respiratory rate|weight)\b", t):
        return "vitals"
    if re.search(r"(ضغط|نبض|حرارة|تنفس|وزن|mmhg|bpm)", text, re.I):
        return "vitals"
    if re.search(r"\b(ecg|ekg|st depression|st elevation|sinus|arrhythmia|lvh|qt)\b", t):
        return "ecg"
    if re.search(r"(تخطيط|قلب|ecg|ekg)", text, re.I):
        return "ecg"
    if re.search(r"\b(bnp|troponin|hba1c|creatinine|hemoglobin|lab|wbc|platelet|potassium|sodium|glucose)\b", t):
        return "laboratory_results"
    if re.search(r"(تروبونين|bnp|مختبر|تحليل|hba1c|كريات)", text, re.I):
        return "laboratory_results"
    if re.search(r"\b(lvef|ef\b|ejection fraction|mitral|aortic|hypokinesia|echo|echocardiogram)\b", t):
        return "echo"
    if re.search(r"(إيكو|echo|ejection|كسر\s*الطرح)", text, re.I):
        return "echo"
    if re.search(r"\b(x-ray|xray|ct scan|mri|ultrasound|chest film|imaging|radiograph)\b", t):
        return "imaging"
    if re.search(r"(أشعة|x-ray|xray|ct|mri|تصوير)", text, re.I):
        return "imaging"
    return default


def _organize_objective_sections(data: dict[str, Any]) -> dict[str, Any]:
    soap = data.get("soap_note") or {}
    obj = soap.get("objective")
    if not isinstance(obj, dict):
        obj = {}

    collected: list[tuple[str, str]] = []
    for src_key in ("vitals", "physical_exam", "ecg", "laboratory_results", "imaging", "echo"):
        for item in _as_str_list(obj.get(src_key)):
            collected.append((item, src_key))

    for item in _vitals_to_strings(data.get("vital_signs")):
        collected.append((item, "vitals"))
    for item in _as_str_list(data.get("ecg")):
        collected.append((item, "ecg"))
    for item in _as_str_list(data.get("laboratory_results")):
        collected.append((item, "laboratory_results"))
    for item in _as_str_list(data.get("imaging")):
        collected.append((item, "imaging"))
    for item in _as_str_list(data.get("echocardiogram")):
        collected.append((item, "echo"))

    buckets: dict[str, list[str]] = {
        "vitals": [],
        "physical_exam": [],
        "ecg": [],
        "laboratory_results": [],
        "imaging": [],
        "echo": [],
    }
    for item, src in collected:
        bucket = _rebucket_objective_key(item, src)
        if item not in buckets[bucket]:
            buckets[bucket].append(item)

    ecg_set = {_norm_key(x) for x in buckets["ecg"]}
    buckets["imaging"] = [
        x for x in buckets["imaging"]
        if not (_norm_key(x).startswith("ecg") or _norm_key(x) in ecg_set)
    ]

    soap["objective"] = {k: _dedupe_strings(v) for k, v in buckets.items()}
    data["soap_note"] = soap
    return data


def _plan_item_is_medication(item: str, rx_names: set[str]) -> bool:
    il = _norm_key(item)
    if any(rx in il or il in rx for rx in rx_names if rx):
        return True
    med_words = (" mg", " tablet", " daily", " po ", " iv ", " bid", " tid", " qd")
    return any(w in il for w in med_words) and any(c.isdigit() for c in il)


def _dedupe_plan_section(data: dict[str, Any]) -> dict[str, Any]:
    soap = data.get("soap_note") or {}
    plan = _as_str_list(soap.get("plan"))
    assessment_keys = {_norm_key(x) for x in _as_str_list(soap.get("assessment"))}
    diagnosis_keys = {_norm_key(str(x)) for x in data.get("diagnoses") or []}
    all_dx = assessment_keys | diagnosis_keys

    rx_names: set[str] = set()
    for med in (data.get("prescription") or []) + (data.get("medications_current") or []):
        if isinstance(med, dict):
            name = (med.get("name") or med.get("medication_name") or "").strip()
            if name:
                rx_names.add(_norm_key(name))

    doctor_note_keys = {_norm_key(str(n)) for n in data.get("doctor_notes") or []}
    follow_keywords = (
        "follow-up", "follow up", "repeat echo", "repeat lab", "recheck", "return in", "cardiology follow",
        "متابعة", "إعادة", "مراجعة", "تكرار",
    )

    cleaned: list[str] = []
    seen: set[str] = set()
    for item in plan:
        key = _norm_key(item)
        if not key or key in seen:
            continue
        if key in doctor_note_keys:
            continue
        if any(key == dx or key in dx or dx in key for dx in all_dx if dx):
            continue
        if _plan_item_is_medication(item, rx_names):
            continue
        if any(k in key for k in follow_keywords):
            continue
        seen.add(key)
        cleaned.append(item.strip())

    soap["plan"] = cleaned
    data["soap_note"] = soap
    return data


def _ensure_follow_up(data: dict[str, Any]) -> dict[str, Any]:
    items: list[str] = []
    fu = data.get("follow_up_items") or data.get("follow_up")
    if isinstance(fu, list):
        items.extend(str(x).strip() for x in fu if str(x).strip())
    elif isinstance(fu, str) and fu.strip():
        items.append(fu.strip())

    plan = _as_str_list((data.get("soap_note") or {}).get("plan"))
    follow_keywords = (
        "follow-up", "follow up", "repeat", "monitor", "recheck", "return",
        "cardiology", "echocardiogram", "laboratory", "renal function",
        "blood pressure", "daily weight", "lifestyle",
        "متابعة", "إعادة", "مراقبة", "مراجعة", "تكرار", "ضغط", "وزن",
    )
    remaining_plan: list[str] = []
    for item in plan:
        il = _norm_key(item)
        if any(k in il for k in follow_keywords):
            items.append(item)
        else:
            remaining_plan.append(item)

    data["follow_up_items"] = _dedupe_strings(items)
    data["follow_up"] = "; ".join(data["follow_up_items"]) if data["follow_up_items"] else None
    if isinstance(data.get("soap_note"), dict):
        data["soap_note"]["plan"] = remaining_plan
    return data


def _infer_severity(data: dict[str, Any]) -> str:
    existing = (data.get("severity") or "").strip().lower()
    if existing in ("mild", "moderate", "severe", "critical"):
        return existing

    blob = json.dumps(data, ensure_ascii=False).lower()
    score = 0
    if any(x in blob for x in ("critical", "cardiac arrest", "cardiogenic shock", "intubated", "icu", "حرج", "صدمة", "إنعاش")):
        score += 4
    if re.search(r"lvef|ef\s*[:<]?\s*3[0-9]|ejection fraction.{0,20}3[0-9]|كسر.{0,10}طرح", blob):
        score += 2
    if "decompensated" in blob or "acute decompensated" in blob or "تفاقم" in blob:
        score += 2
    if "elevated troponin" in blob or "acute coronary" in blob or "acs" in blob.split() or "تروبونين" in blob:
        score += 2
    if "elevated bnp" in blob or "bnp elevated" in blob:
        score += 1
    if any(x in blob for x in ("admit", "admission", "hospitalization", "inpatient", "تنويم", "دخول")):
        score += 1
    if "severe" in blob or "شديد" in blob:
        score += 1
    if ("mild" in blob or "خفيف" in blob) and score == 0:
        return "mild"
    if score >= 4:
        return "critical"
    if score >= 3:
        return "severe"
    if score >= 1:
        return "moderate"
    if _symptom_names(data):
        return "mild"
    return "unknown"


def _build_clinical_summary(data: dict[str, Any]) -> str:
    lang = _output_lang(data)
    existing = (data.get("clinical_summary") or "").strip()
    if len(existing) > 60 and not (lang == "en" and existing.lower().startswith("patient with")):
        return existing

    mh = data.get("medical_history") or {}
    pmh = _as_str_list(mh.get("past_medical_history"))
    symptoms = _symptom_names(data)
    presenting = ", ".join(symptoms[:5]) if symptoms else (data.get("chief_complaint") or "").strip()
    if not presenting:
        presenting = _localized(lang, "presenting complaints", "الشكوى الرئيسية")

    diagnoses = data.get("diagnoses") or []
    primary = diagnoses[0] if diagnoses else _localized(lang, "findings under evaluation", "نتائج قيد التقييم")
    secondary = ", ".join(diagnoses[1:3]) if len(diagnoses) > 1 else ""
    obj_bits = _objective_highlights(data)
    obj_text = "; ".join(obj_bits[:3]) if obj_bits else ""
    plan = _as_str_list((data.get("soap_note") or {}).get("plan"))
    management = plan[0] if plan else _localized(
        lang, "Further evaluation and management as clinically indicated", "متابعة التقييم والعلاج حسب الحالة السريرية"
    )

    if lang == "ar":
        context = f"مريض لديه {', '.join(pmh[:2])}" if pmh else "المريض"
        summary = f"{context}، يشكو من {presenting.rstrip('.')}."
        if obj_text:
            summary += f" نتائج الفحص تشمل {obj_text}."
        summary += f" التقييم السريري يشير إلى {primary}"
        if secondary:
            summary += f"، مع {secondary}"
        summary += f". {management.rstrip('.')}."
        return re.sub(r"\s+", " ", summary).strip()

    context = f"Patient with {', '.join(pmh[:2])}" if pmh else "The patient"
    summary = f"{context} presents with {presenting.rstrip('.')}."
    if obj_text:
        summary += f" Objective findings include {obj_text}."
    summary += f" Clinical assessment indicates {primary}"
    if secondary:
        summary += f", with {secondary} also considered"
    summary += f". Immediate plan: {management.rstrip('.')}."
    return re.sub(r"\s+", " ", summary).strip()


def _extract_ef_percent(blob: str) -> str | None:
    m = re.search(r"(?:lvef|ef|ejection fraction)[^\d]{0,15}(\d{1,3})\s*%?", blob, re.I)
    return m.group(1) if m else None


def _build_clinical_findings(data: dict[str, Any]) -> list[str]:
    lang = _output_lang(data)
    existing = data.get("clinical_findings") or []
    if existing:
        return _dedupe_strings([str(x).strip() for x in existing if str(x).strip()])

    blob = json.dumps(data, ensure_ascii=False)
    blob_l = blob.lower()
    findings: list[str] = []

    ef = _extract_ef_percent(blob_l)
    if ef and int(ef) <= 40:
        findings.append(
            _localized(lang, f"Reduced Ejection Fraction ({ef}%)", f"انخفاض كسر طرح البطين ({ef}%)")
        )

    if re.search(r"troponin.{0,30}elevated|elevated.{0,30}troponin|تروبونين", blob_l):
        findings.append(_localized(lang, "Elevated Troponin", "ارتفاع التروبونين"))
    if re.search(r"bnp.{0,30}elevated|elevated.{0,30}bnp", blob_l):
        findings.append(_localized(lang, "Elevated BNP", "ارتفاع BNP"))
    if any(x in blob_l for x in ("pulmonary congestion", "crackles", "pulmonary edema", "bibasilar", "احتقان", "rales")):
        findings.append(_localized(lang, "Pulmonary Congestion", "احتقان رئوي"))
    if any(x in blob_l for x in ("acute coronary", "acs", "st depression", "st elevation", "nstemi", "stemi")):
        findings.append(_localized(lang, "Possible Acute Coronary Syndrome", "احتمال متلازمة الشريان التاجي الحاد"))
    if re.search(r"hba1c.{0,15}([89]\.\d|[1-9]\d)", blob_l):
        findings.append(_localized(lang, "Poorly Controlled Diabetes", "سكري غير متحكم"))
    elif any("diabetes" in _norm_key(str(d)) or "سكر" in str(d) or "سكري" in str(d) for d in data.get("diagnoses") or []):
        if re.search(r"hba1c|a1c|glucose|سكر", blob_l):
            findings.append(_localized(lang, "Poorly Controlled Diabetes", "سكري غير متحكم"))

    for dx in data.get("diagnoses") or []:
        dl = _norm_key(str(dx))
        dx_text = str(dx)
        if ("hypertension" in dl or "ضغط" in dx_text) and not any("hypertension" in _norm_key(f) or "ضغط" in f for f in findings):
            findings.append(_localized(lang, "Hypertension", "ارتفاع ضغط الدم"))
        if (("heart failure" in dl or "hf" == dl) or "فشل" in dx_text or "قلب" in dx_text) and not any("ejection" in _norm_key(f) or "طرح" in f for f in findings):
            findings.append(_localized(lang, "Heart Failure", "فشل القلب"))

    obj = ((data.get("soap_note") or {}).get("objective") or {})
    if isinstance(obj, dict):
        for item in _as_str_list(obj.get("physical_exam")):
            if "jvp" in item.lower() and "elevated jvp" not in [f.lower() for f in findings]:
                findings.append(_localized(lang, "Elevated JVP", "ارتفاع الضغط الوريدي الوداجي"))
            if "edema" in item.lower() or "وذمة" in item or "تورم" in item:
                findings.append(_localized(lang, "Peripheral Edema", "وذمة طرفية"))
                break

    return _dedupe_strings(findings)


def _clean_subjective_section(data: dict[str, Any]) -> dict[str, Any]:
    soap = data.get("soap_note") or {}
    subjective = (soap.get("subjective") or "").strip()
    if not subjective or _subjective_contains_history(subjective) or len(subjective) > 600:
        soap["subjective"] = _compose_patient_subjective(data)
    else:
        cleaned = _strip_history_from_subjective(subjective)
        soap["subjective"] = cleaned or _compose_patient_subjective(data)
    data["soap_note"] = soap
    return data


def _refine_extraction(data: dict[str, Any]) -> dict[str, Any]:
    """Post-process normalized extraction for EHR-quality output."""
    data = _ensure_medical_history(data)
    data = _clean_subjective_section(data)
    data = _organize_objective_sections(data)
    data = _ensure_follow_up(data)
    data = _dedupe_plan_section(data)
    data = _dedupe_cross_sections(data)
    # Severity/summary finalized in extraction_pipeline after validation
    return data


_NEGATION_PATTERNS_EN = re.compile(
    r"\b(?:no|not|denies|denied|without|absent|negative for|rules?\s*out|"
    r"never|nor|free of|lack of|doesn'?t have|don'?t have|did not have)\b",
    re.IGNORECASE,
)
_NEGATION_PATTERNS_AR = re.compile(
    r"(?:لا |ما |مفيش|مافيش|بدون|عدم|ينفي|نفى|ما عندو|ما عندها|مش عنده|مش عندها|"
    r"ما فيش|لا يوجد|لا توجد|ليس لديه|ليس لديها|من غير)",
)

_SYMPTOM_SYNONYMS: dict[str, list[str]] = {
    "fever": ["fever", "pyrexia", "febrile", "حمى", "حرارة", "سخونية", "سخونيه"],
    "cough": ["cough", "coughing", "كحة", "كحه", "سعال"],
    "vomiting": ["vomiting", "vomit", "emesis", "ترجيع", "قيء", "استفراغ", "قىء"],
    "nausea": ["nausea", "nauseated", "غثيان"],
    "headache": ["headache", "cephalalgia", "صداع", "وجع راس", "وجع رأس"],
    "diarrhea": ["diarrhea", "diarrhoea", "إسهال", "اسهال"],
    "dyspnea": ["dyspnea", "shortness of breath", "sob", "ضيق تنفس", "ضيق نفس"],
    "chest_pain": ["chest pain", "ألم صدر", "وجع صدر"],
    "abdominal_pain": ["abdominal pain", "stomach pain", "ألم بطن", "وجع بطن", "مغص"],
}


def _symptom_is_negated(symptom_name: str, source_text: str) -> bool:
    """Check if a symptom was explicitly negated in the source text."""
    name_lower = symptom_name.lower().strip()
    text_lower = source_text.lower()

    all_terms = [name_lower]
    for _group, synonyms in _SYMPTOM_SYNONYMS.items():
        if name_lower in [s.lower() for s in synonyms]:
            all_terms = [s.lower() for s in synonyms]
            break

    for term in all_terms:
        for pattern in [_NEGATION_PATTERNS_EN, _NEGATION_PATTERNS_AR]:
            for match in pattern.finditer(text_lower):
                neg_pos = match.end()
                window = text_lower[neg_pos:neg_pos + 40]
                if term in window:
                    positive_before = text_lower[max(0, match.start() - 30):match.start()]
                    if not re.search(r"\b(has|have|with|complain|يشتكي|عنده|عندها)\b", positive_before, re.IGNORECASE):
                        return True
    return False


def _filter_negated_symptoms(symptoms: list[dict[str, Any]], source_text: str) -> list[dict[str, Any]]:
    """Remove symptoms that were explicitly negated in the source text."""
    if not source_text:
        return symptoms
    return [s for s in symptoms if not _symptom_is_negated(s.get("name", ""), source_text)]


def normalize_extraction(
    raw: dict[str, Any],
    source_text: str | None = None,
    verify_call: Callable[[str, str], str | None] | None = None,
) -> dict[str, Any]:
    """Normalize LLM output into consistent structured EHR payload."""
    data = dict(raw or {})
    lang = _resolve_output_language(data, source_text)
    data["language_detected"] = lang

    # Legacy key migration
    if "diagnosis" in data and "diagnoses" not in data:
        data["diagnoses"] = data.pop("diagnosis")
    if "treatment_plan" in data and isinstance(data.get("soap_note"), dict):
        soap = data["soap_note"]
        if not soap.get("plan") and data["treatment_plan"]:
            tp = data["treatment_plan"]
            soap["plan"] = tp if isinstance(tp, list) else [str(tp)]
    if "medications" in data and not data.get("prescription"):
        data["prescription"] = data.pop("medications")

    symptoms = normalize_symptoms(data.get("symptoms", []))
    if source_text:
        symptoms = _filter_negated_symptoms(symptoms, source_text)
    data["symptoms"] = symptoms

    diagnoses_raw = data.get("diagnoses") or []
    if isinstance(diagnoses_raw, str):
        diagnoses_raw = [diagnoses_raw]
    diagnoses = _dedupe_strings([_normalize_diagnosis(str(d), lang) for d in diagnoses_raw if str(d).strip()])
    data["diagnoses"] = diagnoses

    soap = data.get("soap_note") or {}
    if isinstance(soap, dict):
        obj = soap.get("objective")
        if isinstance(obj, str):
            soap["objective"] = {"physical_exam": [obj] if obj.strip() else []}
        elif not isinstance(obj, dict):
            soap["objective"] = {
                "vitals": [],
                "physical_exam": [],
                "ecg": data.get("ecg") or [],
                "laboratory_results": data.get("laboratory_results") or [],
                "imaging": data.get("imaging") or [],
                "echo": data.get("echocardiogram") or [],
            }
        if isinstance(soap.get("assessment"), str):
            soap["assessment"] = [soap["assessment"]] if soap["assessment"].strip() else []
        if isinstance(soap.get("plan"), str):
            soap["plan"] = [soap["plan"]] if soap["plan"].strip() else []
        data["soap_note"] = soap

    data["prescription"] = data.get("prescription") or []
    data["medications_current"] = data.get("medications_current") or []
    data["medications_discontinued"] = data.get("medications_discontinued") or []
    data = _ensure_soap_sections(data)
    data = _refine_extraction(data)
    if source_text:
        from transcript_enrichment import safe_enrich_from_transcript
        data = safe_enrich_from_transcript(data, source_text)
        data = _dedupe_cross_sections(data)
        soap = data.get("soap_note") or {}
        if not (soap.get("subjective") or "").strip() or _subjective_contains_history(soap.get("subjective", "")):
            data = _clean_subjective_section(data)
    from extraction_pipeline import run_extraction_pipeline
    data, validation = run_extraction_pipeline(data, source_text)
    if verify_call and source_text and source_text.strip():
        from extraction_verify import run_verify_pass
        data, verify_report = run_verify_pass(data, source_text, verify_call)
        data["verification_pass"] = verify_report
        if verify_report.get("removed"):
            data, validation = run_extraction_pipeline(data, source_text)
            data["verification_pass"] = verify_report
            data["validation_report"] = validation
    if not data.get("clinical_findings"):
        data["clinical_findings"] = _build_clinical_findings(data)
    return data


def _symptom_names(data: dict[str, Any]) -> list[str]:
    out: list[str] = []
    for s in data.get("symptoms") or []:
        if isinstance(s, dict):
            name = (s.get("name") or "").strip()
            if name:
                out.append(name)
        elif str(s).strip():
            out.append(str(s).strip())
    return out


def _vitals_to_strings(vitals: Any) -> list[str]:
    if not isinstance(vitals, dict):
        return []
    labels = {
        "blood_pressure": "BP",
        "heart_rate": "HR",
        "temperature": "Temp",
        "respiratory_rate": "RR",
        "weight": "Weight",
    }
    lines: list[str] = []
    for key, label in labels.items():
        val = vitals.get(key)
        if val:
            lines.append(f"{label} {val}")
    return lines


def _ensure_soap_sections(data: dict[str, Any]) -> dict[str, Any]:
    """Fill missing SOAP sections when the model dumps clinical data only into objective."""
    lang = _output_lang(data)
    soap = data.get("soap_note")
    if not isinstance(soap, dict):
        soap = {}
        data["soap_note"] = soap

    subjective = (soap.get("subjective") or "").strip()
    if not subjective:
        soap["subjective"] = _compose_patient_subjective(data)

    assessment = soap.get("assessment")
    if not assessment or (isinstance(assessment, list) and len(assessment) == 0):
        soap["assessment"] = list(data.get("diagnoses") or [])

    plan = soap.get("plan")
    if not plan or (isinstance(plan, list) and len(plan) == 0):
        plan_items: list[str] = []
        tp = data.get("treatment_plan")
        if isinstance(tp, list):
            plan_items.extend(str(x).strip() for x in tp if str(x).strip())
        elif isinstance(tp, str) and tp.strip():
            plan_items.append(tp.strip())
        soap["plan"] = _dedupe_strings(plan_items)

    obj = soap.get("objective")
    if not isinstance(obj, dict):
        obj = {}

    if not obj.get("vitals") and data.get("vital_signs"):
        obj["vitals"] = _vitals_to_strings(data["vital_signs"])
    if not obj.get("ecg") and data.get("ecg"):
        obj["ecg"] = _as_str_list(data["ecg"])
    if not obj.get("laboratory_results") and data.get("laboratory_results"):
        obj["laboratory_results"] = _as_str_list(data["laboratory_results"])
    if not obj.get("imaging") and data.get("imaging"):
        obj["imaging"] = _as_str_list(data["imaging"])
    if not obj.get("echo") and data.get("echocardiogram"):
        obj["echo"] = _as_str_list(data["echocardiogram"])

    # Remove ECG duplicates mistakenly placed under imaging
    ecg_set = {_norm_key(x) for x in _as_str_list(obj.get("ecg"))}
    if ecg_set and obj.get("imaging"):
        obj["imaging"] = [
            x for x in _as_str_list(obj["imaging"])
            if not (_norm_key(x).startswith("ecg") or _norm_key(x) in ecg_set)
        ]

    soap["objective"] = obj
    data["soap_note"] = soap
    return data


def _as_str_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, list):
        return [str(x).strip() for x in value if str(x).strip()]
    return [str(value).strip()]


def build_api_response(
    extracted: dict[str, Any],
    source: str,
    source_text: str | None = None,
    verify_call: Callable[[str, str], str | None] | None = None,
) -> dict[str, Any]:
    """Flatten structured data for API + legacy text fields."""
    data = normalize_extraction(extracted, source_text=source_text, verify_call=verify_call)
    lang = _output_lang(data)
    soap = data.get("soap_note") or {}
    objective = soap.get("objective") if isinstance(soap.get("objective"), dict) else {}

    diagnoses = data.get("diagnoses") or []
    plan_items = soap.get("plan") or []
    if isinstance(plan_items, str):
        plan_items = [plan_items]

    return {
        "extracted_data": data,
        "structured": data,
        "source": source,
        "chief_complaint": data.get("chief_complaint"),
        "symptoms": symptoms_to_string(data.get("symptoms", [])),
        "symptoms_list": data.get("symptoms", []),
        "diagnosis": _numbered_list(diagnoses),
        "diagnoses": diagnoses,
        "severity": data.get("severity") or "undetermined",
        "validation_report": data.get("validation_report") or {},
        "verification_pass": data.get("verification_pass") or {},
        "vitals_source": data.get("vitals_source") or "sensor",
        "treatment_plan": _list_to_bullets(plan_items),
        "plan_list": plan_items,
        "prescription": data.get("prescription") or [],
        "medications": data.get("prescription") or [],
        "medications_current": data.get("medications_current") or [],
        "medications_discontinued": data.get("medications_discontinued") or [],
        "vital_signs": data.get("vital_signs") or {},
        "subjective": soap.get("subjective") or "",
        "objective": _objective_dict_to_text(objective, lang),
        "objective_structured": objective,
        "assessment": _numbered_list(soap.get("assessment") or []),
        "assessment_list": soap.get("assessment") or [],
        "plan": _list_to_bullets(plan_items),
        "follow_up": data.get("follow_up"),
        "follow_up_items": data.get("follow_up_items") or [],
        "clinical_summary": data.get("clinical_summary") or "",
        "clinical_findings": data.get("clinical_findings") or [],
        "patient_info": data.get("patient_info") or {},
        "medical_history": data.get("medical_history") or {},
        "notes": "\n".join(data.get("doctor_notes") or []) or None,
    }


def structured_to_record_fields(structured: dict[str, Any]) -> dict[str, Any]:
    api = build_api_response(structured, "stored")
    return {
        "chief_complaint": api.get("chief_complaint") or "Consultation",
        "symptoms": api.get("symptoms") or "See SOAP subjective",
        "diagnosis": ", ".join(api.get("diagnoses") or []) or "See SOAP assessment",
        "severity": api.get("severity") or "moderate",
        "treatment_plan": api.get("treatment_plan") or "See SOAP plan",
        "notes": api.get("notes"),
        "soap_subjective": api.get("subjective"),
        "soap_objective": api.get("objective"),
        "soap_assessment": api.get("assessment"),
        "soap_plan": api.get("plan"),
        "structured_data": json.dumps(structured, ensure_ascii=False),
    }
