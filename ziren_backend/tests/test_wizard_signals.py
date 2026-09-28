"""The bridge from what the app sends to what the rubric reads.

These drive the payload the live report screen actually produces — the keys
and the Filipino answer strings from `_questionsFor` in
wizard_report_screen.dart — rather than synthetic signal dicts. That is the
gap these tests exist to close: every rubric test before this one built its
own signals by hand, so a mapping that read keys no client ever sent passed
the whole suite while producing almost nothing in production.
"""
import pytest

from app.services.dispatch_service import _wizard_to_signals


def signals(category, **answers):
    return _wizard_to_signals({
        "incident_category": category,
        "wizard_answers": answers,
        "overlap_agencies": [],
    })


# ── the bug that made every crime report carry a weapon ──────────────────────

class TestWeapon:
    def test_yes_is_a_weapon(self):
        assert signals("domestic_dispute_crime", weapon="Oo")["weapon_mentioned"] is True

    def test_wala_is_not_a_weapon(self):
        # bool("Wala") is True, which is how every crime report used to report
        # a weapon and trip PNP-004.
        assert signals("domestic_dispute_crime", weapon="Wala")["weapon_mentioned"] is False

    def test_dont_know_is_unknown_not_false(self):
        assert signals("domestic_dispute_crime", weapon="Hindi ko alam")["weapon_mentioned"] is None

    def test_unanswered_is_unknown(self):
        assert signals("domestic_dispute_crime")["weapon_mentioned"] is None

    def test_weapon_named_as_the_incident_type(self):
        assert signals("domestic_dispute_crime", type="May armas")["weapon_mentioned"] is True


# ── unknown must never read as "no" ──────────────────────────────────────────

class TestTriState:
    def test_injured_yes(self):
        assert signals("fire", injured="Oo")["casualty_mentioned"] is True

    def test_injured_none(self):
        assert signals("fire", injured="Wala")["casualty_mentioned"] is False

    def test_injured_unknown(self):
        # A rule testing `casualty_mentioned: false` must not match this.
        assert signals("fire", injured="Hindi ko alam")["casualty_mentioned"] is None

    def test_unasked_is_unknown(self):
        # The crime step has no injury question at all.
        assert signals("domestic_dispute_crime", weapon="Oo")["casualty_mentioned"] is None

    def test_bleeding_counts_as_a_casualty(self):
        assert signals("medical_trauma", bleeding="Oo")["casualty_mentioned"] is True

    def test_a_yes_anywhere_wins(self):
        s = signals("medical_trauma", bleeding="Oo", conscious="Oo, gising")
        assert s["casualty_mentioned"] is True

    def test_children_are_unknown_not_absent(self):
        # No question asks about children, so no rule may assume there are none.
        assert signals("fire", material="Bahay")["children_involved"] is None


# ── what is burning, and what kind of place ──────────────────────────────────

class TestFire:
    @pytest.mark.parametrize("material,fire_type,structure", [
        ("Bahay",             "residential", "house"),
        ("Gusali / Bodega",   "structural",  "building"),
        ("Sasakyan",          "vehicle",     None),
        ("Kagubatan / Bukid", "grass",       "forest"),
        ("Iba pa",            None,          None),
    ])
    def test_material_maps(self, material, fire_type, structure):
        s = signals("fire", material=material)
        assert s["fire_type"] == fire_type
        assert s["structure_type"] == structure

    def test_structure_type_is_set_at_all(self):
        # It was never assigned anywhere, so every rule testing it was dead.
        assert signals("fire", material="Bahay")["structure_type"] is not None


# ── counts, read in the escalating direction ────────────────────────────────

class TestCounts:
    @pytest.mark.parametrize("answer,expected", [
        ("1", 1), ("2–5", 5), ("Higit sa 5", 6), ("Hindi ko alam", None),
    ])
    def test_victim_count(self, answer, expected):
        assert signals("medical_trauma", victim_count=answer)["injured_count"] == expected

    @pytest.mark.parametrize("answer,expected", [
        ("1–5", 5), ("6–20", 20), ("Higit sa 20", 21),
    ])
    def test_families_affected(self, answer, expected):
        assert signals("flood_landslide_calamity", affected=answer)["injured_count"] == expected


# ── urgency from the call, not just the category ────────────────────────────

class TestMedicalUrgency:
    def test_unconscious_is_critical(self):
        s = signals("medical_trauma", conscious="Hindi, nawalan ng malay")
        assert s["urgency_level"] == "critical"

    def test_bleeding_is_critical(self):
        assert signals("medical_trauma", bleeding="Oo")["urgency_level"] == "critical"

    def test_awake_and_not_bleeding_is_moderate(self):
        s = signals("medical_trauma", conscious="Oo, gising", bleeding="Wala")
        assert s["urgency_level"] == "moderate"

    def test_nothing_answered_is_unknown(self):
        assert signals("medical_trauma")["urgency_level"] == "unknown"


# ── calamity: people before roads ───────────────────────────────────────────

class TestCalamity:
    def test_evacuation_means_homes_are_affected(self):
        s = signals("flood_landslide_calamity", evacuation="Oo, urgent")
        assert s["structure_type"] == "residential"

    def test_blocked_road_when_no_homes_reported(self):
        s = signals("flood_landslide_calamity", road_blocked="Oo")
        assert s["structure_type"] == "road"

    def test_homes_win_over_road(self):
        s = signals("flood_landslide_calamity", evacuation="Oo, urgent", road_blocked="Oo")
        assert s["structure_type"] == "residential"


# ── crime type, for the rules about a crime in progress ─────────────────────

class TestCrimeType:
    @pytest.mark.parametrize("answer,expected", [
        ("Pagnanakaw / Holdap", "robbery"),
        ("Pambubugbog",         "assault"),
        ("Awayan / Kaguluhan",  None),
    ])
    def test_why_category(self, answer, expected):
        assert signals("domestic_dispute_crime", type=answer)["why_category"] == expected


# ── rows written by older builds still evaluate ─────────────────────────────

class TestLegacyRows:
    def test_legacy_keys_still_read(self):
        s = signals("fire", may_nasugatan="oo", fire_type="structural")
        assert s["casualty_mentioned"] is True
        assert s["fire_type"] == "structural"

    def test_legacy_counts_still_read(self):
        assert signals("fire", injured_count="4")["injured_count"] == 4


# ── the wrapper the dispatcher queue actually calls ─────────────────────────
#
# Everything above tests the mapping. Nothing tested `_suggest_severity`
# itself, and that is exactly where a swallowed TypeError lived: the call
# passed (agency_type, signals) to `evaluate(signals, agency_type)`, which
# raised deep inside the config cache and came back out of the broad `except`
# as None. Every incident in every queue got no suggestion, and the whole
# rubric suite still passed because it called `evaluate` directly.

from unittest.mock import MagicMock, patch

from app.services import dispatch_service, rubric_service


@pytest.fixture
def seed_rubric():
    """Force the seed configs, so these assert rules and not DB state."""
    rubric_service._config_cache.clear()
    db = MagicMock()
    db.table.return_value.select.return_value \
        .eq.return_value.eq.return_value \
        .limit.return_value.execute.return_value.data = []
    db.table.return_value.insert.return_value.execute.return_value.data = [{"id": "x"}]
    with patch.object(rubric_service, "get_supabase", return_value=db):
        yield
    rubric_service._config_cache.clear()


def row(agency, category, **answers):
    return {
        "incident_category": category,
        "wizard_answers": answers,
        "overlap_agencies": [],
        "stations": {"agencies": {"agency_type": agency}},
    }


class TestSuggestSeverity:
    def test_a_fire_gets_a_suggestion_at_all(self, seed_rubric):
        # The regression: this was None for every row ever queued.
        assert dispatch_service._suggest_severity(
            row("BFP", "fire", material="Bahay")) is not None

    def test_bleeding_medical_is_not_low(self, seed_rubric):
        got = dispatch_service._suggest_severity(
            row("MDRRMO", "medical_trauma", bleeding="Oo", victim_count="2–5"))
        assert got is not None
        assert getattr(got, "value", got) in ("critical", "high")

    def test_no_agency_type_is_still_none(self, seed_rubric):
        assert dispatch_service._suggest_severity(
            {"incident_category": "fire", "wizard_answers": {}, "stations": None}) is None

    def test_unmatched_report_asks_for_a_human(self, seed_rubric):
        # 'other' matches no rule in any rubric; the dispatcher should be told
        # nothing was understood rather than handed a 'low'.
        assert dispatch_service._suggest_severity(row("PNP", "other")) is None


# ── model signals → rubric, the path a report actually takes today ───────
#
# The resident flow asks no chip questions, so `wizard_answers` is empty on
# every report the app files. What arrives instead is what the model read out
# of the spoken text. These assert the translation between the two
# vocabularies, and that the wizard mapping is still used when there is no
# model reading to prefer.

from app.services.dispatch_service import _model_to_signals


def model_row(category, agency="BFP", **extracted):
    return {
        "incident_category": category,
        "wizard_answers": {},
        "overlap_agencies": [],
        "stations": {"agencies": {"agency_type": agency}},
        "signals": {"engine": "ziren-model", "signals": extracted},
    }


class TestModelToSignals:
    def test_no_signals_blob_returns_none(self):
        assert _model_to_signals({"signals": None}) is None

    def test_empty_extraction_returns_none(self):
        # None, not {} — the caller must be able to fall back to the wizard.
        assert _model_to_signals(model_row("fire")) is None

    def test_trapped_is_a_casualty_and_critical(self):
        s = _model_to_signals(model_row("fire", entrapment=True))
        assert s["casualty_mentioned"] is True
        assert s["urgency_level"] == "critical"

    def test_denied_injury_is_false_not_unknown(self):
        s = _model_to_signals(model_row("fire", injured=False))
        assert s["casualty_mentioned"] is False

    def test_unknown_injury_stays_unknown(self):
        s = _model_to_signals(model_row("fire", structure_involved=True))
        assert s["casualty_mentioned"] is None

    def test_burning_structure_becomes_a_fire_type(self):
        s = _model_to_signals(model_row("fire", structure_involved=True))
        assert s["fire_type"] == "structural"

    def test_structure_type_is_not_invented(self):
        # STRUCT cannot tell a house from a warehouse; guessing would be worse
        # than leaving the rules that need it unreachable.
        s = _model_to_signals(model_row("fire", structure_involved=True))
        assert s["structure_type"] is None

    def test_headcount_is_not_a_casualty_count(self):
        s = _model_to_signals(model_row("vehicular", people_involved=4))
        assert s["injured_count"] is None

    def test_headcount_counts_once_someone_is_hurt(self):
        s = _model_to_signals(model_row("vehicular", injured=True, people_involved=4))
        assert s["injured_count"] == 4

    def test_fatalities_carry_over(self):
        s = _model_to_signals(model_row("vehicular", fatalities=2))
        assert s["dead_count"] == 2
        assert s["urgency_level"] == "critical"

    def test_children_are_never_assumed_absent(self):
        s = _model_to_signals(model_row("fire", entrapment=True))
        assert s["children_involved"] is None


class TestSuggestionPrefersTheModel:
    def test_model_reading_is_used(self, seed_rubric):
        row = model_row("fire", entrapment=True, structure_involved=True)
        assert dispatch_service._suggest_severity(row) is not None

    def test_falls_back_to_wizard_when_model_read_nothing(self, seed_rubric):
        # An older build's report: chips present, no model signals.
        row = {
            "incident_category": "fire",
            "wizard_answers": {"material": "Bahay", "injured": "Oo"},
            "overlap_agencies": [],
            "stations": {"agencies": {"agency_type": "BFP"}},
            "signals": None,
        }
        assert dispatch_service._suggest_severity(row) is not None
