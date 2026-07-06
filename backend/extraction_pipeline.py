"""Deterministic post-AI extraction pipeline: normalize → resolve → validate → summarize."""

from __future__ import annotations

import copy
import json
import re
from typing import Any

from extraction_schema import (
    DiagnosisCertainty,
    Experiencer,
    MedAction,
    SeverityLevel,
    Temporality,
    canonical_med_action,
)

# Re-use shared helpers from medical_extraction without circular imports at module level
from medical_extraction import (
    _as_str_list,
    _dedupe_strings,
    _norm_key,
    _normalize_diagnosis,
    _output_lang,
    normalize_symptoms,
)

_NEGATION_EN = re.compile(
    r"\b(?:no|not|denies|denied|without|absent|negative for|rules?\s*out|never|nor|"
    r"free of|lack of|doesn'?t have|don'?t have|did not have|no evidence of)\b",
    re.IGNORECASE,
)
_NEGATION_AR = re.compile(
    r"(?:لا\s|ما\s|مفيش|مافيش|بدون|عدم|ينفي|نفى|ما\s*عند|مش\s*عند|"
    r"لا\s*يوجد|لا\s*توجد|ليس\s*لد|من\s*غير|سلبي\s*ل)",
)

_HISTORICAL_CUES = re.compile(
    r"(?:past|previous|old|former|history of|had\s+in\s+the\s+past|years?\s+ago|"
    r"previously|prior|remote|childhood|سابق|قديم|من\s*زمان|سابقًا|في\s*الماضي|"
    r"منذ\s*\d+\s*س(?:نة|ن)|old\s+record|previous\s+visit|prior\s+admission|"
    r"discharge\s+summary|old\s+medication\s+list|prior\s+meds?)",
    re.IGNORECASE,
)
_PLANNED_CUES = re.compile(
    r"(?:will|plan to|schedule|follow[- ]?up|repeat|order|request|refer|admit|"
    r"سوف|سيتم|خطة|متابعة|طلب|إحالة|تنويم|schedule|ordered)",
    re.IGNORECASE,
)
_FAMILY_CUES = re.compile(
    r"(?:family\s+history|f/h|fhx|father|mother|brother|sister|sibling|parent|"
    r"الأب|الاب|الأم|الام|الاخ|الأخ|الاخت|الأخت|العائلة|عائلة|والد|والدة|أخ|أخت)",
    re.IGNORECASE,
)
_FATHER_CUES = re.compile(r"(?:father|dad|paternal|الأب|الاب|والد|أبو)", re.IGNORECASE)
_MOTHER_CUES = re.compile(r"(?:mother|mom|maternal|الأم|الام|والدة|أم)", re.IGNORECASE)
_SIBLING_CUES = re.compile(r"(?:brother|sister|sibling|الأخ|الاخت|الأخت|أخ|أخت)", re.IGNORECASE)

_VAGUE_FINDING = re.compile(
    r"^(?:ecg|ekg|cxr|x-?ray|mri|ct|echo|ultrasound|labs?|blood\s*work|"
    r"تخطيط|أشعة|تحاليل|إيكو|سونار)(?:\s+(?:done|ordered|requested|pending|normal|abnormal))?$",
    re.IGNORECASE,
)

_ORDER_ONLY = re.compile(
    r"^(?:order|request|schedule|do|get|repeat|طلب|إجراء)\s+",
    re.IGNORECASE,
)

_MED_ACTION_CUES: list[tuple[re.Pattern[str], MedAction]] = [
    (re.compile(r"\b(?:start|begin|initiate|prescribe|add|commence|ابدأ|وصف|هنبدأ|هكتبلك|هنزود)\b", re.I), MedAction.START),
    (re.compile(r"\b(?:continue|maintain|ongoing|استمر|مستمر|يستمر)\b", re.I), MedAction.CONTINUE),
    (re.compile(r"\b(?:hold|suspend|pause|ايقاف\s*مؤقت|إيقاف\s*مؤقت)\b", re.I), MedAction.HOLD),
    (re.compile(r"\b(?:stop|discontinue|cease|وقف|ايقاف|إيقاف|بلاش|أوقف)\b", re.I), MedAction.STOP),
    (re.compile(r"\b(?:one[- ]time|single\s+dose|stat\s+dose|مرة\s*واحدة)\b", re.I), MedAction.ONE_TIME),
    (re.compile(r"\b(?:prn|if\s+needed|when\s+needed|عند\s+الحاجة|conditional)\b", re.I), MedAction.CONDITIONAL),
]

_DIAG_CERTAINTY_CUES: list[tuple[re.Pattern[str], DiagnosisCertainty]] = [
    (re.compile(r"(?:rule\s*out|r/o|\?|possible|probable|suspect|likely|maybe|احتمال|مشتبه|محتمل)", re.I), DiagnosisCertainty.SUSPECTED),
    (re.compile(r"(?:confirmed|diagnosed with|known|established|مؤكد|تشخيص)", re.I), DiagnosisCertainty.CONFIRMED),
]


def _snippet(text: str, start: int, end: int, radius: int = 60) -> str:
    if not text:
        return ""
    a = max(0, start - radius)
    b = min(len(text), end + radius)
    return text[a:b].strip()


def _is_negated_before(text: str, start: int) -> bool:
    """True when negation immediately precedes an entity (not trailing rule-out differentials)."""
    window_before = text[max(0, start - 50):start]
    for pat in (_NEGATION_EN, _NEGATION_AR):
        if pat.search(window_before):
            return True
    return False


def _is_negated_near(text: str, start: int, end: int) -> bool:
    window_before = text[max(0, start - 50):start]
    window_after = text[end:min(len(text), end + 20)]
    for pat in (_NEGATION_EN, _NEGATION_AR):
        if pat.search(window_before) or pat.search(window_after[:30]):
            return True
    return False


def _detect_temporality(context: str) -> Temporality:
    if _FAMILY_CUES.search(context):
        return Temporality.FAMILY_HISTORY
    if _HISTORICAL_CUES.search(context):
        return Temporality.HISTORICAL
    if _PLANNED_CUES.search(context):
        return Temporality.PLANNED
    if re.search(r"(?:recent|last\s+(?:week|month|few\s+days)|آخر\s*(?:أسبوع|شهر))", context, re.I):
        return Temporality.RECENT
    return Temporality.CURRENT


def _detect_experiencer(context: str) -> Experiencer:
    if _FATHER_CUES.search(context):
        return Experiencer.FATHER
    if _MOTHER_CUES.search(context):
        return Experiencer.MOTHER
    if _SIBLING_CUES.search(context):
        return Experiencer.SIBLING
    if _FAMILY_CUES.search(context):
        return Experiencer.OTHER
    return Experiencer.PATIENT


def _find_in_source(name: str, source: str) -> tuple[int, int, str]:
    if not name or not source:
        return -1, -1, ""
    for term in {name, name.lower(), name.title()}:
        idx = source.lower().find(term.lower())
        if idx >= 0:
            return idx, idx + len(term), _snippet(source, idx, idx + len(term))
    return -1, -1, ""


def _find_med_in_source(name: str, action: MedAction, source: str) -> tuple[int, int, str]:
    """Locate the best-matching mention of a drug for a given action in source text."""
    if not name or not source:
        return -1, -1, ""
    name_l = name.lower()
    source_l = source.lower()
    best_pos = -1
    best_end = -1
    best_evidence = ""
    start_at = 0
    while True:
        idx = source_l.find(name_l, start_at)
        if idx < 0:
            break
        end = idx + len(name)
        ctx = _snippet(source, idx, end)
        matched = action == MedAction.UNKNOWN
        if not matched:
            for pat, act in _MED_ACTION_CUES:
                if act == action and pat.search(ctx):
                    matched = True
                    break
        if matched and idx >= best_pos:
            best_pos = idx
            best_end = end
            best_evidence = ctx
        start_at = idx + 1
    if best_pos >= 0:
        return best_pos, best_end, best_evidence
    return _find_in_source(name, source)


def _clean_text(text: str) -> str:
    t = (text or "").strip()
    t = re.sub(r"\s+", " ", t)
    t = re.sub(r"^[,\-–—•*]+\s*", "", t)
    t = re.sub(r"\s*[,\-–—•*]+$", "", t)
    if len(t) < 2 or t in {".", "-", "—", "..."}:
        return ""
    return t


def _is_malformed(text: str) -> bool:
    t = _clean_text(text)
    if not t:
        return True
    if len(t) <= 2 and not t.isdigit():
        return True
    if re.fullmatch(r"[\W_]+", t):
        return True
    return False


def _normalize_med_item(item: Any, source_text: str = "") -> dict[str, Any] | None:
    if isinstance(item, str):
        name = _clean_text(item)
        if not name:
            return None
        start, end, evidence = _find_in_source(name, source_text)
        ctx = _snippet(source_text, start, end) if start >= 0 else name
        action = MedAction.UNKNOWN
        for pat, act in _MED_ACTION_CUES:
            if pat.search(ctx):
                action = act
                break
        start, end, evidence = _find_med_in_source(name, action, source_text)
        ctx = _snippet(source_text, start, end) if start >= 0 else name
        return {
            "name": name,
            "action": action.value,
            "dosage": None,
            "frequency": None,
            "route": None,
            "duration": None,
            "notes": None,
            "temporality": _detect_temporality(ctx).value,
            "source_evidence": evidence or None,
            "confidence": 0.6 if action == MedAction.UNKNOWN else 0.8,
            "position": start if start >= 0 else 999999,
        }
    if not isinstance(item, dict):
        return None
    name = _clean_text(item.get("name") or item.get("medication_name") or "")
    if not name:
        return None
    start, end, evidence = _find_in_source(name, source_text)
    ctx = _snippet(source_text, start, end) if start >= 0 else json.dumps(item, ensure_ascii=False)
    action = canonical_med_action(item.get("action"))
    start, end, evidence = _find_med_in_source(name, action, source_text)
    ctx = _snippet(source_text, start, end) if start >= 0 else json.dumps(item, ensure_ascii=False)
    for pat, act in _MED_ACTION_CUES:
        if action == MedAction.UNKNOWN and pat.search(ctx):
            action = act
            break
    temp = item.get("temporality")
    if isinstance(temp, str) and temp.upper() in Temporality.__members__:
        temporality = Temporality[temp.upper()]
    else:
        temporality = _detect_temporality(ctx)
    return {
        "name": name,
        "action": action.value,
        "dosage": item.get("dosage") or item.get("dose"),
        "frequency": item.get("frequency"),
        "route": item.get("route"),
        "duration": item.get("duration"),
        "notes": item.get("notes") or item.get("instructions"),
        "temporality": temporality.value,
        "source_evidence": item.get("source_evidence") or evidence or None,
        "confidence": float(item.get("confidence") or 0.75),
        "position": int(item.get("position") if item.get("position") is not None else (start if start >= 0 else 999999)),
    }


def _collect_medication_mentions(data: dict[str, Any], source_text: str) -> list[dict[str, Any]]:
    mentions: list[dict[str, Any]] = []
    for key in ("medications_current", "prescription"):
        for item in data.get(key) or []:
            med = _normalize_med_item(item, source_text)
            if med:
                med["origin"] = key
                mentions.append(med)
    for raw in _as_str_list(data.get("medications_discontinued")):
        med = _normalize_med_item({"name": raw, "action": MedAction.STOP.value}, source_text)
        if med:
            med["origin"] = "discontinued"
            mentions.append(med)
    return mentions


def reconcile_medications(data: dict[str, Any], source_text: str) -> dict[str, Any]:
    """Latest explicit instruction wins per normalized drug name."""
    mentions = _collect_medication_mentions(data, source_text)
    mentions.sort(key=lambda m: (m.get("position", 999999), m.get("name", "")))

    by_drug: dict[str, dict[str, Any]] = {}
    for med in mentions:
        key = _norm_key(med["name"])
        if not key:
            continue
        if med.get("temporality") == Temporality.HISTORICAL.value and med.get("action") == MedAction.UNKNOWN.value:
            continue
        existing = by_drug.get(key)
        if existing is None or med.get("position", 0) >= existing.get("position", 0):
            by_drug[key] = med

    current: list[dict[str, Any]] = []
    prescription: list[dict[str, Any]] = []
    discontinued: list[str] = []

    for med in by_drug.values():
        action = MedAction[med["action"]] if med["action"] in MedAction.__members__ else MedAction.UNKNOWN
        temp = med.get("temporality", Temporality.CURRENT.value)
        if temp == Temporality.HISTORICAL.value:
            continue
        if action in (MedAction.STOP, MedAction.HOLD):
            discontinued.append(med["name"])
            continue
        if action in (MedAction.START, MedAction.ONE_TIME, MedAction.CONDITIONAL, MedAction.UNKNOWN):
            if action == MedAction.UNKNOWN:
                med["action"] = MedAction.CONTINUE.value
                current.append(_strip_internal_med_fields(med))
            else:
                prescription.append(_strip_internal_med_fields(med))
        elif action == MedAction.CONTINUE:
            current.append(_strip_internal_med_fields(med))
        else:
            prescription.append(_strip_internal_med_fields(med))

    data["medications_current"] = current
    data["prescription"] = prescription
    data["medications_discontinued"] = _dedupe_strings(discontinued)
    data["medications_reconciled"] = list(by_drug.values())
    return data


def _strip_internal_med_fields(med: dict[str, Any]) -> dict[str, Any]:
    out = {k: v for k, v in med.items() if k not in ("origin", "position")}
    return out


def _resolve_symptoms(data: dict[str, Any], source_text: str) -> dict[str, Any]:
    symptoms = normalize_symptoms(data.get("symptoms", []))
    resolved: list[dict[str, Any]] = []
    for s in symptoms:
        name = _clean_text(s.get("name", ""))
        if not name or _is_malformed(name):
            continue
        start, end, evidence = _find_in_source(name, source_text)
        ctx = _snippet(source_text, start, end) if start >= 0 else name
        negated = _is_negated_near(source_text, start, end) if start >= 0 else False
        exp = _detect_experiencer(ctx)
        temp = _detect_temporality(ctx)
        if negated or temp == Temporality.FAMILY_HISTORY or exp != Experiencer.PATIENT:
            continue
        if temp == Temporality.HISTORICAL:
            mh = data.setdefault("medical_history", {})
            if isinstance(mh, dict):
                pmh = _as_str_list(mh.get("past_medical_history"))
                _append_unique(pmh, name)
                mh["past_medical_history"] = _dedupe_strings(pmh)
            continue
        resolved.append({
            **s,
            "name": name,
            "negated": False,
            "temporality": temp.value,
            "experiencer": exp.value,
            "source_evidence": evidence or None,
            "confidence": 0.85,
        })
    data["symptoms"] = resolved
    return data


def _append_unique(items: list[str], value: str) -> None:
    v = _clean_text(value)
    if not v:
        return
    key = _norm_key(v)
    if any(_norm_key(x) == key for x in items):
        return
    items.append(v)


def _resolve_diagnoses(data: dict[str, Any], source_text: str) -> dict[str, Any]:
    lang = _output_lang(data)
    raw = data.get("diagnoses") or []
    if isinstance(raw, str):
        raw = [raw]
    resolved: list[dict[str, Any]] = []
    for item in raw:
        if isinstance(item, dict):
            name = _clean_text(item.get("name") or item.get("text") or "")
            certainty_raw = item.get("certainty")
        else:
            name = _clean_text(str(item))
            certainty_raw = None
        if not name or _is_malformed(name):
            continue
        start, end, evidence = _find_in_source(name, source_text)
        ctx = _snippet(source_text, start, end) if start >= 0 else name
        if _is_negated_before(source_text, start) if start >= 0 else False:
            continue
        exp = _detect_experiencer(ctx)
        temp = _detect_temporality(ctx)
        if exp != Experiencer.PATIENT or temp == Temporality.FAMILY_HISTORY:
            mh = data.setdefault("medical_history", {})
            if isinstance(mh, dict):
                fh = _as_str_list(mh.get("family_history"))
                label = f"{exp.value}: {name}" if exp != Experiencer.OTHER else name
                _append_unique(fh, label)
                mh["family_history"] = _dedupe_strings(fh)
            continue
        if temp == Temporality.HISTORICAL:
            continue
        if temp == Temporality.PLANNED and not re.search(r"diagnos|تشخيص", ctx, re.I):
            continue
        certainty = DiagnosisCertainty.UNKNOWN
        if certainty_raw and str(certainty_raw).upper() in DiagnosisCertainty.__members__:
            certainty = DiagnosisCertainty[str(certainty_raw).upper()]
        else:
            for pat, cert in _DIAG_CERTAINTY_CUES:
                if pat.search(name) or pat.search(ctx):
                    certainty = cert
                    break
        if certainty == DiagnosisCertainty.UNKNOWN and not _diagnosis_explicitly_documented(name, ctx, source_text):
            continue
        resolved.append({
            "name": _normalize_diagnosis(name, lang),
            "certainty": certainty.value,
            "temporality": temp.value,
            "experiencer": exp.value,
            "source_evidence": evidence or None,
            "confidence": 0.8 if certainty != DiagnosisCertainty.UNKNOWN else 0.65,
        })
    data["diagnoses_structured"] = resolved
    data["diagnoses"] = [d["name"] for d in resolved]
    return data


def _diagnosis_explicitly_documented(name: str, ctx: str, source_text: str) -> bool:
    """Require diagnostic language near the term — not symptom-only inference."""
    diagnostic_cues = re.compile(
        r"(?:diagnos|assessment|impression|dx\b|icd|condition|disease|disorder|syndrome|"
        r"تشخيص|تشخيصات|حالة|مرض|متلازمة|Assessment|Plan:)",
        re.IGNORECASE,
    )
    blob = f"{ctx} {name}"
    if diagnostic_cues.search(blob):
        return True
    if re.search(r"(?:possible|probable|suspect|rule\s*out|\?|احتمال|مشتبه|محتمل)", blob, re.I):
        return True
    # Explicit numbered assessment lines in source
    if source_text and re.search(rf"(?:^|\n)\s*(?:\d+[\.\)]\s*)?{re.escape(name[:20])}", source_text, re.I):
        start, end, _ = _find_in_source(name, source_text)
        if start >= 0:
            return diagnostic_cues.search(_snippet(source_text, start, end))
    return False


def _resolve_family_history(data: dict[str, Any], source_text: str) -> dict[str, Any]:
    if not source_text:
        return data
    mh = data.setdefault("medical_history", {})
    if not isinstance(mh, dict):
        mh = {}
        data["medical_history"] = mh
    fh = _as_str_list(mh.get("family_history"))
    for m in re.finditer(
        r"(?:family\s+history|f/h|fhx|(?:father|mother|brother|sister)[^\n\.]{0,40})",
        source_text,
        re.IGNORECASE,
    ):
        line = _clean_text(m.group(0))
        if line and len(line) > 5:
            exp = _detect_experiencer(line)
            _append_unique(fh, f"{exp.value}: {line}" if exp != Experiencer.PATIENT else line)
    mh["family_history"] = _dedupe_strings(fh)
    return data


def _filter_objective_items(items: list[str]) -> list[str]:
    out: list[str] = []
    for raw in items:
        text = _clean_text(raw)
        if not text or _is_malformed(text):
            continue
        if _VAGUE_FINDING.match(text):
            continue
        if _ORDER_ONLY.match(text) and len(text.split()) <= 4:
            continue
        out.append(text)
    return _dedupe_strings(out)


def _resolve_objective_sections(data: dict[str, Any]) -> dict[str, Any]:
    soap = data.get("soap_note") or {}
    obj = soap.get("objective") if isinstance(soap.get("objective"), dict) else {}
    for key in ("vitals", "physical_exam", "laboratory_results", "ecg", "imaging", "echo"):
        obj[key] = _filter_objective_items(_as_str_list(obj.get(key)))
    soap["objective"] = obj
    data["soap_note"] = soap
    for top_key, obj_key in [
        ("laboratory_results", "laboratory_results"),
        ("imaging", "imaging"),
        ("ecg", "ecg"),
        ("echocardiogram", "echo"),
    ]:
        data[top_key] = _filter_objective_items(_as_str_list(data.get(top_key)))
    return data


def _strip_note_vitals(data: dict[str, Any]) -> dict[str, Any]:
    """Vitals come from Octocare sensors — do not treat note dict as hardware vitals."""
    data["vital_signs"] = {}
    data["vitals_source"] = "sensor"
    soap = data.get("soap_note") or {}
    if isinstance(soap.get("objective"), dict):
        soap["objective"]["vitals"] = []
        data["soap_note"] = soap
    return data


def _dedupe_plan_followup(data: dict[str, Any]) -> dict[str, Any]:
    soap = data.get("soap_note") or {}
    plan = _dedupe_strings(_as_str_list(soap.get("plan")))
    follow = _dedupe_strings(_as_str_list(data.get("follow_up_items")))
    dx_keys = {_norm_key(str(d)) for d in data.get("diagnoses") or []}

    def not_dx(item: str) -> bool:
        k = _norm_key(item)
        return k not in dx_keys and not any(d in k or k in d for d in dx_keys if d)

    plan = [p for p in plan if not_dx(p) and _clean_text(p)]
    follow = [f for f in follow if _clean_text(f)]
    seen = {_norm_key(x) for x in plan}
    follow = [f for f in follow if _norm_key(f) not in seen]

    soap["plan"] = plan
    data["soap_note"] = soap
    data["follow_up_items"] = follow
    data["follow_up"] = "; ".join(follow) if follow else None
    return data


def validate_extraction(data: dict[str, Any], source_text: str) -> tuple[dict[str, Any], dict[str, Any]]:
    warnings: list[str] = []
    errors: list[str] = []

    for med in (data.get("medications_current") or []) + (data.get("prescription") or []):
        action = med.get("action")
        if action not in MedAction.__members__:
            warnings.append(f"Invalid medication action for {med.get('name')}: {action}")
            med["action"] = MedAction.UNKNOWN.value

    for s in data.get("symptoms") or []:
        if s.get("negated"):
            errors.append(f"Negated symptom leaked: {s.get('name')}")
        if s.get("experiencer") not in (Experiencer.PATIENT.value, None):
            errors.append(f"Non-patient symptom: {s.get('name')}")

    for d in data.get("diagnoses_structured") or []:
        if d.get("experiencer") not in (Experiencer.PATIENT.value, None):
            errors.append(f"Family diagnosis on patient list: {d.get('name')}")

    if not data.get("diagnoses") and source_text and re.search(r"diagnos|تشخيص|assessment", source_text, re.I):
        warnings.append("No diagnoses extracted despite diagnostic language in note")

    report = {
        "warnings": warnings,
        "errors": errors,
        "valid": len(errors) == 0,
    }
    data["validation_report"] = report
    return data, report


def generate_summary_and_severity(data: dict[str, Any]) -> dict[str, Any]:
    lang = _output_lang(data)
    symptoms = [s.get("name") for s in data.get("symptoms") or [] if s.get("name")]
    diagnoses = data.get("diagnoses") or []
    findings = _as_str_list(data.get("clinical_findings"))

    if lang == "ar":
        parts = []
        if symptoms:
            parts.append(f"يشكو المريض من {', '.join(symptoms[:4])}")
        if diagnoses:
            parts.append(f"التقييم يشمل {', '.join(diagnoses[:3])}")
        if findings:
            parts.append(f"من findings: {', '.join(findings[:2])}")
        data["clinical_summary"] = ". ".join(parts) + "." if parts else "ملخص سريري محدود بناءً على البيانات المؤكدة."
    else:
        parts = []
        if symptoms:
            parts.append(f"Patient reports {', '.join(symptoms[:4])}")
        if diagnoses:
            parts.append(f"Assessment includes {', '.join(diagnoses[:3])}")
        if findings:
            parts.append(f"Notable findings: {', '.join(findings[:2])}")
        data["clinical_summary"] = ". ".join(parts) + "." if parts else "Limited clinical summary from validated structured data."

    explicit = (data.get("severity") or "").strip().lower()
    if explicit in ("mild", "moderate", "severe", "critical"):
        data["severity"] = explicit
        return data

    score = 0
    sev_symptoms = [s for s in data.get("symptoms") or [] if (s.get("severity") or "").lower() in ("severe", "critical", "شديد")]
    if sev_symptoms:
        score += 2
    blob = " ".join(diagnoses).lower()
    if any(x in blob for x in ("critical", "shock", "arrest", "حرج")):
        score += 3
    if any(x in blob for x in ("severe", "acute", "شديد", "حاد")):
        score += 1
    if score >= 4:
        data["severity"] = SeverityLevel.CRITICAL.value
    elif score >= 3:
        data["severity"] = SeverityLevel.SEVERE.value
    elif score >= 1:
        data["severity"] = SeverityLevel.MODERATE.value
    elif symptoms:
        data["severity"] = SeverityLevel.MILD.value
    else:
        data["severity"] = SeverityLevel.UNDETERMINED.value
    return data


def _rebuild_soap_from_validated(data: dict[str, Any]) -> dict[str, Any]:
    soap = data.get("soap_note") or {}
    if not isinstance(soap, dict):
        soap = {}
    if not (soap.get("assessment") or []):
        soap["assessment"] = list(data.get("diagnoses") or [])
    data["soap_note"] = soap
    return data


def run_extraction_pipeline(data: dict[str, Any], source_text: str | None = None) -> tuple[dict[str, Any], dict[str, Any]]:
    """Full deterministic pipeline after initial LLM normalization."""
    source = source_text or ""
    payload = copy.deepcopy(data)

    payload = _strip_note_vitals(payload)
    payload = _resolve_symptoms(payload, source)
    payload = _resolve_family_history(payload, source)
    payload = _resolve_diagnoses(payload, source)
    payload = reconcile_medications(payload, source)
    payload = _resolve_objective_sections(payload)
    payload = _dedupe_plan_followup(payload)
    payload = _rebuild_soap_from_validated(payload)
    payload, report = validate_extraction(payload, source)
    payload = generate_summary_and_severity(payload)
    return payload, report
