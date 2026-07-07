"""
Unit tests for agent_intent.py — intent detection and language detection.
No DB needed; pure function tests.
"""

from __future__ import annotations

import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from agent_intent import detect_intent, detect_language


# ─── detect_language ─────────────────────────────────────────────────────────

class TestDetectLanguage:
    def test_english_text(self):
        assert detect_language("How do I book an appointment?") == "en"

    def test_arabic_text(self):
        assert detect_language("كيف أحجز موعدًا؟") == "ar"

    def test_mixed_text_detected_as_arabic(self):
        assert detect_language("I need مساعدة") == "ar"

    def test_empty_string_is_english(self):
        assert detect_language("") == "en"

    def test_numbers_are_english(self):
        assert detect_language("12345") == "en"


# ─── detect_intent — patient ─────────────────────────────────────────────────

class TestPatientIntents:
    def test_clinic_hours_question(self):
        intents = detect_intent("What are your working hours?", "patient")
        assert "clinic_info" in intents

    def test_fee_question(self):
        intents = detect_intent("How much does an appointment cost?", "patient")
        assert "clinic_info" in intents

    def test_doctor_search(self):
        intents = detect_intent("Can you recommend a doctor for back pain?", "patient")
        assert "doctor_search" in intents

    def test_symptom_triggers_advice(self):
        intents = detect_intent("I have a headache and fever", "patient")
        assert "symptom_advice" in intents

    def test_my_appointments(self):
        intents = detect_intent("Show me my appointments", "patient")
        assert "my_appointments" in intents

    def test_arabic_clinic_info(self):
        intents = detect_intent("ما هي ساعات العمل؟", "patient")
        assert "clinic_info" in intents

    def test_arabic_doctor_search(self):
        intents = detect_intent("أريد أفضل طبيب عيون", "patient")
        assert "doctor_search" in intents

    def test_arabic_symptom(self):
        intents = detect_intent("أعاني من ألم في الصدر", "patient")
        assert "symptom_advice" in intents

    def test_patient_cannot_trigger_revenue(self):
        intents = detect_intent("What is the total revenue?", "patient")
        assert "revenue" not in intents

    def test_patient_cannot_trigger_cancellations(self):
        intents = detect_intent("How many cancellations today?", "patient")
        assert "cancellations" not in intents

    def test_patient_cannot_trigger_admin_overview(self):
        intents = detect_intent("Give me the total dashboard", "patient")
        assert "admin_overview" not in intents

    def test_patient_my_appointments_not_for_receptionist(self):
        intents = detect_intent("Show me my appointments", "receptionist")
        assert "my_appointments" not in intents

    def test_fallback_returns_clinic_info(self):
        intents = detect_intent("hello", "patient")
        assert "clinic_info" in intents

    def test_multiple_intents_fire(self):
        intents = detect_intent("I feel sick, which doctor should I see?", "patient")
        assert "symptom_advice" in intents
        assert "doctor_search" in intents


# ─── detect_intent — receptionist ────────────────────────────────────────────

class TestReceptionistIntents:
    def test_today_stats(self):
        intents = detect_intent("How many appointments today?", "receptionist")
        assert "today_stats" in intents

    def test_revenue_intent(self):
        intents = detect_intent("What is today's revenue?", "receptionist")
        assert "revenue" in intents

    def test_cancellations_intent(self):
        intents = detect_intent("Who cancelled their appointment today?", "receptionist")
        assert "cancellations" in intents

    def test_arabic_revenue(self):
        intents = detect_intent("كم الإيراد هذا الأسبوع؟", "receptionist")
        assert "revenue" in intents

    def test_arabic_cancellations(self):
        intents = detect_intent("من الذي ألغى موعده؟", "receptionist")
        assert "cancellations" in intents

    def test_receptionist_cannot_trigger_admin_overview(self):
        intents = detect_intent("total dashboard summary", "receptionist")
        assert "admin_overview" not in intents

    def test_receptionist_cannot_trigger_patient_lookup(self):
        intents = detect_intent("find patient Ahmed", "receptionist")
        assert "patient_lookup" not in intents


# ─── detect_intent — doctor ───────────────────────────────────────────────────

class TestDoctorIntents:
    def test_my_schedule(self):
        intents = detect_intent("What is my schedule today?", "doctor")
        assert "my_schedule" in intents

    def test_my_reviews(self):
        intents = detect_intent("What are my reviews?", "doctor")
        assert "my_reviews" in intents

    def test_arabic_schedule(self):
        intents = detect_intent("ما هو جدولي اليوم؟", "doctor")
        assert "my_schedule" in intents

    def test_arabic_reviews(self):
        intents = detect_intent("ما هي تقييماتي؟", "doctor")
        assert "my_reviews" in intents

    def test_doctor_cannot_see_revenue(self):
        intents = detect_intent("What is total revenue?", "doctor")
        assert "revenue" not in intents

    def test_doctor_cannot_see_admin_overview(self):
        intents = detect_intent("Give me the admin dashboard", "doctor")
        assert "admin_overview" not in intents

    def test_doctor_cannot_search_other_doctors(self):
        intents = detect_intent(
            "can you tell me other doctors appointments and free slots",
            "doctor",
        )
        assert "doctor_search" not in intents
        assert "doctor_availability" not in intents
        assert "my_schedule" in intents


# ─── detect_intent — admin ────────────────────────────────────────────────────

class TestAdminIntents:
    def test_admin_overview(self):
        intents = detect_intent("Give me the overall summary", "admin")
        assert "admin_overview" in intents

    def test_compare_doctors(self):
        intents = detect_intent("Compare doctors by appointments", "admin")
        assert "doctor_compare" in intents

    def test_patient_lookup(self):
        intents = detect_intent("Find patient named Ahmed", "admin")
        assert "patient_lookup" in intents

    def test_staff_list(self):
        intents = detect_intent("List all staff members", "admin")
        assert "staff_list" in intents

    def test_audit(self):
        intents = detect_intent("Show me the audit log", "admin")
        assert "audit" in intents

    def test_arabic_admin_overview(self):
        intents = detect_intent("أعطني ملخص الإجمالي", "admin")
        assert "admin_overview" in intents

    def test_arabic_patient_lookup(self):
        intents = detect_intent("مريض اسمه خالد", "admin")
        assert "patient_lookup" in intents

    def test_arabic_audit(self):
        intents = detect_intent("أرني سجل التدقيق", "admin")
        assert "audit" in intents

    def test_admin_also_gets_revenue(self):
        intents = detect_intent("What is the revenue this month?", "admin")
        assert "revenue" in intents

    def test_admin_also_gets_cancellations(self):
        intents = detect_intent("How many cancellations this week?", "admin")
        assert "cancellations" in intents

    def test_admin_gets_today_stats(self):
        intents = detect_intent("How many patients today?", "admin")
        assert "today_stats" in intents

    def test_admin_fallback_is_overview(self):
        intents = detect_intent("hello", "admin")
        assert "admin_overview" in intents

    def test_no_duplicate_intents(self):
        intents = detect_intent("Compare doctors and overview summary", "admin")
        assert len(intents) == len(set(intents))

    def test_busiest_doctor_triggers_compare(self):
        intents = detect_intent("Who is the busiest doctor this month?", "admin")
        assert "doctor_compare" in intents


# ─── Egyptian Arabic dialect tests ────────────────────────────────────────────

class TestEgyptianArabic:
    """Verify all intent keywords work with Egyptian dialect (عامية مصرية)."""

    # Clinic info
    def test_clinic_btkam(self):
        intents = detect_intent("الكشف بكام عندكم؟", "patient")
        assert "clinic_info" in intents

    def test_clinic_ezzay(self):
        intents = detect_intent("ازاي احجز موعد؟", "patient")
        assert "clinic_info" in intents

    def test_clinic_fein(self):
        intents = detect_intent("العيادة فين؟", "patient")
        assert "clinic_info" in intents

    def test_clinic_btftah(self):
        intents = detect_intent("العيادة بتفتح الساعة كام؟", "patient")
        assert "clinic_info" in intents

    def test_clinic_ayez_ahgez(self):
        intents = detect_intent("عايز احجز عند دكتور", "patient")
        assert "clinic_info" in intents

    # Doctor search
    def test_doctor_ahsan(self):
        intents = detect_intent("مين أحسن دكتور عندكم؟", "patient")
        assert "doctor_search" in intents

    def test_doctor_ashtar(self):
        intents = detect_intent("أشطر دكتور قلب ايه؟", "patient")
        assert "doctor_search" in intents

    def test_doctor_tarshahli(self):
        intents = detect_intent("ترشحلي دكتور كويس", "patient")
        assert "doctor_search" in intents

    def test_doctor_tansahni(self):
        intents = detect_intent("تنصحني بأنهي دكتور؟", "patient")
        assert "doctor_search" in intents

    # Symptoms
    def test_symptom_bywgani(self):
        intents = detect_intent("بيوجعني ضهري أوي", "patient")
        assert "symptom_advice" in intents

    def test_symptom_taban(self):
        intents = detect_intent("أنا تعبان ومش قادر أقوم", "patient")
        assert "symptom_advice" in intents

    def test_symptom_ayan(self):
        intents = detect_intent("أنا عيان من امبارح", "patient")
        assert "symptom_advice" in intents

    def test_symptom_skhoneya(self):
        intents = detect_intent("عندي سخونية عالية", "patient")
        assert "symptom_advice" in intents

    def test_symptom_waga_batn(self):
        intents = detect_intent("عندي وجع بطن شديد", "patient")
        assert "symptom_advice" in intents

    def test_symptom_hassasiya(self):
        intents = detect_intent("عندي حساسية في جلدي", "patient")
        assert "symptom_advice" in intents

    # Availability
    def test_availability_fadi_emta(self):
        intents = detect_intent("الدكتور أحمد فاضي امتى؟", "patient")
        assert "doctor_availability" in intents

    def test_availability_bokra(self):
        intents = detect_intent("مواعيد الدكتور بكرة", "patient")
        assert "doctor_availability" in intents

    def test_availability_naharda(self):
        intents = detect_intent("مين فاضي النهارده؟", "patient")
        assert "doctor_availability" in intents

    def test_availability_emta(self):
        intents = detect_intent("الدكتور سامي امتى؟", "patient")
        assert "doctor_availability" in intents

    def test_availability_baad_bokra(self):
        intents = detect_intent("عنده مواعيد بعد بكره؟", "patient")
        assert "doctor_availability" in intents

    def test_availability_ando_waqt(self):
        intents = detect_intent("الدكتور عنده وقت بكرا؟", "patient")
        assert "doctor_availability" in intents

    # My appointments
    def test_my_apts_hagzi(self):
        intents = detect_intent("فين حجزي؟", "patient")
        assert "my_appointments" in intents

    def test_my_apts_ana_hagez(self):
        intents = detect_intent("أنا حاجز امتى؟", "patient")
        assert "my_appointments" in intents

    def test_my_apts_meadi(self):
        intents = detect_intent("الميعاد بتاعي ايه؟", "patient")
        assert "my_appointments" in intents

    def test_my_apts_forgot_booking_ar(self):
        msg = "انا نسيت المعادل اللي انا حجزت فيه ممكن تقولي المعادل اللي انا حجزته"
        intents = detect_intent(msg, "patient")
        assert "my_appointments" in intents

    # Revenue (receptionist)
    def test_revenue_felos(self):
        intents = detect_intent("كسبنا كام النهارده؟", "receptionist")
        assert "revenue" in intents

    def test_revenue_dahkl(self):
        intents = detect_intent("الدخل بتاعنا كام الشهر ده؟", "receptionist")
        assert "revenue" in intents

    def test_revenue_gebna_kam(self):
        intents = detect_intent("جبنا كام فلوس النهارده؟", "receptionist")
        assert "revenue" in intents

    # Cancellations (receptionist)
    def test_cancel_lagha(self):
        intents = detect_intent("مين لغى النهارده؟", "receptionist")
        assert "cancellations" in intents

    def test_cancel_atkansel(self):
        intents = detect_intent("كام واحد اتكنسل؟", "receptionist")
        assert "cancellations" in intents

    def test_cancel_magash(self):
        intents = detect_intent("كام مريض مجاش النهارده؟", "receptionist")
        assert "cancellations" in intents

    def test_cancel_khasarna(self):
        intents = detect_intent("خسرنا كام بسبب الإلغاءات؟", "receptionist")
        assert "cancellations" in intents

    # Stats
    def test_stats_naharda(self):
        intents = detect_intent("كام مريض النهارده؟", "receptionist")
        assert "today_stats" in intents

    def test_stats_dlwqty(self):
        intents = detect_intent("ايه الوضع دلوقتي؟", "receptionist")
        assert "today_stats" in intents

    def test_stats_taboor(self):
        intents = detect_intent("الطابور فيه كام واحد؟", "receptionist")
        assert "today_stats" in intents

    # Doctor schedule
    def test_my_schedule_naharda(self):
        intents = detect_intent("مواعيدي النهارده ايه؟", "doctor")
        assert "my_schedule" in intents

    def test_my_schedule_meen_andy(self):
        intents = detect_intent("مين عندي النهارده؟", "doctor")
        assert "my_schedule" in intents

    def test_my_schedule_kshfi(self):
        intents = detect_intent("الكشف بتاعي النهارده", "doctor")
        assert "my_schedule" in intents

    # Doctor reviews
    def test_my_reviews_taqeemi(self):
        intents = detect_intent("التقييم بتاعي كام؟", "doctor")
        assert "my_reviews" in intents

    def test_my_reviews_nas_btqol(self):
        intents = detect_intent("الناس بتقول ايه عني؟", "doctor")
        assert "my_reviews" in intents

    # Admin
    def test_admin_wareni(self):
        intents = detect_intent("وريني كل حاجة عن النظام", "admin")
        assert "admin_overview" in intents

    def test_admin_meen_aktar(self):
        intents = detect_intent("مين أكتر دكتور شغال؟", "admin")
        assert "doctor_compare" in intents

    def test_admin_el_mwazafeen(self):
        intents = detect_intent("وريني الموظفين كلهم", "admin")
        assert "staff_list" in intents

    def test_admin_dawar_ala_marid(self):
        intents = detect_intent("دور على مريض اسمه أحمد", "admin")
        assert "patient_lookup" in intents

    def test_admin_meen_amal(self):
        intents = detect_intent("مين عمل ايه في النظام؟", "admin")
        assert "audit" in intents

    def test_admin_el_arqam(self):
        intents = detect_intent("وريني الأرقام والإحصائيات", "admin")
        assert "admin_overview" in intents
