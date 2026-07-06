"""Regression tests for medical extraction pipeline (negation, meds, diagnoses, vitals)."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from extraction_pipeline import reconcile_medications, run_extraction_pipeline
from medical_extraction import normalize_extraction


def _symptom_names(data: dict) -> list[str]:
    return [s.get("name", "") for s in data.get("symptoms") or [] if isinstance(s, dict)]


def _dx_names(data: dict) -> list[str]:
    return list(data.get("diagnoses") or [])


class TestNegation:
    def test_denies_fever_removed(self):
        raw = {"symptoms": [{"name": "Fever"}], "diagnoses": [], "soap_note": {}}
        source = "Patient denies fever. No cough or vomiting."
        data = normalize_extraction(raw, source_text=source)
        assert not any("fever" in n.lower() for n in _symptom_names(data))

    def test_arabic_negation_removed(self):
        raw = {"symptoms": [{"name": "سعال"}], "diagnoses": [], "soap_note": {}}
        source = "المريض لا يشتكي من سعال ولا حمى."
        data = normalize_extraction(raw, source_text=source)
        assert not any("سعال" in n for n in _symptom_names(data))


class TestFamilyHistory:
    def test_father_diabetes_not_patient_dx(self):
        raw = {"symptoms": [], "diagnoses": ["Diabetes mellitus"], "soap_note": {}}
        source = "Family history: father has type 2 diabetes mellitus."
        data = normalize_extraction(raw, source_text=source)
        fh = (data.get("medical_history") or {}).get("family_history") or []
        assert any("diabetes" in str(x).lower() or "father" in str(x).lower() for x in fh)
        assert not any("diabetes" in d.lower() for d in _dx_names(data))

    def test_mother_hypertension_not_symptom(self):
        raw = {"symptoms": [{"name": "Hypertension"}], "diagnoses": [], "soap_note": {}}
        source = "Mother has hypertension on amlodipine."
        data = normalize_extraction(raw, source_text=source)
        assert not any("hypertension" in n.lower() for n in _symptom_names(data))


class TestMedications:
    def test_start_action_in_prescription(self):
        raw = {
            "prescription": [{"name": "Amoxicillin", "action": "START", "dosage": "500mg"}],
            "medications_current": [],
            "soap_note": {},
        }
        source = "Plan: start amoxicillin 500mg TID for 7 days."
        data = normalize_extraction(raw, source_text=source)
        rx = [m.get("name", "") for m in data.get("prescription") or []]
        assert any("amoxicillin" in n.lower() for n in rx)

    def test_stop_wins_over_start(self):
        raw = {
            "prescription": [
                {"name": "Metformin", "action": "START"},
                {"name": "Metformin", "action": "STOP"},
            ],
            "medications_current": [],
            "soap_note": {},
        }
        source = "Start metformin 500mg twice daily. Decision: stop metformin due to GI upset."
        data = normalize_extraction(raw, source_text=source)
        disc = [d.lower() for d in data.get("medications_discontinued") or []]
        rx = [m.get("name", "").lower() for m in data.get("prescription") or []]
        assert any("metformin" in d for d in disc)
        assert not any("metformin" in r for r in rx)

    def test_unknown_not_default_continue_from_llm(self):
        raw = {
            "medications_current": [{"name": "Aspirin", "action": "Continue"}],
            "prescription": [],
            "soap_note": {},
        }
        source = "On aspirin 81mg daily."
        data = normalize_extraction(raw, source_text=source)
        cur = data.get("medications_current") or []
        assert cur
        assert all(m.get("action") in ("CONTINUE", "UNKNOWN") for m in cur)


class TestDiagnoses:
    def test_inferred_diagnosis_dropped_without_evidence(self):
        raw = {
            "symptoms": [{"name": "Chest pain"}],
            "diagnoses": ["Acute myocardial infarction"],
            "soap_note": {"assessment": []},
        }
        source = "Patient reports chest pain for 2 hours. ECG pending. No diagnosis confirmed."
        data = normalize_extraction(raw, source_text=source)
        assert not any("infarction" in d.lower() or "mi" == d.lower().strip() for d in _dx_names(data))

    def test_suspected_diagnosis_kept(self):
        raw = {
            "symptoms": [],
            "diagnoses": ["Possible acute coronary syndrome"],
            "soap_note": {"assessment": ["Possible acute coronary syndrome"]},
        }
        source = "Assessment: possible acute coronary syndrome, rule out NSTEMI."
        data = normalize_extraction(raw, source_text=source)
        assert any("coronary" in d.lower() or "acs" in d.lower() for d in _dx_names(data))


class TestVitals:
    def test_note_vitals_stripped(self):
        raw = {
            "vital_signs": {"bp": "140/90", "hr": 88},
            "soap_note": {"objective": {"vitals": ["BP 140/90", "HR 88"]}},
            "symptoms": [],
        }
        source = "Vitals: BP 140/90, HR 88. Patient stable."
        data = normalize_extraction(raw, source_text=source)
        assert data.get("vital_signs") == {}
        assert data.get("vitals_source") == "sensor"
        obj = (data.get("soap_note") or {}).get("objective") or {}
        assert not obj.get("vitals")


class TestObjectiveFiltering:
    def test_vague_ecg_order_removed(self):
        raw = {
            "soap_note": {"objective": {"ecg": ["ECG ordered"]}},
            "ecg": ["ECG"],
            "symptoms": [],
        }
        source = "Order ECG."
        data = normalize_extraction(raw, source_text=source)
        obj = (data.get("soap_note") or {}).get("objective") or {}
        ecg_items = obj.get("ecg") or []
        assert not any(x.lower().strip() in ("ecg", "ecg ordered") for x in ecg_items)


class TestValidation:
    def test_validation_report_present(self):
        raw = {"symptoms": [{"name": "Headache"}], "diagnoses": [], "soap_note": {}}
        source = "Patient with headache."
        data = normalize_extraction(raw, source_text=source)
        report = data.get("validation_report") or {}
        assert "valid" in report
        assert isinstance(report.get("warnings"), list)
        assert isinstance(report.get("errors"), list)

    def test_clinical_summary_generated(self):
        raw = {"symptoms": [{"name": "Headache"}], "diagnoses": [], "soap_note": {}}
        source = "Patient with headache for 3 days."
        data = normalize_extraction(raw, source_text=source)
        assert (data.get("clinical_summary") or "").strip()
        assert data.get("severity") in ("mild", "moderate", "severe", "critical", "undetermined")


class TestPipelineDirect:
    def test_reconcile_medications_latest_position(self):
        payload = {
            "medications_current": [],
            "prescription": [
                {"name": "Lisinopril", "action": "CONTINUE", "position": 10},
                {"name": "Lisinopril", "action": "STOP", "position": 100},
            ],
            "medications_discontinued": [],
        }
        out = reconcile_medications(payload, "Continue lisinopril. Stop lisinopril today.")
        assert any("lisinopril" in d.lower() for d in out.get("medications_discontinued") or [])

    def test_pipeline_returns_report(self):
        payload = {"symptoms": [], "diagnoses": [], "soap_note": {}}
        result, report = run_extraction_pipeline(payload, "")
        assert result.get("vitals_source") == "sensor"
        assert report.get("valid") is True
