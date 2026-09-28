"""Exact corrections for mistakes a recogniser actually made.

Every row asserted here came from a real recording on a real handset, with the
speaker confirming afterwards what they had said. None are invented, and none
are typing mistakes — those belong in the model release's misspellings.csv.

This layer exists because the sound layer cannot reach these. A letter ADDED or
DROPPED changes the phonetic key, so "sunong" cannot be reduced to "sunog" by
any rule about vowels; only a person who listened to the audio can say what it
was. That makes each row expensive to produce and worth protecting with a test.
"""
import pytest

from app.services import triage_service as T
from app.ml.tools import predict as P


@pytest.fixture(scope="module", autouse=True)
def loaded():
    T.load()


def corrected(text):
    out, _changes = T.normalise_text(text)
    return out


def signals(text):
    sig, _ = P.extract(text)
    return {k: v for k, v in sig.items() if v is not None}


# ── each row does what it says ─────────────────────────────────────────────

class TestTheRows:
    @pytest.mark.parametrize("heard,expected,clip", [
        ("doha",      "duha",         "1 — two, o/u on a numeral"),
        ("solod",     "sulod",        "1 — inside"),
        ("sunong",    "sunog",        "A — fire, inserted n"),
        ("anasamdan", "an nasamdan",  "3 — merged 'an nasamdan'"),
        ("tulukataw", "tulo ka tawo", "3 — merged 'tulo ka tawo'"),
    ])
    def test_applies(self, heard, expected, clip):
        out = corrected(f"may {heard} didi")
        for word in expected.split():
            assert word in out.split(), clip


# ── what they are for ──────────────────────────────────────────────────────

class TestSignalsRecovered:
    def test_clip_3_recovers_the_injured_count(self):
        # Verbatim transcript. Before these rows the report knew someone was
        # injured but not that there were three of them.
        heard = ("May nagbangga ng adohaka motor didi hahighway "
                 "tulukataw anasamdan.")
        assert "injured_count" not in signals(heard)
        assert signals(corrected(heard))["injured_count"] == 3

    def test_clip_3_becomes_critical(self):
        r = T.triage(
            report_text="May nagbangga ng adohaka motor didi hahighway "
                        "tulukataw anasamdan.",
            incident_category=None,
        )
        assert r["severity"].value == "critical"

    def test_sulod_alone_carries_entrapment(self):
        # "sa sulod" is the phrase TRAPPED_AFFIRM matches. Without the
        # correction a report saying someone is inside yields nothing.
        assert signals("naay tawo sa solod") == {}
        assert signals(corrected("naay tawo sa solod"))["entrapment"] is True

    def test_duha_alone_carries_a_count(self):
        assert "injured_count" not in signals("doha ka tawo an nasamdan")
        assert signals(corrected("doha ka tawo an nasamdan"))["injured_count"] == 2


# ── the warning narrows rather than disappearing ───────────────────────────

class TestInteractionWithTheGluedWarning:
    def test_a_fixed_count_no_longer_warns_about_that_word(self):
        r = T.triage(
            report_text="May nagbangga ng adohaka motor didi hahighway "
                        "tulukataw anasamdan.",
            incident_category=None,
        )
        note = r["signals"]["count_note"]
        # tulukataw is now known, so it is no longer uncertain...
        assert "tulukataw" not in note
        # ...but adohaka ("duha ka") is still welded, and the VEHICLE count is
        # still lost. The warning has to survive for the part still broken.
        assert "adohaka" in note
        assert r["signals"]["count_uncertain"] is True

    def test_a_fully_corrected_report_stops_warning(self):
        r = T.triage(report_text="tulukataw anasamdan", incident_category=None)
        assert r["signals"]["count_uncertain"] is False
        assert r["signals"]["signals"]["injured_count"] == 3


# ── they must not fire on correct speech ───────────────────────────────────

class TestNoCollateralDamage:
    @pytest.mark.parametrize("text", [
        "duha ka tawo an nasamdan",
        "may sunog sa balay",
        "naay tawo sa sulod",
        "tulo ka tawo an nasamdan",
    ])
    def test_correct_text_is_left_alone(self, text):
        assert corrected(text) == text

    def test_real_words_are_not_rewritten(self):
        # nagbangga and dabang were both deliberately NOT added: the first is
        # a real Tagalog word, the second changed no signal and lowered
        # confidence. Asserted so a future edit has to argue with a test.
        assert "nagbangga" in corrected("may nagbangga nga duha ka motor")
        assert "dabang" in corrected("need namog dabang")
