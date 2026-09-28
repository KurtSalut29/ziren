"""
Phase 5.4 — PNP rubric test matrix.

Every PNP rule (PNP-001 through PNP-012) has:
  - A "fires" test: the minimal signal set that triggers the rule
  - A "does not fire" test: the minimal change that breaks the match
  - A severity assertion

PNP decision table (v2.0.0):
  PNP-001  weapon=True + dead >= 1                               → critical
  PNP-002  weapon=True + type firearm + casualty=True            → critical
  PNP-003  weapon=True + type bladed + casualty=True             → high
  PNP-004  weapon=True + casualty=False                          → high
  PNP-005  domestic_dispute_crime + weapon=True + children=True  → critical
  PNP-006  domestic_dispute_crime + casualty=True + weapon=False → high
  PNP-007  domestic_dispute_crime + casualty=False + weapon=False → medium
  PNP-008  crime + why_category robbery/assault + casualty=True  → critical
  PNP-009  crime + why_category robbery/assault + casualty=False → high
  PNP-010  RETIRED v2.0.0 — missing_person merged out of taxonomy
  PNP-011  RETIRED v2.0.0 — missing_person merged out of taxonomy
  PNP-012  crime + weapon=True + multi_agency=True               → critical

Run: pytest tests/test_rubric_pnp.py -v
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
    "app", "rubric_configs", "PNP_v1.json",
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
    return rs.evaluate(signals, AgencyType.PNP, db=mock_db)


# =============================================================================
# PNP-001: Weapon + confirmed fatality
# =============================================================================

class TestPNP001:

    def test_fires_weapon_and_death(self):
        result = _evaluate({"weapon_mentioned": True, "dead_count": 1})
        assert "PNP-001" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_high_dead_count(self):
        result = _evaluate({"weapon_mentioned": True, "dead_count": 3})
        assert "PNP-001" in result.triggered_rules

    def test_does_not_fire_dead_count_zero(self):
        result = _evaluate({"weapon_mentioned": True, "dead_count": 0})
        assert "PNP-001" not in result.triggered_rules

    def test_does_not_fire_no_weapon(self):
        result = _evaluate({"weapon_mentioned": False, "dead_count": 1})
        assert "PNP-001" not in result.triggered_rules

    def test_does_not_fire_missing_dead_count(self):
        result = _evaluate({"weapon_mentioned": True})
        assert "PNP-001" not in result.triggered_rules


# =============================================================================
# PNP-002: Firearm + casualty
# =============================================================================

class TestPNP002:

    def test_fires_firearm_with_casualty(self):
        result = _evaluate({
            "weapon_mentioned": True,
            "weapon_type": "firearm",
            "casualty_mentioned": True,
        })
        assert "PNP-002" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_all_firearm_vocabulary(self):
        for wtype in ["baril", "gun", "pistol", "rifle"]:
            result = _evaluate({
                "weapon_mentioned": True,
                "weapon_type": wtype,
                "casualty_mentioned": True,
            })
            assert "PNP-002" in result.triggered_rules, f"weapon_type={wtype} did not fire PNP-002"

    def test_does_not_fire_bladed_weapon(self):
        """Bladed weapons are handled by PNP-003, not PNP-002."""
        result = _evaluate({
            "weapon_mentioned": True,
            "weapon_type": "bolo",
            "casualty_mentioned": True,
        })
        assert "PNP-002" not in result.triggered_rules

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({
            "weapon_mentioned": True,
            "weapon_type": "firearm",
            "casualty_mentioned": False,
        })
        assert "PNP-002" not in result.triggered_rules

    def test_does_not_fire_weapon_mentioned_false(self):
        result = _evaluate({
            "weapon_mentioned": False,
            "weapon_type": "firearm",
            "casualty_mentioned": True,
        })
        assert "PNP-002" not in result.triggered_rules


# =============================================================================
# PNP-003: Bladed weapon + casualty (high, not critical)
# =============================================================================

class TestPNP003:

    def test_fires_bolo_with_casualty(self):
        result = _evaluate({
            "weapon_mentioned": True,
            "weapon_type": "bolo",
            "casualty_mentioned": True,
        })
        assert "PNP-003" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_fires_all_bladed_vocabulary(self):
        for wtype in ["knife", "itak", "bladed", "sundang"]:
            result = _evaluate({
                "weapon_mentioned": True,
                "weapon_type": wtype,
                "casualty_mentioned": True,
            })
            assert "PNP-003" in result.triggered_rules, f"weapon_type={wtype} did not fire PNP-003"

    def test_firearm_does_not_fire_pnp003(self):
        result = _evaluate({
            "weapon_mentioned": True,
            "weapon_type": "firearm",
            "casualty_mentioned": True,
        })
        assert "PNP-003" not in result.triggered_rules

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({
            "weapon_mentioned": True,
            "weapon_type": "bolo",
            "casualty_mentioned": False,
        })
        assert "PNP-003" not in result.triggered_rules


# =============================================================================
# PNP-004: Weapon present, no casualty (preventive)
# =============================================================================

class TestPNP004:

    def test_fires_weapon_no_casualty(self):
        result = _evaluate({"weapon_mentioned": True, "casualty_mentioned": False})
        assert "PNP-004" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_does_not_fire_with_casualty(self):
        """casualty=True means PNP-002/003 territory, not PNP-004."""
        result = _evaluate({"weapon_mentioned": True, "casualty_mentioned": True})
        assert "PNP-004" not in result.triggered_rules

    def test_does_not_fire_no_weapon(self):
        result = _evaluate({"weapon_mentioned": False, "casualty_mentioned": False})
        assert "PNP-004" not in result.triggered_rules

    def test_pnp004_and_pnp001_cannot_both_fire(self):
        """
        PNP-001 requires dead_count>=1.
        PNP-004 requires casualty=False.
        If dead_count>=1 and casualty=True, PNP-004 does not fire.
        """
        result = _evaluate({
            "weapon_mentioned": True,
            "dead_count": 1,
            "casualty_mentioned": True,
        })
        assert "PNP-001" in result.triggered_rules
        assert "PNP-004" not in result.triggered_rules


# =============================================================================
# PNP-005: Domestic dispute, weapon, children
# =============================================================================

class TestPNP005:

    def test_fires_domestic_dispute_weapon_children(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "weapon_mentioned": True,
            "children_involved": True,
        })
        assert "PNP-005" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_domestic_dispute_alias(self):
        """incident_type='domestic_dispute' also in the any-of list."""
        result = _evaluate({
            "incident_type": "domestic_dispute",
            "weapon_mentioned": True,
            "children_involved": True,
        })
        assert "PNP-005" in result.triggered_rules

    def test_does_not_fire_no_children(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "weapon_mentioned": True,
            "children_involved": False,
        })
        assert "PNP-005" not in result.triggered_rules

    def test_does_not_fire_no_weapon(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "weapon_mentioned": False,
            "children_involved": True,
        })
        assert "PNP-005" not in result.triggered_rules


# =============================================================================
# PNP-006: Domestic dispute, casualty, no weapon
# =============================================================================

class TestPNP006:

    def test_fires_domestic_dispute_casualty_no_weapon(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "casualty_mentioned": True,
            "weapon_mentioned": False,
        })
        assert "PNP-006" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_does_not_fire_weapon_present(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "casualty_mentioned": True,
            "weapon_mentioned": True,
        })
        assert "PNP-006" not in result.triggered_rules

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "casualty_mentioned": False,
            "weapon_mentioned": False,
        })
        assert "PNP-006" not in result.triggered_rules


# =============================================================================
# PNP-007: Domestic dispute, no casualty, no weapon
# =============================================================================

class TestPNP007:

    def test_fires_domestic_dispute_no_casualty_no_weapon(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "casualty_mentioned": False,
            "weapon_mentioned": False,
        })
        assert "PNP-007" in result.triggered_rules
        assert result.severity == SeverityLevel.medium

    def test_does_not_fire_casualty_present(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "casualty_mentioned": True,
            "weapon_mentioned": False,
        })
        assert "PNP-007" not in result.triggered_rules

    def test_does_not_fire_weapon_present(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "casualty_mentioned": False,
            "weapon_mentioned": True,
        })
        assert "PNP-007" not in result.triggered_rules


# =============================================================================
# PNP-008: Crime in progress, casualty
# =============================================================================

class TestPNP008:

    def test_fires_robbery_with_casualty(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "why_category": "robbery",
            "casualty_mentioned": True,
        })
        assert "PNP-008" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_fires_all_why_categories(self):
        for cat in ["assault", "holdup", "pangingikil"]:
            result = _evaluate({
                "incident_type": "domestic_dispute_crime",
                "why_category": cat,
                "casualty_mentioned": True,
            })
            assert "PNP-008" in result.triggered_rules, f"why_category={cat} did not fire PNP-008"

    def test_fires_crime_incident_type_alias(self):
        result = _evaluate({
            "incident_type": "crime",
            "why_category": "robbery",
            "casualty_mentioned": True,
        })
        assert "PNP-008" in result.triggered_rules

    def test_does_not_fire_no_casualty(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "why_category": "robbery",
            "casualty_mentioned": False,
        })
        assert "PNP-008" not in result.triggered_rules

    def test_does_not_fire_unknown_why_category(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "why_category": "unknown_crime",
            "casualty_mentioned": True,
        })
        assert "PNP-008" not in result.triggered_rules


# =============================================================================
# PNP-009: Crime in progress, no casualty
# =============================================================================

class TestPNP009:

    def test_fires_robbery_no_casualty(self):
        result = _evaluate({
            "incident_type": "crime",
            "why_category": "holdup",
            "casualty_mentioned": False,
        })
        assert "PNP-009" in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_does_not_fire_casualty_present(self):
        result = _evaluate({
            "incident_type": "crime",
            "why_category": "holdup",
            "casualty_mentioned": True,
        })
        assert "PNP-009" not in result.triggered_rules


# =============================================================================
# PNP-010: Missing child
# =============================================================================

class TestPNP010:
    """
    Retired in taxonomy v2.0. `missing_person` was merged out of
    IncidentCategory when the Phase 4 triage model was integrated — the model
    has no class for it — so this rule's incident_type condition can no longer
    be satisfied by a real report.

    The rule is deactivated in PNP_v1.json rather than deleted, because its
    rule_id still appears in triggered_rules on evaluations stored before the
    change. These tests assert the retirement holds: they are what would catch
    a merge that quietly reactivates it.
    """

    def test_is_inactive_in_config(self):
        rule = _rule("PNP-010")
        assert rule["active"] is False
        assert "RETIRED" in rule["description"]

    def test_does_not_fire_for_missing_child(self):
        result = _evaluate({
            "incident_type": "missing_person",
            "children_involved": True,
        })
        assert "PNP-010" not in result.triggered_rules

    def test_does_not_fire_missing_adult(self):
        result = _evaluate({
            "incident_type": "missing_person",
            "children_involved": False,
        })
        assert "PNP-010" not in result.triggered_rules


# =============================================================================
# PNP-011: Missing adult — RETIRED in taxonomy v2.0
# =============================================================================

class TestPNP011:
    """Retired alongside PNP-010. See that class for the reasoning."""

    def test_is_inactive_in_config(self):
        rule = _rule("PNP-011")
        assert rule["active"] is False
        assert "RETIRED" in rule["description"]

    def test_does_not_fire_missing_adult(self):
        result = _evaluate({
            "incident_type": "missing_person",
            "children_involved": False,
        })
        assert "PNP-011" not in result.triggered_rules

    def test_does_not_fire_missing_child(self):
        result = _evaluate({
            "incident_type": "missing_person",
            "children_involved": True,
        })
        assert "PNP-011" not in result.triggered_rules

    def test_missing_person_now_falls_through_to_manual_review(self):
        """
        With both missing-person rules retired, a missing_person signal set
        matches nothing and the engine defaults to `low` with
        no_rules_triggered — the documented "flag for dispatcher manual
        review" path. That fall-through is the intended behaviour, not a gap:
        the resident can no longer file this as a category at all, so any such
        signals reaching the rubric came from somewhere unexpected and a human
        should look at them.
        """
        for children in (True, False):
            result = _evaluate({
                "incident_type": "missing_person",
                "children_involved": children,
            })
            assert result.triggered_rules == []
            assert result.no_rules_triggered is True
            assert result.severity == SeverityLevel.low


# =============================================================================
# PNP-012: Crowd disorder with weapons + multi-agency
# =============================================================================

class TestPNP012:

    def test_fires_crime_weapon_multi_agency(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "weapon_mentioned": True,
            "multi_agency_needed": True,
        })
        assert "PNP-012" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_does_not_fire_no_multi_agency(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "weapon_mentioned": True,
            "multi_agency_needed": False,
        })
        assert "PNP-012" not in result.triggered_rules

    def test_does_not_fire_no_weapon(self):
        result = _evaluate({
            "incident_type": "domestic_dispute_crime",
            "weapon_mentioned": False,
            "multi_agency_needed": True,
        })
        assert "PNP-012" not in result.triggered_rules


# =============================================================================
# PNP full matrix summary
# =============================================================================

class TestPNPMatrix:

    MATRIX = [
        # critical
        ({"weapon_mentioned": True, "dead_count": 1},
         "critical", "PNP-001: weapon + death"),
        ({"weapon_mentioned": True, "weapon_type": "firearm", "casualty_mentioned": True},
         "critical", "PNP-002: firearm + casualty"),
        ({"incident_type": "domestic_dispute_crime", "weapon_mentioned": True, "children_involved": True},
         "critical", "PNP-005: DV weapon + children"),
        ({"incident_type": "crime", "why_category": "robbery", "casualty_mentioned": True},
         "critical", "PNP-008: robbery + casualty"),
        ({"incident_type": "domestic_dispute_crime", "weapon_mentioned": True, "multi_agency_needed": True},
         "critical", "PNP-012: crowd weapon multi-agency"),
        # high
        ({"weapon_mentioned": True, "weapon_type": "bolo", "casualty_mentioned": True},
         "high", "PNP-003: bladed + casualty"),
        ({"weapon_mentioned": True, "casualty_mentioned": False},
         "high", "PNP-004: weapon no casualty"),
        ({"incident_type": "domestic_dispute_crime", "casualty_mentioned": True, "weapon_mentioned": False},
         "high", "PNP-006: DV casualty no weapon"),
        ({"incident_type": "crime", "why_category": "holdup", "casualty_mentioned": False},
         "high", "PNP-009: crime no casualty"),
        # medium
        ({"incident_type": "domestic_dispute_crime", "casualty_mentioned": False, "weapon_mentioned": False},
         "medium", "PNP-007: DV no casualty no weapon"),
        # low
        ({}, "low", "empty payload"),
        ({"incident_type": "fire"}, "low", "fire type in PNP rubric → no match"),
        # PNP-010/011 retired in taxonomy v2.0 — missing_person is no longer a
        # category, so these rows now fall through to manual review.
        ({"incident_type": "missing_person", "children_involved": True},
         "low", "PNP-010 retired: missing child → no match"),
        ({"incident_type": "missing_person", "children_involved": False},
         "low", "PNP-011 retired: missing adult → no match"),
    ]

    @pytest.mark.parametrize("signals,expected_severity,note", MATRIX)
    def test_matrix_row(self, signals, expected_severity, note):
        result = _evaluate(signals)
        assert result.severity.value == expected_severity, (
            f"Matrix FAILED — {note}: "
            f"expected={expected_severity}, got={result.severity.value}, "
            f"triggered={result.triggered_rules}"
        )
