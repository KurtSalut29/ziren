"""Word boundaries the release's signal regexes are missing.

app/ml/ is a verbatim copy of the dataset release and stays that way, so these
are applied to the imported module at load() instead of edited in place --
the same layering triage_service already uses for stt_corrections, where ours
goes on last and wins.

Each patch replaces one fragment of one pattern and recompiles. Nothing else in
the expression is retyped, so a future release that adds a weapon or a symptom
keeps that addition; only the anchoring changes. If a fragment is not found the
patch is skipped and logged rather than raised: a release that has already
fixed the anchoring should not stop the API from starting.

Measured on classification_dataset.csv, 1829 rows:

    WEAPON        'gun'        9 matches, 9 of them false: nangunguna (8x,
                               'leading') and nangungulit. Plus nagun-ob, the
                               Cebuano for collapsed, which fired SR005C
                               'weapon present - danger to responders' on a
                               landslide. No legitimate use of the bare
                               fragment anywhere in the corpus.
    MEDICAL_NEED  'pale'       3 matches, all whole words, all kept. The latent
                               harm is 'palehog' -- a spelling of the courtesy
                               word for 'please' -- which embeds it and fires a
                               medical-need signal on a greeting.
    SPREAD        'grabe na'   3 matches, all 3 embedded and all 3 false:
                               grabe nagkabanggaay, grabe nasusulod, grabe
                               nagdidilaab. Never once a standalone phrase.

NOT patched, on purpose: SPREAD's 'padayon nga' has the same shape and would
match 'padayon ngani', but it does not occur in the corpus at all, so there is
no evidence for what anchoring it would do. Left alone rather than guessed at.

Also worth a decision someone else should make: 'grabe nagdidilaab' (severely
blazing) arguably IS a spreading hazard, and it stops being detected here. It
was only ever detected by accident, through a broken boundary. If blazing
should raise SR008 it should say so deliberately, in the pattern.
"""

from __future__ import annotations

import re

import structlog

log = structlog.get_logger(__name__)

#  (pattern name, fragment as it appears in the release, its replacement)
PATCHES: tuple[tuple[str, str, str], ...] = (
    # 'gunshot' and 'gunfire' currently match as substrings and are kept
    # matching, so the only behaviour that changes is the false positives.
    ("WEAPON", "|gun|", r"|\bgun(?:s|shot|fire)?\b|"),
    ("MEDICAL_NEED", "|pale|", r"|\bpale\b|"),
    ("SPREAD", "|grabe na", r"|\bgrabe na\b"),
)


def apply(module) -> list[str]:
    """Recompile the patched patterns onto `module`. Returns the names applied."""
    applied: list[str] = []
    for name, fragment, replacement in PATCHES:
        pattern = getattr(module, name, None)
        if not isinstance(pattern, re.Pattern):
            log.warning("extractor_patch.absent", pattern=name)
            continue
        source = pattern.pattern
        if source.count(fragment) != 1:
            # Either the release fixed it, or the expression moved on far
            # enough that a blind replace would be a guess.
            log.warning(
                "extractor_patch.skipped",
                pattern=name,
                fragment=fragment,
                occurrences=source.count(fragment),
            )
            continue
        setattr(module, name, re.compile(source.replace(fragment, replacement), pattern.flags))
        applied.append(name)
    return applied
