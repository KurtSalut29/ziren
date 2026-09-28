"""
Phase 5.4 — Rubric engine-level tests.

Tests the evaluation engine mechanics independent of any specific agency's
rule content. These tests verify:
  - Null / missing signals (engine must not crash or silently mismatch)
  - Conflicting signals (e.g., casualty_mentioned=True but injured_count=0)
  - Boundary conditions between severity levels
  - Signal source swapping (dict vs ExtractedSignals vs any object)
  - max-of-triggered-rules aggregation correctness
  - No-rules-triggered → low + flag
  - Cache invalidation
  - Known-scenario placeholder class (skips until Kurt fills in TODO values)

All tests use the BFP seed config via load_seed_config() so they are
independent of DB state. The engine is called directly — no HTTP layer.

Run: pytest tests/test_rubric_engine.py -v
"""

import pytest
from unittest.mock import MagicMock, patch

from app.models.rubric import AgencyType, SeverityLevel
from app.models.incident import ExtractedSignals
from app.services import rubric_service as rs
from app.services.rubric_traceability import KNOWN_SCENARIOS, load_seed_config


# ── Shared mock DB (returns no active config → seed fallback path) ────────────

def _mock_db_no_active_config():
    """DB mock that simulates no active config in DB for any agency."""
    mock = MagicMock()
    # table().select().eq().eq().limit().execute() → empty
    mock.table.return_value.select.return_value \
        .eq.return_value.eq.return_value \
        .limit.return_value.execute.return_value.data = []
    # table().insert().execute() → dummy row (audit log write)
    mock.table.return_value.insert.return_value.execute.return_value.data = [{"id": "x"}]
    return mock


def _evaluate(signals, agency_type=AgencyType.BFP, mock_db=None):
    """Helper: evaluate with cache cleared and mocked DB."""
    rs._config_cache.clear()
    db = mock_db or _mock_db_no_active_config()
    return rs.evaluate(signals, agency_type, db=db)


# =============================================================================
# 1. Null / missing signal tests
# =============================================================================

class TestNullAndMissingSignals:
    """
    The engine must handle incomplete signal payloads gracefully.
    Missing signals default to their zero/False/None equivalent.
    No crash, no silent mismatch.
    """

    def test_completely_empty_payload_returns_low(self):
        """An empty signal dict fires no rules → severity=low, flagged."""
        result = _evaluate({})
        assert result.severity == SeverityLevel.low
        assert result.no_rules_triggered is True

    def test_none_values_payload_returns_low(self):
        """All-None payload should behave same as empty."""
        result = _evaluate({
            "incident_type": None,
            "fire_type": None,
            "casualty_mentioned": None,
            "injured_count": None,
            "dead_count": None,
            "weapon_mentioned": None,
            "weapon_type": None,
            "why_category": None,
            "how_category": None,
            "structure_type": None,
            "children_involved": None,
            "urgency_level": None,
            "location_specificity": None,
            "multi_agency_needed": None,
            "language_detected": None,
        })
        assert result.severity == SeverityLevel.low
        assert result.no_rules_triggered is True

    def test_incident_type_present_other_fields_null(self):
        """
        incident_type='fire' without casualties/weapon/etc fires the
        catch-all BFP-009 rule (fire, no casualties, no multi-agency).
        casualty_mentioned defaults to False when absent → BFP-009 matches.
        """
        result = _evaluate({"incident_type": "fire"})
        assert result.severity == SeverityLevel.medium
        assert "BFP-009" in result.triggered_rules
        assert result.no_rules_triggered is False

    def test_casualty_true_but_injured_count_missing(self):
        """
        casualty_mentioned=True but injured_count not provided.
        BFP-002 requires injured_count_gte=1 — missing count means None,
        which should NOT satisfy >= 1. BFP-002 must not fire.
        BFP-009 requires casualty_mentioned=False — so it also doesn't fire.
        Only BFP-010 is irrelevant (no children). Result: no rules fire.
        """
        result = _evaluate({"incident_type": "fire", "casualty_mentioned": True})
        # BFP-002 needs injured_count >= 1 — not provided, so should NOT fire
        assert "BFP-002" not in result.triggered_rules
        # BFP-009 needs casualty_mentioned=False — doesn't fire
        assert "BFP-009" not in result.triggered_rules

    def test_dead_count_zero_not_gte_one(self):
        """dead_count=0 must NOT satisfy dead_count_gte=1 (BFP-001)."""
        result = _evaluate({
            "incident_type": "fire",
            "dead_count": 0,
        })
        assert "BFP-001" not in result.triggered_rules

    def test_dead_count_none_not_gte_one(self):
        """dead_count=None must NOT satisfy dead_count_gte=1."""
        result = _evaluate({
            "incident_type": "fire",
            "dead_count": None,
        })
        assert "BFP-001" not in result.triggered_rules

    def test_unknown_signal_keys_ignored(self):
        """Extra keys in the signal dict are silently ignored."""
        result = _evaluate({
            "incident_type": "fire",
            "nonexistent_signal": "some_value",
            "another_unknown": 42,
        })
        # Should still evaluate fire catch-all without crashing
        assert result is not None

    def test_sos_style_payload_no_wizard_category(self):
        """
        SOS reports have no incident_category, no wizard_answers.
        The engine should run against whatever signals exist.
        An SOS with no signals fires no BFP rules → low.
        """
        sos_signals = {
            "incident_type": None,
            "casualty_mentioned": False,
            "injured_count": None,
            "dead_count": None,
            "weapon_mentioned": False,
            "children_involved": False,
            "multi_agency_needed": False,
            "urgency_level": None,
        }
        result = _evaluate(sos_signals)
        assert result.severity == SeverityLevel.low
        assert result.no_rules_triggered is True


# =============================================================================
# 2. Conflicting signal tests
# =============================================================================

class TestConflictingSignals:
    """
    Signal payloads can be internally inconsistent (reporter provided
    contradictory information). The engine must evaluate rules deterministically
    without crashing — rules either match their conditions or they don't.
    """

    def test_casualty_true_but_casualty_false_in_separate_fields(self):
        """
        casualty_mentioned=True but dead_count=0 and injured_count=0.
        Rules requiring specific counts won't fire; rules checking only the
        boolean flag will. Engine must not raise.
        """
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": True,
            "dead_count": 0,
            "injured_count": 0,
        })
        assert result is not None
        # BFP-001 (dead >= 1): should NOT fire
        assert "BFP-001" not in result.triggered_rules
        # BFP-002 (injured >= 1): should NOT fire
        assert "BFP-002" not in result.triggered_rules

    def test_weapon_mentioned_false_but_weapon_type_set(self):
        """
        weapon_type set but weapon_mentioned=False.
        PNP rules that require weapon_mentioned=True should not fire.
        """
        result = _evaluate(
            {"weapon_mentioned": False, "weapon_type": "firearm", "incident_type": "domestic_dispute_crime"},
            agency_type=AgencyType.PNP,
        )
        # PNP-001 requires weapon_mentioned=True → must not fire
        assert "PNP-001" not in result.triggered_rules
        # PNP-002 requires weapon_mentioned=True → must not fire
        assert "PNP-002" not in result.triggered_rules

    def test_injured_count_above_and_below_threshold_simultaneously(self):
        """
        injured_count=2: satisfies lte=2 (MDRRMO-011) but not gte=3 (MDRRMO-010).
        Both rules also require casualty_mentioned=True. Both require vehicular.
        Only MDRRMO-011 should fire.
        """
        result = _evaluate(
            {
                "incident_type": "vehicular",
                "casualty_mentioned": True,
                "injured_count": 2,
            },
            agency_type=AgencyType.MDRRMO,
        )
        assert "MDRRMO-011" in result.triggered_rules
        assert "MDRRMO-010" not in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_multi_agency_true_and_false_signals(self):
        """
        multi_agency_needed=True should trigger BFP-004 (HAZMAT/fire + multi-agency).
        multi_agency_needed=False should NOT trigger it.
        """
        result_true = _evaluate({"incident_type": "fire", "multi_agency_needed": True})
        assert "BFP-004" in result_true.triggered_rules
        assert result_true.severity == SeverityLevel.critical

        result_false = _evaluate({"incident_type": "fire", "multi_agency_needed": False})
        assert "BFP-004" not in result_false.triggered_rules


# =============================================================================
# 3. Aggregation: max-of-triggered-rules
# =============================================================================

class TestMaxAggregation:
    """
    Verify that when multiple rules fire, the maximum severity wins.
    This is the core aggregation rule — conservative for life safety.
    """

    def test_medium_and_critical_both_fire_result_is_critical(self):
        """
        BFP-009 (medium: fire, no casualty, no multi) and
        BFP-010 (critical: fire + children) both match this payload.
        Result must be critical, not medium.
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

    def test_high_and_critical_both_fire_result_is_critical(self):
        """
        BFP-003 (high: structural fire no casualty) and
        BFP-010 (critical: fire + children) both fire.
        Result: critical.
        """
        result = _evaluate({
            "incident_type": "fire",
            "fire_type": "structural",
            "casualty_mentioned": False,
            "children_involved": True,
        })
        assert result.severity == SeverityLevel.critical

    def test_only_medium_rules_fire_result_is_medium(self):
        """When only medium-severity rules fire, result is medium."""
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": False,
            "multi_agency_needed": False,
            "children_involved": False,
        })
        assert result.severity == SeverityLevel.medium
        assert "BFP-009" in result.triggered_rules

    def test_all_signals_null_no_rules_triggered_is_low(self):
        """Zero rules fired → severity=low, no_rules_triggered=True."""
        result = _evaluate({"incident_type": "completely_unknown_type"})
        assert result.severity == SeverityLevel.low
        assert result.no_rules_triggered is True
        assert result.triggered_rules == []

    def test_recommended_agencies_ordered_by_severity(self):
        """
        When multiple rules fire with different severities, the
        recommended_agencies list should start with the agency recommended
        by the highest-severity rule.
        """
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": False,
            "multi_agency_needed": False,
            "children_involved": True,   # BFP-010 critical → BFP
        })
        assert len(result.recommended_agencies) >= 1
        assert result.recommended_agencies[0] == AgencyType.BFP


# =============================================================================
# 4. Boundary conditions between severity levels
# =============================================================================

class TestBoundaryConditions:
    """
    Tests that sit exactly at the numeric boundaries defined in conditions.
    injured_count=3 is the boundary for MDRRMO-010 (gte=3) vs MDRRMO-011 (lte=2).
    dead_count=1 is the boundary for BFP-001 (gte=1).
    """

    def test_dead_count_exactly_1_triggers_bfp001(self):
        result = _evaluate({"incident_type": "fire", "dead_count": 1})
        assert "BFP-001" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_dead_count_exactly_0_does_not_trigger_bfp001(self):
        result = _evaluate({"incident_type": "fire", "dead_count": 0})
        assert "BFP-001" not in result.triggered_rules

    def test_injured_count_exactly_1_triggers_bfp002(self):
        result = _evaluate({
            "incident_type": "fire",
            "casualty_mentioned": True,
            "injured_count": 1,
        })
        assert "BFP-002" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_injured_count_2_triggers_mdrrmo011_not_mdrrmo010(self):
        """injured_count=2: hits MDRRMO-011 (lte=2), misses MDRRMO-010 (gte=3)."""
        result = _evaluate(
            {"incident_type": "vehicular", "casualty_mentioned": True, "injured_count": 2},
            agency_type=AgencyType.MDRRMO,
        )
        assert "MDRRMO-011" in result.triggered_rules
        assert "MDRRMO-010" not in result.triggered_rules
        assert result.severity == SeverityLevel.high

    def test_injured_count_3_triggers_mdrrmo010_not_mdrrmo011(self):
        """injured_count=3: hits MDRRMO-010 (gte=3), misses MDRRMO-011 (lte=2)."""
        result = _evaluate(
            {"incident_type": "vehicular", "casualty_mentioned": True, "injured_count": 3},
            agency_type=AgencyType.MDRRMO,
        )
        assert "MDRRMO-010" in result.triggered_rules
        assert "MDRRMO-011" not in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_injured_count_exactly_3_for_mdrrmo007(self):
        """Mass casualty threshold (gte=3 + multi_agency_needed) at exactly 3."""
        result = _evaluate(
            {
                "incident_type": "medical_trauma",
                "injured_count": 3,
                "multi_agency_needed": True,
            },
            agency_type=AgencyType.MDRRMO,
        )
        assert "MDRRMO-007" in result.triggered_rules
        assert result.severity == SeverityLevel.critical

    def test_injured_count_2_misses_mdrrmo007_threshold(self):
        """injured_count=2 does NOT reach mass casualty threshold (gte=3)."""
        result = _evaluate(
            {
                "incident_type": "medical_trauma",
                "injured_count": 2,
                "multi_agency_needed": True,
            },
            agency_type=AgencyType.MDRRMO,
        )
        assert "MDRRMO-007" not in result.triggered_rules


# =============================================================================
# 5. Signal source swapping
# =============================================================================

class TestSignalSourceSwapping:
    """
    The engine must accept signals from any source without rubric logic changes.
    This tests the _normalise_signals() path for each supported input type.
    """

    def test_accepts_plain_dict(self):
        result = _evaluate({"incident_type": "fire", "dead_count": 1})
        assert result.severity == SeverityLevel.critical

    def test_accepts_extracted_signals_pydantic_object(self):
        """Drop-in for Phase 4 NLP output — ExtractedSignals Pydantic model."""
        signals_obj = ExtractedSignals(
            incident_type="fire",
            dead_count=1,
            casualty_mentioned=True,
        )
        result = _evaluate(signals_obj)
        assert result.severity == SeverityLevel.critical
        assert "BFP-001" in result.triggered_rules

    def test_extracted_signals_with_all_defaults(self):
        """Default ExtractedSignals (no incident type) → no rules fire."""
        signals_obj = ExtractedSignals()
        result = _evaluate(signals_obj)
        assert result.severity == SeverityLevel.low
        assert result.no_rules_triggered is True

    def test_dict_and_pydantic_produce_identical_results(self):
        """Same signal values via dict and ExtractedSignals must give same result."""
        payload = {
            "incident_type": "fire",
            "casualty_mentioned": True,
            "injured_count": 2,
        }
        result_dict = _evaluate(dict(payload))
        result_pydantic = _evaluate(ExtractedSignals(**payload))
        assert result_dict.severity == result_pydantic.severity
        assert set(result_dict.triggered_rules) == set(result_pydantic.triggered_rules)

    def test_accepts_generic_object_with_dict(self):
        """Any object with __dict__ is also accepted."""
        class FakeSignals:
            def __init__(self):
                self.incident_type = "fire"
                self.dead_count = 2
                self.casualty_mentioned = False

        result = _evaluate(FakeSignals())
        assert "BFP-001" in result.triggered_rules
        assert result.severity == SeverityLevel.critical


# =============================================================================
# 6. Config source tracking
# =============================================================================

class TestConfigSourceTracking:
    """Verify the config_source field in results is set correctly."""

    def test_seed_fallback_sets_config_source(self):
        """When DB has no active config, config_source='seed_fallback'."""
        result = _evaluate({"incident_type": "fire"})
        assert result.config_source == "seed_fallback"

    def test_result_carries_config_version(self):
        """rubric_config_version must be set and match the seed file version."""
        result = _evaluate({"incident_type": "fire"})
        assert result.rubric_config_version == "1.0.0"

    def test_result_carries_agency_type(self):
        """agency_type in result must match the requested agency."""
        for agency in AgencyType:
            result = _evaluate({}, agency_type=agency)
            assert result.agency_type == agency

    def test_db_config_sets_source_to_db(self):
        """When DB returns an active config, config_source='db'."""
        from app.services.rubric_traceability import load_seed_config
        import json

        seed = load_seed_config(AgencyType.BFP)
        rules_payload = [r.model_dump(mode="json") for r in seed.rules]

        mock_db = MagicMock()
        # First call (DB lookup for active config) returns a row
        db_row = {
            "id": "aaaaaaaa-0000-0000-0000-000000000001",
            "agency_type": "BFP",
            "version": "1.0.0",
            "rules": rules_payload,
            "is_active": True,
            "created_by": "bbbbbbbb-0000-0000-0000-000000000001",
            "activated_by": None,
            "activated_at": None,
            "created_at": "2026-01-01T00:00:00+00:00",
        }
        mock_db.table.return_value.select.return_value \
            .eq.return_value.eq.return_value \
            .limit.return_value.execute.return_value.data = [db_row]

        rs._config_cache.clear()
        result = rs.evaluate({"incident_type": "fire", "dead_count": 1}, AgencyType.BFP, db=mock_db)
        assert result.config_source == "db"
        assert result.severity == SeverityLevel.critical


# =============================================================================
# 7. Cache behaviour
# =============================================================================

class TestCacheBehaviour:
    """In-process cache avoids redundant DB round-trips."""

    def test_cache_populated_after_first_evaluate(self):
        """After one evaluate() with a DB config, cache has the entry."""
        from app.services.rubric_traceability import load_seed_config
        seed = load_seed_config(AgencyType.BFP)
        rules_payload = [r.model_dump(mode="json") for r in seed.rules]
        db_row = {
            "id": "aaaaaaaa-0000-0000-0000-000000000001",
            "agency_type": "BFP",
            "version": "1.0.0",
            "rules": rules_payload,
            "is_active": True,
            "created_by": "bbbbbbbb-0000-0000-0000-000000000001",
            "activated_by": None,
            "activated_at": None,
            "created_at": "2026-01-01T00:00:00+00:00",
        }
        mock_db = MagicMock()
        mock_db.table.return_value.select.return_value \
            .eq.return_value.eq.return_value \
            .limit.return_value.execute.return_value.data = [db_row]

        rs._config_cache.clear()
        rs.evaluate({"incident_type": "fire"}, AgencyType.BFP, db=mock_db)
        assert AgencyType.BFP in rs._config_cache

    def test_invalidate_cache_removes_entry(self):
        """invalidate_cache() removes the agency from the cache."""
        from app.services.rubric_traceability import load_seed_config
        rs._config_cache[AgencyType.BFP] = load_seed_config(AgencyType.BFP)
        assert AgencyType.BFP in rs._config_cache
        rs.invalidate_cache(AgencyType.BFP)
        assert AgencyType.BFP not in rs._config_cache


# =============================================================================
# 8. Known field-interview scenarios (skip until TODO filled in)
# =============================================================================

class TestKnownScenarios:
    """
    Validates the rubric against real dispatch scenarios from field interviews.

    These tests are SKIPPED until Kurt fills in the TODO values in
    rubric_traceability.KNOWN_SCENARIOS. Once filled in:
      1. Replace expected_severity TODO strings with real values
      2. Replace signals TODOs with actual signal dicts from the interview
      3. Remove the pytest.skip() call in _run_scenario()

    These are the most important tests for the defense — they demonstrate
    that the rubric encodes real dispatch practice, not invented rules.
    """

    def _run_scenario(self, scenario):
        if scenario.expected_severity.startswith("TODO"):
            pytest.skip(
                f"Scenario {scenario.scenario_id} not yet filled in. "
                f"Kurt: populate signals and expected_severity from field interview: "
                f"{scenario.field_interview_reference}"
            )

        rs._config_cache.clear()
        db = _mock_db_no_active_config()
        result = rs.evaluate(scenario.signals, scenario.agency_type, db=db)
        assert result.severity.value == scenario.expected_severity, (
            f"Scenario {scenario.scenario_id} ({scenario.description}): "
            f"expected severity={scenario.expected_severity}, "
            f"got severity={result.severity.value}. "
            f"Triggered rules: {result.triggered_rules}. "
            f"Field reference: {scenario.field_interview_reference}"
        )

    def test_bfp_field_scenario(self):
        scenario = next(s for s in KNOWN_SCENARIOS if s.scenario_id == "FIELD-BFP-001")
        self._run_scenario(scenario)

    def test_pnp_field_scenario(self):
        scenario = next(s for s in KNOWN_SCENARIOS if s.scenario_id == "FIELD-PNP-001")
        self._run_scenario(scenario)

    def test_mdrrmo_field_scenario(self):
        scenario = next(s for s in KNOWN_SCENARIOS if s.scenario_id == "FIELD-MDRRMO-001")
        self._run_scenario(scenario)
