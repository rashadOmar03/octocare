"""Second-pass verification: remove extracted facts not supported by the source note.

Never adds or suggests missing items — removal only (anti-hallucination).
"""

from __future__ import annotations

import json
import re
from typing import Any, Callable

from json_repair import repair_json

from medical_extraction import _as_str_list, _norm_key

VERIFY_SYSTEM_PROMPT = """You are a strict clinical fact-checker comparing an EXTRACTED JSON record to the ORIGINAL SOURCE NOTE.

Return ONE valid JSON object ONLY:
{
  "unsupported": [
    {
      "category": "symptoms|diagnoses|medications_current|prescription|medications_discontinued|allergies|past_medical_history|family_history|plan|follow_up|physical_exam|laboratory_results|imaging|ecg|echo|clinical_findings|doctor_notes|chief_complaint",
      "value": "exact item text from extraction to remove",
      "reason": "brief reason — must say it is not stated in source"
    }
  ],
  "summary": "one sentence: how many items were unsupported"
}

RULES:
- ONLY flag items already present in EXTRACTED JSON that are NOT clearly supported by SOURCE NOTE.
- NEVER suggest additions, missing items, or corrections to add data.
- NEVER infer, guess, or fill gaps from messy/unclear audio or text.
- If the source is ambiguous or the item might not have been said, mark it unsupported (prefer omission).
- Negated symptoms in source must not appear in extraction — mark unsupported if they do.
- Family history must not appear as patient symptoms/diagnoses.
- Works for Arabic, English, and mixed notes.
- If everything is supported, return "unsupported": [].
"""

_CATEGORY_PATHS: dict[str, Callable[[dict[str, Any]], list[Any]]] = {}


def _get_symptoms(data: dict) -> list[Any]:
    return list(data.get("symptoms") or [])


def _get_diagnoses(data: dict) -> list[Any]:
    return list(data.get("diagnoses") or [])


def _get_meds_current(data: dict) -> list[Any]:
    return list(data.get("medications_current") or [])


def _get_prescription(data: dict) -> list[Any]:
    return list(data.get("prescription") or [])


def _get_meds_disc(data: dict) -> list[Any]:
    return list(data.get("medications_discontinued") or [])


def _get_mh_list(data: dict, key: str) -> list[Any]:
    mh = data.get("medical_history") or {}
    if isinstance(mh, dict):
        return list(mh.get(key) or [])
    return []


def _get_soap_list(data: dict, section: str) -> list[Any]:
    soap = data.get("soap_note") or {}
    if section == "plan":
        return _as_str_list(soap.get("plan"))
    obj = soap.get("objective") if isinstance(soap.get("objective"), dict) else {}
    return _as_str_list(obj.get(section))


def _parse_verify_response(text: str) -> dict[str, Any]:
    cleaned = re.sub(r"```json|```", "", text)
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("No JSON in verify response")
    return json.loads(repair_json(cleaned[start : end + 1]))


def _item_text(item: Any) -> str:
    if isinstance(item, dict):
        return str(item.get("name") or item.get("text") or item.get("suggested_value") or "").strip()
    return str(item).strip()


def _remove_by_norm(items: list[Any], remove_keys: set[str]) -> list[Any]:
    out: list[Any] = []
    for item in items:
        text = _item_text(item)
        if not text:
            continue
        if _norm_key(text) in remove_keys:
            continue
        if any(rk and (rk in _norm_key(text) or _norm_key(text) in rk) for rk in remove_keys if len(rk) > 4):
            continue
        out.append(item)
    return out


def _apply_removals(data: dict[str, Any], unsupported: list[dict[str, Any]]) -> tuple[dict[str, Any], list[str]]:
    """Apply removal list to structured extraction. Returns (data, removed_labels)."""
    by_category: dict[str, set[str]] = {}
    removed_labels: list[str] = []
    for entry in unsupported:
        if not isinstance(entry, dict):
            continue
        cat = str(entry.get("category") or "").strip().lower()
        val = str(entry.get("value") or "").strip()
        if not cat or not val:
            continue
        by_category.setdefault(cat, set()).add(_norm_key(val))
        removed_labels.append(f"{cat}: {val}")

    payload = dict(data)

    if "symptoms" in by_category:
        payload["symptoms"] = _remove_by_norm(payload.get("symptoms") or [], by_category["symptoms"])

    if "diagnoses" in by_category:
        keys = by_category["diagnoses"]
        payload["diagnoses"] = [d for d in (payload.get("diagnoses") or []) if _norm_key(str(d)) not in keys]
        if payload.get("diagnoses_structured"):
            payload["diagnoses_structured"] = _remove_by_norm(payload["diagnoses_structured"], keys)

    if "medications_current" in by_category:
        payload["medications_current"] = _remove_by_norm(payload.get("medications_current") or [], by_category["medications_current"])

    if "prescription" in by_category:
        payload["prescription"] = _remove_by_norm(payload.get("prescription") or [], by_category["prescription"])

    if "medications_discontinued" in by_category:
        payload["medications_discontinued"] = _remove_by_norm(payload.get("medications_discontinued") or [], by_category["medications_discontinued"])

    mh = dict(payload.get("medical_history") or {}) if isinstance(payload.get("medical_history"), dict) else {}
    for mh_key, cat in [
        ("allergies", "allergies"),
        ("past_medical_history", "past_medical_history"),
        ("family_history", "family_history"),
    ]:
        if cat in by_category:
            mh[mh_key] = _remove_by_norm(mh.get(mh_key) or [], by_category[cat])
    payload["medical_history"] = mh

    if "chief_complaint" in by_category:
        cc = str(payload.get("chief_complaint") or "")
        keys = by_category["chief_complaint"]
        if _norm_key(cc) in keys:
            payload["chief_complaint"] = None

    soap = dict(payload.get("soap_note") or {}) if isinstance(payload.get("soap_note"), dict) else {}
    if "plan" in by_category:
        soap["plan"] = _remove_by_norm(_as_str_list(soap.get("plan")), by_category["plan"])

    obj = dict(soap.get("objective") or {}) if isinstance(soap.get("objective"), dict) else {}
    for obj_key, cat in [
        ("physical_exam", "physical_exam"),
        ("laboratory_results", "laboratory_results"),
        ("imaging", "imaging"),
        ("ecg", "ecg"),
        ("echo", "echo"),
    ]:
        if cat in by_category:
            obj[obj_key] = _remove_by_norm(_as_str_list(obj.get(obj_key)), by_category[cat])
    soap["objective"] = obj
    payload["soap_note"] = soap

    for top_key, cat in [
        ("clinical_findings", "clinical_findings"),
        ("follow_up_items", "follow_up"),
        ("doctor_notes", "doctor_notes"),
    ]:
        if cat in by_category:
            payload[top_key if top_key != "follow_up_items" else "follow_up_items"] = _remove_by_norm(
                _as_str_list(payload.get(top_key if cat != "follow_up" else "follow_up_items")),
                by_category[cat],
            )

    return payload, removed_labels


def run_verify_pass(
    data: dict[str, Any],
    source_text: str,
    call_model: Callable[[str, str], str | None],
) -> tuple[dict[str, Any], dict[str, Any]]:
    """LLM verify pass — strip unsupported items only. Never adds data."""
    if not (source_text or "").strip():
        return data, {"applied": False, "reason": "no_source", "removed": [], "unsupported_count": 0}

    user_msg = (
        f"--- SOURCE NOTE ---\n{source_text.strip()}\n\n"
        f"--- EXTRACTED JSON ---\n{json.dumps(data, ensure_ascii=False, indent=2)}"
    )
    raw = call_model(VERIFY_SYSTEM_PROMPT, user_msg)
    report: dict[str, Any] = {
        "applied": False,
        "removed": [],
        "unsupported_count": 0,
        "summary": "",
    }
    if not raw:
        report["reason"] = "model_unavailable"
        return data, report

    try:
        parsed = _parse_verify_response(raw)
    except Exception as exc:
        report["reason"] = f"parse_error: {exc}"
        return data, report

    unsupported = parsed.get("unsupported") or []
    if not isinstance(unsupported, list):
        unsupported = []

    cleaned, removed = _apply_removals(data, unsupported)
    report["applied"] = True
    report["removed"] = removed
    report["unsupported_count"] = len(removed)
    report["summary"] = str(parsed.get("summary") or "").strip()
    return cleaned, report
