"""Alias correction must work at any casing, and must never lie about it.

The release applies an alias with `w.replace(bare, ...)` where `bare` is
lower-cased and `w` is not, so the needle is never found in a capitalised word.
The correction silently does nothing and is appended to the change log anyway.

It survived because nothing could see it. The change log reports success, so
the call site looks healthy; transcript_eval measures the layer through the
same function, so its "after corrections" figure was crediting corrections that
never ran; and every one of the seven human-verified rows in
stt_corrections.csv occurs zero times in the 1829-row corpus -- they were
written from recordings, and the corpus is written text -- so no dataset
measurement could have caught it either. It took a real handset transcript:
"Sir Tabang Naay Na Sunog Didiha Amon", where `didiha -> didi ha` was reported
and not applied.

The last test in this file is the one that matters. Getting the casing right is
a fix; refusing to report a correction that did not happen is what stops the
next silent failure from being invisible for as long as this one was.
"""

import csv
from pathlib import Path

import pytest

from app.services import triage_service as T

_CORRECTIONS = Path(__file__).resolve().parent.parent / "app" / "ml_overrides" / "stt_corrections.csv"


@pytest.fixture(scope="module", autouse=True)
def loaded():
    T.load()


@pytest.fixture(autouse=True)
def repair_on():
    """Every test states its own flag; none may leak into the next."""
    T.ALIAS_CASE_REPAIR = True
    yield
    T.ALIAS_CASE_REPAIR = True


def observed_corrections():
    with _CORRECTIONS.open(encoding="utf-8") as fh:
        return [(r["observed"], r["corrected"]) for r in csv.DictReader(fh)]


class TestCasingDoesNotDefeatACorrection:
    @pytest.mark.parametrize("observed,corrected", observed_corrections())
    @pytest.mark.parametrize("case", [str.lower, str.title, str.upper])
    def test_every_verified_correction_applies(self, observed, corrected, case):
        """All seven rows, at three casings. Each was signed off against audio."""
        out, _ = T.normalise_text(case(observed))
        assert corrected.lower() in out.lower(), f"{case(observed)!r} -> {out!r}"

    def test_the_real_handset_transcript(self):
        raw = ("Sir Tabang Naay Na Sunog Didiha Amon, need na mong help ninyo "
               "kay Naay Natrap Natawo.")
        out, _ = T.normalise_text(raw)
        assert "didi ha" in out
        assert "Didiha" not in out

    def test_surrounding_punctuation_survives(self):
        out, _ = T.normalise_text("Sunog Didiha, dali!")
        assert "didi ha," in out

    def test_protected_words_are_still_untouchable(self):
        protected = getattr(T._Z, "PROTECTED", set())
        assert protected, "PROTECTED is empty; this test would prove nothing"
        for word in list(protected)[:15]:
            out, _ = T.normalise_text(word.title())
            assert out.lower() == word.lower()


class TestTheFlagRestoresReleaseBehaviour:
    def test_off_reproduces_the_bug(self):
        """Kept measurable, the way FUZZY_NORMALISATION is."""
        T.ALIAS_CASE_REPAIR = False
        out, changes = T.normalise_text("Sunog Didiha Amon")
        assert out == "Sunog Didiha Amon"
        assert any("didiha" in c for c in changes)  # the release reports it anyway

    def test_on_fixes_it(self):
        T.ALIAS_CASE_REPAIR = True
        out, _ = T.normalise_text("Sunog Didiha Amon")
        assert out == "Sunog didi ha Amon"


class TestTheChangeLogTellsTheTruth:
    """A reported correction that did not happen is worse than no correction.

    This is the invariant the codebase was missing. The casing bug was one way
    to break it; this test does not care which way the next one arrives.
    """

    @pytest.mark.parametrize(
        "text",
        [
            "Sunog Didiha Amon",
            "sunog didiha amon",
            "TULUKATAW ANASAMDAN",
            "Tulukataw Anasamdan",
            "may Sonog didi ha Brgy Caraycaray",
            "Doha Kataw An Naipit",
            "wala man diri hin problema",
        ],
    )
    def test_every_reported_alias_actually_changed_the_text(self, text):
        out, changes = T.normalise_text(text)
        for change in changes:
            if not change.endswith("(alias)"):
                continue
            before, after = change.replace(" (alias)", "").split(" -> ", 1)
            assert after.lower() in out.lower(), (
                f"change log claims {before!r} -> {after!r}, but the output is {out!r}"
            )
