"""
Formatting-preserving edit helpers for the Ziren weekly report .docx files.

Import these rather than reimplementing. The naive approach --
`paragraph.text = "new text"` -- discards every run in the paragraph, and the
run is where the font, size, colour and highlighting live. On these documents
that means the dark 1E1E1E Consolas code blocks turn into plain body text.
These helpers keep the first run and edit its text instead.

Typical use:

    import sys; sys.path.insert(0, r".claude/skills/weekly-report/scripts")
    from docx_edit import *

    path = "WEEKLY-2-PROGRESS-REPORT.docx"
    backup_docx(path)
    d = load(path)

    table = find_table_by_label(d, "1.1 Problem Statement")
    cell  = row_by_label(table, "1.2 Root Cause Analysis").cells[1]
    set_paragraph_text(cell.paragraphs[0], "app/db/supabase_client.py caches ...")

    d.save(path)   # PermissionError here means the file is open in Word
"""

import copy
import shutil
import sys
from datetime import datetime
from pathlib import Path

import docx

sys.stdout.reconfigure(encoding="utf-8")

__all__ = [
    "backup_docx", "load", "find_table_by_label", "row_by_label",
    "paragraph_by_label", "set_paragraph_text", "set_paragraph_lines",
    "clone_paragraph_after", "delete_paragraph", "cell_text",
]


# ── File handling ────────────────────────────────────────────────────────────

def backup_docx(path: str | Path) -> Path:
    """Copy the file next to itself with a timestamp. Call before every edit
    session -- a bad run is otherwise unrecoverable, and these documents are
    hand-formatted."""
    path = Path(path)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = path.with_name(f"{path.stem}.backup-{stamp}{path.suffix}")
    shutil.copy2(path, dest)
    print(f"backup → {dest.name}")
    return dest


def load(path: str | Path):
    return docx.Document(str(path))


# ── Locating content by label ────────────────────────────────────────────────
# Always locate by the label text visible in Word. Indices drift between weeks,
# and `Document.paragraphs` skips paragraphs nested in tables, so body indices
# do not line up with what you see on screen.

def find_table_by_label(document, label: str):
    """Return the first table containing a cell whose text starts with `label`.
    Use a row label unique to one problem, e.g. "1.1 Problem Statement"."""
    needle = label.strip().casefold()
    for table in document.tables:
        for row in table.rows:
            if row.cells[0].text.strip().casefold().startswith(needle):
                return table
    raise LookupError(f"No table has a first-column cell starting with {label!r}")


def row_by_label(table, label: str):
    """Return the row of `table` whose first cell starts with `label`."""
    needle = label.strip().casefold()
    for row in table.rows:
        if row.cells[0].text.strip().casefold().startswith(needle):
            return row
    raise LookupError(f"No row in this table starts with {label!r}")


def paragraph_by_label(document, label: str):
    """Return the first body paragraph starting with `label`. Body only --
    for anything inside a table use find_table_by_label + row_by_label."""
    needle = label.strip().casefold()
    for p in document.paragraphs:
        if p.text.strip().casefold().startswith(needle):
            return p
    raise LookupError(f"No body paragraph starts with {label!r}")


def cell_text(cell) -> str:
    return "\n".join(p.text for p in cell.paragraphs)


# ── Editing text without losing formatting ───────────────────────────────────

def set_paragraph_text(paragraph, text: str):
    """Replace a paragraph's text, keeping the first run's formatting and
    dropping the rest. Word often splits a visually uniform sentence across
    several runs (spellcheck, editing history), so surviving runs would
    otherwise leave stale fragments behind."""
    runs = paragraph.runs
    if not runs:
        paragraph.add_run(text)
        return paragraph
    runs[0].text = text
    for r in runs[1:]:
        r._element.getparent().remove(r._element)
    return paragraph


def set_paragraph_lines(paragraph, lines):
    """Replace a paragraph with multiple visual lines inside one paragraph.

    This is how the ERROR / SOLUTION code blocks are built: a "\\n" inside run
    text renders as a single long line in Word, so each break must be a real
    <w:br/> element. run.add_break() emits exactly that, and the run keeps its
    Consolas + dark-background formatting across every line."""
    lines = list(lines)
    if not lines:
        return paragraph
    runs = paragraph.runs
    if not runs:
        run = paragraph.add_run()
    else:
        run = runs[0]
        for r in runs[1:]:
            r._element.getparent().remove(r._element)
    run.text = lines[0]
    for line in lines[1:]:
        run.add_break()
        run.add_text(line)
    return paragraph


# ── Adding and removing paragraphs ───────────────────────────────────────────

def clone_paragraph_after(paragraph, text: str | None = None):
    """Deep-copy a paragraph's XML and insert the copy right after it.

    Cloning is how you add a bullet or an extra code line: the copy inherits
    the source paragraph's style, indentation, numbering and run formatting,
    which a freshly added paragraph would not. Pass `text` to set the new
    paragraph's content in one step."""
    new_p = copy.deepcopy(paragraph._p)
    paragraph._p.addnext(new_p)
    cloned = docx.text.paragraph.Paragraph(new_p, paragraph._parent)
    if text is not None:
        set_paragraph_text(cloned, text)
    return cloned


def delete_paragraph(paragraph):
    """Remove a paragraph entirely (e.g. trimming a cloned bullet list back)."""
    element = paragraph._p
    element.getparent().remove(element)
