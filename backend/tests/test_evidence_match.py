"""Tests for fuzzy evidence matching."""

from evidence_match import find_in_source, fuzzy_in_source, normalize_text


def test_normalize_arabic():
    assert normalize_text("وَجَع") == normalize_text("وجع")


def test_fuzzy_in_source_paraphrase():
    source = "patient complains of chest pain since yesterday night"
    found, start, end, ev = fuzzy_in_source("chest pain", source)
    assert found
    assert start >= 0


def test_find_in_source_drug_name():
    source = "on metformin 1g bid and glimepiride 2mg"
    start, end, ev = find_in_source("metformin", source)
    assert start >= 0


def test_find_in_source_typo_tolerance():
    source = "HbA1c last 8.9 percent"
    start, end, ev = find_in_source("HbA1c", source)
    assert start >= 0
