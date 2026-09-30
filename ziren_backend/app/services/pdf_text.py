"""
Text that the PDF's built-in fonts can actually draw.

Every Ziren PDF is set in ReportLab's standard Helvetica, which only has
glyphs for Windows-1252 (Latin letters, ñ, é, curly quotes, dashes). Anything
else - an emoji, or a voice note the speech model heard as Hindi and stored in
Devanagari - is drawn as a row of black boxes, which on a printed government
record reads as redaction. Such a run is replaced by a plain note instead; the
Excel and CSV exports carry the original text untouched.
"""
from __future__ import annotations

import re

UNPRINTABLE = "[characters this PDF cannot print — see the Excel file]"


def _printable(ch: str) -> bool:
    try:
        ch.encode("cp1252")
        return True
    except UnicodeEncodeError:
        return False


def printable(text: str) -> str:
    out: list[str] = []
    for ch in text:
        if _printable(ch):
            out.append(ch)
        elif not out or out[-1] != UNPRINTABLE:
            out.append(UNPRINTABLE)
    s = "".join(out)
    # "शाँचिक शाँचिके" is two runs split by a space; say so once.
    note = re.escape(UNPRINTABLE)
    return re.sub(rf"{note}(?:\s+{note})+", UNPRINTABLE, s)
