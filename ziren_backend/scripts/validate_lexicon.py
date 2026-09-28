#!/usr/bin/env python3
"""Hard invariants for ziren_lexicon.json.

The lexicon is a normalisation dictionary: it rewrites what a resident said
into a canonical form before the classifier and the signal extractors see it.
Every rewrite is therefore a chance to destroy evidence, and the ways it can
destroy evidence are not obvious by eye — they were all found by reading the
file, one at a time, after it already passed a validator that checked three
invariants and reported "OK".

So the rules below are deliberately stricter than "the JSON parses". Each one
is a defect that was actually present in v0.3.0, restated as something the file
is not allowed to contain. The comment above each check is the incident it came
from; do not relax a rule without reading it.

Usage:
    python scripts/validate_lexicon.py [path/to/ziren_lexicon.json]

Exit 0 = every invariant holds. Exit 1 = at least one violation, listed.
"""

from __future__ import annotations

import json
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

DEFAULT_PATH = (
    Path(__file__).resolve().parent.parent / "app" / "ml_overrides" / "ziren_lexicon.json"
)


def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


def key(s: str) -> str:
    """The form as the normaliser will actually see it: NFC, cased down, trimmed."""
    return nfc(s).strip().lower()


def squash(s: str) -> str:
    """Spacing and hyphenation removed — 'gab i', 'gab-i' and 'gabi' all collide.

    Used to tell an orthographic variant ('land slide' -> 'landslide', which
    loses no evidence) from a semantic one ('malakas na hangin' -> 'hangin',
    which loses the intensity that made the wind worth reporting).
    """
    return key(s).replace(" ", "").replace("-", "").replace("'", "")


def levenshtein(a: str, b: str, cap: int = 3) -> int:
    if abs(len(a) - len(b)) > cap:
        return cap + 1
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        if min(cur) > cap:
            return cap + 1
        prev = cur
    return prev[-1]


def longest_common_substring(a: str, b: str) -> int:
    if not a or not b:
        return 0
    best = 0
    prev = [0] * (len(b) + 1)
    for i in range(1, len(a) + 1):
        cur = [0] * (len(b) + 1)
        for j in range(1, len(b) + 1):
            if a[i - 1] == b[j - 1]:
                cur[j] = prev[j - 1] + 1
                best = max(best, cur[j])
        prev = cur
    return best


def shares_stem(a: str, b: str) -> bool:
    """Two forms look like inflections of one another rather than synonyms.

    Within a language a variant is nearly always morphology — a prefix, an
    infix, a vowel swap: nasunog/nasonog, tabang/tabangi, baha/bumabaha. Across
    languages it is suppletion: atop and bubong share nothing at all. That
    asymmetry is what INV07 leans on.
    """
    sa, sb = squash(a), squash(b)
    if not sa or not sb:
        return False
    if sa in sb or sb in sa:
        return True
    if levenshtein(sa, sb, cap=2) <= 2:
        return True
    # An infixed or reduplicated form shares a long run with its stem:
    # nagsuka/nagsusuka, away/nagaaway, dugo/nagdurugo.
    return longest_common_substring(sa, sb) >= 4


class Report:
    def __init__(self) -> None:
        self.problems: list[tuple[str, str]] = []

    def fail(self, code: str, msg: str) -> None:
        self.problems.append((code, msg))

    def __bool__(self) -> bool:
        return not self.problems


def check(doc: dict) -> Report:
    r = Report()
    meta = doc.get("meta", {})
    lex = doc.get("lexicon", [])
    phrases = doc.get("phrases", [])
    locations = doc.get("locations", [])

    grammar = {key(w) for w in meta.get("grammar_excluded", [])}
    ambiguous = {key(w) for w in meta.get("ambiguous_places_left_to_ner", [])}
    suppletive = {(key(a), key(b)) for a, b in meta.get("suppletive_variants", [])}
    negation_forms = {key(w) for w in meta.get("negation_forms", [])}
    reserved_places = {key(w) for w in meta.get("reserved_place_forms", [])}
    forbidden = {frozenset((key(a), key(b))) for a, b in meta.get("forbidden_merges", [])}

    lex_canon = {key(e["canonical"]) for e in lex}
    loc_forms = set()
    for loc in locations:
        loc_forms.add(key(loc["canonical"]))
        loc_forms.update(key(v) for v in loc["variants"])

    # ── INV00  Unicode is NFC everywhere ──────────────────────────────────
    # bahâ, guhô, bulíg, baláy, tawó and manggagawà are correctly spelled, but
    # a precomposed â and a decomposed a + U+0302 are different strings and
    # only one of them can ever match. Pinning the file to NFC makes the
    # loader's own NFC pass a no-op rather than a silent second normalisation.
    def scan_nfc(s: str, where: str) -> None:
        if s != nfc(s):
            r.fail("INV00", f"not NFC-normalised: {s!r} ({where})")

    for e in lex:
        scan_nfc(e["canonical"], f"lex:{e['canonical']}")
        for v in e["variants"]:
            scan_nfc(v, f"lex:{e['canonical']}")
    for loc in locations:
        scan_nfc(loc["canonical"], "location")
        for v in loc["variants"]:
            scan_nfc(v, "location")

    # ── INV01-04  the rewrite map is a function, and its entries are unique ─
    targets: dict[str, set[str]] = defaultdict(set)
    seen: Counter[str] = Counter()
    surfaces: list[tuple[str, str, str]] = []
    for e in lex:
        for v in e["variants"]:
            surfaces.append((v, e["canonical"], f"lex:{e['canonical']}"))
    for p in phrases:
        for v in p["variants"]:
            surfaces.append((v, p["canonical"], f"phrase:{p['canonical']}"))

    for v, c, where in surfaces:
        targets[key(v)].add(key(c))
        seen[key(v)] += 1
        if key(v) in lex_canon and key(v) != key(c):
            r.fail("INV02", f"{v!r} is a variant of {c!r} AND a canonical elsewhere ({where})")
        if key(v) == key(c):
            r.fail("INV03", f"variant identical to canonical: {v!r} ({where})")
    for v, t in targets.items():
        if len(t) > 1:
            r.fail("INV01", f"{v!r} rewrites to multiple canonicals: {sorted(t)}")
    for v, n in seen.items():
        if n > 1:
            r.fail("INV04", f"variant {v!r} declared {n}x")

    # ── INV05  a rewrite may drop grammar, never content ──────────────────
    # This is the greeting bug. 'maayong adlaw' -> 'maayong' deleted adlaw, and
    # adlaw is the whole time-of-day register: every report that opened with a
    # greeting — 244 of them — lost its only "when" evidence before anything
    # downstream could read it. 'malakas na hangin' -> 'hangin' has the same
    # shape and costs an intensity signal instead.
    #
    # Dropping a grammar particle is fine and necessary ('kanto ng' -> 'kanto');
    # dropping a content word never is. Respellings are exempt because they
    # delete nothing: they rewrite the same words.
    for v, c, where in surfaces:
        if squash(v) == squash(c):
            continue  # 'gab i' -> 'gab-i', 'nag report' -> 'nagreport'
        if levenshtein(squash(v), squash(c), cap=2) <= 2:
            continue  # 'hold up' -> 'holdap'
        v_content = [w for w in key(v).split() if w not in grammar]
        c_content = [w for w in key(c).split() if w not in grammar]
        if len(v_content) > len(c_content):
            dropped = [w for w in v_content if w not in c_content]
            r.fail("INV05", f"{key(v)!r} -> {key(c)!r} deletes content {dropped} ({where})")

    # ── INV06  one lemma, one concept ─────────────────────────────────────
    # 'burning' resolved to FIRE or to None depending on which entry a dict
    # comprehension happened to insert last, because the uncurated auto-extract
    # re-declared four lemmas the curated half already owned. A lemma that is
    # not single-valued is not a feature, it is a coin flip.
    concepts: dict[str, set[tuple]] = defaultdict(set)
    for e in lex:
        concepts[e["lemma"]].add((e.get("incident_concept"), e.get("hazard_subtype")))
    for lemma, vals in sorted(concepts.items()):
        if len(vals) > 1:
            r.fail("INV06", f"lemma {lemma!r} carries conflicting concepts: {sorted(vals, key=str)}")

    # ── INV07  no cross-language variant inside an entry ──────────────────
    # The surface layer is documented as within-language; the lemma layer is
    # what links languages. Filing bubong (fil) under atop (war) collapses the
    # two before anything can tell them apart, permanently destroying the
    # evidence a language-ID feature would need — and silently mislabelling the
    # entry's own `lang`.
    #
    # Within a language a variant is morphology and shares a stem. Suppletive
    # same-language synonyms (saklolo/tulong) genuinely do not, so they are
    # allowed — but only by name, in meta.suppletive_variants, where a reviewer
    # can see them. Cross-language dumping is then impossible to do quietly: it
    # fails, or it lands in a list somebody reads.
    for e in lex:
        for v in e["variants"]:
            if shares_stem(v, e["canonical"]):
                continue
            if (key(v), key(e["canonical"])) in suppletive:
                continue
            r.fail(
                "INV07",
                f"{v!r} shares no stem with canonical {e['canonical']!r} "
                f"(lang={e['lang']}, lemma={e['lemma']}) -- split it into its own entry "
                f"with the same lemma, or declare it in meta.suppletive_variants",
            )

    # ── INV08  negation is modelled, never dumped ─────────────────────────
    # "dili makaginhawa" and "makaginhawa" differ by one word and by an
    # ambulance. v0.3.0 filed dili/hindi/wala as register 'uncurated', lang
    # 'unknown', gloss '' — neither excluded nor described, so the extractor's
    # _negated() had nothing to stand on.
    by_canon = {key(e["canonical"]): e for e in lex}
    for w in sorted(negation_forms):
        e = by_canon.get(w)
        if e is None:
            r.fail("INV08", f"negation form {w!r} has no lexicon entry")
            continue
        if e["register"] == "uncurated":
            r.fail("INV08", f"negation form {w!r} is register 'uncurated'")
        if not e.get("negation"):
            r.fail("INV08", f"negation form {w!r} lacks negation: true")
        if w in grammar:
            r.fail("INV08", f"negation form {w!r} is in grammar_excluded -- it must survive normalisation")

    # ── INV09  uncurated is for content, not for function words ───────────
    # coverage_policy says pure grammar is excluded by design; 31 function
    # words sat in the uncurated auto-extract anyway, inflating the entry count
    # and implying a curation backlog that does not exist.
    for e in lex:
        if e["register"] == "uncurated" and key(e["canonical"]) in grammar:
            r.fail("INV09", f"uncurated entry {e['canonical']!r} is also in grammar_excluded")

    # ── INV10  a form belongs to exactly one policy ───────────────────────
    # 'mula' was listed in grammar_excluded (drop it), in
    # ambiguous_places_left_to_ner (do not touch it, NER decides) and as a
    # variant of 'tikang' (rewrite it), all at once. The rewrite runs first, so
    # the place name died before NER was ever consulted.
    all_forms: dict[str, set[str]] = defaultdict(set)
    for e in lex:
        all_forms[key(e["canonical"])].add("lexicon:canonical")
        for v in e["variants"]:
            all_forms[key(v)].add("lexicon:variant")
    for p in phrases:
        all_forms[key(p["canonical"])].add("phrase:canonical")
        for v in p["variants"]:
            all_forms[key(v)].add("phrase:variant")
    for w in grammar:
        all_forms[w].add("grammar_excluded")
    for w in ambiguous:
        all_forms[w].add("ambiguous_places_left_to_ner")
    for w in loc_forms:
        all_forms[w].add("locations")
    for form, policies in sorted(all_forms.items()):
        rewrite = {p for p in policies if p.endswith(":variant")}
        protect = policies & {"ambiguous_places_left_to_ner", "locations"}
        drop = policies & {"grammar_excluded"}
        if rewrite and protect:
            r.fail("INV10", f"{form!r} is both rewritten and protected: {sorted(policies)}")
        if drop and (rewrite or protect):
            r.fail("INV10", f"{form!r} is both dropped and used: {sorted(policies)}")

    # ── INV11  curated and uncurated never share a lemma ───────────────────
    curated_l = {e["lemma"] for e in lex if e["register"] != "uncurated"}
    uncurated_l = {e["lemma"] for e in lex if e["register"] == "uncurated"}
    for lemma in sorted(curated_l & uncurated_l):
        r.fail("INV11", f"lemma {lemma!r} exists in both the curated and uncurated halves")

    # ── INV12  a place name is never rewritten into a common word ─────────
    # 'sabang' -> 'tabang' erased a real barangay name to recover a mishearing.
    # It is also the wrong layer: a recogniser confusing s- for t- is a machine
    # error and belongs in stt_corrections.csv, where a human signs it off
    # against the recording. The lexicon describes what people say, not what
    # Whisper hears.
    for v, c, where in surfaces:
        if key(v) in reserved_places:
            r.fail("INV12", f"{v!r} is a reserved place form but is rewritten to {c!r} ({where})")

    # ── INV13  declared never-merge pairs stay unmerged ───────────────────
    # 'asawa' was a variant of 'bana'. bana is husband; asawa is wife. The
    # rewrite turned every wife in the corpus into a husband. Nothing mechanical
    # catches a meaning collapse, so the pairs are named here and the file is
    # held to them.
    for e in lex:
        forms = {key(e["canonical"])} | {key(v) for v in e["variants"]}
        for pair in forbidden:
            if pair <= forms:
                r.fail("INV13", f"entry {e['canonical']!r} merges forbidden pair {sorted(pair)}")

    # ── INV14  schema ─────────────────────────────────────────────────────
    required = ("lemma", "canonical", "lang", "variants", "gloss", "register", "source", "verified")
    langs = set(meta.get("languages", []))
    registers = set(meta.get("registers", []))
    for e in lex:
        for k in required:
            if k not in e:
                r.fail("INV14", f"entry {e.get('canonical', '?')!r} missing {k!r}")
        if langs and e.get("lang") not in langs:
            r.fail("INV14", f"entry {e['canonical']!r} has lang {e.get('lang')!r} not in meta.languages")
        if registers and e.get("register") not in registers:
            r.fail("INV14", f"entry {e['canonical']!r} has register {e.get('register')!r} not in meta.registers")
        if e.get("source") == "dataset" and e.get("freq", 0) == 0:
            r.fail("INV14", f"entry {e['canonical']!r} claims source 'dataset' but freq is 0")

    return r


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT_PATH
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 — report and exit, do not traceback
        print(f"FAIL: could not read {path}: {exc}")
        return 1

    lex = doc.get("lexicon", [])
    curated = [e for e in lex if e.get("register") != "uncurated"]
    print(
        f"{path.name}: {len(lex)} entries "
        f"({len(curated)} curated, {len(lex) - len(curated)} uncurated), "
        f"{len(doc.get('locations', []))} locations, {len(doc.get('phrases', []))} phrases"
    )

    report = check(doc)
    if report:
        print("All invariants hold. OK.")
        return 0

    by_code: dict[str, list[str]] = defaultdict(list)
    for code, msg in report.problems:
        by_code[code].append(msg)
    print(f"\nFAIL: {len(report.problems)} violation(s) across {len(by_code)} invariant(s):\n")
    for code in sorted(by_code):
        msgs = by_code[code]
        print(f"  {code}  ({len(msgs)})")
        for m in msgs[:12]:
            print(f"      {m}")
        if len(msgs) > 12:
            print(f"      ... and {len(msgs) - 12} more")
        print()
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
