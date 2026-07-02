"""
Tests for agent_router.py — semantic intent parsing and merging.
"""

from __future__ import annotations

import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from agent_router import (
    baseline_intents_for_role,
    classify_intents_semantic,
    merge_intent_results,
    _parse_router_json,
)


class TestParseRouterJson:
    def test_plain_json(self):
        assert _parse_router_json('{"intents": ["my_appointments", "clinic_info"]}') == [
            "my_appointments",
            "clinic_info",
        ]

    def test_markdown_wrapped(self):
        raw = '```json\n{"intents": ["doctor_search"]}\n```'
        assert _parse_router_json(raw) == ["doctor_search"]

    def test_invalid_returns_none(self):
        assert _parse_router_json("not json") is None


class TestMergeIntentResults:
    def test_semantic_preferred_and_merged(self):
        merged = merge_intent_results(
            ["my_appointments"],
            ["clinic_info", "doctor_search"],
            "patient",
        )
        assert "my_appointments" in merged
        assert "clinic_info" in merged

    def test_keyword_only_when_semantic_missing(self):
        merged = merge_intent_results(None, ["revenue"], "receptionist")
        assert merged == ["revenue"]

    def test_patient_my_apts_drops_availability_conflict(self):
        merged = merge_intent_results(
            ["my_appointments", "doctor_availability"],
            [],
            "patient",
        )
        assert "my_appointments" in merged
        assert "doctor_availability" not in merged


class TestBaselineIntents:
    def test_patient_always_gets_appointments_context(self):
        baseline = baseline_intents_for_role("patient")
        assert "my_appointments" in baseline
        assert "clinic_info" in baseline


class TestSemanticClassifier:
    def test_forgot_appointment_arabic(self):
        def fake_llm(system: str, user: str) -> str:
            assert "patient" in system
            return '{"intents": ["my_appointments", "clinic_info"]}'

        result = classify_intents_semantic(
            "نسيت المعاد اللي حجزته وعايز اعرف ازاي احجز تاني",
            "patient",
            fake_llm,
        )
        assert result == ["my_appointments", "clinic_info"]

    def test_rejects_intents_not_allowed_for_role(self):
        def fake_llm(_system: str, _user: str) -> str:
            return '{"intents": ["revenue", "clinic_info"]}'

        result = classify_intents_semantic("How much money?", "patient", fake_llm)
        assert result == ["clinic_info"]
        assert "revenue" not in (result or [])

    def test_returns_none_on_bad_llm_output(self):
        assert classify_intents_semantic("hello", "patient", lambda _s, _u: "sorry") is None
