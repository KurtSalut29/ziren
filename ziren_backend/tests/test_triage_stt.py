"""
Speech-recognition corrections in the triage pipeline.

The app listens on the resident's handset and posts whatever the recogniser
produced. That text is not clean, and it is not wrong in the way typed text is
wrong: it fails on proper nouns, because no recogniser has Biliran municipality
names in its vocabulary and substitutes the nearest ordinary word it knows.

Recorded live on a handset, spoken in Waray:

    said:  "Mayda sunog didi ha Caibiran"
    got:   "mayda sunog didiha kaibigan kaibigan"

Three separate failures in one short sentence — a word-boundary merge, a place
name replaced by an unrelated word, and a stutter. The Waray itself came
through: `mayda` and `sunog` are both correct.
"""

import pytest

from app.models.incident import IncidentCategory, SeverityLevel
from app.services import triage_service as T


@pytest.fixture(scope="module", autouse=True)
def _model():
    if not T.load():
        pytest.skip(f"triage model unavailable: {T.status().get('error')}")


class TestCollapseRepeats:
    def test_drops_an_adjacent_duplicate(self):
        assert (
            T._collapse_immediate_repeats("mayda sunog kaibigan kaibigan")
            == "mayda sunog kaibigan"
        )

    def test_is_case_insensitive(self):
        assert T._collapse_immediate_repeats("Sunog sunog") == "Sunog"

    def test_keeps_a_repeat_that_is_not_adjacent(self):
        # "sunog ... sunog" separated by other words is a person repeating
        # themselves for emphasis, not the recogniser stuttering.
        text = "sunog ha balay ngan sunog ha kakahuyan"
        assert T._collapse_immediate_repeats(text) == text

    def test_leaves_empty_and_single_words_alone(self):
        assert T._collapse_immediate_repeats("") == ""
        assert T._collapse_immediate_repeats("tabang") == "tabang"


class TestSttCorrections:
    def test_the_override_file_is_loaded(self):
        corrections = T._load_stt_corrections()
        assert corrections, "stt_corrections.csv did not load"
        assert corrections["kaibigan"] == "Caibiran"

    def test_corrections_reach_the_alias_table(self):
        # Layered on top of the release dictionary, not instead of it: the
        # release's own misspellings must survive the merge.
        assert T._ALIASES.get("kaibigan") == "Caibiran"
        assert T._ALIASES.get("sonog") == "sunog", "release dictionary was lost"


class TestTheRecordedFailure:
    """The exact string a handset produced, end to end."""

    RAW = "mayda sunog didiha kaibigan kaibigan"

    def _triage(self):
        return T.triage(report_text=self.RAW, incident_category=IncidentCategory.fire)

    def test_the_place_name_is_recovered(self):
        result = self._triage()
        # Caibiran is already in predict.py's BARANGAYS list — it was never a
        # gap in the pipeline's knowledge, only in what reached it.
        assert result["signals"]["signals"].get("location") == "Caibiran"

    def test_the_merged_words_are_split(self):
        result = self._triage()
        assert "didi ha" in result["signals"]["normalisation"]["text"]

    def test_the_stutter_does_not_become_a_doubled_place(self):
        result = self._triage()
        assert result["signals"]["normalisation"]["text"].count("Caibiran") == 1

    def test_every_correction_is_recorded_for_the_dispatcher(self):
        # A silently rewritten emergency report would be worse than an
        # uncorrected one. The changes are stored on the incident so a
        # dispatcher can see what the system altered and why.
        changes = self._triage()["signals"]["normalisation"]["changes"]
        assert any("kaibigan -> Caibiran" in c for c in changes)
        assert any("didiha -> didi ha" in c for c in changes)

    def test_the_category_still_reads_as_fire(self):
        result = self._triage()
        assert result["signals"]["model_predicted"] == "FIRE"

    def test_severity_stays_at_the_category_floor(self):
        # Correcting the transcript must not invent urgency beyond what the
        # resident already asserted. The sentence says there is a fire; it
        # says nothing about injuries, entrapment or spreading, so nothing
        # here should reach SR001-SR004 or SR006-SR008. What it does get is
        # SR005E, the FIRE category floor: the resident tapped FIRE, and fire
        # risk compounds without intervention regardless of what else the
        # transcript could or could not recover.
        result = self._triage()
        assert result["signals"]["severity_rule"] == "SR005E"
        assert result["severity"].value == "high"


class TestFailSafe:
    def test_a_missing_override_file_does_not_break_loading(self, monkeypatch):
        monkeypatch.setattr(T, "_OVERRIDES_ROOT", "/nonexistent/path")
        assert T._load_stt_corrections() == {}


class TestFuzzyNormalisationIsOffOnPurpose:
    """The fuzzy pass is disabled, and that is a decision, not an accident.

    It was previously off because rapidfuzz was missing from requirements.txt
    and predict.py swallows the ImportError. Turning it on made triage worse:
    measured on the release's own 249-row test split, severity moved on 10 rows
    — 3 up, 7 down — because Tagalog and Waray affixes put unrelated words a
    couple of edits apart.
    """

    def test_rapidfuzz_is_installed(self):
        # Pinned so the switch means something. An off switch that is really a
        # missing package is indistinguishable from a bug.
        import rapidfuzz  # noqa: F401

    def test_the_pool_handed_to_normalise_is_empty(self):
        assert T.FUZZY_NORMALISATION is False
        assert T._fuzzy_pool() == []

    def test_the_alias_table_still_runs(self):
        # Disabling fuzzy must not disable exact correction. This is the pass
        # that fixes real observed misspellings.
        text, changes = T._Z.normalise("mayda sonog didi", T._ALIASES, T._fuzzy_pool())
        assert "sunog" in text
        assert any("sonog -> sunog" in c for c in changes)

    def test_rapidfuzz_would_still_work_if_re_enabled(self):
        # Handing it a pool directly proves the library is functional, so a
        # future re-tuning starts from a working matcher.
        text, changes = T._Z.normalise("mayda nasamdann didi", T._ALIASES, T._TERMS)
        assert "nasamdan" in text
        assert any("nasamdann -> nasamdan" in c for c in changes)


class TestAHouseFireIsNotDowngraded:
    """The specific harm the fuzzy pass caused, nine times in 249 rows.

    `bahay` (house) scores 89 against `baha` (flood); the threshold for a
    five-letter word is 85, and `bahay` is not in predict.PROTECTED. So
    "nasusunog po ang bahay" became a flood report and lost SR005 — the rule
    that escalates a fire because a structure is involved.
    """

    TEXT = "nasusunog po ang bahay dito sa Naval"

    def test_the_word_for_house_survives_normalisation(self):
        text, _ = T._Z.normalise(self.TEXT, T._ALIASES, T._fuzzy_pool())
        assert "bahay" in text
        assert "baha " not in text and not text.endswith("baha")

    def test_it_would_not_survive_with_the_fuzzy_pass_on(self):
        # Guards the finding itself. If a future dictionary or threshold change
        # makes this pass, the reason for FUZZY_NORMALISATION being off has
        # gone away and the flag deserves revisiting.
        text, _ = T._Z.normalise(self.TEXT, T._ALIASES, T._TERMS)
        assert "baha" in text and "bahay" not in text

    def test_the_structure_signal_is_kept(self):
        result = T.triage(
            report_text=self.TEXT, incident_category=IncidentCategory.fire
        )
        assert result["signals"]["model_predicted"] == "FIRE"
        assert result["signals"]["severity_rule"] == "SR005"
        assert result["severity"] == SeverityLevel.high


class TestPlaceNamesAreNotFuzzyMatched:
    """A measured limitation, recorded so it is not mistaken for working.

    normalise() fuzzy-matches against `terms` — the emergency vocabulary — and
    BARANGAYS is not part of it. So a mangled place name is only ever fixed by
    a hand-written entry in stt_corrections.csv:

        kaibigan -> Caibiran   in the file, corrected
        kaibiran -> Caibiran   not in the file, NOT corrected (ratio 87.5,
                               threshold 78 — it would pass easily if barangays
                               were candidates at all)

    Both came off real handsets for the same spoken sentence. Place names are
    where the recogniser actually fails, which makes this the gap worth closing.
    """

    def test_no_barangay_is_in_the_fuzzy_candidate_pool(self):
        # True of the vocabulary itself, independent of whether the pass runs.
        assert not {b for b in T._Z.BARANGAYS if b in T._TERMS}

    def test_an_unlisted_mangling_survives_uncorrected(self):
        text, _ = T._Z.normalise(
            "maida sunog didiha kaibiran", T._ALIASES, T._fuzzy_pool()
        )
        assert "kaibiran" in text
        assert "Caibiran" not in text

    def test_it_is_near_enough_that_fuzzy_matching_would_catch_it(self):
        from rapidfuzz import fuzz

        assert fuzz.ratio("kaibiran", "caibiran") >= T._Z._threshold_for("kaibiran")


class TestALandmarkNamesThePlaceWithoutRaisingSeverity:
    """A landmark says what the incident is NEXT TO, not what it is.

    Residents here give directions by landmark, and nearly every landmark
    names a building — a bahay, a store, a school, the barangay hall. Folded
    into report_text those words reach predict.extract() as description of the
    incident:

        "Malapit sa: harap ng bahay ni Mang Juan"  ->  structure_involved

    SR005 fires on that and claims a STRUCTURAL fire specifically. A house
    standing beside a fire is not a house on fire, so almost every landmark
    would have put a false claim in front of the dispatcher — even though,
    since the FIRE category floor (SR005E) now puts every fire report at HIGH
    regardless, a wrong SR005 attribution would not change the severity
    NUMBER here. It would still be a wrong reason, and "why is this HIGH" is
    exactly what a dispatcher reads to decide what they're walking into.
    """

    def _go(self, landmark, text="Sunog"):
        return T.triage(
            report_text=text,
            incident_category=IncidentCategory.fire,
            landmark_note=landmark,
        )

    def test_a_building_in_the_landmark_does_not_escalate(self):
        for landmark in [
            "harap ng bahay ni Mang Juan",
            "tapat ng sari-sari store ni Aling Nena",
            "katabi ng barangay hall",
            "malapit sa simbahan",
        ]:
            r = self._go(landmark)
            # SR005E (the FIRE category floor) is expected and correct here —
            # the resident tapped FIRE, nothing more. SR005 (STRUCTURAL fire)
            # is what the landmark must never cause: that would mean this
            # test's whole premise failed and a landmark's incidental
            # building got reported to the dispatcher as the fire's own.
            assert r["signals"]["severity_rule"] == "SR005E", landmark
            assert r["severity"] == SeverityLevel.high, landmark

    def test_it_does_not_set_structure_involved(self):
        r = self._go("harap ng bahay ni Mang Juan")
        assert not r["signals"]["signals"].get("structure_involved")

    def test_a_barangay_named_in_it_is_still_recovered(self):
        # The one thing a landmark can safely contribute. Worth having: the
        # coordinates cannot always be named, because OpenStreetMap's Biliran
        # coverage is thin.
        assert (
            self._go("katabi ng Talustusan Elementary School")["signals"][
                "signals"
            ].get("location")
            == "Talustusan"
        )
        assert (
            self._go("tapat ng Caibiran public market")["signals"]["signals"].get(
                "location"
            )
            == "Caibiran"
        )

    def test_the_report_text_still_decides_severity(self):
        # Guards the other direction: quieting the landmark must not quiet the
        # report. A real structure fire is still HIGH.
        r = self._go(None, text="Nasusunog ang bahay")
        assert r["signals"]["severity_rule"] == "SR005"
        assert r["severity"] == SeverityLevel.high

    def test_a_location_in_the_report_wins_over_the_landmark(self):
        # What is burning locates the incident better than what stands beside
        # it, so the landmark only fills a gap.
        r = self._go("tapat ng Caibiran public market", text="Sunog ha Naval")
        assert r["signals"]["signals"].get("location") == "Naval"

    def test_an_empty_or_missing_landmark_changes_nothing(self):
        base = self._go(None)["signals"]["severity_rule"]
        assert self._go("")["signals"]["severity_rule"] == base
        assert self._go("   ")["signals"]["severity_rule"] == base
