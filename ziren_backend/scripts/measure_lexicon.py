#!/usr/bin/env python3
"""What the lexicon pass would do to the release test split, before it does it.

This is the same measurement that decided FUZZY_NORMALISATION, written up at
triage_service.py:205-225: the release's own test split, 249 rows, counted as
rows rewritten and severities moved, with the individual rewrites named rather
than aggregated. That measurement is the reason the fuzzy pass is off by
decision instead of by accident, and the lexicon has to clear the same bar.

The decision rule is pre-registered, before any number is read:

    Any severity DOWNGRADE must be named and explained individually,
    or the pass stays off.

Two things this harness deliberately holds still:

  * The category. run() classifies strip_places(ORIGINAL text), never the
    normalised text -- the comment at predict.py:443 records that feeding
    normalised text to the classifier took errors from 6 to 14. So the lexicon
    cannot move the category as the pipeline is built, and holding it fixed
    across both arms means every severity difference is attributable to the
    signals alone. The counterfactual (what WOULD happen if the classifier saw
    the normalised text) is reported separately, clearly labelled, because it
    is a standing temptation and should be costed rather than argued about.

  * The baseline. It is production's own normalise_text() -- alias, then
    phonetic, fuzzy off -- so the treatment arm measures the lexicon and
    nothing else.

stdlib only, on purpose: pandas is not in the backend venv and a one-off
measurement is not a reason to add a dependency.

    python scripts/measure_lexicon.py <test.csv> [--lexicon path] [--show N]
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services import triage_service as T  # noqa: E402

SEVERITY_ORDER = {"LOW": 0, "MODERATE": 1, "HIGH": 2, "CRITICAL": 3}
TRACKED = ("injured_count", "entrapment", "people_involved")


def key(s: str) -> str:
    return unicodedata.normalize("NFC", s).strip().lower()


class Lexicon:
    """The surface layer only: variant -> canonical, longest phrase first.

    The lemma layer is not applied here. It is a feature key for a classifier
    that is not being retrained in this measurement, and applying it would
    rewrite the text into tokens the signal extractors have never seen, which
    measures a different change than the one being decided.
    """

    def __init__(self, path: Path, protected: set[str]):
        doc = json.loads(path.read_text(encoding="utf-8"))
        self.version = doc["meta"]["version"]
        self.surface: dict[str, str] = {}
        skipped = []
        for entry in doc["lexicon"]:
            for v in entry["variants"]:
                if key(v) in protected:
                    skipped.append(v)
                    continue
                self.surface[key(v)] = entry["canonical"]
        for p in doc.get("phrases", []):
            for v in p["variants"]:
                self.surface[key(v)] = p["canonical"]
        for loc in doc.get("locations", []):
            for v in loc["variants"]:
                self.surface[key(v)] = loc["canonical"]
        self.skipped_protected = skipped
        # Longest first: 'kanto ng' has to be tried before 'kanto', or the
        # shorter key consumes the head of the phrase and the linker is
        # stranded.
        keys = sorted(self.surface, key=lambda k: (-len(k.split()), -len(k)))
        self._patterns = [
            (re.compile(r"(?<!\w)" + re.escape(k) + r"(?!\w)", re.I), k) for k in keys
        ]

    def apply(self, text: str) -> tuple[str, list[tuple[str, str]]]:
        out = text
        changes: list[tuple[str, str]] = []
        for pat, k in self._patterns:
            canon = self.surface[k]
            if pat.search(out):
                new = pat.sub(canon.replace("\\", "\\\\"), out)
                if new != out:
                    changes.append((k, canon))
                    out = new
        return out, changes


def classify(pipe, text: str):
    proba = pipe.predict_proba([T._Z.strip_places(text)])[0]
    classes = list(pipe.named_steps["clf"].classes_)
    i = proba.argmax()
    return classes[i], float(proba[i])


def signal_delta(base: dict, lex: dict) -> tuple[list[str], list[str]]:
    """Signals the lexicon recovered, and signals it destroyed.

    None means unknown, False means explicitly denied, True/int means stated.
    Moving off None is a gain; moving onto None is a loss. A True that becomes
    False (or the reverse) is counted as both, because that is an inversion and
    is worse than either.
    """
    gained, lost = [], []
    for k in base:
        b, x = base.get(k), lex.get(k)
        if b == x:
            continue
        if b is None and x is not None:
            gained.append(k)
        elif b is not None and x is None:
            lost.append(k)
        else:
            gained.append(f"{k}:{b}->{x}")
            lost.append(f"{k}:{b}->{x}")
    return gained, lost


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("split", type=Path)
    ap.add_argument("--lexicon", type=Path,
                    default=Path(__file__).resolve().parent.parent
                    / "app" / "ml_overrides" / "ziren_lexicon.json")
    ap.add_argument("--show", type=int, default=25)
    ap.add_argument(
        "--treatment",
        choices=("lexicon", "alias-repair"),
        default="lexicon",
        help="lexicon: production normalise_text vs the same plus the lexicon surface pass. "
             "alias-repair: normalise_text with ALIAS_CASE_REPAIR off vs on -- the release's "
             "case-blind alias application against the fixed one.",
    )
    args = ap.parse_args()

    T.load()
    if T._LOAD_ERROR:
        print(f"FAIL: triage_service did not load: {T._LOAD_ERROR}")
        return 1
    protected = {key(w) for w in getattr(T._Z, "PROTECTED", set())}
    lex = Lexicon(args.lexicon, protected)

    rows = list(csv.DictReader(args.split.open(encoding="utf-8")))
    print(f"split    {args.split.name}  {len(rows)} rows")
    print(f"lexicon  {lex.version}  {len(lex.surface)} surface forms"
          f"  ({len(lex.skipped_protected)} skipped as PROTECTED)")
    print(f"baseline production normalise_text() -- alias + phonetic, fuzzy off")
    print()

    rewritten = 0
    sev_up, sev_down = [], []
    cat_cf_changed = []
    gained_c: Counter[str] = Counter()
    lost_c: Counter[str] = Counter()
    rewrite_c: Counter[tuple[str, str]] = Counter()
    rewrite_rows: dict[tuple[str, str], list[str]] = defaultdict(list)
    tracked_gain: Counter[str] = Counter()
    tracked_loss: Counter[str] = Counter()

    for row in rows:
        text = row["report_text"]
        rid = row["report_id"]

        if args.treatment == "lexicon":
            base_norm, _ = T.normalise_text(text)
            lex_norm, changes = lex.apply(base_norm)
        else:
            # Both arms are normalise_text; only the repair flag differs, so
            # the delta is the case fix and nothing else.
            T.ALIAS_CASE_REPAIR = False
            base_norm, _ = T.normalise_text(text)
            T.ALIAS_CASE_REPAIR = True
            lex_norm, applied = T.normalise_text(text)
            changes = (
                [tuple(c.replace(" (alias)", "").split(" -> ", 1)) for c in applied
                 if c.endswith("(alias)")]
                if base_norm != lex_norm else []
            )

        if changes:
            rewritten += 1
            for pair in changes:
                if key(pair[0]) != key(pair[1]):
                    rewrite_c[pair] += 1
                    rewrite_rows[pair].append(rid)

        sig_base, _hedged_base = T._Z.extract(base_norm)
        sig_lex, _hedged_lex = T._Z.extract(lex_norm)

        # Category held fixed across both arms: the pipeline classifies the
        # original text, so this is what production would actually route on.
        cat, conf = classify(T._MODEL, text)
        cat_cf, conf_cf = classify(T._MODEL, lex_norm)
        if cat_cf != cat:
            cat_cf_changed.append((rid, cat, conf, cat_cf, conf_cf, row["incident_type"]))

        _, lvl_base, why_base = T._Z.severity(sig_base, cat, conf, category_from_user=False)
        _, lvl_lex, why_lex = T._Z.severity(sig_lex, cat, conf, category_from_user=False)

        if SEVERITY_ORDER[lvl_lex] > SEVERITY_ORDER[lvl_base]:
            sev_up.append((rid, lvl_base, lvl_lex, why_base, why_lex, text, changes))
        elif SEVERITY_ORDER[lvl_lex] < SEVERITY_ORDER[lvl_base]:
            sev_down.append((rid, lvl_base, lvl_lex, why_base, why_lex, text, changes))

        g, l = signal_delta(sig_base, sig_lex)
        for k in g:
            gained_c[k] += 1
            if k in TRACKED:
                tracked_gain[k] += 1
        for k in l:
            lost_c[k] += 1
            if k in TRACKED:
                tracked_loss[k] += 1

    # ── report ────────────────────────────────────────────────────────────
    print("=" * 72)
    print(f"rows rewritten .............. {rewritten} / {len(rows)}")
    print(f"severity UPGRADED ........... {len(sev_up)}")
    print(f"severity DOWNGRADED ......... {len(sev_down)}   <-- the pre-registered gate")
    print(f"category changed (as built) . 0   (classifier reads the original text by design)")
    print(f"category changed (counterfactual, if it read the normalised text) . {len(cat_cf_changed)}")
    print()

    print("signals, tracked:")
    for k in TRACKED:
        print(f"    {k:18} gained {tracked_gain[k]:3}   lost {tracked_loss[k]:3}")
    other_g = {k: v for k, v in gained_c.items() if k not in TRACKED}
    other_l = {k: v for k, v in lost_c.items() if k not in TRACKED}
    if other_g or other_l:
        print("signals, other:")
        for k in sorted(set(other_g) | set(other_l)):
            print(f"    {k:18} gained {other_g.get(k, 0):3}   lost {other_l.get(k, 0):3}")
    print()

    if sev_down:
        print("-" * 72)
        print("SEVERITY DOWNGRADES -- each must be explained or the pass stays off")
        for rid, b, x, wb, wx, text, ch in sev_down:
            print(f"\n  {rid}  {b} -> {x}")
            print(f"      was: {wb}")
            print(f"      now: {wx}")
            print(f"      rewrites: {[f'{a}->{c}' for a, c in ch if key(a) != key(c)]}")
            print(f"      {text[:150]}")
        print()

    if sev_up:
        print("-" * 72)
        print("SEVERITY UPGRADES")
        for rid, b, x, wb, wx, text, ch in sev_up[: args.show]:
            print(f"  {rid}  {b} -> {x}   ({wx})")
            print(f"      rewrites: {[f'{a}->{c}' for a, c in ch if key(a) != key(c)]}")
        if len(sev_up) > args.show:
            print(f"  ... and {len(sev_up) - args.show} more")
        print()

    print("-" * 72)
    print(f"distinct rewrites, by frequency ({len(rewrite_c)} distinct):")
    for (a, b), n in rewrite_c.most_common(args.show):
        rows_hit = rewrite_rows[(a, b)]
        sample = ",".join(rows_hit[:3]) + ("..." if len(rows_hit) > 3 else "")
        print(f"    {n:4}x  {a:22} -> {b:22}  [{sample}]")
    if len(rewrite_c) > args.show:
        print(f"    ... and {len(rewrite_c) - args.show} more distinct rewrites")
    print()

    if cat_cf_changed:
        print("-" * 72)
        print("COUNTERFACTUAL ONLY -- category if the classifier read normalised text.")
        print("Not what the pipeline does. Reported so the cost is on the record.")
        for rid, cb, fb, cx, fx, gold in cat_cf_changed[: args.show]:
            mark = "correct" if cx == gold else ("was correct" if cb == gold else "both wrong")
            print(f"    {rid}  {cb} ({fb:.2f}) -> {cx} ({fx:.2f})   gold={gold}  [{mark}]")
        if len(cat_cf_changed) > args.show:
            print(f"    ... and {len(cat_cf_changed) - args.show} more")
        print()

    print("=" * 72)
    verdict = "PASSES the pre-registered rule" if not sev_down else (
        f"{len(sev_down)} downgrade(s) -- each needs an individual explanation, "
        f"or the pass stays off")
    print(f"VERDICT  {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
