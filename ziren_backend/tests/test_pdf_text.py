"""
pdf_text.printable - what the PDFs' Helvetica can draw, and a plain note for
what it cannot (it would otherwise print black boxes).

Run with: pytest tests/test_pdf_text.py -v
"""
import pytest

from app.services.pdf_text import UNPRINTABLE, printable


@pytest.mark.parametrize("text", [
    "Sunog sa bahay, may naiwan pang bata sa loob",
    "Señor Niño, Brgy. Sto. Niño — “tabang!”",
    "Fire — among litson way kayo",
])
def test_latin_text_is_untouched(text):
    assert printable(text) == text


def test_a_run_in_another_script_becomes_one_note():
    # A real stored transcript: the speech model heard a Waray voice note as Hindi.
    assert printable("(Voice) शाँचिक शाँचिके लो") == f"(Voice) {UNPRINTABLE}"


def test_emoji_become_a_note_and_the_words_around_them_stay():
    assert printable("may sunog 🔥🔥 dito") == f"may sunog {UNPRINTABLE} dito"
