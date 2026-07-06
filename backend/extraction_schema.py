"""Canonical enums and helpers for medical extraction entities."""

from __future__ import annotations

from enum import Enum
from typing import Any


class MedAction(str, Enum):
    START = "START"
    CONTINUE = "CONTINUE"
    HOLD = "HOLD"
    STOP = "STOP"
    ONE_TIME = "ONE_TIME"
    CONDITIONAL = "CONDITIONAL"
    UNKNOWN = "UNKNOWN"


class Temporality(str, Enum):
    CURRENT = "CURRENT"
    RECENT = "RECENT"
    HISTORICAL = "HISTORICAL"
    FAMILY_HISTORY = "FAMILY_HISTORY"
    PLANNED = "PLANNED"


class Experiencer(str, Enum):
    PATIENT = "PATIENT"
    FATHER = "FATHER"
    MOTHER = "MOTHER"
    SIBLING = "SIBLING"
    OTHER = "OTHER"


class DiagnosisCertainty(str, Enum):
    CONFIRMED = "CONFIRMED"
    SUSPECTED = "SUSPECTED"
    RULE_OUT = "RULE_OUT"
    UNKNOWN = "UNKNOWN"


class SeverityLevel(str, Enum):
    MILD = "mild"
    MODERATE = "moderate"
    SEVERE = "severe"
    CRITICAL = "critical"
    UNDETERMINED = "undetermined"


# Map legacy / LLM action strings → canonical MedAction
LEGACY_ACTION_MAP: dict[str, MedAction] = {
    "start": MedAction.START,
    "started": MedAction.START,
    "new": MedAction.START,
    "prescribe": MedAction.START,
    "prescribed": MedAction.START,
    "begin": MedAction.START,
    "add": MedAction.START,
    "ابدأ": MedAction.START,
    "بدء": MedAction.START,
    "وصف": MedAction.START,
    "continue": MedAction.CONTINUE,
    "continued": MedAction.CONTINUE,
    "ongoing": MedAction.CONTINUE,
    "maintenance": MedAction.CONTINUE,
    "استمر": MedAction.CONTINUE,
    "مستمر": MedAction.CONTINUE,
    "hold": MedAction.HOLD,
    "held": MedAction.HOLD,
    "suspend": MedAction.HOLD,
    "suspended": MedAction.HOLD,
    "ايقاف مؤقت": MedAction.HOLD,
    "إيقاف مؤقت": MedAction.HOLD,
    "stop": MedAction.STOP,
    "stopped": MedAction.STOP,
    "discontinue": MedAction.STOP,
    "discontinued": MedAction.STOP,
    "cease": MedAction.STOP,
    "وقف": MedAction.STOP,
    "ايقاف": MedAction.STOP,
    "إيقاف": MedAction.STOP,
    "بلاش": MedAction.STOP,
    "one time": MedAction.ONE_TIME,
    "one-time": MedAction.ONE_TIME,
    "single dose": MedAction.ONE_TIME,
    "stat dose": MedAction.ONE_TIME,
    "مرة واحدة": MedAction.ONE_TIME,
    "conditional": MedAction.CONDITIONAL,
    "if needed": MedAction.CONDITIONAL,
    "prn": MedAction.CONDITIONAL,
    "عند الحاجة": MedAction.CONDITIONAL,
    "increase": MedAction.START,
    "decrease": MedAction.START,
    "administered": MedAction.ONE_TIME,
    "given": MedAction.ONE_TIME,
}


def canonical_med_action(raw: Any) -> MedAction:
    if raw is None:
        return MedAction.UNKNOWN
    text = str(raw).strip().lower()
    if not text:
        return MedAction.UNKNOWN
    if text.upper() in MedAction.__members__:
        return MedAction[text.upper()]
    for key, action in LEGACY_ACTION_MAP.items():
        if key in text:
            return action
    return MedAction.UNKNOWN


def entity_meta(
    *,
    text: str,
    source_evidence: str | None = None,
    confidence: float = 0.7,
    temporality: Temporality = Temporality.CURRENT,
    experiencer: Experiencer = Experiencer.PATIENT,
    negated: bool = False,
) -> dict[str, Any]:
    return {
        "text": text,
        "source_evidence": source_evidence,
        "confidence": confidence,
        "temporality": temporality.value,
        "experiencer": experiencer.value,
        "negated": negated,
    }
