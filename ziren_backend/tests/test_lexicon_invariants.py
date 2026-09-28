"""The lexicon is held to its invariants on every run, not on every review.

scripts/validate_lexicon.py encodes eight defects that shipped in
ziren_lexicon.json 0.3.0 as rules the file may not violate. This module runs
those rules in CI, and then pins the individual defects a second time.

The duplication is deliberate. An invariant can be relaxed by one line in the
validator; a named regression test cannot be relaxed without someone deleting a
test that says what the bug did. The greeting case is the reason: it survived a
validator that reported "All invariants hold", and nothing about the entry
looked wrong -- 'maayong adlaw' -> 'maayong' reads like tidying until you notice
adlaw is the whole time-of-day register.
"""

import importlib.util
import json
from pathlib import Path

import pytest

_BACKEND = Path(__file__).resolve().parent.parent
_LEXICON = _BACKEND / "app" / "ml_overrides" / "ziren_lexicon.json"
_VALIDATOR = _BACKEND / "scripts" / "validate_lexicon.py"


def _load_validator():
    spec = importlib.util.spec_from_file_location("validate_lexicon", _VALIDATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def doc():
    return json.loads(_LEXICON.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def validator():
    return _load_validator()


@pytest.fixture(scope="module")
def entries(doc):
    return {e["canonical"].lower(): e for e in doc["lexicon"]}


@pytest.fixture(scope="module")
def variant_of(doc):
    """canonical -> the set of surface forms that rewrite into it."""
    out = {}
    for e in doc["lexicon"]:
        out[e["canonical"].lower()] = {v.lower() for v in e["variants"]}
    return out


def test_every_invariant_holds(doc, validator):
    report = validator.check(doc)
    assert report.problems == [], "\n".join(f"{c}  {m}" for c, m in report.problems)


# ── the defects, pinned one at a time ─────────────────────────────────────


class TestGreetingsDoNotEatTheClock:
    """'maayong adlaw' -> 'maayong' deleted adlaw.

    adlaw, araw, gab-i and buntag are the entire `time` register. Because 244
    reports open with a greeting, the rewrite meant those reports could never
    produce a time-of-day signal -- the evidence was gone before any extractor
    ran. Greetings are now standalone words with no content-bearing variants.
    """

    @pytest.mark.parametrize("greeting", ["maayong", "maupay", "magandang", "good"])
    def test_greeting_has_no_content_bearing_variant(self, greeting, variant_of, doc):
        # A greeting may keep a variant that only adds a particle -- 'maayo nga'
        # is one word plus a linker, and rewriting it to 'maayong' deletes
        # nothing. It may not keep one that carries a second content word,
        # which is what 'maayong adlaw' did.
        grammar = {w.lower() for w in doc["meta"]["grammar_excluded"]}
        for variant in variant_of[greeting]:
            content = [w for w in variant.split() if w not in grammar]
            assert len(content) <= 1, f"{variant!r} carries content beyond the greeting: {content}"

    @pytest.mark.parametrize("word", ["adlaw", "araw", "gab-i", "buntag", "aga"])
    def test_time_words_survive_as_their_own_entries(self, word, entries):
        assert entries[word]["register"] == "time"


class TestNegationSurvivesNormalisation:
    """"dili makaginhawa" and "makaginhawa" differ by one word and by an ambulance.

    0.3.0 filed dili/hindi/wala as register 'uncurated', lang 'unknown', gloss
    '' -- neither excluded nor described. predict._negated() can only act on
    words that are still in the string, so a negator that gets dropped does not
    weaken a signal, it inverts one.
    """

    @pytest.mark.parametrize("word", ["dili", "hindi", "wala", "waray", "not", "cannot", "ayaw"])
    def test_negator_is_described_and_kept(self, word, entries, doc):
        entry = entries[word]
        assert entry["negation"] is True
        assert entry["register"] == "descriptor"
        assert word not in {w.lower() for w in doc["meta"]["grammar_excluded"]}


class TestMeaningIsNotCollapsed:
    """bana is husband; asawa is wife. The rewrite turned wives into husbands.

    Same shape as son/daughter. The lemma may link them -- that is what the
    lemma layer is for -- but the surface form must not be overwritten, because
    a responder reading the transcript is reading the surface.
    """

    @pytest.mark.parametrize(
        "a,b",
        [
            ("bana", "asawa"),
            ("husband", "wife"),
            ("son", "daughter"),
            ("tulong", "katulong"),
            ("lying", "collapsed"),
        ],
    )
    def test_pair_is_never_merged_into_one_entry(self, a, b, doc):
        for e in doc["lexicon"]:
            forms = {e["canonical"].lower()} | {v.lower() for v in e["variants"]}
            assert not {a, b} <= forms, f"{e['canonical']!r} merges {a}/{b}"

    def test_spouse_lemma_still_links_them(self, entries):
        assert entries["bana"]["lemma"] == entries["asawa"]["lemma"] == "spouse"


class TestIntensityIsNotDeletedIntoItsNoun:
    """'malakas na hangin' -> 'hangin' dropped the only word that made it worth reporting.

    Strong wind and wind are not the same report. The intensity now lives in
    its own `strong` entry and normalises independently, so both survive.
    """

    def test_wind_has_no_multiword_variant(self, variant_of):
        assert all(" " not in v for v in variant_of["hangin"])

    def test_strong_is_reachable_in_both_languages(self, entries):
        assert entries["malakas"]["lemma"] == entries["kusog"]["lemma"] == "strong"


class TestPlaceNamesAreNotRewritten:
    """'mula' was dropped, protected and rewritten at the same time.

    It sat in grammar_excluded, in ambiguous_places_left_to_ner and in tikang's
    variants. The rewrite runs first, so a place called Mula died before NER was
    ever consulted. 'sabang' was the same hazard from the other direction: a
    real barangay name rewritten to 'tabang' to recover a mishearing.
    """

    def test_mula_is_protected_only(self, doc):
        meta = doc["meta"]
        assert "mula" in meta["ambiguous_places_left_to_ner"]
        assert "mula" not in {w.lower() for w in meta["grammar_excluded"]}
        assert not any("mula" in [v.lower() for v in e["variants"]] for e in doc["lexicon"])

    def test_reserved_place_forms_are_never_rewritten(self, doc):
        reserved = {w.lower() for w in doc["meta"]["reserved_place_forms"]}
        for e in doc["lexicon"]:
            assert not reserved & {v.lower() for v in e["variants"]}


class TestLemmaIsAFeatureNotACoinFlip:
    """'burning' resolved to FIRE or to None depending on dict insertion order.

    The uncurated auto-extract re-declared four lemmas the curated half already
    owned, each with incident_concept null. Any {lemma: concept} mapping built
    from the file was therefore order-dependent.
    """

    def test_one_concept_per_lemma(self, doc):
        seen = {}
        for e in doc["lexicon"]:
            pair = (e.get("incident_concept"), e.get("hazard_subtype"))
            assert seen.setdefault(e["lemma"], pair) == pair, e["lemma"]

    def test_curated_and_uncurated_share_no_lemma(self, doc):
        curated = {e["lemma"] for e in doc["lexicon"] if e["register"] != "uncurated"}
        uncurated = {e["lemma"] for e in doc["lexicon"] if e["register"] == "uncurated"}
        assert not curated & uncurated


class TestHedgesAreNotInflated:
    """'about' and 'like' were variants of 'maybe'.

    'about 20 people trapped' became 'maybe 20 people trapped' -- an
    approximator rewritten into uncertainty, inside the numeral span that
    predict._count() reads. 'heavy' -> 'severe' was the same trade in the
    opposite direction.
    """

    @pytest.mark.parametrize("word", ["about", "like", "heavy"])
    def test_word_is_not_a_variant_of_anything(self, word, doc):
        for e in doc["lexicon"]:
            assert word not in [v.lower() for v in e["variants"]], e["canonical"]


class TestNoRewriteBlindsAnExtractor:
    """A rewrite may not delete a signal the extractor could already read.

    This is the invariant the file needed and did not have. 'baka' -> 'siguro'
    looked like an ordinary same-language synonym and was allowlisted as one;
    predict.UNSURE matches baka and not siguro, so the rewrite deleted the
    hedge and read "baka may nasugatan" -- MAYBE someone is hurt -- as a
    statement that someone is. It moved four severities up on the release test
    split before anyone noticed, and no rule in validate_lexicon.py could have
    seen it, because the defect is not in the lexicon: it is in the join
    between the lexicon and predict.py.

    Gaining a signal is the whole point of normalising and is allowed --
    'nalulumos' -> 'nalumos' is exactly what the file is for. Losing one is
    not, and has to be declared here with the reason.

    ALLOWED_LOSSES is empty, and that is the interesting part. Two rewrites --
    nagun-ob -> naguba and palehog -> palihog -- did used to sit here, because
    WEAPON matched a bare 'gun' and MEDICAL_NEED a bare 'pale', so those
    rewrites were defusing the release's own false positives. Anchoring the
    fragments (app/services/extractor_patches.py) removed the false positives
    at the source, and the exceptions with them. A lexicon that has to be
    allowed to break a signal is describing a bug somewhere else.
    """

    ALLOWED_LOSSES: dict[tuple[str, str, str], str] = {}

    @pytest.fixture(scope="class")
    def patterns(self):
        """The patterns as production runs them -- patched, not as shipped.

        load() applies extractor_patches, so testing the unpatched module would
        test a configuration that never serves a report. Applying them here
        makes the result the same whether or not another module got to load()
        first; apply() is idempotent.
        """
        import re

        from app.ml.tools import predict
        from app.services import extractor_patches

        extractor_patches.apply(predict)
        return {
            name: value
            for name, value in vars(predict).items()
            if isinstance(value, re.Pattern) and name.isupper()
        }

    def test_no_undeclared_signal_loss(self, doc, patterns):
        losses = []
        pairs = [(v, e["canonical"]) for e in doc["lexicon"] for v in e["variants"]]
        pairs += [(v, p["canonical"]) for p in doc["phrases"] for v in p["variants"]]
        for variant, canonical in pairs:
            for name, pat in patterns.items():
                if pat.search(variant) and not pat.search(canonical):
                    if (variant, canonical, name) not in self.ALLOWED_LOSSES:
                        losses.append(f"{variant!r} -> {canonical!r} stops matching {name}")
        assert not losses, "\n".join(losses)

    def test_no_rewrite_destroys_a_numeral(self, doc):
        """predict._count() reads WORDNUM; a numeral rewritten out of it is a lost count."""
        from app.ml.tools import predict

        numerals = {n.lower() for n in predict.WORDNUM}
        for e in doc["lexicon"]:
            for v in e["variants"]:
                if v.lower() in numerals:
                    assert e["canonical"].lower() in numerals, (
                        f"{v!r} -> {e['canonical']!r} takes a numeral out of WORDNUM"
                    )

    def test_baka_still_reads_as_a_hedge(self, entries):
        from app.ml.tools import predict

        assert "baka" in entries, "baka must stay in the lexicon, just unrewritten"
        assert predict.UNSURE.search("baka may nasugatan")
