"""The correction layer that replaced the one measured doing harm.

Every case in TestKnownRegressions is a rewrite the DISABLED edit-distance
pass actually made, taken from the measurement recorded above
`triage_service.FUZZY_NORMALISATION`: 249 rows, severity changed on ten, three
up and seven down. They are here so that turning correction back on can never
quietly reintroduce them.

The rest is what the layer is for: a word whose sounds are right and whose
letters are not, across every incident type — not just fire.
"""
import pytest

from app.services import phonetic
from app.services import triage_service as T


@pytest.fixture(scope="module", autouse=True)
def loaded():
    T.load()


def corrected(text: str) -> str:
    out, _changes = T.normalise_text(text)
    return out


# ── the rewrites that made the old approach unshippable ────────────────────

class TestKnownRegressions:
    """None of these words may be rewritten into the other. Ever."""

    @pytest.mark.parametrize("word,wrong,harm", [
        ("bahay", "baha", "house -> flood; cut a burning house from HIGH to MODERATE, 9x"),
        ("tulo", "tulong", "three -> help; destroys the casualty count"),
        ("nagsusuntukan", "nagsusuka", "brawl -> vomiting"),
        ("makaginhawa", "makagawas", "can breathe -> can get out"),
        ("nakakaon", "nakawan", "eating -> robbery"),
        ("nagtataas", "nagtatae", "water rising -> diarrhoea"),
    ])
    def test_keys_do_not_collide(self, word, wrong, harm):
        assert phonetic.key(word) != phonetic.key(wrong), harm

    def test_a_burning_house_stays_a_house(self):
        # The concrete harm, in a whole sentence rather than a word pair.
        out = corrected("nasusunog po ang bahay")
        assert "bahay" in out
        assert "baha " not in out + " "

    def test_a_count_is_not_a_plea_for_help(self):
        assert "tulong" not in corrected("tulo ka tawo ang nasamdan")

    def test_valid_words_are_never_rewritten(self):
        # The old pass rewrote words that were already correct. This one is
        # only allowed to touch words the vocabulary does not contain.
        for word in ("sunog", "baha", "nasamdan", "patay", "naipit"):
            assert corrected(f"may {word} didi") == f"may {word} didi"


# ── what the layer is actually for ─────────────────────────────────────────

class TestSoundsRightSpelledWrong:
    @pytest.mark.parametrize("typo,expected,category", [
        ("zunog",     "sunog",     "fire — the panel's own example"),
        ("sunug",     "sunog",     "fire — o/u are allophones"),
        ("kalayu",    "kalayo",    "fire — Cebuano"),
        ("aksidenti", "aksidente", "vehicular"),
        ("nagdugu",   "nagdugo",   "medical — bleeding"),
        ("kutsilyu",  "kutsilyo",  "crime — blade"),
        ("lindul",    "lindol",    "calamity — earthquake"),
        ("naypit",    "naipit",    "entrapment — the glide y/i"),
    ])
    def test_corrected(self, typo, expected, category):
        assert expected in corrected(f"may {typo} didi ha amon"), category

    def test_every_incident_type_is_covered(self):
        # The panel's request was explicitly not fire-only.
        sentence = "may zunog ug aksidenti ug lindul ug naypit"
        out = corrected(sentence)
        for expected in ("sunog", "aksidente", "lindol", "naipit"):
            assert expected in out


# ── what it deliberately does not do ───────────────────────────────────────

class TestSubstitutionsOnly:
    """Added or dropped letters change the sound, so no sound rule reaches them.

    These belong to the exact alias table — misspellings.csv and
    stt_corrections.csv — which is why both files still matter. Asserted so the
    boundary between the two layers stays documented in something that runs.
    """

    def test_an_inserted_letter_is_not_reachable(self):
        # Observed live from faster-whisper on Waray: "sunog" -> "sunong".
        assert phonetic.key("sunong") != phonetic.key("sunog")

    def test_a_dropped_letter_is_not_reachable(self):
        # Already carried as an exact row in misspellings.csv.
        assert phonetic.key("tabng") != phonetic.key("tabang")


# ── index construction ─────────────────────────────────────────────────────

class TestIndex:
    def test_ambiguous_keys_are_dropped_not_guessed(self):
        # Two real terms that sound alike must correct to neither, rather than
        # to whichever happened to be inserted first.
        index = phonetic.build_index(["sunog", "sunug", "banggaan"])
        assert phonetic.key("sunog") not in index
        assert index[phonetic.key("banggaan")] == "banggaan"

    def test_short_terms_are_excluded(self):
        # Short words collide on sound constantly and carry little severity.
        assert phonetic.build_index(["aso", "usa", "duha"]) == {}

    def test_empty_index_is_a_no_op(self):
        text = "may zunog sa balay"
        assert phonetic.correct(text, {}) == (text, [])

    def test_changes_are_reported_for_promotion(self):
        # Every firing is logged so a recurring one can be promoted into the
        # exact alias table.
        _out, changes = T.normalise_text("may zunog didi")
        assert any("zunog -> sunog" in c for c in changes)
