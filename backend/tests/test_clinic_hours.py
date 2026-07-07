"""Tests for clinic hour normalization and slot generation."""

from __future__ import annotations

import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from clinic_schedule import normalize_clinic_time_pair, repair_invalid_clinic_hours  # noqa: E402
from routers.appointments import _generate_slots  # noqa: E402


def test_normalize_clinic_time_pair_fixes_pm_end():
    start, end = normalize_clinic_time_pair("08:00", "4:30")
    assert start == "08:00"
    assert end == "16:30"


def test_generate_slots_with_ambiguous_end_time():
    slots = _generate_slots("08:00", "4:30", 30)
    assert len(slots) > 0
    assert slots[0] == "08:00"
    assert slots[-1] == "16:00"


def test_generate_slots_normal_24h():
    slots = _generate_slots("09:00", "17:00", 30)
    assert len(slots) == 16
    assert "16:30" in slots
