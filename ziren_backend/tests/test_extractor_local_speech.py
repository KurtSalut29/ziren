"""What the extractor recovers from how residents actually speak.

Every case here is either a real report from the Ziren database or a minimal
variation on one. The two it was written for — "naay na trap sa sulod" and
"duha kabook ang na trap" — are verbatim from filed reports, and both were
silently returning "nothing known" about the most important fact in them.
"""
import pytest

from app.ml.tools.predict import extract


def sig(text):
    signals, _hedged = extract(text)
    return signals


class TestEntrapmentBorrowing:
    """"na trap" is the English verb carrying a Bisaya/Waray perfective prefix."""

    @pytest.mark.parametrize("text", [
        "naay na trap sa sulod",
        "naay na-trap sa sulod",
        "naay natrap sa sulod",
        "duha kabook ang na trap",
        "may na trapped pa sa loob",
    ])
    def test_recovered(self, text):
        assert sig(text)["entrapment"] is True

    def test_real_fire_report(self):
        # Verbatim, incident 013477d6.
        s = sig("Sunog / Fire — mayda sunog Didi ha caibiran, dako na Ang sunog "
                "tapos mga Balay Kay dikit dikit og naay na trap sa sulod")
        assert s["entrapment"] is True
        assert s["structure_involved"] is True
        assert s["location"] == "Caibiran"

    def test_denial_still_denies(self):
        # A denial must stay a denial, not become a match on the new pattern.
        assert sig("waray na trap, safe na kami")["entrapment"] is False

    def test_silence_is_not_denial(self):
        assert sig("may sunog sa may tulay")["entrapment"] is None


class TestCountingClassifier:
    """"kabuok" / "kabook" / "ka buok" — counting people without naming them."""

    def test_trapped_count(self):
        # Verbatim, incident 3dbe1468.
        s = sig("May sunog Ari sa may tulay sir duha kabook ang na trap")
        assert s["entrapment"] is True
        assert s["people_involved"] == 2

    @pytest.mark.parametrize("text,expected", [
        ("tulo kabuok ang nasamdan", 3),
        ("duha kabook ang nasamdan", 2),
        ("duha ka tawo ang nasamdan", 2),
        ("tulo ka tawo an nasamdan", 3),
    ])
    def test_injured_count_survives_the_classifier(self, text, expected):
        assert sig(text)["injured_count"] == expected

    def test_a_denied_entrapment_imports_no_count(self):
        assert sig("waray na trap didi")["people_involved"] is None


class TestNoRegression:
    """The phrasings that already worked must keep working."""

    def test_vehicles_are_not_people(self):
        s = sig("duha ka motor nag bangga")
        assert s["vehicles_involved"] == 2
        assert s["people_involved"] is None
        assert s["injured"] is None

    def test_naipit_still_reads(self):
        s = sig("tulo ka tawo nga naipit sa balay")
        assert s["entrapment"] is True
        assert s["people_involved"] == 3

    @pytest.mark.parametrize("text,dead", [
        ("usa ka patay", 1),
        ("duha ang patay", 2),
    ])
    def test_fatalities_still_read(self, text, dead):
        assert sig(text)["fatalities"] == dead
