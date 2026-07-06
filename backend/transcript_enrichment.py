"""Rule-based transcript enrichment when the LLM misses clinical facts."""

from __future__ import annotations

import re
from typing import Any

from extraction_schema import Temporality
from medical_extraction import (
    _as_str_list,
    _dedupe_strings,
    _filter_negated_symptoms,
    _localized,
    _norm_key,
    _output_lang,
    _symptom_is_negated,
    normalize_symptoms,
)

# pattern, Arabic label, English label ({years} optional)
_PMH_RULES: list[tuple[str, str, str]] = [
    (r"ضغط\s*(?:from|من)\s*(?:long\s*)?time\s*(?:~?\s*)?(\d+)\s*(?:yrs?|years?|س(?:نة|ن))", "ارتفاع ضغط الدم (منذ {years} سنة)", "Hypertension ({years} years)"),
    (r"ضغط\s*(?:from|من)\s*(?:long\s*)?time|ضغط\s*(?:من|منذ)\s*زمان|[-–]\s*ضغط|on meds.*BP|hypertension|(?:^|\s)HTN(?:\s|$)", "ارتفاع ضغط الدم", "Hypertension"),
    (r"سكر\s*(?:~?\s*)?(\d+)\s*(?:yrs?|years?|س(?:نة|ن))", "داء السكري (منذ {years} سنة)", "Diabetes mellitus ({years} years)"),
    (r"سكر\s*(?:from|من)\s*(?:long\s*)?time|[-–]\s*سكر|diabetes|(?:^|\s)DM(?:\s|$)|T2DM|type\s*2\s*diabetes", "داء السكري", "Type 2 diabetes mellitus"),
    (r"CHF|heart failure|decompensated\s*HF|فشل\s*قلب|قصور\s*قلب", "فشل القلب", "Heart failure"),
    (r"CAD|coronary artery|coronary disease|ACS rule-out", "مرض الشريان التاجي", "Coronary artery disease"),
    (r"ربو|asthma|COPD|انسداد\s*رئوي", "الربو / COPD", "Asthma / COPD"),
    (r"hypothyroid|خمول\s*الغدة|underactive thyroid", "خمول الغدة الدرقية", "Hypothyroidism"),
    (r"depression|اكتئاب|major depressive", "اكتئاب", "Major depression"),
    (r"fracture|كسر", "كسر سابق", "History of fracture"),
]

# pattern, ar_name, en_name, ar_duration, en_duration
_SYMPTOM_RULES: list[tuple[str, str, str, str | None, str | None]] = [
    (r"نفس[يى]\s*بيق?ف|مش\s*قادر\s*أ?تنفس|shortness of breath|SOB\b|dyspnea on exertion|بيطلع\s*السلم", "ضيق نفس", "Shortness of breath", "مع الجهد", "on exertion"),
    (r"وجع\s*(?:في\s*)?(?:نص\s*)?(?:ال)?صدر|chest pain|CP\b|ألم\s*صدري", "ألم صدري", "Chest pain", None, None),
    (r"مخنوق|محتاج\s*(?:أ?كثر\s*من\s*)?مخد|orthopnea|PND\b|paroxysmal nocturnal", "ضيق نفس ليلي / orthopnea", "Orthopnea / PND", None, None),
    (r"تورم\s*(?:في\s*)?(?:ال)?ر(?:جل|جلين)|edema|وذمة|الجزمة\s*ضيق|pitting edema", "وذمة طرفية", "Peripheral edema", None, None),
    (r"دوخ[ةه]|dizz|lightheaded", "دوخة", "Dizziness", "عند الوقوف السريع", "on standing"),
    (r"كough|cough|كحة|productive cough", "سعال", "Cough", None, None),
    (r"حرارة|fever|temp\s*3[89]|39\s*°", "حمى", "Fever", None, None),
    (r"ألم\s*بطن|abdominal pain|belly pain| stomach pain", "ألم بطن", "Abdominal pain", None, None),
    (r"knee pain|وجع\s*ركبة|ركبة\s*يمين", "ألم الركبة", "Knee pain", None, None),
    (r"wheeze|wheezing|صفير|ربو\s*مزمن", "صفير", "Wheezing", None, None),
    (r"insomnia|أرق|cannot sleep", "أرق", "Insomnia", None, None),
    (r"sore throat|التهاب\s*حلق|حلق\s*يوجع", "التهاب حلق", "Sore throat", None, None),
    (r"nausea|غثيان|vomit", "غثيان", "Nausea", None, None),
    (r"weakness|ضعف|left\s*weakness|hemiparesis", "ضعف", "Weakness", None, None),
    (r"headache|صداع", "صداع", "Headache", None, None),
]

_DX_INFERENCE: list[tuple[list[str], str, str]] = [
    (["ألم صدري", "chest pain", "ضيق نفس", "dyspnea", "shortness of breath"], "احتمال متلازمة الشريان التاجي الحاد", "Possible acute coronary syndrome"),
    (["وذمة", "edema", "orthopnea", "peripheral edema"], "احتمال فشل قلبي", "Possible heart failure"),
    (["ارتفاع ضغط", "hypertension", "ضغط", "htn"], "ارتفاع ضغط الدم", "Hypertension"),
    (["سكر", "diabetes", "dm", "type 2 diabetes"], "داء السكري", "Diabetes mellitus"),
    (["pneumonia", "productive cough", "chest infection", "التهاب رئوي"], "التهاب رئوي", "Pneumonia"),
    (["depression", "اكتئاب", "insomnia"], "اكتئاب", "Major depression"),
    (["asthma", "wheeze", "wheezing", "ربو"], "تفاقم الربo", "Asthma exacerbation"),
    (["stroke", "weakness", "hemiparesis", "سكتة"], "احتمال سكتة دماغية", "Possible stroke"),
    (["fracture", "كسر"], "كسر", "Fracture"),
    (["hypothyroid", "خمول"], "خمول الغدة الدرقية", "Hypothyroidism"),
]

_PLAN_PATTERNS: list[tuple[str, str, str]] = [
    (r"echo|إيكو|echocardiogram", "طلب إيكو قلب", "Order echocardiogram"),
    (r"troponin|تروبونين|bnp|hba1c|HbA1c", "طلب تحاليل مخبرية", "Order laboratory tests"),
    (r"admit|admission|تنويم|دخول\s*مستشف|Admit for", "تقييم تنويم/دخول", "Consider admission"),
    (r"cardiology consult|Cardiology|neurology|استشارة\s*قلب", "استشارة تخصصية", "Specialist consult"),
    (r"daily weights|fluid restriction|diabetes education", "تثقيف وتعليمات متابعة", "Patient education and monitoring"),
    (r"ecg|ekg|تخطيط\s*قلب", "تخطيط قلب", "ECG"),
    (r"chest x.?ray|أشعة\s*صدر|CXR", "أشعة صدر", "Chest X-ray"),
    (r"mri|رنين\s*مغناطيس", "طلب MRI", "Order MRI"),
    (r"ct head|CT\s*head|أشعة\s*مقطعية\s*دماغ", "CT رأس عاجل", "Stat CT head"),
    (r"endoscopy|منظار", "طلب منظار", "Order endoscopy"),
    (r"x.?ray|أشعة\s*عادية|radiograph", "طلب أشعة", "Order X-ray"),
    (r"ultrasound|سونar|موجات\s*فوق\s*صوتية", "طلب سونar", "Order ultrasound"),
    (r"follow.?up|متابعة|review in|f/u", "متابعة عيادة", "Clinic follow-up"),
    (r"cast|جبيرة|splint", "جبيرة / تثبيت", "Cast / splint"),
]

# pattern, drug, action (Continue/Start), dose capture group pattern
_RX_PATTERNS: list[tuple[str, str, str, str | None]] = [
    (r"continue\s+metformin|continue metformin", "Metformin", "Continue", None),
    (r"start\s+insulin|insulin glargine|insulin\s+\d+\s*u", "Insulin", "Start", None),
    (r"Start:\s*aspirin|start aspirin|aspirin\s*(\d+\s*mg)?|أسبرين", "Aspirin", "Start", None),
    (r"start\s+furosemide|furosemide\s*(\d+\s*mg)?|lasix|Lasix|مدر\s*بول", "Furosemide", "Start", None),
    (r"start\s+atorvastatin|atorvastatin\s*(\d+\s*mg)?|lipitor", "Atorvastatin", "Start", None),
    (r"metformin|ميتفورمين", "Metformin", "Continue", None),
    (r"continue\s+amlodipine|amlodipine\s*(\d+\s*mg)?|أملودипин", "Amlodipine", "Continue", None),
    (r"lisinopril|ramipril|\bACE\b|\bARB\b", "ACE inhibitor", "Continue", None),
    (r"nitroglycerin|GTN|nitro", "Nitroglycerin", "Start", None),
    (r"amoxicillin|أموكسيسيلين", "Amoxicillin", "Start", None),
    (r"azithromycin|zithromax|أزithromycin", "Azithromycin", "Start", None),
    (r"ibuprofen|إيبوبروفين|brufen", "Ibuprofen", "Start", None),
    (r"paracetamol|acetaminophen|panadol|بارacetamol", "Paracetamol", "Start", None),
    (r"start\s+sertraline|sertraline\s*(\d+\s*mg)?|zoloft", "Sertraline", "Start", None),
    (r"salbutamol|albuterol|ventolin|بخاخ\s*الربo", "Salbutamol", "Continue", None),
    (r"start\s+budesonide|budesonide|بودesonide", "Budesonide", "Start", None),
    (r"omeprazole|losec|أومeprazole", "Omeprazole", "Start", None),
    (r"levothyroxine|synthroid|ليفoثyroxine", "Levothyroxine", "Continue", None),
    (r"prenatal vitamins|folic acid", "Prenatal vitamins", "Continue", None),
]

_EXAM_PATTERNS: list[tuple[str, str, str]] = [
    (r"تورم|edema|وذمة|الجزمة\s*ضيق|pitting edema", "وذمة طرفية bilaterally", "Bilateral pitting edema"),
    (r"مرهق|fatigue| tired|يبدو\s*مرهق", "المريض يبدو مرهقاً", "Patient appears fatigued"),
    (r"crackles|crepitations|رALE|احتقان", "أصوات رALE / احتقان رئوي", "Basilar crackles / congestion"),
    (r"wheezes|wheezing|صفير", "صفير عند التنفس", "Expiratory wheeze"),
]

_ALLERGY_PATTERNS: list[tuple[str, str, str]] = [
    (r"penicillin allergy|allergic to penicillin|حساسية\s*.*بنسلين|حساسية\s*بنسلين", "حساسية بنسلين", "Penicillin allergy"),
    (r"NKDA|no known allergies|NO allergy|لا\s*يوجد\s*حساسية", "—SKIP—", "—SKIP—"),
    (r"sulfa allergy|حساسية\s*سلfa", "حساسية sulfa", "Sulfa allergy"),
]


def _has_item(items: list[str], needle: str) -> bool:
    nk = _norm_key(needle)
    return any(nk in _norm_key(x) or _norm_key(x) in nk for x in items if x)


def _symptom_names(data: dict[str, Any]) -> list[str]:
    out: list[str] = []
    for s in data.get("symptoms") or []:
        if isinstance(s, dict):
            n = (s.get("name") or "").strip()
            if n:
                out.append(n)
        elif str(s).strip():
            out.append(str(s).strip())
    return out


def _append_unique(target: list[str], value: str) -> None:
    if not value or _has_item(target, value):
        return
    target.append(value)


def _append_symptom(data: dict[str, Any], name: str, duration: str | None = None) -> None:
    symptoms = data.get("symptoms") or []
    if not isinstance(symptoms, list):
        symptoms = []
    names = _symptom_names(data)
    if _has_item(names, name):
        return
    symptoms.append({"name": name, "duration": duration, "severity": None, "location": None})
    data["symptoms"] = symptoms


def _append_objective(data: dict[str, Any], section: str, text: str) -> None:
    soap = data.get("soap_note") or {}
    obj = soap.get("objective") if isinstance(soap.get("objective"), dict) else {}
    items = _as_str_list(obj.get(section))
    _append_unique(items, text)
    obj[section] = items
    soap["objective"] = obj
    data["soap_note"] = soap


def _append_medication(data: dict[str, Any], list_key: str, med: dict[str, Any]) -> None:
    current = data.get(list_key) or []
    if not isinstance(current, list):
        current = []
    names = [
        _norm_key((m.get("name") or "") if isinstance(m, dict) else str(m))
        for m in current
    ]
    nk = _norm_key(med.get("name") or "")
    if nk and nk not in names:
        current.append(med)
    data[list_key] = current


def _apply_label(template: str, match: re.Match[str] | None) -> str:
    value = template
    if match and "{years}" in value and match.lastindex and match.group(1):
        value = value.replace("{years}", match.group(1))
    return value


def safe_enrich_from_transcript(data: dict[str, Any], transcript: str) -> dict[str, Any]:
    """Safe gap-fill: PMH/allergies/plan only. No diagnosis inference, no hardcoded drug lists."""
    if not (transcript or "").strip():
        return data

    from medical_extraction import _filter_negated_symptoms, _symptom_is_negated

    lang = _output_lang(data)
    text = transcript
    mh = data.get("medical_history") if isinstance(data.get("medical_history"), dict) else {}
    pmh = _as_str_list(mh.get("past_medical_history"))
    allergies = _as_str_list(mh.get("allergies"))

    for pattern, ar_label, en_label in _PMH_RULES:
        m = re.search(pattern, text, re.I)
        if not m:
            continue
        label = _apply_label(_localized(lang, en_label, ar_label), m)
        ctx = _snippet(text, m.start(), m.end())
        if _detect_temporality(ctx) == Temporality.FAMILY_HISTORY:
            fh = _as_str_list(mh.get("family_history"))
            _append_unique(fh, label)
            mh["family_history"] = _dedupe_strings(fh)
        else:
            _append_unique(pmh, label)

    for pattern, ar_label, en_label in _ALLERGY_PATTERNS:
        if not re.search(pattern, text, re.I):
            continue
        label = _localized(lang, en_label, ar_label)
        if label == "—SKIP—":
            continue
        _append_unique(allergies, label)

    mh["past_medical_history"] = _dedupe_strings(pmh)
    mh["allergies"] = _dedupe_strings(allergies)
    data["medical_history"] = mh

    for pattern, ar_name, en_name, ar_dur, en_dur in _SYMPTOM_RULES:
        m = re.search(pattern, text, re.I)
        if not m:
            continue
        name = _localized(lang, en_name, ar_name)
        if _symptom_is_negated(name, text):
            continue
        ctx = _snippet(text, m.start(), m.end())
        if _detect_temporality(ctx) == Temporality.FAMILY_HISTORY:
            continue
        duration = _localized(lang, en_dur or "", ar_dur or "") or None if (ar_dur or en_dur) else None
        _append_symptom(data, name, duration)

    data["symptoms"] = normalize_symptoms(data.get("symptoms", []))
    if source_text := text:
        data["symptoms"] = _filter_negated_symptoms(data.get("symptoms") or [], source_text)

    if not (data.get("chief_complaint") or "").strip():
        names = _symptom_names(data)
        if names:
            data["chief_complaint"] = names[0]

    soap = data.get("soap_note") or {}
    plan = _as_str_list(soap.get("plan"))
    follow = _as_str_list(data.get("follow_up_items"))
    for pattern, ar_item, en_item in _PLAN_PATTERNS:
        m = re.search(pattern, text, re.I)
        if not m:
            continue
        item = _localized(lang, en_item, ar_item)
        if _detect_temporality(_snippet(text, m.start(), m.end())) == Temporality.PLANNED:
            _append_unique(follow, item)
        else:
            _append_unique(plan, item)

    for pattern, ar_finding, en_finding in _EXAM_PATTERNS:
        m = re.search(pattern, text, re.I)
        if m and not _is_negated_near(text, m.start(), m.end()):
            _append_objective(data, "physical_exam", _localized(lang, en_finding, ar_finding))

    if isinstance(data.get("soap_note"), dict):
        data["soap_note"]["plan"] = _dedupe_strings(plan)
    data["follow_up_items"] = _dedupe_strings(follow)
    data["follow_up"] = "; ".join(follow) if follow else data.get("follow_up")
    return data


_ENRICH_NEGATION = re.compile(
    r"(?:no|not|denies|without|لا |ما |مفيش|بدون|عدم|لا\s*يوجد)",
    re.IGNORECASE,
)
_ENRICH_HISTORICAL = re.compile(
    r"(?:past|previous|old|former|history of|سابق|قديم|من\s*زمان|previous\s+visit|old\s+record)",
    re.IGNORECASE,
)
_ENRICH_FAMILY = re.compile(
    r"(?:family\s+history|f/h|father|mother|brother|sister|الأب|الأم|العائلة)",
    re.IGNORECASE,
)
_ENRICH_PLANNED = re.compile(
    r"(?:will|plan to|schedule|follow[- ]?up|order|طلب|متابعة|تنويم)",
    re.IGNORECASE,
)


def _snippet(text: str, start: int, end: int, radius: int = 40) -> str:
    a = max(0, start - radius)
    b = min(len(text), end + radius)
    return text[a:b]


def _is_negated_near(text: str, start: int, end: int) -> bool:
    window_before = text[max(0, start - 50):start]
    return bool(_ENRICH_NEGATION.search(window_before))


def _detect_temporality(context: str) -> Temporality:
    if _ENRICH_FAMILY.search(context):
        return Temporality.FAMILY_HISTORY
    if _ENRICH_HISTORICAL.search(context):
        return Temporality.HISTORICAL
    if _ENRICH_PLANNED.search(context):
        return Temporality.PLANNED
    return Temporality.CURRENT


# Backward-compatible alias — routes to safe enrichment
def enrich_from_transcript(data: dict[str, Any], transcript: str) -> dict[str, Any]:
    return safe_enrich_from_transcript(data, transcript)
