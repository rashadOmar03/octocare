"""
Semantic intent router for the clinic AI agent.

Uses a short LLM call to understand Arabic/English (any dialect) and pick
which DB tools to run. Keyword matching in agent_intent.py remains as fallback
when the model is offline.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Callable

logger = logging.getLogger(__name__)

# Intents each role may use (security boundary for the router)
ROLE_ALLOWED: dict[str, set[str]] = {
    "patient": {
        "clinic_info",
        "doctor_search",
        "doctor_availability",
        "symptom_advice",
        "my_appointments",
    },
    "receptionist": {
        "clinic_info",
        "doctor_search",
        "doctor_availability",
        "live_queue",
        "patient_lookup",
        "today_stats",
        "revenue",
        "cancellations",
        "doctor_workload",
    },
    "doctor": {
        "clinic_info",
        "my_schedule",
        "my_reviews",
        "today_stats",
    },
    "admin": {
        "clinic_info",
        "doctor_search",
        "doctor_availability",
        "live_queue",
        "patient_lookup",
        "today_stats",
        "revenue",
        "cancellations",
        "doctor_workload",
        "my_schedule",
        "my_reviews",
        "doctor_compare",
        "staff_list",
        "audit",
        "admin_overview",
    },
}

INTENT_GUIDE: dict[str, str] = {
    "clinic_info": "Clinic hours, address, phone, fees, duration, general booking steps",
    "doctor_search": "Find/recommend doctors, specialties, ratings, reviews",
    "doctor_availability": "When a doctor is free, open slots, book on a date",
    "symptom_advice": "Health symptoms, pain, feeling unwell (not their appointment list)",
    "my_appointments": "The logged-in user's OWN bookings: when their visit is, forgot their time, list their reservations",
    "live_queue": "Who is with the doctor now, waiting room, current patient in consultation",
    "patient_lookup": "Search/find a specific patient by name (staff only)",
    "today_stats": "Today's counts, queue size, operational status now",
    "revenue": "Money earned, payments, income",
    "cancellations": "Cancelled appointments, no-shows, refunds, lost revenue",
    "doctor_workload": "How busy each doctor is today",
    "my_schedule": "Logged-in doctor's patients/appointments today",
    "my_reviews": "Logged-in doctor's ratings and feedback",
    "doctor_compare": "Compare doctors by workload or performance",
    "staff_list": "List staff, doctors, receptionists",
    "audit": "Audit log, who changed what in the system",
    "admin_overview": "Dashboard totals: patient count, doctor count, overall summary",
}

_ROUTER_SYSTEM = """You are the routing brain for a clinic AI assistant.
The user writes in Arabic (formal or Egyptian dialect) or English — understand meaning, not exact words.

Return ONLY valid JSON: {{"intents": ["intent1", "intent2"]}}

Rules:
- Pick every intent needed to fully answer the message (multiple allowed).
- my_appointments = the user's personal bookings only (patient role).
- clinic_info = general clinic contact/hours/fees OR how to book in general.
- If they ask about THEIR appointment AND how booking works, include both.
- symptom_advice = medical symptoms; do not use it for appointment scheduling questions.
- patient_lookup = only when searching for another person by name (staff roles).
- Never invent intent names. Use only from the allowed list below.
- For vague greetings with no real question, return ["clinic_info"].

Allowed intents for role "{role}":
{allowed_block}
"""


def _build_router_prompt(role: str) -> str:
    allowed = ROLE_ALLOWED.get(role, ROLE_ALLOWED["patient"])
    lines = []
    for name in sorted(allowed):
        desc = INTENT_GUIDE.get(name, name)
        lines.append(f"- {name}: {desc}")
    return _ROUTER_SYSTEM.format(role=role, allowed_block="\n".join(lines))


def _parse_router_json(text: str) -> list[str] | None:
    if not text or not text.strip():
        return None
    cleaned = re.sub(r"```json\s*", "", text)
    cleaned = re.sub(r"```", "", cleaned).strip()
    try:
        data = json.loads(cleaned)
    except json.JSONDecodeError:
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start == -1 or end == -1:
            return None
        try:
            data = json.loads(cleaned[start : end + 1])
        except json.JSONDecodeError:
            return None
    raw = data.get("intents") if isinstance(data, dict) else None
    if not isinstance(raw, list):
        return None
    return [str(x).strip() for x in raw if x]


def _filter_intents(intents: list[str], role: str) -> list[str]:
    allowed = ROLE_ALLOWED.get(role, ROLE_ALLOWED["patient"])
    seen: set[str] = set()
    out: list[str] = []
    for intent in intents:
        key = intent.lower().strip().replace("-", "_").replace(" ", "_")
        if key in allowed and key not in seen:
            seen.add(key)
            out.append(key)
    return out


def _resolve_conflicts(intents: list[str], role: str) -> list[str]:
    """Same priority rules as keyword router."""
    result = list(intents)
    if role == "patient" and "my_appointments" in result and "doctor_availability" in result:
        result.remove("doctor_availability")
    if role == "doctor":
        for drop in ("doctor_availability", "doctor_search", "symptom_advice"):
            if drop in result:
                result.remove(drop)
        if "my_schedule" in result:
            for drop in ("clinic_info",):
                if drop in result:
                    result.remove(drop)
    return result


def classify_intents_semantic(
    message: str,
    role: str,
    call_llm: Callable[[str, str], str | None],
) -> list[str] | None:
    """
    Ask the LLM which tools to run. Returns None if the model is unavailable
    or returns invalid JSON.
    """
    if role not in ROLE_ALLOWED:
        role = "patient"
    system = _build_router_prompt(role)
    user = f"User message:\n{message.strip()}"
    try:
        raw = call_llm(system, user)
    except Exception as exc:
        logger.warning("Semantic intent router LLM call failed: %s", exc)
        return None
    parsed = _parse_router_json(raw or "")
    if not parsed:
        logger.warning("Semantic intent router returned unparseable response: %r", (raw or "")[:200])
        return None
    filtered = _filter_intents(parsed, role)
    if not filtered:
        return None
    return _resolve_conflicts(filtered, role)


def merge_intent_results(
    semantic: list[str] | None,
    keyword: list[str],
    role: str,
) -> list[str]:
    """
    Prefer semantic routing; merge with keyword fallback intents so we never
    miss critical tools when the LLM under-selects.
    """
    combined: list[str] = []
    for source in (semantic or [], keyword):
        for intent in source:
            if intent not in combined:
                combined.append(intent)
    if not combined:
        combined = ["clinic_info"]
    allowed = ROLE_ALLOWED.get(role, ROLE_ALLOWED["patient"])
    combined = [i for i in combined if i in allowed]
    if not combined:
        combined = ["clinic_info"]
    return _resolve_conflicts(combined, role)


def baseline_intents_for_role(role: str) -> list[str]:
    """Always-loaded context so the agent knows role-specific facts without perfect routing."""
    if role == "patient":
        return ["my_appointments", "clinic_info"]
    if role == "doctor":
        return ["my_schedule"]
    if role == "receptionist":
        return ["today_stats"]
    if role == "admin":
        return ["admin_overview"]
    return []
