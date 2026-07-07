"""Tests for removal-only extraction verify pass."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from extraction_verify import _apply_removals, run_verify_pass


def test_apply_removals_strips_unsupported_symptom():
    data = {
        "symptoms": [{"name": "Fever"}, {"name": "Cough"}],
        "diagnoses": [],
        "soap_note": {},
    }
    cleaned, removed = _apply_removals(
        data,
        [{"category": "symptoms", "value": "Fever", "reason": "not in source"}],
    )
    names = [s["name"] for s in cleaned["symptoms"]]
    assert "Fever" not in names
    assert "Cough" in names
    assert any("Fever" in r for r in removed)


def test_apply_removals_never_adds_fields():
    data = {"symptoms": [], "diagnoses": []}
    cleaned, removed = _apply_removals(data, [])
    assert cleaned["symptoms"] == []
    assert removed == []


def test_run_verify_pass_skips_without_source():
    data = {"symptoms": [{"name": "Headache"}]}
    out, report = run_verify_pass(data, "", lambda s, u: None)
    assert out == data
    assert report.get("applied") is False


def test_run_verify_pass_applies_removals():
    data = {
        "symptoms": [{"name": "Fever"}, {"name": "Headache"}],
        "diagnoses": ["Hypertension"],
        "soap_note": {},
    }
    source = "Patient reports headache only."

    def fake_model(system: str, user: str) -> str:
        return (
            '{"unsupported": ['
            '{"category": "symptoms", "value": "Fever", "reason": "not stated"},'
            '{"category": "diagnoses", "value": "Hypertension", "reason": "not stated"}'
            '], "summary": "Removed 2 unsupported items"}'
        )

    out, report = run_verify_pass(data, source, fake_model)
    assert report.get("applied") is True
    assert report.get("unsupported_count", 0) >= 1
    names = [s["name"] for s in out.get("symptoms") or []]
    assert "Fever" not in names
    assert "Headache" in names
