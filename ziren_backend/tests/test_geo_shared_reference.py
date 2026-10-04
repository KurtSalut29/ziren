"""Evaluator finding #24: one set of reference cases for distance and ETA.

shared/geo_reference_cases.json is read by this test, by the dashboard's
(lib/geo/geodesic.test.ts) and by the mobile app's (test/geo_shared_reference_test.dart),
so the three implementations are held to the same numbers.
"""

import json
from pathlib import Path

import pytest

from app.core import geo

CASES = json.loads((Path(__file__).resolve().parents[2] / "shared" / "geo_reference_cases.json").read_text("utf-8"))


@pytest.mark.parametrize("case", CASES["distances"], ids=lambda c: c["name"])
def test_distance_matches_the_shared_reference(case):
    (a, b), (c, d) = case["from"], case["to"]
    assert geo.geodesic_m(a, b, c, d) == pytest.approx(case["metres"], abs=CASES["distance_tolerance_m"])


@pytest.mark.parametrize("case", CASES["eta"], ids=lambda c: f'{c["km"]} km')
def test_eta_matches_the_shared_reference(case):
    assert geo.estimate_eta_minutes(case["km"]) == case["minutes"]


def test_the_assumed_speed_is_the_shared_one():
    assert geo.ASSUMED_SPEED_KMH == CASES["assumed_speed_kmh"]
