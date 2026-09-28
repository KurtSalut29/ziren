"""
Dump the structure of a .docx so you can locate content by label instead of
by a guessed index.

Usage:
    python inspect_docx.py WEEKLY-2-PROGRESS-REPORT.docx
    python inspect_docx.py ZIREN-PROBLEM-EXPLANATIONS.docx --full

Prints every non-empty body paragraph with its index and style, then every
table as a row/cell grid. Body paragraph indices are what `d.paragraphs[i]`
returns -- note that paragraphs nested inside tables are NOT in that list,
which is why table content is printed separately.

Truncates cell text to keep the output readable; pass --full for everything.
"""

import argparse
import sys

import docx

# The report uses U+2611 (BALLOT BOX WITH CHECK) and em dashes, which the
# Windows console's cp1252 codec cannot encode -- without this the script
# dies partway through with UnicodeEncodeError.
sys.stdout.reconfigure(encoding="utf-8")


def clip(text: str, width: int, full: bool) -> str:
    flat = text.strip().replace("\n", " | ")
    if full or len(flat) <= width:
        return flat
    return flat[:width] + "…"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--full", action="store_true", help="do not truncate cell text")
    ap.add_argument("--width", type=int, default=90)
    args = ap.parse_args()

    d = docx.Document(args.path)
    print(f"{args.path}: {len(d.paragraphs)} body paragraphs, {len(d.tables)} tables\n")

    print("=== BODY PARAGRAPHS ===")
    for i, p in enumerate(d.paragraphs):
        if p.text.strip():
            bold = " [bold]" if any(r.bold for r in p.runs if r.bold) else ""
            print(f"  p{i:<3} [{p.style.name}]{bold} {clip(p.text, args.width, args.full)}")

    print("\n=== TABLES ===")
    for ti, tb in enumerate(d.tables):
        print(f"\n  table {ti}: {len(tb.rows)} rows x {len(tb.columns)} cols")
        for ri, row in enumerate(tb.rows):
            cells = [clip(c.text, args.width, args.full) for c in row.cells]
            print(f"    r{ri}: {cells}")


if __name__ == "__main__":
    main()
