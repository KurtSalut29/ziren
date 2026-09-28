"""
Phase 5.4 — BFP rubric test matrix.

Every BFP rule (BFP-001 through BFP-010) has:
  - A "fires" test: the minimal signal set that should trigger the rule
  - A "does not fire" test: the minimal change that should break the match
  - A severity assertion: the result matches the rule's severity_contribution

This file is also a reviewable artifact — the test names and docstrings
describe the signal combination → expected severity table readable by a
non-developer (e.g., a panel member reviewing the rubric logic).

BFP decision table (v1.0.0):
  BFP-001  fire + dead >= 1                          → critical
  BFP-002  fire + casualty=True + injured >= 1       → critical
  BFP-003  fire + fire_type structural/residential + no casualty → high
  BFP-004  fire/hazmat + multi_agency=True           → critical
  BFP-005  fire + fire_type vehicle + no casualty    → high
  BFP-006  fire + fire_type vehicle + casualty=True  → critical
  BFP-007  fire + fire_type grass/wildfire + residential/barangay structure → high
  BFP-008  fire + fire_type grass/wildfire + open_field/forest structure → medium
  BFP-009  fire + no casualty + no multi-agency (catch-all) → medium
  BFP-010  fire + children_involved=True             → critical

Run: pytest tests/test_rubric_bfp.py -v
"""

import pytest
from unittest.mock import MagicMock

from app.models.rubric import AgencyType, SeverityLevel
from app.services import rubric_service as rs


def _evaluate(signals):
    rs._config_cache.clear()
    mock_db = MagicMock()
    mock_db.table.return_value.select.return_value \
        .eq.return_value.eq.return_value \
        .limit.return_value.execute.return_value.data = []
    mock_db.table.return_value.insert.return_value.execute.return_value.data = [{"id": "x"}]
    return rs.evaluate(signals, AgencyType.BFP, db=mock_db)


# =============================================================================
# BFP-001: Structure fire with confirmed fatalities
# =============================================================================

class TestBFP001:

    def test_fires_with_dead_count_1(self):
        """fire + dead_count=1 → BFP-001 fires, severity=critical."""
        result = _evaluate({"incident_type": "fire", "dead_count": 1})
        assert "BFP-001" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_with_dead_count_5(self):
        """dead_count=5 still satisfies gte=1."""
        result = _evaluate({"incident_type": "fire", "dead_count": 5})
        assert "BFP-001" in result.triggered_rules

    def test_does_not_fire_dead_count_0(self):
        """dead_count=0 does NOT satisfy gte=1."""
        result = _evaluate({"incident_type": "fire", "dead_count": 0})
        assert "BFP-001" not in result.triggered_rules

    def test_does_not_fire_dead_count_missing(self):
        """Missing dead_count → treated as None → does NOT satisfy gte=1."""
        result = _evaluate({"incident_type": "fire"})
        assert "BFP-001" not in result.triggered_rules

    def test_does_not_fire_wrong_incident_type(self):
        """incident_type='flood' with dead_count=1 does not trigger BFP-001."""
        result = _evaluate({"incident_type": "flood", "dead_count": 1})
        assert "BFP-001" not in result.triggered_rules


# =============================================================================
# BFP-002: Structure fire with confirmed injuries (no fatalities)
# =============================================================================

class TestBFP002:

    def test_fires_with_casualty_and_injured_count_1(self):
        """fire + casualty=True + injured_count=1 → BFP-002, critical."""
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": True,
            "injured_count": 1,
        })
        assert "BFP-002" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_with_high_injured_count(self):
        """injured_count=10 still satisfies gte=1."""
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": True,
            "injured_count": 10,
        })
        assert "BFP-002" in result.triggered_rules

    def test_does_not_fire_casualty_false(self):
        """casualty_mentioned=False prevents BFP-002 even with injured count."""
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": False,
            "injured_count": 3,
        })
        assert "BFP-002" not in result.triggered_rules

    def test_does_not_fire_injured_count_zero(self):
        """injured_count=0 does NOT satisfy gte=1."""
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": True,
            "injured_count": 0,
        })
        assert "BFP-002" not in result.triggered_rules

    def test_does_not_fire_injured_count_missing(self):
        """injured_count=None does NOT satisfy gte=1."""
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": True,
        })
        assert "BFP-002" not in result.triggered_rules


# =============================================================================
# BFP-003: Structural/residential fire, no casualties
# =============================================================================

class TestBFP003:

    def test_fires_structural_fire_no_casualty(self):
        """fire + fire_type=structural + casualty=False → BFP-003, high."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "structural",
            "casualty_mentioned": False,
        })
        assert "BFP-003" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_fires_residential_fire_no_casualty(self):
        """fire_type=residential also satisfies the any-of list."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "residential",
            "casualty_mentioned": False,
        })
        assert "BFP-003" in result.triggered_rules

    def test_does_not_fire_casualty_true(self):
        """BFP-003 requires casualty=False — casualty=True breaks the match."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "structural",
            "casualty_mentioned": True,
        })
        assert "BFP-003" not in result.triggered_rules

    def test_does_not_fire_wrong_fire_type(self):
        """fire_type=vehicle does not satisfy structural/residential list."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "vehicle",
            "casualty_mentioned": False,
        })
        assert "BFP-003" not in result.triggered_rules

    def test_does_not_fire_missing_fire_type(self):
        """fire_type=None does not satisfy the any-of list."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": None,
            "casualty_mentioned": False,
        })
        assert "BFP-003" not in result.triggered_rules


# =============================================================================
# BFP-004: HAZMAT/fire with multi-agency flag
# =============================================================================

class TestBFP004:

    def test_fires_fire_multi_agency(self):
        """fire + multi_agency_needed=True → BFP-004, critical."""
        result = _evaluate({"incident_type": "fire", "multi_agency_needed": True})
        assert "BFP-004" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_hazmat_multi_agency(self):
        """incident_type=hazmat also in the any-of list."""
        result = _evaluate({"incident_type": "hazmat", "multi_agency_needed": True})
        assert "BFP-004" in result.triggered_rules

    def test_does_not_fire_multi_agency_false(self):
        """multi_agency_needed=False prevents BFP-004."""
        result = _evaluate({"incident_type": "fire", "multi_agency_needed": False})
        assert "BFP-004" not in result.triggered_rules

    def test_does_not_fire_wrong_incident_type(self):
        """incident_type=flood with multi_agency does not trigger BFP-004."""
        result = _evaluate({"incident_type": "flood", "multi_agency_needed": True})
        assert "BFP-004" not in result.triggered_rules


# =============================================================================
# BFP-005: Vehicle fire, no casualties
# =============================================================================

class TestBFP005:

    def test_fires_vehicle_fire_no_casualty(self):
        """fire + fire_type=vehicle + casualty=False → BFP-005, high."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "vehicle",
            "casualty_mentioned": False,
        })
        assert "BFP-005" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_does_not_fire_casualty_true(self):
        """casualty=True shifts to BFP-006 territory; BFP-005 requires False."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "vehicle",
            "casualty_mentioned": True,
        })
        assert "BFP-005" not in result.triggered_rules

    def test_does_not_fire_non_vehicle_fire_type(self):
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "structural",
            "casualty_mentioned": False,
        })
        assert "BFP-005" not in result.triggered_rules


# =============================================================================
# BFP-006: Vehicle fire with injuries
# =============================================================================

class TestBFP006:

    def test_fires_vehicle_fire_with_casualty(self):
        """fire + fire_type=vehicle + casualty=True → BFP-006, critical."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "vehicle",
            "casualty_mentioned": True,
        })
        assert "BFP-006" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "vehicle",
            "casualty_mentioned": False,
        })
        assert "BFP-006" not in result.triggered_rules


# =============================================================================
# BFP-007: Wildfire near residential / barangay
# =============================================================================

class TestBFP007:

    def test_fires_grass_fire_near_barangay(self):
        """fire + fire_type=grass + structure=barangay → BFP-007, high."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "grass",
            "structure_type": "barangay",
        })
        assert "BFP-007" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_fires_wildfire_near_residential(self):
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "wildfire",
            "structure_type": "residential_area",
        })
        assert "BFP-007" in result.triggered_rules

    def test_does_not_fire_open_field_structure(self):
        """Open field is in BFP-008's list, not BFP-007's."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "grass",
            "structure_type": "open_field",
        })
        assert "BFP-007" not in result.triggered_rules

    def test_does_not_fire_missing_structure_type(self):
        """structure_type=None → does not satisfy the any-of list."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "grass",
        })
        assert "BFP-007" not in result.triggered_rules


# =============================================================================
# BFP-008: Grass fire in open field / forest
# =============================================================================

class TestBFP008:

    def test_fires_grass_fire_open_field(self):
        """fire + fire_type=grass + structure=open_field → BFP-008, medium."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "grass",
            "structure_type": "open_field",
        })
        assert "BFP-008" in result.triggered_rules
        assert result.severity == SeverityLevel.medium

    def test_fires_wildfire_forest(self):
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "wildfire",
            "structure_type": "forest",
        })
        assert "BFP-008" in result.triggered_rules

    def test_does_not_fire_residential_structure(self):
        """Residential structure is in BFP-007's list."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "grass",
            "structure_type": "barangay",
        })
        assert "BFP-008" not in result.triggered_rules


# =============================================================================
# BFP-009: Fire catch-all (no escalating signals)
# =============================================================================

class TestBFP009:

    def test_fires_fire_no_escalating_signals(self):
        """fire + no casualty + no multi-agency → BFP-009, medium."""
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": False,
            "multi_agency_needed": False,
        })
        assert "BFP-009" in result.triggered_rules
        assert result.severity == SeverityLevel.medium

    def test_fires_fire_with_unknown_fire_type(self):
        """fire_type unknown + no casualty → BFP-009 still fires (catch-all)."""
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "unknown_type",
            "casualty_mentioned": False,
            "multi_agency_needed": False,
        })
        assert "BFP-009" in result.triggered_rules

    def test_does_not_fire_casualty_true(self):
        """BFP-009 requires casualty=False."""
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": True,
            "multi_agency_needed": False,
        })
        assert "BFP-009" not in result.triggered_rules

    def test_does_not_fire_multi_agency_true(self):
        """BFP-009 requires multi_agency_needed=False."""
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": False,
            "multi_agency_needed": True,
        })
        assert "BFP-009" not in result.triggered_rules

    def test_incident_type_missing_does_not_fire(self):
        """BFP-009 requires incident_type in ['fire']."""
        result = _evaluate({
            "casualty_mentioned": False,
            "multi_agency_needed": False,
        })
        assert "BFP-009" not in result.triggered_rules


# =============================================================================
# BFP-010: Fire with children involved
# =============================================================================

class TestBFP010:

    def test_fires_fire_children_involved(self):
        """fire + children_involved=True → BFP-010, critical."""
        result = _evaluate({"incident_type": "fire", "children_involved": True})
        assert "BFP-010" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_does_not_fire_children_not_involved(self):
        result = _evaluate({"incident_type": "fire", "children_involved": False})
        assert "BFP-010" not in result.triggered_rules

    def test_does_not_fire_children_missing(self):
        """Missing children_involved → defaults to False → does not fire."""
        result = _evaluate({"incident_type": "fire"})
        assert "BFP-010" not in result.triggered_rules

    def test_children_escalates_medium_to_critical(self):
        """
        BFP-009 (medium) + BFP-010 (critical) both fire.
        Max-aggregation → critical wins.
        """
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": False,
            "multi_agency_needed": False,
            "children_involved": True,
        })
        assert "BFP-009" in result.triggered_rules
        assert "BFP-010" in result.triggered_rules
        assert result.severity == SeverityLevel.critical


# =============================================================================
# BFP full matrix summary test
# =============================================================================

class TestBFPMatrix:
    """
    Compact matrix covering every severity level at least once per path.
    Signal combination → expected severity.
    Reviewable as a single table for the defense.

    Row format: (signals_dict, expected_severity, note)
    """

    MATRIX = [
        # critical paths
        ({"incident_type": "fire", "dead_count": 2},
         "critical", "BFP-001: fatality"),
        ({"incident_type": "fire", "casualty_mentioned": True, "injured_count": 1},
         "critical", "BFP-002: injuries"),
        ({"incident_type": "fire", "multi_agency_needed": True},
         "critical", "BFP-004: multi-agency"),
        ({"incident_type": "fire", "fire_type": "vehicle", "casualty_mentioned": True},
         "critical", "BFP-006: vehicle fire + casualty"),
        ({"incident_type": "fire", "children_involved": True},
         "critical", "BFP-010: children present"),
        # high paths
        ({"incident_type": "fire", "fire_type": "structural", "casualty_mentioned": False},
         "high", "BFP-003: structural, no casualty"),
        ({"incident_type": "fire", "fire_type": "vehicle", "casualty_mentioned": False},
         "high", "BFP-005: vehicle fire, no casualty"),
        ({"incident_type": "fire", "fire_type": "grass", "structure_type": "barangay"},
         "high", "BFP-007: grass near residential"),
        # medium paths
        ({"incident_type": "fire", "fire_type": "grass", "structure_type": "open_field"},
         "medium", "BFP-008: open-field grass fire"),
        ({"incident_type": "fire", "casualty_mentioned": False, "multi_agency_needed": False},
         "medium", "BFP-009: catch-all fire"),
        # low paths
        ({"incident_type": "completely_unknown"},
         "low", "no rules fire"),
        ({},
         "low", "empty payload"),
    ]

    @pytest.mark.parametrize("signals,expected_severity,note", MATRIX)
    def test_matrix_row(self, signals, expected_severity, note):
        result = _evaluate(signals)
        assert result.severity.value == expected_severity, (
            f"Matrix row FAILED — {note}: "
            f"expected={expected_severity}, got={result.severity.value}, "
            f"triggered={result.triggered_rules}"
        )
