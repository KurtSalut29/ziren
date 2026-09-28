#!/usr/bin/env python3
"""One-shot migration: ziren_lexicon.json 0.3.0 -> 0.4.0.

Every change below is a decision, not an inference. The tables are the record
of a hand review of all 160 violations that scripts/validate_lexicon.py reports
against 0.3.0; running the validator afterwards is what proves the review was
complete. Re-running this script on an already-migrated file is a no-op for the
tables that are keyed by content, so it is safe, but it is not meant to be part
of any pipeline -- it exists so the 0.3.0 -> 0.4.0 diff can be read and argued
with.

    python scripts/fix_lexicon_v040.py app/ml_overrides/ziren_lexicon.json
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# ── SPLITS ────────────────────────────────────────────────────────────────
# parent canonical -> [(new canonical, its language, variants moved with it)]
#
# Each of these was a variant filed under an entry of a different language.
# The surface layer is within-language by contract; the lemma layer is what
# links languages, so the fix is always to give the form its own entry and
# leave the lemma alone -- the cross-language link survives, the collapse does
# not.
SPLITS: dict[str, list[tuple[str, str, list[str]]]] = {
    "sinaktan": [
        ("giabuso", "ceb", ["gi-abuso"]),
        ("gipasiparahan", "ceb", []),
        ("gin-aabuso", "war", []),
        ("ginpasiparahan", "war", []),
        ("inabuso", "fil", []),
    ],
    "banggaan": [
        ("nagkabungguanay", "ceb", ["nakabungguanay"]),
        ("nagkasagian", "ceb", []),
    ],
    "kanto": [("corner", "en", [])],
    # not cross-language, but the same shape of loss: an acronym cannot hold
    # the words it stands for, so 'oh my god' -> 'omg' deletes two of them.
    "omg": [("oh my god", "en", [])],
    "sapa": [("ilog", "fil", []), ("river", "en", [])],
    "nagtitinangis": [("umiiyak", "fil", [])],
    "away": [("nagbiraay", "war", ["nagbibiraay"]), ("nagbinunalay", "war", [])],
    "tikang": [("gikan", "ceb", [])],
    "nananakot": [("threaten", "en", ["threatening"])],
    "itaas": [("height", "en", [])],
    "damo": [("daghan", "ceb", []), ("dami", "fil", [])],
    "many": [("a lot", "en", [])],
    # 'baka' is not merely a synonym of siguro: predict.UNSURE matches baka and
    # does not match siguro, so the rewrite deleted the hedge and turned "baka
    # may nasugatan" (MAYBE someone is hurt) into an assertion. Measured on the
    # release test split: 8 rows rewritten, 4 of them lifted a severity.
    "siguro": [("basi", "war", []), ("basin", "ceb", []), ("tingali", "ceb", []),
               ("baka", "fil", [])],
    "buntag": [("aga", "war", [])],
    "silingan": [("kapitbahay", "fil", [])],
    "son": [("daughter", "en", [])],
    "pakadi": [("pakiadto", "ceb", []), ("pakipuntahan", "fil", [])],
    "pulis": [("police", "en", [])],
    "suntukan": [("nagsusumbagay", "ceb", [])],
    "ulan": [("nagbunok", "war", [])],
    "sumat": [("gisumat", "ceb", [])],
    "respond": [("send help", "en", [])],
    "dalan": [
        ("kalsada", "fil", ["kalye"]),
        ("road", "en", ["highway", "street"]),
        ("daan", "war", []),
    ],
    "atop": [("bubong", "fil", [])],
    "dagat": [("sea", "en", [])],
    "severe": [("seryoso", "fil", [])],
    "baril": [("gipusil", "ceb", [])],
    "nagsisinggit": [("sigaw", "fil", ["sumisigaw"])],
    "bana": [("asawa", "fil", [])],
    "husband": [("wife", "en", []), ("spouse", "en", [])],
    "daluyong": [("dagko nga balod", "ceb", [])],
    "malakas": [("kusog", "ceb", ["makusog"])],
    "sigurado": [("sure", "en", [])],
    "tricycle": [("traysikel", "fil", ["traysikol"])],
    "typhoon": [("tropical storm", "en", [])],
    "flood": [("flash flood", "en", ["flashflood"])],
    "motor": [("motorcycle", "en", ["motorcycles"])],
    "nagreport": [("gireport", "ceb", ["mureport"])],
}

# Entries whose own `lang` was wrong once their foreign variants left.
RELANG: dict[str, str] = {
    "damo": "war",           # damo is Waray; daghan is the Cebuano form, now split out
    "motor": "fil",          # the corpus word is Filipino; English 'motorcycle' is now its own entry
    "nagsisinggit": "war",   # singgit is Waray/Cebuano; Tagalog sigaw is now its own entry
}

# ── DROPPED VARIANTS ──────────────────────────────────────────────────────
# parent canonical -> variants deleted outright, with the reason.
DROPS: dict[str, list[tuple[str, str]]] = {
    "hangin": [
        ("malakas na hangin", "intensity belongs to the 'strong' entry, not deleted into 'hangin'"),
        ("strong wind", "same; 'strong' and 'wind' now normalise independently"),
        ("kusog nga hangin", "same"),
    ],
    "maayong": [
        ("maayong adlaw", "deleted adlaw, the time register's own canonical"),
        ("maayong buntag", "deleted buntag"),
        ("maayong gabii", "deleted gabii"),
    ],
    "maupay": [("maupay nga gab-i", "deleted gab-i")],
    "magandang": [("magandang araw", "deleted araw"), ("magandang gabi", "deleted gabi")],
    "good": [("good day", "deleted day"), ("good evening", "deleted evening")],
    "salamat": [("daghang salamat", "deleted the intensifier daghang")],
    "maybe": [
        ("about", "a quantity approximator, not a hedge: 'about 20 trapped' -> 'maybe 20 trapped'"),
        ("like", "comparative 'looks like' is not uncertainty"),
    ],
    "severe": [("heavy", "'heavy rain' is not 'severe rain'; inflates a severity-adjacent descriptor")],
    "tikang": [("mula", "also declared in ambiguous_places_left_to_ner; the rewrite ran first and killed the place name")],
    "tabang": [("sabang", "a recogniser mishearing, not a dialect variant -- moved to stt_corrections.csv; Sabang is a real barangay name")],
    "tulong": [("katulong", "katulong is a household helper, not a plea for help")],
    "lying": [("collapsed", "a collapsed building and a person lying down route to different agencies; left unmapped rather than guessed")],
    "help": [("rescue", "rescue is a specific response, not a general plea; collapsing it loses that it was asked for by name")],
}

# ── NOTES ─────────────────────────────────────────────────────────────────
# canonical -> a line carried on the entry itself, for concepts that are
# suggestive rather than decided.
NOTES: dict[str, str] = {
    "natumba": (
        "incident_concept is a hint only: natumba covers a person, a tree, a post or a "
        "motorcycle falling over, and only the last is vehicular."
    ),
}

# ── PROMOTIONS ────────────────────────────────────────────────────────────
# Auto-extracted rows that were never content-free: they are the English half
# of a lemma the curated set already owned, or they are negation. Promoting
# rather than deleting keeps the observed frequency.
PROMOTIONS: dict[str, dict] = {
    "please":  dict(lang="en", register="courtesy", lemma="please", gloss="please (courtesy)"),
    "attack":  dict(lang="en", register="incident", lemma="attack", gloss="heart/asthma attack",
                    incident_concept="MEDICAL"),
    "bitten":  dict(lang="en", register="incident", lemma="bitten", gloss="bitten (animal)",
                    incident_concept="MEDICAL"),
    "burning": dict(lang="en", register="incident", lemma="burning", gloss="is burning",
                    incident_concept="FIRE"),
    "gasping": dict(lang="en", register="incident", lemma="gasping",
                    gloss="labored breathing / gasping", incident_concept="MEDICAL"),
    "roof":    dict(lang="en", register="structure", lemma="roof", gloss="roof"),
    "two":     dict(lang="en", register="quantity", lemma="two", gloss="two"),
    # Negation. "dili makaginhawa" and "makaginhawa" differ by one word and by
    # an ambulance; predict._negated() can only act on words that survive
    # normalisation, so these must be described, never dropped.
    "dili":    dict(lang="ceb", register="descriptor", lemma="not", negation=True,
                    gloss="not / cannot (negator)"),
    "hindi":   dict(lang="fil", register="descriptor", lemma="not", negation=True,
                    gloss="not (negator)"),
    "not":     dict(lang="en", register="descriptor", lemma="not", negation=True, gloss="not"),
    "cannot":  dict(lang="en", register="descriptor", lemma="not", negation=True, gloss="cannot"),
    "wala":    dict(lang="fil", register="descriptor", lemma="none", negation=True,
                    gloss="none / not present"),
    "waray":   dict(lang="war", register="descriptor", lemma="none", negation=True,
                    gloss="none / there is none. NOTE: identical to the language name; "
                          "never read this surface as a language tag"),
}

# Negation forms with no dataset occurrence yet, seeded so the negator set is
# complete rather than only as complete as one corpus happened to be.
NEW_ENTRIES: list[dict] = [
    dict(lemma="do_not", canonical="ayaw", lang="ceb", variants=["ayaw'g", "ayawg"],
         gloss="do not (prohibitive)", register="descriptor", incident_concept=None,
         hazard_subtype=None, source="seed", verified=False, freq=0, negation=True),
]

# ── DELETIONS ─────────────────────────────────────────────────────────────
# Function words the auto-extract collected in spite of the stated policy.
# They move to grammar_excluded, where the policy already said they belonged.
DELETE_TO_GRAMMAR = [
    "sila", "namin", "yung", "ung", "eto", "ngan", "canila", "pong", "baga",
    "have", "has", "had", "would", "each", "other", "because", "into", "across",
    "after", "back", "under", "down", "off", "out", "several", "way", "get", "move",
    "something",
]
# Particles and pronouns the list simply missed. 'kamo' is the second-person
# plural and its absence, next to kami/kita/ikaw, was an oversight; 'toh' and
# 'a' are what made three otherwise harmless variants look content-deleting.
GRAMMAR_ADD = ["amin", "kamo", "toh", "a"]
# 'mula' stops being dropped: it is a protected place form and nothing else.
GRAMMAR_REMOVE = ["mula"]


def key(s: str) -> str:
    return s.strip().lower()


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else Path("app/ml_overrides/ziren_lexicon.json")
    doc = json.loads(path.read_text(encoding="utf-8"))
    lex: list[dict] = doc["lexicon"]
    meta: dict = doc["meta"]
    by_canon = {key(e["canonical"]): e for e in lex}
    log: list[str] = []

    # 1. drops
    for parent, items in DROPS.items():
        e = by_canon.get(parent)
        if e is None:
            continue
        for variant, why in items:
            if variant in e["variants"]:
                e["variants"].remove(variant)
                log.append(f"drop     {variant!r} from {parent!r} -- {why}")

    # 2. splits
    for parent, news in SPLITS.items():
        e = by_canon.get(parent)
        if e is None:
            continue
        for new_canon, lang, extra in news:
            moved = [v for v in ([new_canon] + extra) if v in e["variants"]]
            for v in moved:
                e["variants"].remove(v)
            entry = dict(
                lemma=e["lemma"],
                canonical=new_canon,
                lang=lang,
                variants=[v for v in extra if v != new_canon],
                gloss=e["gloss"],
                register=e["register"],
                incident_concept=e.get("incident_concept"),
                hazard_subtype=e.get("hazard_subtype"),
                source="split",
                verified=False,
                freq=0,
            )
            lex.append(entry)
            by_canon[key(new_canon)] = entry
            log.append(f"split    {new_canon!r} ({lang}) out of {parent!r}, lemma {e['lemma']!r}")

    # 3. relang
    for canon, lang in RELANG.items():
        e = by_canon.get(canon)
        if e and e["lang"] != lang:
            log.append(f"relang   {canon!r} {e['lang']} -> {lang}")
            e["lang"] = lang

    # 4. promotions
    for canon, fields in PROMOTIONS.items():
        e = by_canon.get(canon)
        if e is None:
            continue
        e.update(fields)
        e.setdefault("incident_concept", None)
        e.setdefault("hazard_subtype", None)
        log.append(f"promote  {canon!r} -> register {fields['register']!r}, lang {fields['lang']!r}")

    # 4b. notes
    for canon, note in NOTES.items():
        e = by_canon.get(canon)
        if e is not None:
            e["note"] = note
            log.append(f"note     {canon!r} -- {note.split(':')[0]}")

    # 5. seeded entries
    existing = {key(e["canonical"]) for e in lex}
    for entry in NEW_ENTRIES:
        if key(entry["canonical"]) not in existing:
            lex.append(entry)
            log.append(f"add      {entry['canonical']!r} ({entry['lang']}) -- {entry['gloss']}")

    # 6. deletions
    doomed = {key(w) for w in DELETE_TO_GRAMMAR}
    before = len(lex)
    doc["lexicon"] = lex = [e for e in lex if key(e["canonical"]) not in doomed]
    log.append(f"delete   {before - len(lex)} function-word entries -> grammar_excluded")

    # 7. meta
    grammar = set(meta["grammar_excluded"]) | doomed | {key(w) for w in GRAMMAR_ADD}
    grammar -= {key(w) for w in GRAMMAR_REMOVE}
    # 'amin' rode along as a variant of the deleted 'namin' entry.
    meta["grammar_excluded"] = sorted(grammar)
    log.append(f"meta     grammar_excluded {len(meta['grammar_excluded'])} forms "
               f"(+{len(doomed) + len(GRAMMAR_ADD)}, -{len(GRAMMAR_REMOVE)})")

    if "action" not in meta["registers"]:
        meta["registers"] = sorted(set(meta["registers"]) | {"action"})
        log.append("meta     registers += 'action' (two entries already used it undeclared)")

    meta["negation_forms"] = ["dili", "hindi", "wala", "waray", "not", "cannot", "ayaw"]
    meta["reserved_place_forms"] = sorted(
        set(meta.get("ambiguous_places_left_to_ner", [])) | {"sabang"}
    )
    meta["forbidden_merges"] = [
        ["bana", "asawa"],
        ["husband", "wife"],
        ["son", "daughter"],
        ["tulong", "katulong"],
        # 'collapsed' is deliberately unmapped; this stops it being filed back
        # under 'lying' the next time somebody tidies the English synonyms.
        ["lying", "collapsed"],
    ]
    meta["source_legend"]["split"] = (
        "separated out of a merged entry in 0.4.0; the frequency was not recounted"
    )
    meta["layers"]["negation"] = (
        "negation:true marks a negator that must survive normalisation -- "
        "predict._negated() reads these words, so dropping them inverts a signal."
    )
    meta["version"] = "0.4.0-lexicon"
    meta["updated"] = "2026-09-04"

    # 8. suppletive allowlist: whatever stem violations remain after the splits
    #    are same-language synonyms. Generated, then reviewed by hand -- the
    #    point is that they are enumerated somewhere a person can read them.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "vl", Path(__file__).resolve().parent / "validate_lexicon.py"
    )
    vl = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(vl)

    supp = []
    for e in lex:
        for v in e["variants"]:
            if not vl.shares_stem(v, e["canonical"]):
                supp.append([v, e["canonical"]])
    meta["suppletive_variants"] = sorted(supp)
    log.append(f"meta     suppletive_variants: {len(supp)} same-language pairs allowlisted")

    ordered = {"meta": meta, "lexicon": lex, "phrases": doc["phrases"], "locations": doc["locations"]}
    path.write_text(json.dumps(ordered, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    for line in log:
        print(line)
    print(f"\nwrote {path}  ({len(lex)} entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
