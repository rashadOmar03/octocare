"""
Intent detection for the AI agent (keyword fallback).

Primary routing uses LLM semantic classification in agent_router.py.
These keywords are kept as a safety net when the model is offline or returns
invalid JSON, and for fast unit tests without an LLM call.
"""

from __future__ import annotations

import re

ARABIC_RE = re.compile(r"[\u0600-\u06FF]")


def detect_language(text: str) -> str:
    return "ar" if ARABIC_RE.search(text) else "en"


# ─── keyword sets ─────────────────────────────────────────────────────────────

_CLINIC_KW = {
    # English
    "hours", "open", "close", "working", "schedule", "address", "location",
    "phone", "contact", "fee", "cost", "price", "flow", "process", "step",
    "how to", "how do", "booking", "appointment", "days", "duration", "clinic",
    "where is", "how much",
    # Formal Arabic
    "ساعات", "يفتح", "يغلق", "عنوان", "اتصال", "رسوم", "سعر", "تكلفة",
    "كيف", "خطوات", "مواعيد", "أيام", "هاتف", "عيادة",
    # Egyptian Arabic
    "بتفتح", "بتقفل", "بتقفلو", "فين", "فاين", "فنين",
    "العنوان", "المكان", "الكشف", "كشف", "بكام", "كام",
    "الحجز", "احجز", "اعمل حجز", "عايز احجز", "عاوز احجز",
    "عايزه احجز", "عاوزه احجز", "نمره", "نمرة", "رقم",
    "ازاي", "إزاي", "ازى", "إزى", "ازاى",
    "الخطوات", "الأسعار", "يعني ايه", "يعنى ايه", "يعنى إيه",
    "تليفون", "موبايل", "رقم التليفون", "رقم الموبايل",
    "مدة", "المدة", "قد ايه", "قد إيه",
    "الكلينيك", "المركز", "المستشفى",
}

_DOCTOR_KW = {
    # English
    "doctor", "dr.", "dr ", "physician", "specialist", "find doctor", "who is",
    "recommend", "rated", "rating", "review", "best doctor", "top doctor",
    "available", "availability", "free slot", "open slot", "book with",
    # Formal Arabic
    "طبيب", "أطباء", "دكتور", "تخصص", "أفضل", "تقييم", "مراجعة",
    "متاح", "متوفر", "متاحة",
    # Egyptian Arabic
    "دكتوره", "دكتورة", "الدكتور", "الدكتوره", "الدكتورة",
    "فاضي", "فاضى", "فاضية", "فاضيه",
    "احسن دكتور", "أحسن دكتور", "أشطر دكتور", "اشطر دكتور",
    "دكتور كويس", "دكتور شاطر", "دكتورة كويسة", "دكتورة شاطرة",
    "تقييمه", "تقييمها", "رأيكم في", "رأيكو في",
    "ترشحلي", "ترشحولي", "تنصحني", "تنصحوني",
    "عند دكتور", "مع دكتور", "عند الدكتور",
}

_SYMPTOM_KW = {
    # English
    "symptom", "feel", "pain", "hurt", "sick", "disease", "condition",
    "i have", "suffering", "problem with my", "headache", "fever", "cough",
    # Formal Arabic
    "أعاني", "أشعر", "ألم", "مريض", "مرض", "حالة", "مشكلة", "صداع", "حمى",
    # Egyptian Arabic
    "بيوجعني", "وجعني", "وجعاني", "وجع", "بيألمني",
    "تعبان", "تعبانه", "تعبانة", "عيان", "عيانه", "عيانة",
    "حاسس", "حاسه", "حاساه", "حاسة",
    "عندي", "بعاني", "باعاني",
    "صداع", "سخونية", "سخونيه", "حرارة", "كحة", "كحه", "زكام",
    "دوخة", "دوخه", "ترجيع", "استفراغ", "مغص",
    "وجع بطن", "وجع ضهر", "وجع راس", "وجع رأس",
    "وجع صدر", "وجع ودن", "وجع سنان", "وجع عين",
    "وجع ركبة", "وجع ركبه", "وجع رجل", "وجع إيد",
    "حساسية", "حساسيه", "التهاب",
    "مش قادر", "مش قادره", "بحس", "احس",
}

_AVAILABILITY_KW = {
    # English
    "available", "availability", "free", "open slot", "free slot", "when can",
    "tomorrow", "next week", "next day", "slot", "time slot", "book with",
    "when is", "schedule for",
    # Formal Arabic
    "متاح", "متوفر", "متاحة", "غدا", "غداً",
    # Egyptian Arabic
    "فاضي", "فاضى", "فاضية", "فاضيه",
    "بكرا", "بكره", "بكرة",
    "أقرب موعد", "اقرب موعد", "اقرب ميعاد",
    "مواعيد", "موعد", "ميعاد", "مواعيده", "مواعيدها",
    "امتى", "إمتى", "متى", "امتا", "إمتا",
    "فاضي امتى", "فاضى امتى", "فاضي امتا",
    "النهارده", "النهاردة", "النهارده", "بعد بكرا", "بعد بكره", "بعد بكرة",
    "ميعاده", "ميعادها",
    "عنده وقت", "عندها وقت", "عنده فراغ",
    "يوم ايه", "يوم إيه", "يوم كام",
    "الأسبوع الجاي", "الاسبوع الجاي", "الأسبوع اللي جاي",
}

_MY_APTS_KW = {
    # English
    "my appointment", "my booking", "my visit", "my upcoming",
    "do i have", "am i booked", "my schedule", "my next",
    "when is my", "i have an appointment", "i am booked",
    # Formal Arabic
    "مواعيدي", "حجوزاتي", "زياراتي", "مواعيدي القادمة",
    "هل عندي", "هل لدي",
    # Egyptian Arabic
    "حجزي", "حجزاتي", "مواعيدي", "ميعادي",
    "انا حاجز", "أنا حاجز", "أنا حاجزه", "انا حاجزة",
    "حجزت امتى", "ميعادي امتى", "موعدي امتى",
    "حجوزاتي", "الحجز بتاعي", "الميعاد بتاعي",
    "فين حجزي", "فين ميعادي", "فين موعدي",
    "عندي ميعاد", "عندي حجز", "انا حاجز عند",
    "نسيت", "نسيت المعاد", "نسيت الميعاد", "نسيت الموعد",
    "المعاد", "المعادل", "الميعاد", "الموعد",
    "حجزت", "حجزته", "حجزت فيه", "اللي حجزته", "اللي انا حجزت",
    "ايه بالظبط", "إيه بالظبط", "موعدي ايه", "ميعادي ايه",
    "الميعاد اللي", "المعاد اللي", "الموعد اللي",
}

_REVENUE_KW = {
    # English
    "revenue", "money", "earn", "income", "paid", "payment", "profit",
    "how much", "total money", "financial", "earnings",
    # Formal Arabic
    "إيراد", "إيرادات", "مدفوع", "مكسب", "دخل", "أموال", "ربح",
    # Egyptian Arabic
    "فلوس", "الفلوس", "كسبنا كام", "جبنا كام", "دخلنا كام",
    "المكسب", "الربح", "الدخل", "الإيراد",
    "المدفوعات", "اللي اتدفع", "اللي ندفع",
    "كام واحد دفع", "مين دفع", "مين مدفعش",
    "حصيلة", "الحصيلة", "اتقبض كام",
    "مجموع الفلوس", "كام فلوس", "اجمالي",
    "اللي دخل", "اللي خرج",
}

_CANCEL_KW = {
    # English
    "cancel", "cancell", "no show", "miss", "lost", "refund", "cancelled",
    # Formal Arabic
    "إلغاء", "ملغى", "ألغى", "إلغاءات", "خسارة", "استرداد",
    # Egyptian Arabic
    "لغى", "الغى", "لغت", "لغا", "الغا",
    "كانسل", "كنسل", "اتكنسل", "اتلغى", "اتلغت",
    "مجاش", "مجتش", "ماجاش", "ماجتش",
    "مجيش", "مجيتش", "مردش", "مردتش",
    "من ألغى", "مين لغى", "مين الغى", "مين كنسل",
    "خسرنا", "الخسارة", "خسرنا كام",
    "استرجاع", "فلوس مسترجعة", "رجعنا فلوس",
    "اللي لغوا", "اللي كنسلوا",
}

_STATS_KW = {
    # English
    "today", "now", "queue", "waiting", "current", "status", "count",
    "how many", "number of",
    # Formal Arabic
    "اليوم", "الآن", "قائمة", "انتظار", "حالي", "عدد",
    # Egyptian Arabic
    "النهارده", "النهاردة", "النهارده", "دلوقتي", "دلوقت",
    "الطابور", "الدور", "مين مستني", "مستنيين كام",
    "كام واحد", "كام مريض", "كام حجز",
    "كم عدد", "عددهم كام", "قد ايه", "قد إيه",
    "الحالة", "ايه الوضع", "إيه الوضع", "ايه الأخبار", "إيه الأخبار",
    "احنا ماشيين ازاي", "الشغل ماشي ازاي",
}

_QUEUE_KW = {
    # English
    "who is with", "currently with", "with dr", "with doctor", "in consultation",
    "seeing now", "who is seeing", "who are they seeing", "current patient",
    "who is in", "which patient", "queue", "waiting", "live", "right now",
    "who is he with", "who is she with", "who is the patient",
    "who is this patient", "this patient", "patient with",
    # Formal Arabic
    "مع الدكتور", "مع دكتور", "عند الدكتور", "في الكشف",
    "المريض الحالي", "المريضة الحالية", "حاليا", "الآن",
    # Egyptian Arabic
    "مين مع", "مين عند", "مين جوا", "مين في الكشف",
    "مين بيتكشف", "مين بتتكشف", "مين داخل",
    "مع دكتور مين", "عند مين", "جوا عند مين",
    "مين مستني", "مين مستنية", "مين مستنيين",
    "الدور وصل فين", "الدور فين", "الطابور",
    "مين في الانتظار", "مين في العيادة",
    "مين اللي جوا", "مين اللي عند الدكتور",
    "مين بيكشف عليه", "مين بتكشف عليها",
    "الكشف وصل فين", "وصلنا فين",
    "مين الحالة اللي جوا", "مين المريض",
}

_COMPARE_DOC_KW = {
    # English
    "compare", "busiest", "most appointment", "best doctor", "top doctor",
    "leaderboard", "rank", "performance", "who has more", "which doctor",
    # Formal Arabic
    "مقارنة", "أكثر مواعيد", "أفضل طبيب", "ترتيب", "أداء", "أي طبيب",
    # Egyptian Arabic
    "قارن", "قارن بين", "الأكتر شغل", "الاكتر شغل",
    "مين أكتر", "مين اكتر", "مين شغال أكتر", "مين شغال اكتر",
    "أحسن دكتور", "احسن دكتور", "أشطر دكتور", "اشطر دكتور",
    "مين أحسن", "مين احسن", "أنهي دكتور", "أنهى دكتور", "انهي دكتور",
    "الدكاترة ماشيين ازاي", "أداء الدكاترة",
}

_PATIENT_LOOKUP_KW = {
    # English
    "patient named", "find patient", "search patient", "who is patient",
    "tell me about patient", "patient called",
    # Formal Arabic
    "مريض اسمه", "مريضة اسمها", "ابحث عن مريض", "من هو المريض",
    # Egyptian Arabic
    "دور على مريض", "دور على مريضة", "دورلي على مريض",
    "فين المريض", "فين المريضة",
    "مريض اسمه", "مريضة اسمها",
    "عايز اعرف عن مريض", "عاوز اعرف عن مريض",
    "هاتلي بيانات مريض", "هاتلي بيانات",
    "بيانات المريض", "ملف المريض",
}

_STAFF_KW = {
    # English
    "staff", "employee", "team", "receptionist", "all doctor", "worker",
    "how many doctor", "how many staff",
    # Formal Arabic
    "موظف", "موظفين", "فريق", "استقبال", "عمال",
    # Egyptian Arabic
    "الموظفين", "كل الموظفين", "الناس اللي شغالين",
    "الدكاترة", "كل الدكاترة", "كل الأطباء",
    "الاستقبال", "موظفين الاستقبال", "بتوع الاستقبال",
    "كام دكتور", "كم طبيب", "كام موظف",
    "الفريق", "فريق العمل", "مين شغال", "مين بيشتغل",
    "الناس بتوعنا", "طاقم العمل",
}

_AUDIT_KW = {
    # English
    "audit", "log", "who did", "activity", "action", "history", "did what",
    # Formal Arabic
    "تدقيق", "سجل", "من فعل", "نشاط", "ما الذي تم",
    # Egyptian Arabic
    "مين عمل", "مين عمل ايه", "مين عمل إيه",
    "مين غير", "مين غيّر", "ايه اللي حصل", "إيه اللي حصل",
    "السجل", "سجل العمليات", "سجل الأحداث",
    "مين دخل", "مين اشتغل", "ايه التغييرات", "إيه التغييرات",
    "تاريخ العمليات", "الحركات", "حركات النظام",
}

_MY_SCHEDULE_KW = {
    # English
    "my schedule", "my patients today", "my appointments today", "my queue",
    "who do i see", "my list",
    # Formal Arabic
    "جدولي", "مواعيدي اليوم", "مرضاي", "قائمتي",
    # Egyptian Arabic
    "الجدول بتاعي", "مواعيدي النهارده", "مواعيدي النهاردة",
    "مين عندي النهارده", "مين عندي النهاردة",
    "المرضى بتوعي", "المرضى اللي عندي",
    "مين جاي النهارده", "مين جاي النهاردة",
    "ليستي", "القايمة بتاعتي", "القائمة بتاعتي",
    "الكشف بتاعي", "كشفي", "مين مستنيني",
    "عندي كام مريض", "مواعيد النهارده",
}

_MY_REVIEWS_KW = {
    # English
    "my review", "my rating", "my feedback", "patient opinion", "my score",
    # Formal Arabic
    "تقييماتي", "آراء المرضى عني", "تقييمي", "ماذا يقول المرضى",
    # Egyptian Arabic
    "التقييم بتاعي", "التقييمات بتاعتي",
    "الناس بتقول ايه عني", "الناس بتقول إيه عني",
    "المرضى بيقولوا ايه", "المرضى بيقولوا إيه",
    "رأي المرضى فيا", "رأي الناس فيا",
    "كام نجمة", "كام ستار",
    "تقييمي كام", "ريتنج", "ريتنجي",
}

_ADMIN_OVERVIEW_KW = {
    # English
    "total", "overview", "summary", "dashboard", "overall", "all stats",
    "how many patients", "how many doctors", "registered patients",
    "total patients", "total doctors", "in the system", "in the clinic",
    "patient count", "doctor count",
    # Formal Arabic
    "إجمالي", "ملخص", "نظرة عامة", "كل الإحصائيات",
    "كم عدد المرضى", "كم عدد الاطباء", "كم مريض", "كم طبيب",
    "عدد المرضى", "عدد الأطباء",
    # Egyptian Arabic
    "الإجمالي", "المجموع", "ملخص عام",
    "ورّيني كل حاجة", "وريني كل حاجه", "وريني كل حاجة",
    "ايه الوضع العام", "إيه الوضع العام",
    "احصائيات", "الإحصائيات", "الأرقام", "الارقام",
    "كل الأرقام", "تقرير", "التقرير",
    "كام مريض مسجل", "كام دكتور عندنا", "عدد المرضى المسجلين",
    "عدد الأطباء المسجلين", "كم عدد", "المرضى والاطباء",
}


def _match(text: str, keywords: set[str]) -> bool:
    t = text.lower()
    return any(kw in t for kw in keywords)


def detect_intent(message: str, role: str) -> list[str]:
    """
    Returns a list of intent tags based on the message and caller's role.
    The backend uses these tags to select which DB tools to run.
    Multiple intents can be active at once.
    """
    intents: list[str] = []

    # ── Universal intents (patients + staff; doctors see only own clinical data) ─
    if _match(message, _CLINIC_KW):
        intents.append("clinic_info")

    if role != "doctor":
        if _match(message, _DOCTOR_KW):
            intents.append("doctor_search")

        if _match(message, _AVAILABILITY_KW) or (
            _match(message, _DOCTOR_KW) and any(
                w in message.lower()
                for w in (
                    "tomorrow", "today", "next",
                    "بكرا", "بكره", "بكرة", "غدا", "غداً",
                    "اليوم", "النهارده", "النهاردة", "النهارده",
                    "بعد بكرا", "بعد بكره", "بعد بكرة",
                    "امتى", "إمتى", "امتا", "إمتا", "متى",
                )
            )
        ):
            intents.append("doctor_availability")

    if role == "patient" and _match(message, _SYMPTOM_KW):
        intents.append("symptom_advice")

    # ── Patient only ───────────────────────────────────────────────────────────
    if role == "patient":
        personal_booking = (
            any(k in message for k in ("انا", "أنا", "لي", "بتاعي", "بتاعى", "عندي", "نسيت"))
            and any(
                k in message
                for k in (
                    "حجز", "حجزت", "حجزته", "موعد", "ميعاد", "معاد", "المعاد", "المعادل",
                )
            )
        )
        if _match(message, _MY_APTS_KW) or personal_booking:
            intents.append("my_appointments")
            if "doctor_availability" in intents:
                intents.remove("doctor_availability")

    # ── Receptionist & admin ───────────────────────────────────────────────────
    if role in ("receptionist", "admin"):
        if _match(message, _QUEUE_KW):
            intents.append("live_queue")
        if _match(message, _PATIENT_LOOKUP_KW):
            intents.append("patient_lookup")
        if _match(message, _STATS_KW):
            intents.append("today_stats")
        if _match(message, _REVENUE_KW):
            intents.append("revenue")
        if _match(message, _CANCEL_KW):
            intents.append("cancellations")
        if _match(message, _DOCTOR_KW) and _match(message, _STATS_KW):
            intents.append("doctor_workload")

    # ── Doctor ─────────────────────────────────────────────────────────────────
    if role == "doctor":
        if _match(message, _MY_SCHEDULE_KW) or _match(message, _STATS_KW):
            intents.append("my_schedule")
        if _match(message, _MY_REVIEWS_KW):
            intents.append("my_reviews")
        if _match(message, _STATS_KW):
            intents.append("today_stats")
        # Questions about other doctors / other doctors' patients → own schedule only
        if _match(message, _DOCTOR_KW) or _match(message, _AVAILABILITY_KW) or _match(message, _PATIENT_LOOKUP_KW):
            if "my_schedule" not in intents:
                intents.append("my_schedule")

    # ── Admin only ─────────────────────────────────────────────────────────────
    if role == "admin":
        if _match(message, _COMPARE_DOC_KW) or (
            _match(message, _DOCTOR_KW) and _match(message, _STATS_KW)
        ):
            intents.append("doctor_compare")
        if _match(message, _PATIENT_LOOKUP_KW):
            intents.append("patient_lookup")
        if _match(message, _STAFF_KW):
            intents.append("staff_list")
        if _match(message, _AUDIT_KW):
            intents.append("audit")
        if _match(message, _ADMIN_OVERVIEW_KW) or not intents:
            intents.append("admin_overview")

    # ── Default fallback ───────────────────────────────────────────────────────
    if not intents:
        intents.append("clinic_info")

    return list(dict.fromkeys(intents))  # preserve order, remove dupes
