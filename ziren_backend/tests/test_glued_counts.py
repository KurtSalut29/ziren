"""Warning when the recogniser welds a number onto the word after it.

The case this exists for is real and measured. A resident recorded:

    "may nabangga nga duha ka motor didi ha highway, tulo ka tawo an nasamdan"
     (two motorcycles collided, three people injured)

faster-whisper returned:

    "May nagbangga ng adohaka motor didi hahighway tulukataw anasamdan."

The injury survived, because "nasamdan" is still findable inside "anasamdan".
Both counts did not: _count() matches a numeral followed by a separate noun,
and there were no separate words left. The incident scored HIGH instead of
CRITICAL and nothing said a number had gone missing.

These assert the flag is raised. They do NOT assert any un-gluing, because the
code deliberately does not attempt it: "tulukataw" could be "tulo ka tawo" or
"tulo ka taw", and a dispatcher who reads a wrong count sends for that many.
"""
import pytest

from app.services import triage_service as T


@pytest.fixture(scope="module", autouse=True)
def loaded():
    T.load()


def glued(text):
    return T._glued_number_words(text)


# ── the measured case ──────────────────────────────────────────────────────

class TestTheRealTranscript:
    def test_tulo_ka_tawo_glued_is_flagged(self):
        assert "tulukataw" in glued("tulukataw anasamdan")

    def test_the_whole_transcript_flags_both(self):
        # Verbatim from the recording. "adohaka" is "duha ka" with the same
        # fault, and it cost the vehicle count.
        found = glued(
            "May nagbangga ng adohaka motor didi hahighway tulukataw anasamdan."
        )
        assert "tulukataw" in found
        assert "adohaka" in found

    def test_the_signals_blob_carries_the_flag(self):
        r = T.triage(
            report_text="May nagbangga ng adohaka motor didi hahighway "
                        "tulukataw anasamdan.",
            incident_category=None,
        )
        assert r is not None
        assert r["signals"]["count_uncertain"] is True
        assert "confirm how many" in r["signals"]["count_note"]

    def test_the_note_names_the_words(self):
        # "adohaka" and not "tulukataw": the latter has since been confirmed
        # against the recording and added to stt_corrections.csv, so it is no
        # longer uncertain. The note must name what is STILL unknown.
        r = T.triage(
            report_text="May nagbangga ng adohaka motor didi hahighway",
            incident_category=None,
        )
        assert "adohaka" in r["signals"]["count_note"]


# ── the same sentence, transcribed properly ────────────────────────────────

class TestCleanCountsAreNotFlagged:
    def test_the_sentence_as_it_was_actually_said(self):
        assert glued("tulo ka tawo an nasamdan") == []

    def test_a_clean_report_carries_no_flag_or_note(self):
        r = T.triage(
            report_text="may nabangga nga duha ka motor, tulo ka tawo an nasamdan",
            incident_category=None,
        )
        assert r["signals"]["count_uncertain"] is False
        assert r["signals"]["count_note"] is None

    def test_the_counts_still_extract(self):
        # The warning must not disturb the reading of a good transcript.
        r = T.triage(
            report_text="may nabangga nga duha ka motor, tulo ka tawo an nasamdan",
            incident_category=None,
        )
        sig = r["signals"]["signals"]
        assert sig["injured_count"] == 3
        assert sig["vehicles_involved"] == 2


# ── ordinary words that merely contain a numeral ───────────────────────────

class TestWordsThatOnlyLookGlued:
    """A warning that fires on normal speech is a warning nobody reads."""

    @pytest.mark.parametrize("text,trap", [
        ("tulong tabang tabangi", "tulong (help) contains tulo (three)"),
        ("may sunog sa gusali",   "gusali (building) contains usa (one)"),
        ("naay kapitolyo didi",   "kapitolyo contains pito (seven)"),
        ("duha ka motor nag bangga", "a clean count, separate words"),
        ("nasamdan ang bata",     "no numeral at all"),
    ])
    def test_not_flagged(self, text, trap):
        assert glued(text) == [], trap

    def test_a_bare_numeral_is_not_glued(self):
        assert glued("tulo") == []
        assert glued("dalawa") == []

    def test_empty_text(self):
        assert glued("") == []


# ── it warns, it never rewrites ────────────────────────────────────────────

class TestItOnlyWarns:
    """The detector never splits a word. Two layers, two different powers.

    An EXACT row in stt_corrections.csv may un-glue a specific token, because
    a person listened to the recording and confirmed what was said —
    "tulukataw" is now one of those. This detector may not, because it is
    guessing, and a dispatcher who reads a wrong count sends for that many.

    So these use a glued token nobody has confirmed.
    """

    def test_the_text_is_left_alone(self):
        out, _changes = T.normalise_text("duhakatawo anasamdan")
        assert "duhakatawo" in out

    def test_no_count_is_invented(self):
        r = T.triage(report_text="duhakatawo nasamdan", incident_category=None)
        sig = r["signals"]["signals"]
        assert "injured_count" not in sig or sig.get("injured_count") is None

    def test_an_unconfirmed_glued_token_is_flagged_not_fixed(self):
        r = T.triage(report_text="duhakatawo nasamdan", incident_category=None)
        assert r["signals"]["count_uncertain"] is True
        assert "duhakatawo" in r["signals"]["count_note"]

    def test_a_confirmed_one_is_fixed_and_not_flagged(self):
        # The other half of the same rule: once a human has ruled on a
        # specific string, it stops being a guess.
        r = T.triage(report_text="tulukataw anasamdan", incident_category=None)
        assert r["signals"]["count_uncertain"] is False
        assert r["signals"]["signals"]["injured_count"] == 3


# ── the resident's own count, tapped at report time ────────────────────────
#
# The other half of the same problem. The detector above can only warn that a
# count was lost; this recovers it, from the one source that actually knows.
# Asked on the confirm screen the moment a recording exists, defaulted to "not
# sure", and never blocking the send.

class TestPeopleCountFromTheResident:
    def _triage(self, text, count=None):
        wa = {"people_count": count} if count else {}
        return T.triage(report_text=text, incident_category=None,
                        wizard_answers=wa)

    @pytest.mark.parametrize("value,expected", [
        ("1person", 1),
        ("2people", 2),
        ("3people", 3),
        ("4plus",   4),
    ])
    def test_a_tapped_count_reaches_the_signals(self, value, expected):
        r = self._triage("may sunog sa balay", count=value)
        assert r["signals"]["signals"]["people_involved"] == expected
        assert "people_involved" in r["signals"]["signals_from_wizard"]

    def test_not_sure_contributes_nothing(self):
        # An unanswered question must add no number at all, not a zero.
        r = self._triage("may sunog sa balay", count="notsure")
        assert "people_involved" not in r["signals"]["signals"]
        assert r["signals"]["signals_from_wizard"] == []

    def test_absent_is_the_same_as_not_sure(self):
        r = self._triage("may sunog sa balay")
        assert "people_involved" not in r["signals"]["signals"]

    def test_the_transcript_wins_when_it_read_more(self):
        # merged with max(): a resident tapping "1" must not erase three
        # people the recording clearly named.
        r = self._triage("tulukataw anasamdan", count="1person")
        assert r["signals"]["signals"]["people_involved"] == 3

    def test_the_tap_wins_when_the_transcript_read_nothing(self):
        # The case this exists for. The recogniser glued the number away;
        # the resident tapped it.
        r = self._triage("duhakatawo nasamdan", count="2people")
        assert r["signals"]["signals"]["people_involved"] == 2

    def test_values_are_machine_readable_not_display_labels(self):
        # Every other wizard answer is stored as its Filipino label, which
        # makes the UI copy part of the scoring table — translate a chip and
        # it silently stops counting. This field is deliberately not like
        # that, so the screen can say "4+ katao" or "4+ people" freely.
        from app.services.triage_service import _COUNT_ANSWERS
        for machine in ("1person", "2people", "3people", "4plus"):
            assert machine in _COUNT_ANSWERS
        assert "notsure" not in _COUNT_ANSWERS

    def test_it_never_blocks_a_report(self):
        # No count of any kind, including the key being absent entirely.
        r = self._triage("may sunog sa balay")
        assert r is not None
        assert r["severity"] is not None
