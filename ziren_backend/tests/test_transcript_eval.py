"""
Transcript evaluation — WER and critical word accuracy.

The central claim these tests protect: for an emergency report, WER alone is
misleading. A transcript can score badly and still convey everything a
dispatcher acts on, and it can score well while losing the one word that
decides whether anyone is trapped.
"""

import pytest

from app.services import transcript_eval as E


# A fixed vocabulary, so the WER and scoring tests do not depend on the model
# being loadable. The tests that exercise the real dictionaries say so.
VOCAB = {
    "emergency": {"sunog", "nasamdan", "nagdurugo", "naipit", "baha", "linog"},
    "place": {"caibiran", "naval", "almeria", "san", "isidro"},
    "agency": set(E.AGENCY_WORDS),
}


class TestWordErrorRate:
    def test_perfect_transcript(self):
        r = E.word_error_rate("mayda sunog didi", "mayda sunog didi")
        assert r.wer == 0
        assert r.correct == 3

    def test_case_and_punctuation_are_not_errors(self):
        r = E.word_error_rate("Mayda sunog, didi!", "mayda sunog didi")
        assert r.wer == 0

    def test_substitution(self):
        r = E.word_error_rate("mayda sunog", "mayda tubig")
        assert (r.substitutions, r.deletions, r.insertions) == (1, 0, 0)

    def test_deletion_and_insertion_are_counted_apart(self):
        # Words lost and words invented need different fixes, so a single
        # error count would hide which one you have.
        assert E.word_error_rate("a b c", "a c").deletions == 1
        assert E.word_error_rate("a b", "a b b").insertions == 1

    def test_empty_transcript_loses_everything(self):
        r = E.word_error_rate("mayda sunog", "")
        assert r.deletions == 2
        assert r.wer == 1.0

    def test_empty_reference_does_not_divide_by_zero(self):
        assert E.word_error_rate("", "").wer == 0
        assert E.word_error_rate("", "sunog").insertions == 1

    def test_wer_can_exceed_one_when_words_are_invented(self):
        r = E.word_error_rate("sunog", "kaibigan kaibigan kaibigan")
        assert r.wer > 1.0


class TestCriticalWords:
    def test_finds_emergency_terms_and_places(self):
        found = dict(E.critical_words("mayda sunog didi ha Caibiran", VOCAB))
        assert found["sunog"] == "emergency"
        assert found["caibiran"] == "place"

    def test_ordinary_words_are_not_critical(self):
        found = dict(E.critical_words("mayda didi ha", VOCAB))
        assert found == {}

    def test_agency_names_count(self):
        found = dict(E.critical_words("tawag kayo sa bombero", VOCAB))
        assert found["bombero"] == "agency"

    def test_a_sentence_with_no_critical_words_scores_one_but_reports_zero(self):
        # Accuracy of 1.0 with nothing at stake is not the same as doing well,
        # so `total` has to be readable alongside it.
        s = E.score_critical_words("mayda didi ha", "mayda didi ha", VOCAB)
        assert s.total == 0
        assert s.accuracy == 1.0

    def test_word_order_does_not_matter(self):
        # A recogniser that gets `sunog` but misplaces it has still conveyed
        # that there is a fire.
        s = E.score_critical_words("sunog ha Naval", "naval may sunog", VOCAB)
        assert s.accuracy == 1.0


class TestTheRecordedSample:
    """The pair captured on a handset, speaking Waray.

    Which recogniser produced it is not recorded, and the guess written here
    first — Cebuano — is contradicted by the device: the diagnostic screen
    later showed the handset has no ceb and no fil recogniser installed at all,
    only English variants. Do not restate the locale in the paper without a
    diagnostic run that names it.
    """

    SAID = "Mayda sunog didi ha Caibiran"
    HEARD = "mayda sunog didiha kaibigan kaibigan"

    def test_wer_looks_bad(self):
        assert E.word_error_rate(self.SAID, self.HEARD).wer > 0.5

    def test_but_the_emergency_word_survived(self):
        s = E.score_critical_words(self.SAID, self.HEARD, VOCAB)
        assert "sunog" in s.hit
        assert "caibiran" in s.missed

    def test_the_breakdown_is_the_finding(self):
        # Two numbers carry the whole story: the emergency vocabulary came
        # through intact, the place names did not.
        s = E.score_critical_words(self.SAID, self.HEARD, VOCAB)
        assert s.by_kind["emergency"] == {"total": 1, "recognised": 1}
        assert s.by_kind["place"] == {"total": 1, "recognised": 0}


class TestEvaluateEndToEnd:
    """Uses the real dictionaries, so it needs the model."""

    @pytest.fixture(autouse=True)
    def _model(self):
        from app.services import triage_service as T

        if not T.load():
            pytest.skip(f"triage model unavailable: {T.status().get('error')}")

    def test_correction_recovers_the_place_name(self):
        r = E.evaluate(
            "Mayda sunog didi ha Caibiran",
            "mayda sunog didiha kaibigan kaibigan",
        )
        assert "corrected" in r
        assert r["raw"]["critical_words"]["missed"] == ["caibiran"]
        assert r["corrected"]["critical_words"]["accuracy"] == 1.0
        assert "caibiran" in r["critical_words_recovered"]

    def test_correction_improves_wer_on_this_sample(self):
        # The measured justification for the correction layer. If this ever
        # inverts, the layer is making transcripts worse.
        r = E.evaluate(
            "Mayda sunog didi ha Caibiran",
            "mayda sunog didiha kaibigan kaibigan",
        )
        assert (
            r["corrected"]["word_error_rate"]["wer"]
            <= r["raw"]["word_error_rate"]["wer"]
        )

    def test_a_clean_transcript_is_not_made_worse(self):
        clean = "may sunog ha Naval"
        r = E.evaluate(clean, clean)
        assert r["raw"]["word_error_rate"]["wer"] == 0
        assert r["corrected"]["word_error_rate"]["wer"] == 0

    def test_an_empty_transcript_evaluates_without_raising(self):
        r = E.evaluate("mayda sunog", "")
        assert r["raw"]["word_error_rate"]["wer"] == 1.0
        assert r["raw"]["critical_words"]["recognised"] == 0

    def test_real_vocabulary_includes_biliran_places(self):
        vocab = E._critical_vocabulary()
        assert "caibiran" in vocab["place"]
        assert "naval" in vocab["place"]
        assert "sunog" in vocab["emergency"]
