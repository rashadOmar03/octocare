"""Multi-note extraction quality suite — Arabic, English, and mixed clinical notes."""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from typing import Any, Callable

from medical_extraction import build_api_response, mock_extraction_for_language
from extraction_review import run_extraction_review

# ─── Helpers ───────────────────────────────────────────────────────────────────


def _blob(d: dict[str, Any]) -> str:
    return json.dumps(d, ensure_ascii=False).lower()


def _pmh(d: dict[str, Any]) -> list[str]:
    mh = d.get("medical_history") or {}
    return list((mh.get("past_medical_history") or []) if isinstance(mh, dict) else [])


def _allergies(d: dict[str, Any]) -> list[str]:
    mh = d.get("medical_history") or {}
    return list((mh.get("allergies") or []) if isinstance(mh, dict) else [])


def _dx(d: dict[str, Any]) -> list[str]:
    return list(d.get("diagnoses") or [])


def _plan(d: dict[str, Any]) -> list[str]:
    soap = d.get("soap_note") or {}
    return list((soap.get("plan") or []) if isinstance(soap, dict) else [])


def _rx_names(d: dict[str, Any]) -> list[str]:
    return [str(m.get("name", m)) for m in (d.get("prescription") or []) if m]


def _cur_names(d: dict[str, Any]) -> list[str]:
    return [str(m.get("name", m)) for m in (d.get("medications_current") or []) if m]


def _symptoms(d: dict[str, Any]) -> list[str]:
    out: list[str] = []
    for s in d.get("symptoms") or []:
        if isinstance(s, dict):
            out.append(str(s.get("name") or ""))
        else:
            out.append(str(s))
    return out


def contains(*needles: str) -> Callable[[dict[str, Any]], bool]:
    def _fn(d: dict[str, Any]) -> bool:
        b = _blob(d)
        return all(n.lower() in b for n in needles)
    return _fn


def any_contains(*needles: str) -> Callable[[dict[str, Any]], bool]:
    def _fn(d: dict[str, Any]) -> bool:
        b = _blob(d)
        return any(n.lower() in b for n in needles)
    return _fn


def min_count(getter: Callable[[dict[str, Any]], list], n: int) -> Callable[[dict[str, Any]], bool]:
    return lambda d: len(getter(d)) >= n


def make_partial(lang: str, symptoms: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    """Simulate weak LLM output (symptoms only — common real-world failure)."""
    partial = mock_extraction_for_language(lang)
    partial["symptoms"] = symptoms or []
    partial["chief_complaint"] = ""
    partial["diagnoses"] = []
    partial["prescription"] = []
    partial["medications_current"] = []
    partial["medical_history"] = {
        "past_medical_history": [],
        "family_history": [],
        "social_history": [],
        "smoking": None,
        "alcohol": None,
        "allergies": [],
    }
    partial["soap_note"] = {
        "subjective": "",
        "objective": {
            "vitals": [],
            "physical_exam": [],
            "ecg": [],
            "laboratory_results": [],
            "imaging": [],
            "echo": [],
        },
        "assessment": [],
        "plan": [],
    }
    return partial


@dataclass
class NoteCase:
    name: str
    lang: str
    note: str
    checks: list[tuple[str, Callable[[dict[str, Any]], bool]]] = field(default_factory=list)
    partial_symptoms: list[dict[str, Any]] | None = None


# ─── Test notes (messy Arabic / English / mixed) ──────────────────────────────

CARDIOLOGY_MIXED = """
**عيادة الباطنة - ملاحظات الزيارة**  (messy copy-paste)
Patient: Ahmed Mahmoud / أحمد محمود
Age ~61y | Nasr City Cairo
Dr: إزيك يا أستاذ أحمد؟
Pt: from ~2 weeks SOB when climb stairs OR walk → نفسي بيقف
Pt: chest pain mid chest → L shoulder, lasts 10-15 min
Pt: woke choking at night (PND?)
Dr: needs 2-3 pillows (orthopnea)
Pt: leg swelling evening x ~12 days, dizziness on standing
PMH: ضغط from long time ~18 yrs on meds (amlodipine)
PMH: سكر ~12 yrs — metformin daily | NO known allergies
Exam: tired, bilateral pitting edema, basilar crackles
Plan: Admit for ACS rule-out vs decompensated HF
ECG, troponin, BNP, CXR, Echo LVEF
Start: aspirin 81mg, atorvastatin 40mg, furosemide 40mg daily
Continue home BP/DM meds | Cardiology consult | daily weights
Follow up cardiology clinic 1 week if discharged
"""

DIABETES_EN = """
Endocrine clinic — messy note
Pt Mary S, 54F, T2DM x 10 years (poor control)
HbA1c today 9.2% (was 8.1)
Complains polyuria, thirst x 2 months
Continue metformin 1000mg BID
Start insulin glargine 10 units qHS tonight
Diabetes education + home glucose log
Follow up 3 months / sooner if hypoglycemia
BP OK on lisinopril — continue
"""

PEDIATRIC_AR = """
عيادة أطفال — ملاحظات فوضوية!!
الطفل عمره 5 سنوات — الأم: عنده حرارة 39 من امبارح
كough جاف + runny nose | NO allergy
Exam: febrile, throat mildly red
Dx: viral vs bacterial — treat empirically
Amoxicillin 250mg tid x 7 days
Paracetamol 15mg/kg PRN fever
Follow up 48h if not better
"""

ORTHO_EN = """
Orthopedic walk-in (dictated, typos)
32M fell on knee playing football 3 weeks ago
Right knee pain + swelling, worse stairs
No locking but instability sensation
MRI knee ordered stat
Ibuprofen 400mg TID with food x 2 weeks
Rest, ice, elevation | PT referral if MRI negative
Follow up 2 weeks with MRI result
"""

ASTHMA_MIXED = """
Chest clinic — pt Fatma 42F
ربo منذ الطفولة — worsening wheeze last 5 days
Uses salbutamol inhaler PRN (3-4x/day now)
Night cough, SOB on exertion
Exam: expiratory wheeze bilaterally
Start budesonide inhaler 200mcg BID
Continue salbutamol PRN | peak flow diary
Follow up 4 weeks
"""

PSYCH_EN = """
Psychiatry intake — fragmented
28F presents with low mood x 6 months, insomnia, anhedonia
Denies SI/HI | no psych history
Major depression — moderate
Start sertraline 50mg daily in AM
Sleep hygiene counseling
Follow up 2 weeks for medication review
"""

HTN_AR = """
عيادة ضغط — زيارة متابعة
مريض 58 سنة — ضغط من زمان
BP اليوم 150/95 (في العيادة)
يأخذ amlodipine 5mg daily — sometimes forgets
No chest pain / no headache
Plan: continue amlodipine, home BP log
Follow up 4 weeks
"""

PNEUMONIA_EN = """
Urgent care note — copy paste error
45M productive cough + fever 5 days (Tmax 38.9)
Smoker 10 cigs/day | no known allergies
Lungs: crackles R base
Community acquired pneumonia likely
CXR ordered | start azithromycin 500mg day1 then 250mg x4 days
Follow up 1 week
"""

GASTRO_AR = """
 gastro enterology — ملاحظات
سيدة 47 سنة — ألم بطن upper x 3 weeks + nausea
No vomiting blood | PMH: nothing major
Plan endoscopy next week
Start omeprazole 20mg daily before breakfast
Avoid NSAIDs | follow up after scope
"""

ALLERGY_EN = """
Allergy documented!!
Penicillin allergy — rash/hives in 2015
Presenting with strep-like sore throat 3 days
Avoid amoxicillin — prescribe azithromycin instead
Azithromycin 500mg day 1
Follow up if worsening
"""

FRACTURE_AR = """
طوارئ — ملاحظات سريعة
شاب 22 سنة — كسر في radius after fall
X-ray done — cast applied today
Pain controlled with ibuprofen 400mg TID
Follow up ortho clinic 2 weeks for cast check
"""

STROKE_EN = """
ED note — STAT
67M sudden left arm weakness + slurred speech 1 hour ago
Hypertension on amlodipine
CT head stat — admit neurology
If no bleed: aspirin 325mg load (already discussed)
Follow up stroke clinic
"""

THYROID_AR = """
عيada الغدد — messy
سيدة 39 — خمول الغدة من 5 سنوات
TSH high on last labs | tired + weight gain
Continue levothyroxine 50mcg every morning fasting
Repeat TSH 6 weeks | follow up
"""

URI_EN = """
Fast visit — sore throat 3 days, low grade fever
No dyspnea | viral URI likely
Acetaminophen 500mg q6h PRN
Fluids, rest, honey tea
Follow up if fever >3 more days
"""

EGYPTIAN_RESP = """
دكتور.. انا تعبان من كحة بقالي 10 أيام
فيه بلغm خضr وحرارة على فترات
مش قادر أنام من الكحة
Chest: crepitations | CXR ordered
Azithromycin + paracetamol | follow up
"""

PREGNANCY_EN = """
OB clinic — 24 weeks pregnant
Routine prenatal visit | fundal height OK
Continue prenatal vitamins daily
Anatomy scan ultrasound scheduled
Follow up 4 weeks
"""

NEUROLOGY_AR = """
عيادة مخ وأعصاب
صداع متكرر 3 أشهر + dizziness
MRI brain ordered
Start ibuprofen PRN | avoid triggers
Follow up with MRI results
"""

# ─── Case definitions ───────────────────────────────────────────────────────────

CASES: list[NoteCase] = [
    NoteCase(
        "01_cardiology_mixed_ar_en",
        "ar",
        CARDIOLOGY_MIXED,
        [
            ("PMH hypertension", any_contains("ضغط", "hypertension")),
            ("PMH diabetes", any_contains("سكر", "diabetes")),
            ("Diagnoses >= 2", min_count(_dx, 2)),
            ("Plan >= 3", min_count(_plan, 3)),
            ("Rx aspirin/furosemide", any_contains("aspirin", "furosemide")),
            ("Current metformin/amlodipine", any_contains("metformin", "amlodipine")),
            ("Symptoms SOB/chest", any_contains("ضيق", "chest", "shortness")),
        ],
        partial_symptoms=[{"name": "ضيق نفس", "duration": None, "severity": None, "location": None}],
    ),
    NoteCase(
        "02_diabetes_english",
        "en",
        DIABETES_EN,
        [
            ("PMH diabetes", any_contains("diabetes", "t2dm")),
            ("Continue metformin", any_contains("metformin")),
            ("Start insulin", any_contains("insulin")),
            ("Plan follow-up/labs", any_contains("follow", "laboratory", "education")),
            ("Diagnosis diabetes", any_contains("diabetes")),
        ],
    ),
    NoteCase(
        "03_pediatric_fever_arabic",
        "ar",
        PEDIATRIC_AR,
        [
            ("Fever symptom", any_contains("حمى", "fever")),
            ("Cough symptom", any_contains("سعال", "cough")),
            ("Rx amoxicillin", any_contains("amoxicillin")),
            ("Rx paracetamol", any_contains("paracetamol")),
            ("Follow-up plan", min_count(_plan, 1)),
        ],
    ),
    NoteCase(
        "04_orthopedic_english",
        "en",
        ORTHO_EN,
        [
            ("Knee pain", any_contains("knee", "ركبة")),
            ("MRI plan", any_contains("mri")),
            ("Ibuprofen rx", any_contains("ibuprofen")),
            ("Follow-up", any_contains("follow")),
        ],
    ),
    NoteCase(
        "05_asthma_mixed",
        "ar",
        ASTHMA_MIXED,
        [
            ("Asthma PMH", any_contains("ربo", "asthma", "copd")),
            ("Wheeze symptom", any_contains("wheez", "صفير")),
            ("Salbutamol current", any_contains("salbutamol")),
            ("Budesonide start", any_contains("budesonide")),
        ],
    ),
    NoteCase(
        "06_psychiatry_english",
        "en",
        PSYCH_EN,
        [
            ("Depression dx", any_contains("depression", "اكتئاب")),
            ("Insomnia symptom", any_contains("insomnia", "أرق")),
            ("Sertraline rx", any_contains("sertraline")),
            ("Follow-up plan", min_count(_plan, 1)),
        ],
    ),
    NoteCase(
        "07_hypertension_arabic",
        "ar",
        HTN_AR,
        [
            ("HTN PMH", any_contains("ضغط", "hypertension")),
            ("Amlodipine current", any_contains("amlodipine")),
            ("Follow-up", any_contains("متابعة", "follow")),
        ],
    ),
    NoteCase(
        "08_pneumonia_english",
        "en",
        PNEUMONIA_EN,
        [
            ("Cough/fever symptoms", any_contains("cough", "fever", "سعال", "حمى")),
            ("Pneumonia dx", any_contains("pneumonia", "التهاب رئوي")),
            ("CXR plan", any_contains("x-ray", "chest")),
            ("Azithromycin", any_contains("azithromycin")),
        ],
    ),
    NoteCase(
        "09_gastro_arabic",
        "ar",
        GASTRO_AR,
        [
            ("Abdominal pain", any_contains("بطن", "abdominal")),
            ("Nausea", any_contains("غثيان", "nausea")),
            ("Endoscopy plan", any_contains("منظار", "endoscopy")),
            ("Omeprazole", any_contains("omeprazole")),
        ],
    ),
    NoteCase(
        "10_allergy_english",
        "en",
        ALLERGY_EN,
        [
            ("Penicillin allergy", any_contains("penicillin")),
            ("Sore throat", any_contains("throat", "حلق")),
            ("Azithromycin rx", any_contains("azithromycin")),
        ],
    ),
    NoteCase(
        "11_fracture_arabic",
        "ar",
        FRACTURE_AR,
        [
            ("Fracture PMH/dx", any_contains("كسر", "fracture")),
            ("X-ray plan", any_contains("x-ray", "أشعة")),
            ("Ibuprofen", any_contains("ibuprofen")),
            ("Cast plan", any_contains("cast", "جبيرة")),
        ],
    ),
    NoteCase(
        "12_stroke_english",
        "en",
        STROKE_EN,
        [
            ("Weakness symptom", any_contains("weakness", "ضعف")),
            ("CT head plan", any_contains("ct head", "ct")),
            ("Admission plan", any_contains("admit", "admission")),
            ("Aspirin", any_contains("aspirin")),
            ("Hypertension", any_contains("hypertension", "amlodipine")),
        ],
    ),
    NoteCase(
        "13_thyroid_arabic",
        "ar",
        THYROID_AR,
        [
            ("Hypothyroid PMH", any_contains("خمول", "hypothyroid")),
            ("Levothyroxine", any_contains("levothyroxine")),
            ("Follow-up/labs", min_count(_plan, 1)),
        ],
    ),
    NoteCase(
        "14_uri_english",
        "en",
        URI_EN,
        [
            ("Sore throat", any_contains("throat", "حلق")),
            ("Viral URI dx", any_contains("uri", "respiratory", "viral")),
            ("Acetaminophen", any_contains("acetaminophen", "paracetamol")),
        ],
    ),
    NoteCase(
        "15_egyptian_respiratory_mixed",
        "ar",
        EGYPTIAN_RESP,
        [
            ("Cough symptom", any_contains("سعال", "cough", "كحة")),
            ("CXR plan", any_contains("x-ray", "chest", "أشعة")),
            ("Azithromycin", any_contains("azithromycin")),
            ("Paracetamol", any_contains("paracetamol")),
        ],
    ),
    NoteCase(
        "16_pregnancy_english",
        "en",
        PREGNANCY_EN,
        [
            ("Prenatal vitamins", any_contains("prenatal", "vitamin")),
            ("Ultrasound plan", any_contains("ultrasound", "scan")),
            ("Follow-up", any_contains("follow")),
        ],
    ),
    NoteCase(
        "17_neurology_headache_arabic",
        "ar",
        NEUROLOGY_AR,
        [
            ("Headache", any_contains("صداع", "headache")),
            ("Dizziness", any_contains("دوخة", "dizz")),
            ("MRI plan", any_contains("mri")),
            ("Ibuprofen", any_contains("ibuprofen")),
        ],
    ),
]


def run_case(case: NoteCase) -> tuple[int, int, list[str]]:
    partial = make_partial(case.lang, case.partial_symptoms)
    resp = build_api_response(partial, "mock", source_text=case.note)
    data = resp["extracted_data"]
    passed = 0
    failures: list[str] = []
    for label, check in case.checks:
        ok = check(data)
        if ok:
            passed += 1
        else:
            failures.append(f"  [MISS] {label}")
    return passed, len(case.checks), failures


def main() -> int:
    print("=" * 70)
    print("EXTRACTION QUALITY SUITE — 17 Arabic / English / mixed notes")
    print("(simulates partial LLM output + transcript enrichment)")
    print("=" * 70)

    total_checks = 0
    total_passed = 0
    failed_cases: list[str] = []

    for case in CASES:
        passed, n, failures = run_case(case)
        total_checks += n
        total_passed += passed
        status = "PASS" if not failures else "FAIL"
        print(f"\n[{status}] {case.name} ({case.lang}) — {passed}/{n} checks")
        if failures:
            failed_cases.append(case.name)
            for f in failures:
                print(f)
            # Debug snapshot for failed case
            partial = make_partial(case.lang, case.partial_symptoms)
            d = build_api_response(partial, "mock", source_text=case.note)["extracted_data"]
            print(f"  >> dx={_dx(d)[:3]} | plan={len(_plan(d))} | rx={_rx_names(d)} | cur={_cur_names(d)}")

    print("\n" + "=" * 70)
    pct = (100.0 * total_passed / total_checks) if total_checks else 0
    print(f"TOTAL: {total_passed}/{total_checks} checks passed ({pct:.1f}%)")
    if failed_cases:
        print(f"Failed cases ({len(failed_cases)}): {', '.join(failed_cases)}")
    else:
        print("All cases passed.")

    print("\n--- AI Review smoke test (cardiology note) ---")
    partial = make_partial("ar")
    d = build_api_response(partial, "mock", source_text=CARDIOLOGY_MIXED)["extracted_data"]
    for q in ["هل يوجد prescription؟", "Is there a plan?", "ما الناقص؟"]:
        r = run_extraction_review(CARDIOLOGY_MIXED, d, doctor_prompt=q, call_model=None)
        print(f"  Q: {q[:40]} → {r['answer']}: {r['message'][:80]}")

    return 0 if total_passed == total_checks else 1


if __name__ == "__main__":
    sys.exit(main())
