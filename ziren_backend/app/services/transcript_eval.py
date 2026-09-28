"""
Transcript evaluation — how well speech recognition served a report.

Why Word Error Rate is not enough
---------------------------------
WER treats every word as equally important. For an emergency report they are
not. The first live Waray sample scored badly and was, in the way that
mattered, fine:

    said:  Mayda sunog didi ha Caibiran
    heard: mayda sunog didiha kaibigan kaibigan
    WER:   80%

`sunog` is what makes this a fire. It came through. The errors landed on a
place name the app already takes from GPS. A report can also fail the other
way — a transcript with excellent WER that lost the single word deciding
whether anyone is trapped.

So this module reports two things side by side: WER, for comparability with
published work, and **critical word accuracy**, for whether the words that
change the dispatch decision survived.

What counts as critical
-----------------------
Not a hand-written list. The words are taken from the sources the pipeline
already treats as authoritative:

  * `06_DICTIONARY/emergency_terms.csv` — the vocabulary the model was trained
    on, in Waray, Cebuano, Tagalog and English
  * `predict.BARANGAYS` — Biliran municipalities and barangays
  * agency names, which a resident may say and a dispatcher acts on

Duplicating any of that here would mean two lists drifting apart.

Before and after correction
---------------------------
Every score is computed twice: against the raw transcript, and against the
transcript after the pipeline's normalisation and Ziren's speech corrections.
The difference is the honest measure of whether that correction layer earns
its place. `kaibigan -> Caibiran` should show up as a recovered critical word,
and if it does not, the layer is not doing what it claims.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

import structlog

log = structlog.get_logger()

# Agencies a resident may name aloud. Small, closed, and not held anywhere
# else in a form this needs — the rubric configs key on agency *type* enums,
# not on the spoken words.
AGENCY_WORDS = {
    "pnp", "bfp", "mdrrmo", "pulis", "police", "bombero", "firefighter",
    "ambulansya", "ambulance", "responder", "rescue", "barangay",
}

_TOKEN = re.compile(r"[^\w'\-]+", re.UNICODE)


def _tokenise(text: str) -> list[str]:
    return [t for t in _TOKEN.split((text or "").lower()) if t]


@dataclass
class WordErrorRate:
    substitutions: int
    deletions: int
    insertions: int
    reference_words: int
    correct: int

    @property
    def errors(self) -> int:
        return self.substitutions + self.deletions + self.insertions

    @property
    def wer(self) -> float:
        """0.0 is perfect. Can exceed 1.0 when words are invented."""
        return 0.0 if self.reference_words == 0 else self.errors / self.reference_words

    def as_dict(self) -> dict[str, Any]:
        return {
            "wer": round(self.wer, 4),
            "correct": self.correct,
            "reference_words": self.reference_words,
            "substitutions": self.substitutions,
            "deletions": self.deletions,
            "insertions": self.insertions,
        }


@dataclass
class CriticalWordScore:
    """How the words that change a dispatch decision fared."""

    total: int = 0
    recognised: int = 0
    missed: list[str] = field(default_factory=list)
    hit: list[str] = field(default_factory=list)
    by_kind: dict[str, dict[str, int]] = field(default_factory=dict)

    @property
    def accuracy(self) -> float:
        """1.0 when every critical word survived. 1.0 also when the sentence
        contained none — there was nothing to lose, which is not the same as
        doing well, so callers should read `total` alongside it."""
        return 1.0 if self.total == 0 else self.recognised / self.total

    def as_dict(self) -> dict[str, Any]:
        return {
            "accuracy": round(self.accuracy, 4),
            "total": self.total,
            "recognised": self.recognised,
            "hit": self.hit,
            "missed": self.missed,
            "by_kind": self.by_kind,
        }


def word_error_rate(said: str, heard: str) -> WordErrorRate:
    """Levenshtein over words, with each operation counted separately.

    Words lost and words invented call for different fixes, so a single error
    count would hide the distinction that tells you which one you have.
    """
    ref = _tokenise(said)
    hyp = _tokenise(heard)

    if not ref:
        return WordErrorRate(0, 0, len(hyp), 0, 0)

    rows, cols = len(ref) + 1, len(hyp) + 1
    dist = [[0] * cols for _ in range(rows)]
    for i in range(rows):
        dist[i][0] = i
    for j in range(cols):
        dist[0][j] = j

    for i in range(1, rows):
        for j in range(1, cols):
            cost = 0 if ref[i - 1] == hyp[j - 1] else 1
            dist[i][j] = min(
                dist[i - 1][j] + 1,      # deletion
                dist[i][j - 1] + 1,      # insertion
                dist[i - 1][j - 1] + cost,
            )

    i, j = len(ref), len(hyp)
    subs = dels = ins = correct = 0
    while i > 0 or j > 0:
        if (
            i > 0
            and j > 0
            and dist[i][j] == dist[i - 1][j - 1] + (0 if ref[i - 1] == hyp[j - 1] else 1)
        ):
            if ref[i - 1] == hyp[j - 1]:
                correct += 1
            else:
                subs += 1
            i, j = i - 1, j - 1
        elif i > 0 and dist[i][j] == dist[i - 1][j] + 1:
            dels += 1
            i -= 1
        else:
            ins += 1
            j -= 1

    return WordErrorRate(subs, dels, ins, len(ref), correct)


def _critical_vocabulary() -> dict[str, set[str]]:
    """The authoritative word sets, read from the loaded model.

    Imported lazily and defensively: this module is useful for WER even when
    the triage model has not loaded, and an evaluation helper must never be
    the reason an import fails.
    """
    from app.services import triage_service as T

    emergency: set[str] = set()
    places: set[str] = set()

    T.load()
    if T._TERMS:
        emergency = {t.lower() for t in T._TERMS}

    try:
        from app.ml.tools import predict as Z

        for name in Z.BARANGAYS:
            # Multi-word names ("san isidro") contribute each part, because a
            # recogniser loses them one word at a time.
            places.update(name.lower().split())
    except Exception as e:  # pragma: no cover - only on a broken install
        log.warning("transcript_eval.places_unavailable", error=str(e))

    return {
        "emergency": emergency,
        "place": places,
        "agency": set(AGENCY_WORDS),
    }


def critical_words(said: str, vocabulary: dict[str, set[str]] | None = None) -> list[tuple[str, str]]:
    """The (word, kind) pairs in `said` that matter to a dispatcher."""
    vocab = vocabulary if vocabulary is not None else _critical_vocabulary()
    found: list[tuple[str, str]] = []
    for token in _tokenise(said):
        for kind in ("emergency", "place", "agency"):
            if token in vocab.get(kind, ()):
                found.append((token, kind))
                break
    return found


def score_critical_words(
    said: str,
    heard: str,
    vocabulary: dict[str, set[str]] | None = None,
) -> CriticalWordScore:
    """Of the critical words spoken, how many appear in the transcript.

    Presence is checked as a set rather than by position: a recogniser that
    gets `sunog` but puts it in the wrong place has still conveyed that there
    is a fire, and word order is not what a dispatcher acts on.
    """
    vocab = vocabulary if vocabulary is not None else _critical_vocabulary()
    heard_tokens = set(_tokenise(heard))

    score = CriticalWordScore()
    for word, kind in critical_words(said, vocab):
        bucket = score.by_kind.setdefault(kind, {"total": 0, "recognised": 0})
        bucket["total"] += 1
        score.total += 1
        if word in heard_tokens:
            bucket["recognised"] += 1
            score.recognised += 1
            score.hit.append(word)
        else:
            score.missed.append(word)
    return score


def evaluate(said: str, heard: str) -> dict[str, Any]:
    """Full evaluation of one spoken-vs-transcribed pair.

    Scores the raw transcript and, separately, the transcript after the
    pipeline's normalisation and Ziren's speech corrections — so the value of
    that correction layer is measured rather than asserted.

    Never raises. An evaluation helper that can fail is one that stops being
    run.
    """
    vocab = _critical_vocabulary()

    raw_wer = word_error_rate(said, heard)
    raw_critical = score_critical_words(said, heard, vocab)

    corrected_text: str | None = None
    corrections: list[str] = []
    corrected_wer = None
    corrected_critical = None

    try:
        from app.services import triage_service as T

        if T.is_available():
            # The same call production makes, not a reconstruction of it.
            # See triage_service.normalise_text.
            corrected_text, corrections = T.normalise_text(heard)
            corrected_wer = word_error_rate(said, corrected_text)
            corrected_critical = score_critical_words(said, corrected_text, vocab)
    except Exception as e:
        log.warning("transcript_eval.correction_failed", error=str(e))

    result: dict[str, Any] = {
        "said": said,
        "heard": heard,
        "raw": {
            "text": heard,
            "word_error_rate": raw_wer.as_dict(),
            "critical_words": raw_critical.as_dict(),
        },
    }

    if corrected_text is not None:
        result["corrected"] = {
            "text": corrected_text,
            "corrections": corrections,
            "word_error_rate": corrected_wer.as_dict(),
            "critical_words": corrected_critical.as_dict(),
        }
        result["critical_words_recovered"] = sorted(
            set(corrected_critical.hit) - set(raw_critical.hit)
        )

    return result
