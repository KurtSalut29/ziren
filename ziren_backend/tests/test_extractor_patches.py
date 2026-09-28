"""The false positives three unanchored regex fragments were producing.

WEAPON matched a bare `gun`, MEDICAL_NEED a bare `pale`, SPREAD a bare
`grabe na`. All three fired inside longer words, which in Waray and Cebuano is
not a rare accident: the languages build meaning by prefixing, so a fragment
with no boundary sits inside unrelated vocabulary constantly. `nangunguna`
(leading) carries `gun` eight times in the corpus; `nagun-ob` (collapsed) made
a landslide report announce a weapon.

Every case below is a real row or a real lexicon form. The second class of test
is the one that matters more: the words the patterns are actually FOR still
match, because an anchor that fixes a false positive by deleting a true one is
not a fix.
"""

import pytest

from app.services import triage_service as T


@pytest.fixture(scope="module", autouse=True)
def loaded():
    T.load()


@pytest.fixture(scope="module")
def Z():
    return T._Z


class TestFalsePositivesAreGone:
    @pytest.mark.parametrize(
        "text,pattern",
        [
            # 8 rows in classification_dataset.csv
            ("an nangunguna nga sakyanan nabangga", "WEAPON"),
            ("nangungulit hiya ha amon", "WEAPON"),
            # SR005C 'weapon present - danger to responders', on a landslide
            ("nagun-ob an bungtod didi ha Caraycaray", "WEAPON"),
            # the courtesy word for 'please'
            ("palehog dali kamo didi", "MEDICAL_NEED"),
            # all three 'grabe na' rows in the corpus
            ("grabe nagkabanggaay an duha ka motor", "SPREAD"),
            ("grabe nasusulod an tubig ha balay", "SPREAD"),
            ("grabe nagdidilaab an kalayo", "SPREAD"),
        ],
    )
    def test_no_longer_matches(self, text, pattern, Z):
        assert not getattr(Z, pattern).search(text), f"{pattern} still fires on {text!r}"

    def test_landslide_no_longer_reports_a_weapon(self, Z):
        sig, _ = Z.extract("nagun-ob an bungtod didi ha Caraycaray waray nasamdan")
        assert not sig["weapon_mentioned"]


class TestTruePositivesSurvive:
    @pytest.mark.parametrize(
        "text,pattern",
        [
            ("he has a gun", "WEAPON"),
            ("two men with guns", "WEAPON"),
            ("we heard a gunshot", "WEAPON"),
            ("gunfire near the plaza", "WEAPON"),
            ("may dala nga baril", "WEAPON"),
            ("sundang an gamit", "WEAPON"),
            ("she is very pale and cold", "MEDICAL_NEED"),
            ("namumutla na po siya", "MEDICAL_NEED"),
            ("palihog tawag hin ambulansya", "MEDICAL_NEED"),
            ("the fire is spreading", "SPREAD"),
            ("nagkakalat na an kalayo", "SPREAD"),
        ],
    )
    def test_still_matches(self, text, pattern, Z):
        assert getattr(Z, pattern).search(text), f"{pattern} stopped firing on {text!r}"

    def test_a_real_weapon_still_raises_the_responder_warning(self, Z):
        sig, _ = Z.extract("may lalaki nga may dala nga sundang didi ha kanto")
        assert sig["weapon_mentioned"]
        assert Z.severity(sig, "CRIME", 0.9)[0] == "SR005C"


class TestPatchApplication:
    def test_all_three_applied_at_load(self):
        # load() already applied them; assert on the live module, not by
        # re-applying, which would pass even if load() had skipped it.
        assert r"\bgun" in T._Z.WEAPON.pattern
        assert r"\bpale\b" in T._Z.MEDICAL_NEED.pattern
        assert r"\bgrabe na\b" in T._Z.SPREAD.pattern

    def test_the_rest_of_each_pattern_is_untouched(self):
        """Only the fragment changes -- a release that adds a weapon keeps it."""
        for term in ("kutsilyo", "granada", "sanggot", "armas", "bolo"):
            assert term in T._Z.WEAPON.pattern
        for term in ("ambulansya", "nakuryente", "electrocut", "natumba"):
            assert term in T._Z.MEDICAL_NEED.pattern
        for term in ("nagkakalat", "nagsangyaw", "padayon nga"):
            assert term in T._Z.SPREAD.pattern

    def test_a_missing_fragment_is_skipped_not_raised(self):
        """A release that already fixed the anchoring must not break startup."""
        import re
        import types

        from app.services import extractor_patches

        fake = types.SimpleNamespace(
            WEAPON=re.compile(r"\bgun\b|armas", re.I),      # already anchored
            MEDICAL_NEED=re.compile(r"ambulansya|pale|x", re.I),
            SPREAD=re.compile(r"spreading", re.I),           # fragment gone
        )
        assert extractor_patches.apply(fake) == ["MEDICAL_NEED"]
