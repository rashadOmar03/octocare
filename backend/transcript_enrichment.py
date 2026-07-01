"""Rule-based transcript enrichment when the LLM misses clinical facts."""

from __future__ import annotations

import re
from typing import Any

from medical_extraction import (
    _as_str_list,
    _dedupe_strings,
    _localized,
    _norm_key,
    _normalize_medication_item,
    _output_lang,
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


def enrich_from_transcript(data: dict[str, Any], transcript: str) -> dict[str, Any]:
    """Supplement extraction from transcript patterns (Arabic/English/mixed)."""
    if not (transcript or "").strip():
        return data

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
        if re.search(pattern, text, re.I):
            name = _localized(lang, en_name, ar_name)
            duration = None
            if ar_dur or en_dur:
                duration = _localized(lang, en_dur or "", ar_dur or "") or None
            _append_symptom(data, name, duration)

    data["symptoms"] = normalize_symptoms(data.get("symptoms", []))

    if not (data.get("chief_complaint") or "").strip():
        names = _symptom_names(data)
        if names:
            data["chief_complaint"] = names[0]

    diagnoses = _as_str_list(data.get("diagnoses"))
    blob = _norm_key(text + " " + " ".join(pmh) + " " + " ".join(_symptom_names(data)))

    if re.search(r"ACS|acute coronary|NSTEMI|STEMI|شريان\s*تاج", text, re.I):
        _append_unique(diagnoses, _localized(lang, "Possible acute coronary syndrome", "احتمال متلازمة الشريان التاجي الحاد"))
    if re.search(r"heart failure|فشل\s*قلب|قصور\s*قلب|decompensated\s*HF", text, re.I):
        _append_unique(diagnoses, _localized(lang, "Possible heart failure", "احتمال فشل قلبي"))
    if _has_item(pmh, "ضغط") or _has_item(pmh, "hypertension") or re.search(r"ضغط|htn|hypertension", text, re.I):
        _append_unique(diagnoses, _localized(lang, "Hypertension", "ارتفاع ضغط الدم"))
    if _has_item(pmh, "سكر") or _has_item(pmh, "diabetes") or re.search(r"سكر|diabetes|dm\b|t2dm", text, re.I):
        _append_unique(diagnoses, _localized(lang, "Diabetes mellitus", "داء السكري"))
    if re.search(r"pneumonia|التهاب\s*رئوي|community acquired", text, re.I):
        _append_unique(diagnoses, _localized(lang, "Pneumonia", "التهاب رئوي"))
    if re.search(r"major depression|depression|اكتئاب", text, re.I):
        _append_unique(diagnoses, _localized(lang, "Major depression", "اكتئاب"))
    if re.search(r"viral uri|upper respiratory|URI\b|برد\s*فيروس", text, re.I):
        _append_unique(diagnoses, _localized(lang, "Viral upper respiratory infection", "التهاب تنفسي فيروسي"))

    for symptom_keys, ar_dx, en_dx in _DX_INFERENCE:
        if any(k.lower() in blob or k in blob for k in symptom_keys):
            _append_unique(diagnoses, _localized(lang, en_dx, ar_dx))

    data["diagnoses"] = _dedupe_strings(diagnoses)
    pending = {_norm_key(x) for x in (
        "بانتظار مراجعة الطبيب", "pending physician review", "pending clinical assessment",
    )}
    if len(data["diagnoses"]) > 1:
        data["diagnoses"] = [d for d in data["diagnoses"] if _norm_key(str(d)) not in pending]

    soap = data.get("soap_note") or {}
    assessment = _as_str_list(soap.get("assessment"))
    if not assessment and diagnoses:
        soap["assessment"] = list(diagnoses)
    data["soap_note"] = soap

    for pattern, ar_finding, en_finding in _EXAM_PATTERNS:
        if re.search(pattern, text, re.I):
            _append_objective(data, "physical_exam", _localized(lang, en_finding, ar_finding))

    plan = _as_str_list((data.get("soap_note") or {}).get("plan"))
    follow = _as_str_list(data.get("follow_up_items"))
    for pattern, ar_item, en_item in _PLAN_PATTERNS:
        if re.search(pattern, text, re.I):
            item = _localized(lang, en_item, ar_item)
            _append_unique(plan, item)
            _append_unique(follow, item)

    if isinstance(data.get("soap_note"), dict):
        data["soap_note"]["plan"] = _dedupe_strings(plan)
    data["follow_up_items"] = _dedupe_strings(follow)
    data["follow_up"] = "; ".join(follow) if follow else data.get("follow_up")

    for pattern, drug, action, dose_pat in _RX_PATTERNS:
        if re.search(pattern, text, re.I):
            dose = None
            if dose_pat:
                dm = re.search(dose_pat, text, re.I)
                if dm and dm.lastindex:
                    dose = dm.group(1)
            med = _normalize_medication_item({
                "name": drug,
                "action": action,
                "dosage": dose or "—",
                "frequency": "daily" if action == "Start" else None,
            }, default_action=action)
            if med:
                key = "prescription" if action in ("Start", "Increase", "Decrease", "Administered") else "medications_current"
                _append_medication(data, key, med)

    if not data.get("severity") or data.get("severity") == "unknown":
        if re.search(r"severe|شديد|critical|حرج|ACS|admit|stat", text, re.I):
            data["severity"] = "moderate"

    return data
