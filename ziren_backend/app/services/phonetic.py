"""
Correcting words that sound right and are spelled wrong.

The problem
-----------
Residents type in a hurry and recognisers guess. Both produce the same class
of error: a word whose SOUNDS are right and whose LETTERS are not. "zunog" is
"sunog" written as heard. "lindul" is "lindol". "aksidenti" is "aksidente".
None of them match anything, so the report carries no fire, no earthquake, no
accident, and the severity rules see an empty report.

Why this is not the fuzzy matcher
---------------------------------
`predict.normalise()` already has an edit-distance pass, and it is DISABLED
because it was measured doing harm — 249 rows, severity changed on ten, three
up and seven DOWN. The rewrites say why:

    bahay -> baha            9x   house -> flood
    tulo -> tulong                three -> help
    nagsusuntukan -> nagsusuka    brawl -> vomiting
    nagtataas -> nagtatae         water rising -> diarrhoea

Tagalog, Waray and Cebuano build meaning with affixes — na-, nag-, -um-, -an —
so unrelated words sit two edits apart constantly. An edit-distance ratio
cannot tell an affix from a typo, and no threshold fixes that; it is a property
of the languages.

Why a sound key can
-------------------
The substitutions residents and recognisers actually make are systematic in
Philippine orthography, not arbitrary:

    z/s          no native /z/ — "zunog" is "sunog" spelled as heard
    f/p, v/b     no native /f/ or /v/
    c,q -> k     Spanish orthography surviving in loanwords
    x -> ks
    o/u, e/i     allophones in all three languages: sunog/sunug, dako/daku
    y/i          the glide: naypit/naipit

Reduce a word through those and compare the RESULT — not its similarity. That
is a lookup, not a score, so there is no threshold to tune and therefore none
to tune wrong. `bahay` and `baha` differ by a real consonant, so their keys
differ; edit distance called them 89% alike.

What it does not do
-------------------
Substitutions only. A letter genuinely ADDED or DROPPED changes the key:
"sunong" (extra n) and "tabng" (missing a) are not reachable from "sunog" and
"tabang" by any sound rule. Those need an exact entry in misspellings.csv or
stt_corrections.csv, which is why both files still matter — the two layers
cover different mistakes and neither replaces the other.
"""

from __future__ import annotations

import re

import structlog

log = structlog.get_logger()

# Ordered: multi-character expansions first so a later single-character rule
# cannot eat half of one.
_SUBS: tuple[tuple[str, str], ...] = (
    ("x", "ks"),
    ("z", "s"),
    ("c", "k"),
    ("q", "k"),
    ("f", "p"),
    ("v", "b"),
    ("o", "u"),
    ("e", "i"),
    ("y", "i"),
    # b and p, after v has already become b, so v/f/b/p are one class. The
    # recogniser produced "nagpanggahay" and "nagbanggahay" for the same
    # spoken "nag banggaay" on two takes of one sentence; nothing but a
    # voicing merge connects them. Measured on the 61-term emergency
    # vocabulary: no new collisions.
    ("b", "p"),
)

# Intervocalic /h/ is unstable in Waray and Cebuano orthography and in what the
# recogniser writes down: "banggaay" came back as "nagbanggahay". Removing it
# between vowels makes the two one key. Measured: no new collisions on the
# emergency vocabulary.
_INTERVOCALIC_H = re.compile(r"(?<=[aeiou])h(?=[aeiou])")

# Prefixes Waray, Cebuano and Tagalog build verbs with. The vocabulary lists
# stems -- "banggaay", "samdan", "lason" -- but residents speak inflected forms,
# and an exact-key index cannot bridge the two: key("nagbanggaay") and
# key("banggaay") are simply different strings. Indexing the inflections of
# each stem closes that without loosening the matcher.
#
# A prefixed form that collides with another term is dropped by build_index,
# not guessed at, so widening the index cannot introduce an ambiguous rewrite.
_PREFIXES = ("nag", "na", "gi", "gin", "naka", "maka", "mag", "ma", "nan", "nang", "pag")

# And the suffixes. Waray, Cebuano and Tagalog suffix as heavily as they
# prefix -- "baha" becomes "bahaan", "usok" becomes "usokan", "tabang" becomes
# "tabangi" -- and a stem-only index misses every one of those the same way it
# missed "nagbanggaay". Measured over the vocabulary: indexing prefixes alone
# left roughly a third of plausible manglings uncorrected, and suffixed forms
# were the largest identifiable group in that remainder.
#
# Kept to the affixes that carry grammar rather than every possible ending: a
# one-letter suffix collides far more often than it helps, and a collision is
# a dropped key, which costs coverage rather than buying it.
_SUFFIXES = ("an", "on", "han", "hon", "ay", "un", "in", "i")

# Below this a key is too small to be distinctive: three-letter words collide
# on sound constantly, and the words that matter for severity are longer.
_MIN_LENGTH = 5


def key(word: str) -> str:
    """The sound-shape of a word, as Philippine orthography writes it."""
    w = word.lower().strip()
    for a, b in _SUBS:
        w = w.replace(a, b)
    w = _INTERVOCALIC_H.sub("", w)
    # "banggaan" and "bangan" are one word said at two speeds.
    return re.sub(r"(.)\1+", r"\1", w)


def build_index(terms, *, inflect: bool = True) -> dict[str, str]:
    """key -> canonical term, for the vocabulary to correct towards.

    A key claimed by two different terms is dropped rather than guessed at. If
    two real emergency words sound identical, rewriting one into the other is
    exactly the harm this module exists to avoid.
    """
    index: dict[str, str] = {}
    collisions: set[str] = set()

    def claim(k: str, t: str) -> None:
        if k in index and index[k] != t:
            collisions.add(k)
            return
        index[k] = t

    for term in terms:
        t = (term or "").strip().lower()
        if len(t) < _MIN_LENGTH:
            continue
        claim(key(t), t)
        # The inflections of the same stem, so a resident saying "nagbanggaay"
        # reaches a vocabulary that only lists "banggaay". Each corrects back
        # to the stem: the extractors match on the stem, and a form that
        # collides with a different term is dropped below like any other.
        if inflect:
            for prefix in _PREFIXES:
                claim(key(prefix + t), t)
            for suffix in _SUFFIXES:
                if t.endswith(suffix):
                    continue          # already that shape; nothing to add
                claim(key(t + suffix), t)
                for prefix in _PREFIXES:
                    claim(key(prefix + t + suffix), t)

    for k in collisions:
        index.pop(k, None)

    if collisions:
        log.info("phonetic.ambiguous_keys_dropped", count=len(collisions))
    return index


def correct(
    text: str,
    index: dict[str, str],
    *,
    known: set[str] | None = None,
    protected: set[str] | None = None,
) -> tuple[str, list[str]]:
    """Rewrite misspelled words to the vocabulary term they sound like.

    `known` is the set of words that are already correct. A word in it is never
    touched — the failure mode of the disabled fuzzy pass was rewriting valid
    words, not invalid ones.

    Returns the corrected text and a list of what changed, so every firing is
    visible and a recurring one can be promoted into the exact alias table.
    """
    if not index:
        return text, []

    known = known or set()
    protected = protected or set()
    changes: list[str] = []
    out: list[str] = []

    for token in text.split():
        bare = re.sub(r"[^\w']", "", token.lower())
        if (
            not bare
            or len(bare) < _MIN_LENGTH
            or bare in protected
            or bare in known
        ):
            out.append(token)
            continue

        match = index.get(key(bare))
        if match and match != bare:
            out.append(token.lower().replace(bare, match))
            changes.append(f"{bare} -> {match} (sound)")
            continue

        out.append(token)

    return " ".join(out), changes
