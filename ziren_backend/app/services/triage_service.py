"""
Triage service — runs the trained Ziren model over an incoming report.

This is the Phase 4 NLP pipeline. It replaces the placeholder `severity: None`
that _create_incident_row() used to write, and it is the only place the model
is called from.

Where the model lives
---------------------
`app/ml/tools/predict.py` is a VERBATIM copy of tools/predict.py from the
ZIREN_DATASET release. It is never edited. The surrounding folders
(`app/ml/07_MODELS`, `app/ml/06_DICTIONARY`) reproduce the layout it expects,
so upgrading to a new dataset release is a file copy, not a re-patch. The
release version is recorded in `app/ml/VERSION` and stored on every incident
so a dispatcher can tell which model produced a given severity.

Fidelity to the reference API
-----------------------------
The logic below mirrors tools/api.py's /predict endpoint step for step, so the
standalone API and this backend return the same answer for the same report.
That equivalence is the point: the model demonstrated in isolation is the model
running in production.

Fail-safe contract
------------------
An emergency report must never fail because a classifier is unavailable.
Every entry point here returns None instead of raising. When it returns None
the incident is still saved with severity NULL, which the dispatcher queue
already renders as "needs human triage".
"""

import json
import re
import os
import threading
from typing import Any

import time

import structlog

from app.models.incident import IncidentCategory, SeverityLevel
from app.services import extractor_patches, phonetic

log = structlog.get_logger()

_ML_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ml"
)

# Ziren's own corrections, layered on top of the release dictionaries.
# app/ml/ is a verbatim copy of the dataset release and stays that way; things
# we learn about *our* input channel belong here instead, so a dataset upgrade
# never overwrites them and never has to carry them.
_OVERRIDES_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ml_overrides"
)

# -- Loader state -------------------------------------------------------------
# The model is ~570KB and loads in well under a second, but it is loaded once
# at startup and reused. _lock guards the first load only; predict_proba on a
# fitted scikit-learn pipeline is read-only and safe to call concurrently.
_lock = threading.Lock()
_Z = None            # the predict module
_MODEL = None        # the fitted sklearn pipeline
_ALIASES: dict = {}

# key -> canonical term, built from the emergency vocabulary at load().
# Empty until then, and correct() no-ops on an empty index, so a failed load
# degrades to alias-only correction rather than to a crash.
_PHONETIC_INDEX: dict = {}
_TERMS: list = []
_VERSION = "unknown"
_LOAD_ERROR: str | None = None
_LOADED = False


# -- Taxonomy -----------------------------------------------------------------
# The model knows six categories; the app knows six (hazmat and missing_person
# were retired when the model was integrated). ACCIDENT is the model's generic
# bucket and has no app equivalent, so it lands on `other` — the honest answer
# rather than a forced guess at an agency.
BACKEND_TO_MODEL: dict[IncidentCategory, str] = {
    IncidentCategory.fire:                     "FIRE",
    IncidentCategory.medical_trauma:           "MEDICAL",
    IncidentCategory.vehicular:                "VEHICULAR_ACCIDENT",
    IncidentCategory.flood_landslide_calamity: "NATURAL_HAZARD",
    IncidentCategory.domestic_dispute_crime:   "CRIME",
    # `other` is deliberately absent: it means "the resident did not choose",
    # which the model treats as NO_SELECTION and answers with its own reading.
}

MODEL_TO_BACKEND: dict[str, IncidentCategory] = {
    "FIRE":               IncidentCategory.fire,
    "MEDICAL":            IncidentCategory.medical_trauma,
    "VEHICULAR_ACCIDENT": IncidentCategory.vehicular,
    "NATURAL_HAZARD":     IncidentCategory.flood_landslide_calamity,
    "CRIME":              IncidentCategory.domestic_dispute_crime,
    "ACCIDENT":           IncidentCategory.other,
}

# predict.severity() returns MODERATE; the incidents table CHECK constraint
# spells the same level `medium`. This mapping is the only place that differs.
SEVERITY_MAP: dict[str, SeverityLevel] = {
    "CRITICAL": SeverityLevel.critical,
    "HIGH":     SeverityLevel.high,
    "MODERATE": SeverityLevel.medium,
    "LOW":      SeverityLevel.low,
}


# -- Wizard answers to model chips --------------------------------------------
# Only affirmative answers become chips. "Hindi ko alam" and "Wala" are NOT
# turned into False: predict.severity() distinguishes False from None, and
# rule SR010 ("no signals readable - fail-safe, route to a human") only fires
# when every signal is None. Writing False for an unknown would silently
# disable that fail-safe. tools/api.py makes the same choice.
_AFFIRMATIVE_CHIPS: dict[str, dict[str, str]] = {
    # wizard key   -> { answer option : model signal }
    "spreading":  {"Oo, kumakalat": "hazard_spreading"},
    "injured":    {"Oo": "injured"},
    "bleeding":   {"Oo": "injured"},
    "conscious":  {"Hindi, nawalan ng malay": "unresponsive"},
    "weapon":     {"Oo": "weapon_mentioned"},
    "evacuation": {"Oo, urgent": "structure_involved"},
}

# "Ano ang nasusunog?" — only a building is a structure. A vehicle or a field
# burning is a fire, but not the structural fire that rule SR005 escalates on.
_STRUCTURE_MATERIALS = {"Bahay", "Gusali / Bodega"}

# Head-count questions. The upper bound of each range is used on purpose:
# in emergency triage, sending too many responders is recoverable and sending
# too few is not, so the range is read in the escalating direction.
_COUNT_ANSWERS: dict[str, int] = {
    "1": 1, "2\u20135": 5, "Higit sa 5": 6,             # medical: victim_count
    "1\u20135": 5, "6\u201320": 20, "Higit sa 20": 21,  # calamity: affected families

    # people_count, asked on the confirm screen after a resident records their
    # voice. MACHINE VALUES, not the labels shown on screen.
    #
    # Every key above is a Filipino display string, which means the wizard's
    # UI copy IS this scoring table: translating a chip, or fixing its
    # punctuation, silently stops it counting. The en-dash in "2\u20135" is load
    # bearing for that reason. This field does not repeat the mistake — the
    # screen renders "4+ katao" or "4+ people" as it likes, and sends "4plus"
    # either way.
    "1person": 1, "2people": 2, "3people": 3,
    # "4+" is a floor, not a count. Four is the smallest thing it can mean and
    # the only number safe to act on; a rule wanting more precision should
    # treat this as unknown rather than as four exactly.
    "4plus": 4,
    # "not sure" is deliberately absent. It is the default, and an unanswered
    # question must contribute nothing rather than a zero.
}


def _chips_from_wizard(
    category: IncidentCategory | None,
    wizard_answers: dict[str, Any] | None,
    overlap_agencies: list[str] | None,
) -> tuple[dict[str, bool], int | None]:
    """
    Translate the 5W1H wizard answers into the model's chip vocabulary.

    Returns (chips, people_involved). people_involved is returned separately
    because it is a count, not a boolean chip, and is applied to the extracted
    signals directly.
    """
    chips: dict[str, bool] = {}
    people: int | None = None
    answers = wizard_answers or {}

    for key, value in answers.items():
        if not isinstance(value, str):
            continue
        mapping = _AFFIRMATIVE_CHIPS.get(key)
        if mapping and value in mapping:
            chips[mapping[value]] = True
        if key == "material" and value in _STRUCTURE_MATERIALS:
            chips["structure_involved"] = True
        if key in ("victim_count", "affected", "people_count") and value in _COUNT_ANSWERS:
            people = max(people or 0, _COUNT_ANSWERS[value])
            # Families affected by a flood or landslide means the hazard has
            # reached homes — that is rule SR005D's condition.
            if key == "affected":
                chips["structure_involved"] = True

    # Step 3 overlap flags. Only `injuries` has a model equivalent; `fire`,
    # `flooding`, `hazmat` and `missing_person` describe a second agency's
    # concern, not a severity signal, so they are left for the dispatcher.
    for flag in overlap_agencies or []:
        if flag == "injuries":
            chips["injured"] = True

    return chips, people


# -- Loading ------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Fuzzy normalisation: deliberately OFF
#
# predict.normalise() does two passes — an alias lookup, then a RapidFuzz match
# of every unrecognised word against the 61-term emergency vocabulary. The
# alias pass is exact and safe. The fuzzy pass, at the thresholds the release
# ships (92 / 85 / 78 by word length), is not.
#
# Measured on the release's own test split (249 rows, v2.1.5). The fuzzy pass
# rewrites 35 rows and changes severity on 10 of them:
#
#     severity upgraded ...... 3
#     severity DOWNGRADED .... 7
#
# The rewrites themselves are the argument:
#
#     bahay -> baha (89)             9x   house -> flood
#     nagsusuntukan -> nagsusuka     2x   brawl -> vomiting
#     makaginhawa  -> makagawas      2x   can breathe -> can get out
#     nakakaon     -> nakawan        1x   eating -> robbery
#     nagtataas    -> nagtatae       1x   water rising -> diarrhoea
#
# `bahay` is the concrete harm: "nasusunog po ang bahay" (the house is
# burning) has its severity cut from SR005/HIGH to SR010/MODERATE, nine times,
# because the word for house was rewritten into the word for flood. None of
# these words are in predict.PROTECTED.
#
# This is not a tuning accident. Tagalog and Waray build meaning with affixes
# (na-, nag-, -um-, -an), so unrelated words sit a couple of edits apart far
# more often than in English, and a ratio threshold cannot tell an affix from
# a typo. Fixing it needs a re-tuned matcher measured against this split — not
# a higher number here.
#
# Left importable and pinned in requirements.txt on purpose. Before this, the
# pass was off for a different reason: rapidfuzz was simply never installed and
# predict.py swallows the ImportError. Off by accident and off by decision look
# identical in production and are not the same thing.
# ---------------------------------------------------------------------------
FUZZY_NORMALISATION = False


def _fuzzy_pool() -> list[str]:
    """The candidate vocabulary handed to normalise().

    Empty disables the fuzzy pass — normalise() guards it with `if terms and
    ...` — while leaving the alias table fully in force. That keeps predict.py
    verbatim, which is the rule for everything under app/ml.
    """
    return _TERMS if FUZZY_NORMALISATION else []


# ── Glued number-words ──────────────────────────────────────────
#
# Measured on a real report: "tulo ka tawo an nasamdan" (three people injured)
# came back from the recogniser as "tulukataw anasamdan". The injury survived,
# because "nasamdan" is still findable inside "anasamdan". The COUNT did not:
# _count() matches a numeral followed by a separate noun, and there are no
# separate words left to match.
#
# The incident scored HIGH instead of CRITICAL, and nothing anywhere said a
# number had gone missing. That silence is the problem this addresses.
#
# This deliberately does NOT try to split the word back apart. "tulukataw"
# could be "tulo ka tawo" or "tulo ka taw" or something else entirely, and a
# wrong count is worse than a missing one — a dispatcher who reads "3 injured"
# sends for three. So it only raises a hand: the count here cannot be trusted,
# ask.

# The linkers a numeral takes before its noun: "tulo KA tawo", "duha NGA
# motor", "dalawaNG tao". Finding one welded inside a single token is the
# signature of two words that should have been three.
_LINKERS = ("ka", "nga", "ng", "an", "na", "g")

# Short tokens collide by accident. Every real glued count seen so far is
# longer than this, and "usa" turning up inside a six-letter word is far more
# likely to be a coincidence than a lost headcount.
_MIN_GLUED_LENGTH = 7


def _glued_number_words(text: str) -> list[str]:
    """Tokens where a numeral looks welded to the word after it.

    Compared in phonetic-key space, so the recogniser's vowel substitutions do
    not hide the numeral: "tulukataw" carries "tulu", which is the key for
    "tulo", and "adohaka" carries "duha".

    A numeral only counts as glued when it is either at the start of the token
    or immediately followed by a linker. Without that, "gusali" (building)
    trips on "usa" and "kapitolyo" trips on "pito", and a warning that fires on
    ordinary words is a warning nobody reads.
    """
    if _Z is None:
        return []

    known = set(_TERMS or []) | set(_PHONETIC_INDEX.values())
    protected = getattr(_Z, "PROTECTED", set())
    numerals = {phonetic.key(n): n for n in getattr(_Z, "WORDNUM", {})}

    found: list[str] = []
    for token in re.findall(r"[\w']+", text.lower()):
        if (
            len(token) < _MIN_GLUED_LENGTH
            or token in known
            or token in protected
            or token in getattr(_Z, "WORDNUM", {})
        ):
            continue

        key = phonetic.key(token)
        for num_key in numerals:
            at = key.find(num_key)
            if at < 0:
                continue
            rest = key[at + len(num_key):]
            if not rest:
                continue
            # At the start of the token, or welded to a linker. Either way the
            # numeral is carrying something that should have been its own word.
            if at == 0 or rest.startswith(_LINKERS):
                found.append(token)
                break

    return found


# ---------------------------------------------------------------------------
# The lexicon as vocabulary, not as a rewrite table
#
# ziren_lexicon.json describes the reporting register: 440 entries, 769 surface
# forms. Measured as a find-and-replace pass over the release test split it is
# not worth wiring — 185 rows rewritten to gain three injury signals and four
# locations, most of the rest cosmetic.
#
# Measured as the vocabulary the SOUND matcher searches, it is a different
# proposition. emergency_terms.csv lists 61 words. The recogniser produced
# "nagbanggahay", "nagbangkaay" and "nagpanggahay" across three takes of one
# spoken "nag banggaay", and the vocabulary already contained `banggaay` — the
# matcher could not reach it because the index held bare stems and the resident
# spoke inflected forms.
#
# So the lexicon is loaded here as words to correct TOWARDS, not as pairs to
# rewrite. That is the use its size actually supports, and it is the only
# mechanism available that catches a garbled word nobody wrote down.
#
# Uncurated entries are excluded: they are an auto-extract with no gloss and
# lang 'unknown', and a correction target has to be a word somebody vouched for.
# ---------------------------------------------------------------------------
LEXICON_PHONETICS = True


def _load_lexicon_forms() -> list[str]:
    """Curated surface forms from ziren_lexicon.json, for the phonetic index."""
    if not LEXICON_PHONETICS:
        return []

    path = os.path.join(_OVERRIDES_ROOT, "ziren_lexicon.json")
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        return []
    except Exception as e:  # noqa: BLE001 — a broken lexicon must not stop triage
        log.warning("triage.lexicon_unreadable", error=str(e))
        return []

    # Canonicals only. A variant is a form we want to correct AWAY from; adding
    # it here would list it as a word to correct TOWARDS, and `correct()` never
    # touches a word already in the index — so feeding variants in marks every
    # misspelling as correct. Measured directly: it silently disabled
    # sunug->sunog, aksidenti->aksidente and lindul->lindol, which are the
    # phonetic layer's own regression cases.
    forms = [
        entry["canonical"]
        for entry in doc.get("lexicon", [])
        if entry.get("register") != "uncurated"
    ]
    return [f for f in forms if " " not in f]


# ---------------------------------------------------------------------------
# Alias correction is case-blind in the release, and silently so
#
# predict.normalise() applies an alias like this:
#
#     bare = re.sub(r"[^\w']", "", w.lower())
#     ...
#     out.append(w.replace(bare, aliases[bare]) if bare in w.lower() else aliases[bare])
#
# `bare` is lower-cased. The guard `bare in w.lower()` passes case-insensitively,
# but the action runs `.replace()` against `w`, which still has its original
# case — so the lower-case needle is not found, replace() returns the word
# untouched, and the change is appended to `changes` anyway.
#
# Every alias correction therefore fails on a capitalised token while reporting
# that it succeeded. Measured on the release test split, 249 rows:
#
#     as written ....... 35 reported, 22 rows changed, 10 reported-but-unchanged
#     Title Cased ...... 35 reported,  3 rows changed, 29 reported-but-unchanged
#
# Title-casing the corpus is a simulation, but the input channel is not: a real
# handset transcript read "Sir Tabang Naay Na Sunog Didiha Amon", and
# `didiha -> didi ha` was reported and not applied. That is a row somebody
# confirmed against a recording, which is the whole standard
# stt_corrections.csv is held to, doing nothing in production.
#
# Two reasons this survived. The change log reports success, so the failure is
# invisible at the call site; and transcript_eval measures the correction layer
# through this same function, so its "after corrections" figure has been
# crediting corrections that never happened.
#
# The phonetic and fuzzy passes do NOT have this bug — both lower-case the
# haystack before replacing. The alias branch is the only one that tries to
# preserve the original casing, and that attempt is what breaks it.
#
# Fixed here rather than in app/ml/, which stays a verbatim copy of the
# release. This runs as a pre-pass: by the time predict.normalise() sees the
# text the aliases are already applied, so its own alias branch finds nothing,
# and its fuzzy pass still runs normally on the corrected text — which is the
# order the ladder documents anyway.
#
# The flag is here so the two arms stay measurable, the same way
# FUZZY_NORMALISATION is. Turning it off restores the release behaviour.
# ---------------------------------------------------------------------------
ALIAS_CASE_REPAIR = True


def _apply_aliases(text: str) -> tuple[str, list[str]]:
    """The release's alias pass, applied at any casing. See the note above."""
    protected = getattr(_Z, "PROTECTED", set())
    out: list[str] = []
    changes: list[str] = []

    for w in text.split():
        bare = re.sub(r"[^\w']", "", w.lower())
        if not bare or bare in protected or bare not in _ALIASES:
            out.append(w)
            continue
        # Splice the replacement into the original token so surrounding
        # punctuation survives: "Didiha," -> "didi ha,".
        at = w.lower().index(bare)
        out.append(w[:at] + _ALIASES[bare] + w[at + len(bare):])
        changes.append("%s -> %s (alias)" % (bare, _ALIASES[bare]))

    return " ".join(out), changes


def normalise_text(text: str) -> tuple[str, list[str]]:
    """The correction ladder, in order, as one call.

        0  PROTECTED       never touched (predict.PROTECTED)
        1  exact alias     misspellings.csv + stt_corrections.csv + abbrevs
        2  phonetic        same sounds, different letters
        3  fuzzy           OFF — measured 3 severities up, 7 down

    Both production and transcript_eval go through here, so the evaluation
    reports what a real report would actually get. They were separate before,
    which meant the measured value of the correction layer and the correction
    layer applied to residents could drift apart without anything failing.
    """
    collapsed = _collapse_immediate_repeats(text)
    alias_changes: list[str] = []
    if ALIAS_CASE_REPAIR:
        collapsed, alias_changes = _apply_aliases(collapsed)
    out, changes = _Z.normalise(collapsed, _ALIASES, _fuzzy_pool())
    changes = alias_changes + changes

    # Phonetic runs AFTER the alias pass, never before: an exact correction
    # someone observed on a real handset outranks a rule about sounds.
    sound_out, sound_changes = phonetic.correct(
        out,
        _PHONETIC_INDEX,
        known=set(_TERMS or []) | set(_PHONETIC_INDEX.values()),
        protected=getattr(_Z, "PROTECTED", set()),
    )
    return sound_out, changes + sound_changes


def _load_correction_targets() -> list[str]:
    """Extra words the phonetic layer may correct TOWARDS.

    The model release's emergency_terms.csv is the classifier's vocabulary, and
    it is smaller than the extractor's. `nagdugo` is matched by predict.INJURY
    and appears in no dictionary file, so before this the corrector could not
    reach it: "nagdugu" stayed misspelled, INJURY did not match, and a bleeding
    casualty carried no signal.

    Kept in ml_overrides rather than in 06_DICTIONARY because everything under
    app/ml belongs to the dataset release and stays verbatim — the same reason
    stt_corrections.csv lives here.

    Never raises: a missing or malformed file degrades to the release
    vocabulary alone, which is where this started.
    """
    path = os.path.join(_OVERRIDES_ROOT, "correction_targets.csv")
    out: list[str] = []
    try:
        import csv

        with open(path, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                term = (row.get("term") or "").strip().lower()
                if term:
                    out.append(term)
    except OSError:
        pass
    except Exception as e:
        log.warning("triage.correction_targets_unreadable", error=str(e))
    return out


def _load_stt_corrections() -> dict[str, str]:
    """Speech-recognition confusions observed on real handsets.

    These are not spelling mistakes, which is why they do not belong in the
    release's misspellings.csv. They are a property of the recogniser, and they
    cluster on proper nouns: no engine has Biliran municipality names in its
    vocabulary, so it substitutes the nearest ordinary word it does know.
    Observed live: "Mayda sunog didi ha Caibiran" came back as "mayda sunog
    didiha kaibigan kaibigan" — the Waray carried fine, the place name did not.

    Loaded into the same alias table normalise() already applies, so the
    correction happens before classification and before location extraction,
    where predict.py's BARANGAYS list can then match it.

    Never raises: a missing or malformed override file degrades to no
    corrections, not to a dead triage pass.
    """
    path = os.path.join(_OVERRIDES_ROOT, "stt_corrections.csv")
    out: dict[str, str] = {}
    try:
        import csv

        with open(path, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                observed = (row.get("observed") or "").strip().lower()
                corrected = (row.get("corrected") or "").strip()
                if observed and corrected:
                    out[observed] = corrected
    except OSError:
        pass
    except Exception as e:
        log.warning("triage.stt_corrections_unreadable", error=str(e))
    return out


def _collapse_immediate_repeats(text: str) -> str:
    """Drop a token that is identical to the one directly before it.

    Speech recognisers stutter on words they are unsure of — the live sample
    produced "kaibigan kaibigan" for a single spoken "Caibiran". Only adjacent
    exact repeats are removed, so "tabang tabang tabang" (a person shouting for
    help) keeps its meaning as one call rather than becoming three places.
    """
    out: list[str] = []
    for word in text.split():
        if out and word.lower() == out[-1].lower():
            continue
        out.append(word)
    return " ".join(out)


def _read_version() -> str:
    try:
        with open(os.path.join(_ML_ROOT, "VERSION"), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return "unknown"


def load() -> bool:
    """
    Load the model and dictionaries. Idempotent and never raises.

    predict.py calls sys.exit() when scikit-learn is missing or when it cannot
    find a trained model — appropriate for a CLI, fatal for a web server.
    SystemExit is caught here so a missing artefact degrades triage instead of
    killing the API process at startup.
    """
    global _Z, _MODEL, _ALIASES, _TERMS, _VERSION, _LOAD_ERROR, _LOADED
    global _PHONETIC_INDEX

    if _LOADED:
        return _MODEL is not None

    with _lock:
        if _LOADED:                       # another thread won the race
            return _MODEL is not None

        _VERSION = _read_version()
        try:
            from app.ml.tools import predict as Z

            model = Z.train_if_needed()
            aliases, terms = Z.load_dict()

            # Ours layered last, so a correction here wins over the release's.
            corrections = _load_stt_corrections()
            aliases = {**aliases, **corrections}

            # Word boundaries the release's signal regexes are missing. Same
            # layering as the corrections above: applied to the imported
            # module, never edited into app/ml/. See extractor_patches for the
            # measurement behind each one.
            patched = extractor_patches.apply(Z)

            # A version-skewed artefact unpickles cleanly and passes every
            # check except the one that matters. scikit-learn 1.6.1 loaded a
            # model trained on 1.9.0 without complaint and then raised
            # AttributeError inside predict_proba on the first real report.
            # One throwaway prediction turns that into a startup failure,
            # where it is visible, instead of a per-report silent degradation.
            model.predict_proba(["smoke test"])
        except SystemExit as e:
            _LOAD_ERROR = f"predict.py exited: {e}"
            _LOADED = True
            log.error("triage.model_unavailable", reason=_LOAD_ERROR)
            return False
        except Exception as e:
            _LOAD_ERROR = f"{type(e).__name__}: {e}"
            _LOADED = True
            log.error("triage.model_load_failed", reason=_LOAD_ERROR)
            return False

        _Z, _MODEL, _ALIASES, _TERMS = Z, model, aliases, terms
        _PHONETIC_INDEX = phonetic.build_index(
            list(terms) + _load_correction_targets() + _load_lexicon_forms()
        )
        _LOADED = True
        log.info(
            "triage.model_loaded",
            version=_VERSION,
            categories=list(model.named_steps["clf"].classes_),
            flag_threshold=Z.FLAG_THRESHOLD,
            stt_corrections=len(corrections),
            extractor_patches=patched,
        )
        return True


def is_available() -> bool:
    return _LOADED and _MODEL is not None


def status() -> dict:
    """Health payload — mirrors the standalone API's GET /health."""
    return {
        "model_loaded": is_available(),
        "version": _VERSION,
        "flag_threshold": _Z.FLAG_THRESHOLD if _Z else None,
        "error": _LOAD_ERROR,
    }


# -- The triage pass ----------------------------------------------------------
def _location_from_landmark(landmark_note: str | None) -> str | None:
    """The barangay named inside a landmark, and nothing else from it.

    A landmark says what the incident is NEXT TO. It must never reach
    predict.extract() as ordinary report text, because that reads building
    words as signals about the incident itself:

        "Malapit sa: harap ng bahay ni Mang Juan"  ->  structure_involved

    A house standing beside a fire is not a house on fire, but SR005 fires on
    that signal and lifts the report from MODERATE to HIGH. Every landmark
    mentioning a bahay, a store or a school would have escalated its own
    report — an escalation invented by the address.

    Location is the one thing a landmark can safely contribute. Biliran
    barangays are frequently named in them ("tapat ng Caibiran public market"),
    and predict.py already knows how to find one.
    """
    if not landmark_note or not landmark_note.strip():
        return None
    try:
        sig, _ = _Z.extract(landmark_note)
        return sig.get("location")
    except Exception:  # pragma: no cover - extraction must never break a report
        return None


def triage(
    *,
    report_text: str,
    incident_category: IncidentCategory | None = None,
    wizard_answers: dict[str, Any] | None = None,
    overlap_agencies: list[str] | None = None,
    landmark_note: str | None = None,
) -> dict | None:
    """
    Run one report through normalise -> classify -> chips -> signals -> severity.

    Returns a dict with `severity` (a SeverityLevel), `agencies`, and `signals`
    (the JSONB payload written to incidents.signals), or None when the model is
    unavailable or the pass fails. Never raises.

    `landmark_note` is read for a location only, never for signals — see
    _location_from_landmark for why mixing it into the report text invents
    severity.

    The returned severity is advisory. Nothing here dispatches; the dispatcher
    validates before anyone is sent.
    """
    if not load():
        return None

    trace = _Trace()
    try:
        result = _triage_inner(
            report_text=report_text,
            incident_category=incident_category,
            wizard_answers=wizard_answers,
            overlap_agencies=overlap_agencies,
            landmark_note=landmark_note,
            trace=trace,
        )
    except Exception as e:
        # A malformed report must not cost the resident their report. The stage
        # it failed in is named, so nobody has to trace client -> router ->
        # service -> model to find it (evaluator finding #28).
        log.error("triage.failed", stage=trace.current, completed=trace.names(),
                  error=str(e), error_type=type(e).__name__)
        return None

    trace.done()
    result["signals"]["pipeline_trace"] = trace.steps
    log.info(
        "triage.completed",
        stages=trace.names(),
        total_ms=trace.total_ms(),
        severity=result.get("severity"),
        rule=result["signals"].get("severity_rule"),
        verification=result["signals"].get("verification_status"),
    )
    return result


class _Trace:
    """Which stage of a triage pass is running, and how long each took.

    Stored on the incident as signals.pipeline_trace and logged as
    triage.completed / triage.failed, so a report that came out wrong can be
    followed stage by stage from the dashboard or the server log. See
    docs/TRIAGE_PIPELINE.md.
    """

    def __init__(self) -> None:
        self.steps: list[dict] = []
        self.current = "start"
        self._t = time.perf_counter()

    def stage(self, name: str) -> None:
        now = time.perf_counter()
        if self.current != "start":
            self.steps.append({"stage": self.current, "ms": round((now - self._t) * 1000, 2)})
        self.current, self._t = name, now

    def done(self) -> None:
        self.stage("done")

    def names(self) -> list[str]:
        return [s["stage"] for s in self.steps]

    def total_ms(self) -> float:
        return round(sum(s["ms"] for s in self.steps), 2)


def _triage_inner(
    *,
    report_text: str,
    incident_category: IncidentCategory | None,
    wizard_answers: dict[str, Any] | None,
    overlap_agencies: list[str] | None,
    landmark_note: str | None = None,
    trace: "_Trace | None" = None,
) -> dict:
    step = trace.stage if trace is not None else (lambda _name: None)
    Z = _Z
    text = (report_text or "").strip()
    glued: list[str] = []
    selected = BACKEND_TO_MODEL.get(incident_category) if incident_category else None

    # -- classify, when there is text to classify --------------------------
    if text:
        # Collapse recogniser stutters before normalising, so a doubled word
        # does not become a doubled correction.
        step("normalise")
        text = _collapse_immediate_repeats(text)
        norm, changes = normalise_text(text)
        glued = _glued_number_words(norm)
        step("classify")
        # Classify the ORIGINAL text; `norm` feeds signal extraction only.
        # Normalising before classification causes train/serve skew - see the
        # note in predict.run().
        proba = _MODEL.predict_proba([Z.strip_places(text)])[0]
        classes = list(_MODEL.named_steps["clf"].classes_)
        order = proba.argsort()[::-1]
        predicted, confidence = classes[order[0]], float(proba[order[0]])
        runner_up = {
            "category": classes[order[1]],
            "confidence": round(float(proba[order[1]]), 3),
        }
        step("signals")
        sig, _hedged = Z.extract(norm)
    else:
        norm, changes, predicted, confidence, runner_up = "", [], None, 0.0, None
        sig = {
            k: None
            for k in (
                "injured", "fatalities", "entrapment", "hazard_spreading",
                "structure_involved", "weapon_mentioned", "unresponsive",
                "people_involved", "injured_count",
            )
        }

    # -- a landmark can name the place, and may say nothing else ----------
    # Only filled when the report text yielded no location of its own: what is
    # burning is a better locator than what stands beside it.
    if not sig.get("location"):
        from_landmark = _location_from_landmark(landmark_note)
        if from_landmark:
            sig["location"] = from_landmark

    # -- the resident's own answers win over anything read from the text ---
    step("wizard")
    chips, people = _chips_from_wizard(
        incident_category, wizard_answers, overlap_agencies
    )
    chips_used = []
    for key, value in chips.items():
        if key in sig and value:
            sig[key] = True
            chips_used.append(key)
    if people is not None:
        sig["people_involved"] = max(sig.get("people_involved") or 0, people)
        chips_used.append("people_involved")

    # -- verification: does the model agree with what the resident chose? --
    step("verify")
    if not text:
        status_code = "NO_TEXT"
        message = "No free text supplied; category and wizard answers used as given."
    elif selected is None:
        status_code = "NO_SELECTION"
        message = "Resident made no selection; the model's reading was used."
    elif selected == predicted:
        status_code = "AGREE"
        message = "The model agrees with the resident's selection."
    elif confidence >= Z.FLAG_THRESHOLD:
        status_code = "MISMATCH_FLAGGED"
        message = (
            "The report text reads as %s (%.2f) but %s was selected. "
            "Confirm the category before dispatch." % (predicted, confidence, selected)
        )
    else:
        status_code = "UNCERTAIN"
        message = (
            "The model is unsure (%.2f); the resident's selection stands." % confidence
        )

    # The resident is at the scene and the model is not, so routing follows the
    # resident's selection whenever they made one. A flagged mismatch is
    # surfaced to the dispatcher, never silently overruled.
    routing_category = selected or predicted or "ACCIDENT"

    # `category_from_user` gates rule SR005B (the MEDICAL severity floor).
    # A resident who taps MEDICAL is asserting that a person is in distress,
    # and that assertion stands however the text reads. A low-confidence model
    # guess of MEDICAL asserts nothing and must not lift an unreadable report
    # over the SR010 fail-safe. `selected` is None both when the resident chose
    # nothing and when they chose `other`, which are the same claim: no
    # category was asserted.
    step("severity")
    rule, level, why = Z.severity(
        sig, routing_category, confidence,
        category_from_user=selected is not None,
    )

    step("routing")
    agencies = list(Z.AGENCY.get(routing_category, []))
    if sig.get("entrapment") and "BFP" not in agencies:
        agencies.append("BFP")
    if (sig.get("injured") or sig.get("fatalities")) and "MDRRMO" not in agencies:
        agencies.append("MDRRMO")

    # An agency suggestion is only as good as the category it came from. When
    # the resident asserted nothing AND the model is below the flag threshold,
    # the suggestion rests on a coin-flip guess — say so rather than presenting
    # it with the same confidence as a resident's own selection. The agencies
    # are still returned (an emergency report must reach someone) but the
    # dispatcher is told to choose. Severity is unaffected: SR010/SR011 already
    # handle that case. Added in dataset release 2.1.5.
    agency_basis = (
        "user_selected" if selected is not None
        else "model_confident" if confidence >= Z.FLAG_THRESHOLD
        else "model_uncertain"
    )
    needs_manual_agency = agency_basis == "model_uncertain"
    agency_note = (
        "Agency suggested from a low-confidence model reading (%.2f). "
        "Choose the responder manually." % confidence
    ) if needs_manual_agency else None

    severity = SEVERITY_MAP.get(level)
    if severity is None:
        # An unrecognised level from a newer dataset release must not be
        # written to a column with a CHECK constraint.
        log.warning("triage.unknown_severity_level", level=level, rule=rule)

    return {
        "severity": severity,
        "agencies": agencies,
        "signals": {
            "engine": "ziren-model",
            "engine_version": _VERSION,
            "model_predicted": predicted,
            "model_predicted_category": (
                MODEL_TO_BACKEND[predicted].value
                if predicted in MODEL_TO_BACKEND else None
            ),
            "model_confidence": round(confidence, 3) if text else None,
            "runner_up": runner_up,
            "user_selected": incident_category.value if incident_category else None,
            "verification_status": status_code,
            "verification_message": message,
            "severity_level": level,
            "severity_rule": rule,
            "severity_reason": why,
            "signals": {k: v for k, v in sig.items() if v is not None},
            "signals_unknown": [k for k, v in sig.items() if v is None],
            "signals_from_wizard": chips_used,
            "routing_agencies": agencies,
            "routing_based_on": "user_selected" if selected else "model_predicted",
            "agency_basis": agency_basis,
            "needs_manual_agency": needs_manual_agency,
            "agency_note": agency_note,
            # A count the recogniser welded into another word. Flagged, never
            # guessed at: see _glued_number_words.
            "count_uncertain": bool(glued),
            "count_note": (
                "Count may be unreliable — the recogniser ran a number into "
                "the word after it (%s). Please confirm how many." %
                ", ".join(glued)
            ) if glued else None,
            "normalisation": (
                {"text": norm, "changes": changes} if changes else None
            ),
            "disclaimer": "Advisory only. A responder must validate before dispatch.",
        },
    }
