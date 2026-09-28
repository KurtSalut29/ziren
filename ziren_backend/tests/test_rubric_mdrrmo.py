"""
Phase 5.4 — MDRRMO rubric test matrix.

Every MDRRMO rule (MDRRMO-001 through MDRRMO-015) has:
  - A "fires" test
  - A "does not fire" test
  - A severity assertion

MDRRMO decision table (v2.0.0):
  MDRRMO-001  flood/landslide_calamity + casualty=True           → critical
  MDRRMO-002  landslide + casualty=True                          → critical
  MDRRMO-003  landslide + casualty=False + road structure        → high
  MDRRMO-004  flood + casualty=False + residential structure     → high
  MDRRMO-005  calamity + house/building structure + casualty=True → critical
  MDRRMO-006  calamity + casualty=False                          → medium
  MDRRMO-007  medical_trauma + injured >= 3 + multi_agency=True  → critical
  MDRRMO-008  medical_trauma + urgency critical/life-threatening + multi=False → high
  MDRRMO-009  medical_trauma + urgency unknown/moderate/stable   → medium
  MDRRMO-010  vehicular + injured >= 3 + casualty=True           → critical
  MDRRMO-011  vehicular + casualty=True + injured <= 2           → high
  MDRRMO-012  vehicular + casualty=False                         → medium
  MDRRMO-013  RETIRED v2.0.0 — hazmat merged out of taxonomy
  MDRRMO-014  RETIRED v2.0.0 — hazmat merged out of taxonomy
  MDRRMO-015  flood_landslide_calamity/medical_trauma/vehicular + children=True → critical

Run: pytest tests/test_rubric_mdrrmo.py -v
"""

import io
import json
import os

import pytest
from unittest.mock import MagicMock

from app.models.rubric import AgencyType, SeverityLevel
from app.services import rubric_service as rs

_SEED = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "app", "rubric_configs", "MDRRMO_v1.json",
)


def _rule(rule_id: str) -> dict:
    """Read one rule straight out of the seed config.

    Retirement lives in the config, not in the evaluation result — a rule that
    is merely unmatchable looks identical to one that is deactivated, and only
    the latter is the deliberate policy change.
    """
    with io.open(_SEED, encoding="utf-8") as f:
        cfg = json.load(f)
    for rule in cfg["rules"]:
        if rule["rule_id"] == rule_id:
            return rule
    raise AssertionError(f"{rule_id} not found in {_SEED}")


def _evaluate(signals):
    rs._config_cache.clear()
    mock_db = MagicMock()
    mock_db.table.return_value.select.return_value \
        .eq.return_value.eq.return_value \
        .limit.return_value.execute.return_value.data = []
    mock_db.table.return_value.insert.return_value.execute.return_value.data = [{"id": "x"}]
    return rs.evaluate(signals, AgencyType.MDRRMO, db=mock_db)


# =============================================================================
# MDRRMO-001: Flood with casualties
# =============================================================================

class TestMDRRMO001:

    def test_fires_flood_with_casualty(self):
        result = _evaluate({"incident_type": "flood", "casualty_mentioned": True})
        assert "MDRRMO-001" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_flood_landslide_calamity_type(self):
        result = _evaluate({
            "incident_type": "flood_landslide_calamity",
            "casualty_mentioned": True,
        })
        assert "MDRRMO-001" in result.triggered_rules

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({"incident_type": "flood", "casualty_mentioned": False})
        assert "MDRRMO-001" not in result.triggered_rules

    def test_does_not_fire_wrong_type(self):
        result = _evaluate({"incident_type": "fire", "casualty_mentioned": True})
        assert "MDRRMO-001" not in result.triggered_rules


# =============================================================================
# MDRRMO-002: Landslide with casualties
# =============================================================================

class TestMDRRMO002:

    def test_fires_landslide_with_casualty(self):
        result = _evaluate({"incident_type": "landslide", "casualty_mentioned": True})
        assert "MDRRMO-002" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_flood_landslide_calamity_type(self):
        """The general calamity type also satisfies MDRRMO-002's any-of."""
        result = _evaluate({
            "incident_type": "flood_landslide_calamity",
            "casualty_mentioned": True,
        })
        assert "MDRRMO-002" in result.triggered_rules

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({"incident_type": "landslide", "casualty_mentioned": False})
        assert "MDRRMO-002" not in result.triggered_rules


# =============================================================================
# MDRRMO-003: Landslide blocking road, no casualty
# =============================================================================

class TestMDRRMO003:

    def test_fires_landslide_road_block_no_casualty(self):
        result = _evaluate({
            "incident_type": "landslide",
            "casualty_mentioned": False,
            "structure_type": "road",
        })
        assert "MDRRMO-003" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_fires_highway_structure(self):
        result = _evaluate({
            "incident_type": "landslide",
            "casualty_mentioned": False,
            "structure_type": "highway",
        })
        assert "MDRRMO-003" in result.triggered_rules

    def test_fires_national_road_structure(self):
        result = _evaluate({
            "incident_type": "landslide",
            "casualty_mentioned": False,
            "structure_type": "national_road",
        })
        assert "MDRRMO-003" in result.triggered_rules

    def test_does_not_fire_casualty_present(self):
        result = _evaluate({
            "incident_type": "landslide",
            "casualty_mentioned": True,
            "structure_type": "road",
        })
        assert "MDRRMO-003" not in result.triggered_rules

    def test_does_not_fire_residential_structure(self):
        """Residential structure is in MDRRMO-004, not MDRRMO-003."""
        result = _evaluate({
            "incident_type": "landslide",
            "casualty_mentioned": False,
            "structure_type": "house",
        })
        assert "MDRRMO-003" not in result.triggered_rules

    def test_does_not_fire_missing_structure(self):
        result = _evaluate({
            "incident_type": "landslide",
            "casualty_mentioned": False,
        })
        assert "MDRRMO-003" not in result.triggered_rules


# =============================================================================
# MDRRMO-004: Flood, no casualty, residential area
# =============================================================================

class TestMDRRMO004:

    def test_fires_flood_residential_no_casualty(self):
        result = _evaluate({
            "incident_type": "flood",
            "casualty_mentioned": False,
            "structure_type": "residential",
        })
        assert "MDRRMO-004" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_fires_flood_barangay(self):
        result = _evaluate({
            "incident_type": "flood",
            "casualty_mentioned": False,
            "structure_type": "barangay",
        })
        assert "MDRRMO-004" in result.triggered_rules

    def test_fires_flood_house(self):
        result = _evaluate({
            "incident_type": "flood",
            "casualty_mentioned": False,
            "structure_type": "house",
        })
        assert "MDRRMO-004" in result.triggered_rules

    def test_does_not_fire_casualty_present(self):
        result = _evaluate({
            "incident_type": "flood",
            "casualty_mentioned": True,
            "structure_type": "residential",
        })
        assert "MDRRMO-004" not in result.triggered_rules

    def test_does_not_fire_missing_structure(self):
        result = _evaluate({
            "incident_type": "flood",
            "casualty_mentioned": False,
        })
        assert "MDRRMO-004" not in result.triggered_rules


# =============================================================================
# MDRRMO-005: Storm/calamity structure collapse with casualty
# =============================================================================

class TestMDRRMO005:

    def test_fires_calamity_building_casualty(self):
        result = _evaluate({
            "incident_type": "calamity",
            "structure_type": "building",
            "casualty_mentioned": True,
        })
        assert "MDRRMO-005" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_all_structure_types(self):
        for stype in ["house", "school", "church"]:
            result = _evaluate({
                "incident_type": "calamity",
                "structure_type": stype,
                "casualty_mentioned": True,
            })
            assert "MDRRMO-005" in result.triggered_rules, f"structure_type={stype} did not fire"

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({
            "incident_type": "calamity",
            "structure_type": "house",
            "casualty_mentioned": False,
        })
        assert "MDRRMO-005" not in result.triggered_rules

    def test_does_not_fire_missing_structure(self):
        result = _evaluate({
            "incident_type": "calamity",
            "casualty_mentioned": True,
        })
        assert "MDRRMO-005" not in result.triggered_rules


# =============================================================================
# MDRRMO-006: Storm/calamity, no casualty
# =============================================================================

class TestMDRRMO006:

    def test_fires_calamity_no_casualty(self):
        result = _evaluate({
            "incident_type": "calamity",
            "casualty_mentioned": False,
        })
        assert "MDRRMO-006" in result.triggered_rules
        assert result.severity == SeverityLevel.medium

    def test_does_not_fire_casualty_present(self):
        result = _evaluate({
            "incident_type": "calamity",
            "casualty_mentioned": True,
        })
        assert "MDRRMO-006" not in result.triggered_rules


# =============================================================================
# MDRRMO-007: Mass casualty medical (gte=3 + multi-agency)
# =============================================================================

class TestMDRRMO007:

    def test_fires_mass_casualty_threshold(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "injured_count": 3,
            "multi_agency_needed": True,
        })
        assert "MDRRMO-007" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_above_threshold(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "injured_count": 10,
            "multi_agency_needed": True,
        })
        assert "MDRRMO-007" in result.triggered_rules

    def test_does_not_fire_below_threshold(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "injured_count": 2,
            "multi_agency_needed": True,
        })
        assert "MDRRMO-007" not in result.triggered_rules

    def test_does_not_fire_no_multi_agency(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "injured_count": 5,
            "multi_agency_needed": False,
        })
        assert "MDRRMO-007" not in result.triggered_rules

    def test_boundary_exactly_3(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "injured_count": 3,
            "multi_agency_needed": True,
        })
        assert "MDRRMO-007" in result.triggered_rules

    def test_boundary_exactly_2_misses(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "injured_count": 2,
            "multi_agency_needed": True,
        })
        assert "MDRRMO-007" not in result.triggered_rules


# =============================================================================
# MDRRMO-008: Single critical medical patient
# =============================================================================

class TestMDRRMO008:

    def test_fires_critical_urgency(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "urgency_level": "critical",
            "multi_agency_needed": False,
        })
        assert "MDRRMO-008" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_fires_all_urgency_values(self):
        for uval in ["life-threatening", "emergency"]:
            result = _evaluate({
                "incident_type": "medical_trauma",
                "urgency_level": uval,
                "multi_agency_needed": False,
            })
            assert "MDRRMO-008" in result.triggered_rules, f"urgency_level={uval} did not fire"

    def test_does_not_fire_multi_agency_true(self):
        """multi_agency_needed=True is MDRRMO-007 territory."""
        result = _evaluate({
            "incident_type": "medical_trauma",
            "urgency_level": "critical",
            "multi_agency_needed": True,
        })
        assert "MDRRMO-008" not in result.triggered_rules

    def test_does_not_fire_unclear_urgency(self):
        """Unknown/moderate urgency is MDRRMO-009 territory."""
        result = _evaluate({
            "incident_type": "medical_trauma",
            "urgency_level": "moderate",
            "multi_agency_needed": False,
        })
        assert "MDRRMO-008" not in result.triggered_rules


# =============================================================================
# MDRRMO-009: Medical, unclear urgency
# =============================================================================

class TestMDRRMO009:

    def test_fires_unknown_urgency(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "urgency_level": "unknown",
        })
        assert "MDRRMO-009" in result.triggered_rules
        assert result.severity == SeverityLevel.medium

    def test_fires_stable_urgency(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "urgency_level": "stable",
        })
        assert "MDRRMO-009" in result.triggered_rules

    def test_does_not_fire_critical_urgency(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "urgency_level": "critical",
        })
        assert "MDRRMO-009" not in result.triggered_rules

    def test_does_not_fire_missing_urgency(self):
        result = _evaluate({"incident_type": "medical_trauma"})
        assert "MDRRMO-009" not in result.triggered_rules


# =============================================================================
# MDRRMO-010: Vehicular, multiple casualties (gte=3)
# =============================================================================

class TestMDRRMO010:

    def test_fires_vehicular_3_injured(self):
        result = _evaluate({
            "incident_type": "vehicular",
            "casualty_mentioned": True,
            "injured_count": 3,
        })
        assert "MDRRMO-010" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_does_not_fire_injured_2(self):
        """injured_count=2 < 3, so MDRRMO-010 does not fire."""
        result = _evaluate({
            "incident_type": "vehicular",
            "casualty_mentioned": True,
            "injured_count": 2,
        })
        assert "MDRRMO-010" not in result.triggered_rules

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({
            "incident_type": "vehicular",
            "casualty_mentioned": False,
            "injured_count": 5,
        })
        assert "MDRRMO-010" not in result.triggered_rules


# =============================================================================
# MDRRMO-011: Vehicular, 1-2 injuries
# =============================================================================

class TestMDRRMO011:

    def test_fires_vehicular_1_injured(self):
        result = _evaluate({
            "incident_type": "vehicular",
            "casualty_mentioned": True,
            "injured_count": 1,
        })
        assert "MDRRMO-011" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_fires_vehicular_2_injured(self):
        result = _evaluate({
            "incident_type": "vehicular",
            "casualty_mentioned": True,
            "injured_count": 2,
        })
        assert "MDRRMO-011" in result.triggered_rules

    def test_does_not_fire_injured_3(self):
        """injured_count=3 hits MDRRMO-010, not MDRRMO-011."""
        result = _evaluate({
            "incident_type": "vehicular",
            "casualty_mentioned": True,
            "injured_count": 3,
        })
        assert "MDRRMO-011" not in result.triggered_rules

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({
            "incident_type": "vehicular",
            "casualty_mentioned": False,
            "injured_count": 1,
        })
        assert "MDRRMO-011" not in result.triggered_rules

    def test_boundary_2_and_3_mutually_exclusive_for_010_011(self):
        """
        injured_count=2 → MDRRMO-011, not MDRRMO-010.
        injured_count=3 → MDRRMO-010, not MDRRMO-011.
        """
        for count, expect_011, expect_010 in [(2, True, False), (3, False, True)]:
            result = _evaluate({
                "incident_type": "vehicular",
                "casualty_mentioned": True,
                "injured_count": count,
            })
            assert ("MDRRMO-011" in result.triggered_rules) == expect_011, f"count={count}"
            assert ("MDRRMO-010" in result.triggered_rules) == expect_010, f"count={count}"


# =============================================================================
# MDRRMO-012: Vehicular, no casualty
# =============================================================================

class TestMDRRMO012:

    def test_fires_vehicular_no_casualty(self):
        result = _evaluate({
            "incident_type": "vehicular",
            "casualty_mentioned": False,
        })
        assert "MDRRMO-012" in result.triggered_rules
        assert result.severity == SeverityLevel.medium

    def test_does_not_fire_casualty_present(self):
        result = _evaluate({
            "incident_type": "vehicular",
            "casualty_mentioned": True,
        })
        assert "MDRRMO-012" not in result.triggered_rules


# =============================================================================
# MDRRMO-013: HAZMAT with casualty
# =============================================================================

class TestMDRRMO013:
    """
    Retired in taxonomy v2.0. `hazmat` was merged out of IncidentCategory when
    the Phase 4 triage model was integrated — the model has no class for it —
    so this rule's incident_type condition can no longer be satisfied by a real
    report.

    Deactivated in MDRRMO_v1.json rather than deleted: the rule_id still
    appears in triggered_rules on evaluations stored before the change. These
    tests assert the retirement holds.
    """

    def test_is_inactive_in_config(self):
        rule = _rule("MDRRMO-013")
        assert rule["active"] is False
        assert "RETIRED" in rule["description"]

    def test_does_not_fire_hazmat_with_casualty(self):
        result = _evaluate({"incident_type": "hazmat", "casualty_mentioned": True})
        assert "MDRRMO-013" not in result.triggered_rules

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({"incident_type": "hazmat", "casualty_mentioned": False})
        assert "MDRRMO-013" not in result.triggered_rules


# =============================================================================
# MDRRMO-014: HAZMAT, no casualty — RETIRED in taxonomy v2.0
# =============================================================================

class TestMDRRMO014:
    """Retired alongside MDRRMO-013. See that class for the reasoning."""

    def test_is_inactive_in_config(self):
        rule = _rule("MDRRMO-014")
        assert rule["active"] is False
        assert "RETIRED" in rule["description"]

    def test_does_not_fire_hazmat_no_casualty(self):
        result = _evaluate({"incident_type": "hazmat", "casualty_mentioned": False})
        assert "MDRRMO-014" not in result.triggered_rules

    def test_does_not_fire_casualty_present(self):
        result = _evaluate({"incident_type": "hazmat", "casualty_mentioned": True})
        assert "MDRRMO-014" not in result.triggered_rules

    def test_hazmat_now_falls_through_to_manual_review(self):
        """
        With both HAZMAT rules retired, a hazmat signal set matches nothing and
        the engine defaults to `low` with no_rules_triggered — the documented
        "flag for dispatcher manual review" path.

        Worth stating plainly for the defense: a chemical spill is not a low
        severity event. It is `low` here only because it can no longer arrive
        as a category at all. A resident reporting a leak now files it under a
        surviving category, or flags it via overlap_agencies, and the triage
        model scores that report on its own signals.
        """
        for casualty in (True, False):
            result = _evaluate({
                "incident_type": "hazmat",
                "casualty_mentioned": casualty,
            })
            assert "MDRRMO-013" not in result.triggered_rules
            assert "MDRRMO-014" not in result.triggered_rules


# =============================================================================
# MDRRMO-015: Children in calamity/medical/vehicular
# =============================================================================

class TestMDRRMO015:

    def test_fires_flood_calamity_children(self):
        result = _evaluate({
            "incident_type": "flood_landslide_calamity",
            "children_involved": True,
        })
        assert "MDRRMO-015" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_medical_children(self):
        result = _evaluate({
            "incident_type": "medical_trauma",
            "children_involved": True,
        })
        assert "MDRRMO-015" in result.triggered_rules

    def test_fires_vehicular_children(self):
        result = _evaluate({
            "incident_type": "vehicular",
            "children_involved": True,
        })
        assert "MDRRMO-015" in result.triggered_rules

    def test_does_not_fire_no_children(self):
        result = _evaluate({
            "incident_type": "flood_landslide_calamity",
            "children_involved": False,
        })
        assert "MDRRMO-015" not in result.triggered_rules

    def test_does_not_fire_wrong_incident_type(self):
        """MDRRMO-015 only covers calamity/medical/vehicular, not fire or hazmat."""
        for itype in ["fire", "hazmat", "domestic_dispute_crime"]:
            result = _evaluate({"incident_type": itype, "children_involved": True})
            assert "MDRRMO-015" not in result.triggered_rules, f"itype={itype}"

    def test_children_escalates_medium_to_critical(self):
        """
        MDRRMO-006 (calamity, no casualty) = medium.
        MDRRMO-015 requires incident_type in flood_landslide_calamity/medical_trauma/vehicular.
        Use flood_landslide_calamity which satisfies both MDRRMO-006 (calamity alias)
        and MDRRMO-015 (children). Both fire → max-aggregation → critical.
        """
        result = _evaluate({
            "incident_type": "flood_landslide_calamity",
            "casualty_mentioned": False,
            "children_involved": True,
        })
        assert "MDRRMO-015" in result.triggered_rules
        assert result.severity == SeverityLevel.critical


# =============================================================================
# MDRRMO full matrix summary
# =============================================================================

class TestMDRRMOMatrix:

    MATRIX = [
        # critical
        ({"incident_type": "flood", "casualty_mentioned": True},
         "critical", "MDRRMO-001: flood + casualty"),
        ({"incident_type": "landslide", "casualty_mentioned": True},
         "critical", "MDRRMO-002: landslide + casualty"),
        ({"incident_type": "calamity", "structure_type": "house", "casualty_mentioned": True},
         "critical", "MDRRMO-005: calamity collapse + casualty"),
        ({"incident_type": "medical_trauma", "injured_count": 3, "multi_agency_needed": True},
         "critical", "MDRRMO-007: mass casualty"),
        ({"incident_type": "vehicular", "casualty_mentioned": True, "injured_count": 3},
         "critical", "MDRRMO-010: MVA 3+ injured"),
        ({"incident_type": "vehicular", "children_involved": True},
         "critical", "MDRRMO-015: vehicular + children"),
        # high
        ({"incident_type": "landslide", "casualty_mentioned": False, "structure_type": "road"},
         "high", "MDRRMO-003: landslide road block"),
        ({"incident_type": "flood", "casualty_mentioned": False, "structure_type": "barangay"},
         "high", "MDRRMO-004: flood residential"),
        ({"incident_type": "medical_trauma", "urgency_level": "critical", "multi_agency_needed": False},
         "high", "MDRRMO-008: single critical patient"),
        ({"incident_type": "vehicular", "casualty_mentioned": True, "injured_count": 2},
         "high", "MDRRMO-011: MVA 1-2 injured"),
        # medium
        ({"incident_type": "calamity", "casualty_mentioned": False},
         "medium", "MDRRMO-006: storm no casualty"),
        ({"incident_type": "medical_trauma", "urgency_level": "moderate"},
         "medium", "MDRRMO-009: unclear urgency"),
        ({"incident_type": "vehicular", "casualty_mentioned": False},
         "medium", "MDRRMO-012: MVA no casualty"),
        # low
        ({}, "low", "empty payload"),
        ({"incident_type": "fire"}, "low", "fire type not in MDRRMO rubric"),
        # MDRRMO-013/014 retired in taxonomy v2.0 — hazmat is no longer a
        # category, so these rows now fall through to manual review.
        ({"incident_type": "hazmat", "casualty_mentioned": True},
         "low", "MDRRMO-013 retired: HAZMAT + casualty -> no match"),
        ({"incident_type": "hazmat", "casualty_mentioned": False},
         "low", "MDRRMO-014 retired: HAZMAT no casualty -> no match"),
    ]

    @pytest.mark.parametrize("signals,expected_severity,note", MATRIX)
    def test_matrix_row(self, signals, expected_severity, note):
        result = _evaluate(signals)
        assert result.severity.value == expected_severity, (
            f"Matrix FAILED — {note}: "
            f"expected={expected_severity}, got={result.severity.value}, "
            f"triggered={result.triggered_rules}"
        )
