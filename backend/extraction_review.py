"""Doctor-prompt-driven extraction review assistant."""

from __future__ import annotations

import json
import re
from typing import Any, Callable

from json_repair import repair_json

from medical_extraction import (
    _as_str_list,
    _dedupe_strings,
    _norm_key,
    _output_lang,
    detect_input_language,
    normalize_extraction,
)
from transcript_enrichment import enrich_from_transcript

PROMPT_REVIEW_SYSTEM = """You are a clinical documentation assistant helping a physician review an extracted medical record.

The physician asks a QUESTION in Arabic or English about the extraction (e.g. "Is there a prescription?", "What's missing?", "Check the plan").

You have:
1) ORIGINAL TRANSCRIPT
2) EXTRACTED JSON record
3) PHYSICIAN QUESTION

Return ONE valid JSON object ONLY:
{
  "answer": "yes" | "no" | "partial",
  "message": "Clear natural-language reply to the physician in the SAME language they used",
  "suggestions": [
    {
      "category": "symptoms|diagnoses|medications_current|prescription|allergies|medical_history|family_history|social_history|previous_surgeries|follow_up|laboratory_results|imaging|ecg|echocardiogram|vital_signs|procedures|doctor_notes|clinical_findings|plan|other",
      "field": "target field",
      "suggested_value": "value to add if physician approves",
      "confidence": 0.0-1.0,
      "explanation": "why",
      "source_snippet": "quote from transcript"
    }
  ]
}

RULES:
- Answer the physician's specific question first in message (yes/no/partial + explanation).
- suggestions = ONLY items the physician may want to ADD — never auto-applied.
- Every suggestion MUST include source_snippet that is a verbatim or near-verbatim quote from the transcript.
- If there is no clear quote in the transcript, do NOT suggest that item.
- NEVER suggest items because something "might" have been said or to fill gaps in messy audio.
- No duplicates of data already in extraction.
- Understand Egyptian Arabic.
- If nothing to add with transcript evidence, suggestions = [] but still answer the question in message."""


def _parse_review_json(text: str) -> dict[str, Any]:
    text = re.sub(r"```json", "", text)
    text = re.sub(r"```", "", text)
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("No JSON found")
    return json.loads(repair_json(text[start:end + 1]))


def _flatten_extracted_values(data: dict[str, Any]) -> set[str]:
    keys: set[str] = set()

    def add(val: Any) -> None:
        if isinstance(val, str) and val.strip():
            keys.add(_norm_key(val))
        elif isinstance(val, list):
            for x in val:
                add(x if isinstance(x, str) else (x.get("name") if isinstance(x, dict) else str(x)))
        elif isinstance(val, dict):
            for v in val.values():
                add(v)

    add(data.get("chief_complaint"))
    add(data.get("diagnoses"))
    add(data.get("symptoms"))
    add(data.get("prescription"))
    add(data.get("medications_current"))
    add(data.get("clinical_findings"))
    add(data.get("follow_up_items"))
    soap = data.get("soap_note") or {}
    add(soap.get("plan"))
    add(soap.get("assessment"))
    mh = data.get("medical_history") or {}
    add(mh.get("past_medical_history"))
    add(mh.get("allergies"))
    return keys


def _snippet_in_transcript(snippet: str, transcript: str) -> bool:
    """True when snippet text is clearly present in transcript (no inference)."""
    snippet = (snippet or "").strip()
    if not snippet or not transcript:
        return False
    if snippet.lower() in transcript.lower():
        return True
    words = [w for w in re.split(r"\s+", snippet.lower()) if len(w) > 2]
    blob = transcript.lower()
    return len(words) >= 2 and all(w in blob for w in words[: min(4, len(words))])


def _filter_suggestions_with_evidence(
    suggestions: list[dict[str, Any]], transcript: str
) -> list[dict[str, Any]]:
    """Drop suggestions that cannot be tied to text in the transcript."""
    out: list[dict[str, Any]] = []
    for s in suggestions:
        snippet = (s.get("source_snippet") or s.get("suggested_value") or "").strip()
        if _snippet_in_transcript(snippet, transcript):
            out.append(s)
    return out


def _already_present(value: str, existing: set[str]) -> bool:
    key = _norm_key(value)
    if not key or key in existing:
        return True
    for ex in existing:
        if key in ex or ex in key:
            return True
    return False


def _normalize_suggestions(raw: list[Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        val = (item.get("suggested_value") or item.get("value") or "").strip()
        if not val:
            continue
        try:
            conf = float(item.get("confidence", 0.75))
        except (TypeError, ValueError):
            conf = 0.75
        out.append({
            "category": (item.get("category") or "other").strip(),
            "field": (item.get("field") or item.get("category") or "other").strip(),
            "suggested_value": val,
            "confidence": round(max(0.0, min(1.0, conf)), 2),
            "explanation": (item.get("explanation") or "").strip(),
            "source_snippet": (item.get("source_snippet") or item.get("snippet") or "").strip(),
        })
    out.sort(key=lambda x: x["confidence"], reverse=True)
    return out[:15]


def _prompt_lang(prompt: str) -> str:
    return detect_input_language(prompt) if prompt.strip() else "en"


def _medication_names_from_data(data: dict[str, Any]) -> set[str]:
    names: set[str] = set()
    for key in ("prescription", "medications_current", "medications_discontinued"):
        for item in data.get(key) or []:
            if isinstance(item, dict):
                n = (item.get("name") or "").strip()
            else:
                n = str(item).strip()
            if n:
                names.add(_norm_key(n))
    return names


def _compare_medications(transcript: str, extracted: dict[str, Any]) -> tuple[list[str], list[str], list[str]]:
    """Return (extracted labels, transcript labels, missing from extraction)."""
    enriched = enrich_from_transcript(dict(extracted), transcript)
    extracted_keys = _medication_names_from_data(extracted)
    transcript_keys = _medication_names_from_data(enriched)

    def labels(keys: set[str], source: dict[str, Any]) -> list[str]:
        out: list[str] = []
        for key in ("prescription", "medications_current"):
            for item in source.get(key) or []:
                if isinstance(item, dict):
                    name = (item.get("name") or "").strip()
                else:
                    name = str(item).strip()
                if name and _norm_key(name) in keys:
                    out.append(name)
        return _dedupe_strings(out)

    extracted_labels = labels(extracted_keys, extracted)
    transcript_labels = labels(transcript_keys, enriched)
    missing_keys = transcript_keys - extracted_keys
    missing_labels = labels(missing_keys, enriched)
    return extracted_labels, transcript_labels, missing_labels


def _heuristic_prompt_review(
    transcript: str,
    extracted: dict[str, Any],
    doctor_prompt: str,
) -> dict[str, Any]:
    """Answer common physician questions without LLM."""
    pl = _norm_key(doctor_prompt)
    lang = _prompt_lang(doctor_prompt)
    is_ar = lang in ("ar", "mixed")

    rx = extracted.get("prescription") or []
    current = extracted.get("medications_current") or []
    soap = extracted.get("soap_note") or {}
    plan = _as_str_list(soap.get("plan"))
    diagnoses = _as_str_list(extracted.get("diagnoses"))
    suggestions: list[dict[str, Any]] = []
    answer = "partial"
    message = ""

    enriched = enrich_from_transcript(dict(extracted), transcript)
    enriched_rx = enriched.get("prescription") or []
    enriched_plan = _as_str_list((enriched.get("soap_note") or {}).get("plan"))
    enriched_dx = _as_str_list(enriched.get("diagnoses"))

    asks_rx = any(k in pl for k in ("prescription", "prescrib", "medication", "medicine", "drug", "وصف", "دواء", "ادوية", "أدوية", "روشت"))
    asks_plan = any(k in pl for k in ("plan", "treatment", "management", "خطة", "علاج", "إدارة"))
    asks_dx = any(k in pl for k in ("diagnosis", "diagnos", "assessment", "تشخيص", "تقييم"))
    asks_missing = any(k in pl for k in ("missing", "forgot", "check", "analyze", "review", "ناقص", "نسيت", "راجع", "تحليل", "فحص", "مفقود"))
    asks_forgot_med = any(k in pl for k in ("forgot", "another med", "other med", "more med", "دوا تاني", "دواء آخر", "دواء تاني", "نسيت", "medicine you forgot"))

    extracted_meds, transcript_meds, missing_meds = _compare_medications(transcript, extracted)

    if asks_forgot_med or (asks_rx and any(k in pl for k in ("forgot", "another", "more", "نسيت", "تاني", "آخر"))):
        if missing_meds:
            missing_text = ", ".join(missing_meds[:8])
            extracted_text = ", ".join(extracted_meds[:8]) if extracted_meds else ("—" if not is_ar else "—")
            message = (
                f"نعم — في المحادثة أدوية غير موجودة في الاستخراج: {missing_text}.\n"
                f"المستخرج حالياً: {extracted_text}."
                if is_ar else
                f"Yes — these medications appear in the transcript but NOT in the extraction: {missing_text}.\n"
                f"Currently extracted: {extracted_text or 'none'}."
            )
            answer = "yes"
            for name in missing_meds:
                if not _snippet_in_transcript(name, transcript):
                    continue
                suggestions.append({
                    "category": "prescription",
                    "field": "prescription",
                    "suggested_value": name,
                    "confidence": 0.88,
                    "explanation": "Medication in transcript but missing from extracted prescription/current meds.",
                    "source_snippet": name,
                })
        elif extracted_meds:
            message = (
                f"لا — كل الأدوية المذكورة في المحادثة موجودة في الاستخراج: {', '.join(extracted_meds[:10])}."
                if is_ar else
                f"No — all medications mentioned in the transcript are already in the extraction: {', '.join(extracted_meds[:10])}."
            )
            answer = "no"
        else:
            message = "لا — لا توجد أدوية في الاستخراج أو المحادثة." if is_ar else "No — no medications found in extraction or transcript."
            answer = "no"

    elif asks_rx:
        has_rx = len(rx) > 0
        transcript_has_rx = len(enriched_rx) > len(rx)
        if has_rx:
            names = ", ".join((m.get("name") or "") for m in rx if isinstance(m, dict))[:120]
            message = (
                f"نعم، يوجد {len(rx)} دواء/وصفة في الاستخراج: {names}."
                if is_ar else
                f"Yes — {len(rx)} prescription item(s) found: {names}."
            )
            answer = "yes"
        elif transcript_has_rx:
            message = (
                "لا — لا توجد وصفة جديدة في الاستخراج، لكن المحادثة قد تذكر أدوية. اقترح إضافتها أدناه."
                if is_ar else
                "No — no new prescription in the extraction, but the transcript may mention medications below."
            )
            answer = "no"
            for m in enriched_rx:
                name = m.get("name", "") if isinstance(m, dict) else str(m)
                if (
                    name
                    and _snippet_in_transcript(name, transcript)
                    and not _already_present(name, _flatten_extracted_values(extracted))
                ):
                    suggestions.append({
                        "category": "prescription",
                        "field": "prescription",
                        "suggested_value": name,
                        "confidence": 0.82,
                        "explanation": "Medication name appears in transcript but not in prescription list.",
                        "source_snippet": name,
                    })
        else:
            message = "لا — لا توجد وصفة في الاستخراج ولا يبدو أن المحادثة تصف أدوية جديدة." if is_ar else "No — no prescription found in extraction or transcript."
            answer = "no"

    elif asks_plan:
        has_plan = len(plan) > 0
        if has_plan:
            message = f"نعم — الخطة تحتوي {len(plan)} بند(اً)." if is_ar else f"Yes — plan has {len(plan)} item(s)."
            answer = "yes"
        elif enriched_plan:
            message = "لا — الخطة فارغة." if is_ar else "No — plan section is empty."
            answer = "no"
            for p in enriched_plan:
                if _snippet_in_transcript(p, transcript) and not _already_present(p, _flatten_extracted_values(extracted)):
                    suggestions.append({
                        "category": "plan",
                        "field": "soap_note.plan",
                        "suggested_value": p,
                        "confidence": 0.8,
                        "explanation": "Plan item quoted in transcript.",
                        "source_snippet": p,
                    })
        else:
            message = "لا — لا توجد خطة في الاستخراج." if is_ar else "No — plan section is empty."
            answer = "no"

    elif asks_dx:
        has_dx = len(diagnoses) > 0
        if has_dx:
            message = f"نعم — {len(diagnoses)} تشخيص(ات): {', '.join(diagnoses[:3])}." if is_ar else f"Yes — {len(diagnoses)} diagnosis(es) documented."
            answer = "yes"
        else:
            message = "لا — لا توجد تشخيصات في الاستخراج." if is_ar else "No diagnoses in extraction."
            answer = "no"

    elif asks_missing:
        message = (
            "لا أضيف عناصر تلقائياً — راجع الاستخراج مقابل المحادثة يدوياً."
            if is_ar else
            "Missing items are not auto-suggested — compare extraction to the transcript manually."
        )
        answer = "partial"
    else:
        message = (
            "أجب على سؤالك بناءً على الاستخراج. اسأل مثلاً: هل يوجد وصفة؟ هل الخطة كاملة؟ ما الناقص؟"
            if is_ar else
            "Ask about prescription, plan, diagnosis, or missing items — e.g. 'Is there a prescription?'"
        )
        answer = "partial"

    existing = _flatten_extracted_values(extracted)
    filtered = [s for s in suggestions if not _already_present(s["suggested_value"], existing)]
    filtered = _filter_suggestions_with_evidence(filtered, transcript)

    return {
        "answer": answer,
        "message": message,
        "suggestions": filtered[:15],
        "language_detected": _output_lang(extracted),
        "review_count": len(filtered),
    }


def run_extraction_review(
    transcript: str,
    extracted: dict[str, Any],
    doctor_prompt: str = "",
    call_model: Callable[[str, str], str | None] | None = None,
) -> dict[str, Any]:
    """Answer physician prompt about extraction; return suggestions only (never auto-apply)."""
    normalized = normalize_extraction(extracted, source_text=transcript)
    prompt = (doctor_prompt or "").strip()

    if not prompt:
        return {
            "answer": "no",
            "message": "Please enter a question about the extraction.",
            "suggestions": [],
            "language_detected": _output_lang(normalized),
            "review_count": 0,
        }

    if call_model:
        user_msg = (
            f"PHYSICIAN QUESTION:\n{prompt}\n\n"
            f"TRANSCRIPT LANGUAGE: {detect_input_language(transcript)}\n\n"
            f"--- ORIGINAL TRANSCRIPT ---\n{transcript}\n\n"
            f"--- EXTRACTED JSON ---\n{json.dumps(normalized, ensure_ascii=False, indent=2)}"
        )
        raw = call_model(PROMPT_REVIEW_SYSTEM, user_msg)
        if raw:
            try:
                parsed = _parse_review_json(raw)
                suggestions = _normalize_suggestions(parsed.get("suggestions") or [])
                existing = _flatten_extracted_values(normalized)
                filtered = [s for s in suggestions if not _already_present(s["suggested_value"], existing)]
                filtered = _filter_suggestions_with_evidence(filtered, transcript)
                return {
                    "answer": parsed.get("answer") or "partial",
                    "message": (parsed.get("message") or "").strip(),
                    "suggestions": filtered,
                    "language_detected": _output_lang(normalized),
                    "review_count": len(filtered),
                }
            except Exception:
                pass

    return _heuristic_prompt_review(transcript, normalized, prompt)
