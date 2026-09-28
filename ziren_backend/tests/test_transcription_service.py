"""The path from a resident's recording to a ranked incident.

The rule these exist to protect: the report is already saved before any of
this runs, so nothing here may be able to damage it. Every failure mode below
— no engine, unreadable row, failed download, oversized file, an engine that
raises — has to end with the incident exactly as the resident filed it.
"""
from unittest.mock import MagicMock, patch

import pytest

from app.services import transcription_service as ts


class FakeEngine:
    name = "fake"
    version = "0.0.1"

    def __init__(self, text="mayda sunog didi ha caibiran", raises=False):
        self._text = text
        self._raises = raises
        self.calls = 0

    def transcribe(self, audio: bytes, *, filename: str) -> dict:
        self.calls += 1
        if self._raises:
            raise RuntimeError("engine exploded")
        return {"text": self._text, "language": "fil"}


@pytest.fixture
def no_engine():
    ts.register_engine(None)
    yield
    ts.register_engine(None)


@pytest.fixture
def engine():
    e = FakeEngine()
    ts.register_engine(e)
    yield e
    ts.register_engine(None)


# ── picking the attachment ──────────────────────────────────────────────────

class TestPickAudio:
    def test_finds_the_voice_note(self):
        assert ts.pick_audio(["u/1/photo.jpg", "u/1/ziren_voice_1.m4a"]) \
            == "u/1/ziren_voice_1.m4a"

    def test_ignores_photos(self):
        assert ts.pick_audio(["u/1/a.jpg", "u/1/b.png"]) is None

    def test_ignores_video(self):
        # A video has audio a dispatcher can hear, but no demux step exists.
        assert ts.pick_audio(["u/1/clip.mp4"]) is None

    def test_empty_and_none(self):
        assert ts.pick_audio([]) is None
        assert ts.pick_audio(None) is None


# ── absent engine is a supported state, not an outage ──────────────────────

class TestNoEngine:
    def test_status_says_so(self, no_engine):
        s = ts.status()
        assert s["available"] is False
        assert s["engine"] is None
        assert s["reason"]

    def test_transcribe_returns_none(self, no_engine):
        assert ts.transcribe(b"\x00\x01", filename="a.m4a") is None

    def test_incident_is_never_touched(self, no_engine):
        with patch.object(ts, "get_supabase") as db:
            ts.transcribe_incident("inc-1", "u/1/a.m4a")
            db.assert_not_called()


# ── how the words are joined to what was typed ─────────────────────────────

class TestComposeReportText:
    def test_transcript_alone_when_nothing_typed(self):
        assert ts._compose_report_text("", "may sunog") == "may sunog"
        assert ts._compose_report_text(None, "may sunog") == "may sunog"

    def test_typed_text_stays_first_and_intact(self):
        got = ts._compose_report_text("Sunog / Fire", "may sunog sa balay")
        assert got.startswith("Sunog / Fire")
        assert "may sunog sa balay" in got

    def test_not_duplicated_if_already_present(self):
        base = "Sunog / Fire — may sunog sa balay"
        assert ts._compose_report_text(base, "may sunog sa balay") == base


# ── the full path, with the database mocked ────────────────────────────────

def _db_with(row, audio=b"x" * 20000):
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value \
        .single.return_value.execute.return_value.data = row
    db.storage.from_.return_value.download.return_value = audio
    return db


def _row(**over):
    base = {
        "id": "inc-1",
        "report_text": "Sunog / Fire",
        "status": "received",
        "severity": None,
        "signals": {"engine": "ziren-model"},
        "incident_category": "fire",
        "wizard_answers": None,
        "overlap_agencies": None,
        "landmark_note": None,
    }
    base.update(over)
    return base


class TestTranscribeIncident:
    def test_writes_transcript_and_provenance(self, engine):
        db = _db_with(_row())
        with patch.object(ts, "get_supabase", return_value=db), \
             patch.object(ts.triage_service, "triage", return_value=None):
            ts.transcribe_incident("inc-1", "u/1/a.m4a")

        update = db.table.return_value.update.call_args[0][0]
        assert "mayda sunog" in update["report_text"]
        prov = update["signals"]["transcript"]
        assert prov["engine"] == "fake"
        assert prov["audio_path"] == "u/1/a.m4a"
        # A dispatcher must be able to tell a machine heard this.
        assert "audio is authoritative" in prov["note"]

    def test_already_handled_incident_is_left_alone(self, engine):
        # A dispatcher has acted; rewriting the text under them is worse than
        # having no transcript.
        db = _db_with(_row(status="dispatched"))
        with patch.object(ts, "get_supabase", return_value=db):
            ts.transcribe_incident("inc-1", "u/1/a.m4a")
        db.table.return_value.update.assert_not_called()
        assert engine.calls == 0

    def test_engine_that_raises_changes_nothing(self):
        ts.register_engine(FakeEngine(raises=True))
        db = _db_with(_row())
        try:
            with patch.object(ts, "get_supabase", return_value=db):
                ts.transcribe_incident("inc-1", "u/1/a.m4a")
            db.table.return_value.update.assert_not_called()
        finally:
            ts.register_engine(None)

    def test_empty_transcript_changes_nothing(self):
        ts.register_engine(FakeEngine(text="   "))
        db = _db_with(_row())
        try:
            with patch.object(ts, "get_supabase", return_value=db):
                ts.transcribe_incident("inc-1", "u/1/a.m4a")
            db.table.return_value.update.assert_not_called()
        finally:
            ts.register_engine(None)

    def test_oversized_audio_is_refused(self, engine):
        db = _db_with(_row(), audio=b"x" * (ts._MAX_BYTES + 1))
        with patch.object(ts, "get_supabase", return_value=db):
            ts.transcribe_incident("inc-1", "u/1/a.m4a")
        db.table.return_value.update.assert_not_called()
        assert engine.calls == 0

    def test_failed_download_changes_nothing(self, engine):
        db = _db_with(_row())
        db.storage.from_.return_value.download.side_effect = RuntimeError("gone")
        with patch.object(ts, "get_supabase", return_value=db):
            ts.transcribe_incident("inc-1", "u/1/a.m4a")
        db.table.return_value.update.assert_not_called()

    def test_missing_row_changes_nothing(self, engine):
        db = _db_with(None)
        with patch.object(ts, "get_supabase", return_value=db):
            ts.transcribe_incident("inc-1", "u/1/a.m4a")
        db.table.return_value.update.assert_not_called()


# ── scheduling ─────────────────────────────────────────────────────────────

class TestSchedule:
    def test_queues_when_there_is_audio(self):
        bg = MagicMock()
        ts.schedule(bg, "inc-1", ["u/1/a.jpg", "u/1/v.m4a"])
        bg.add_task.assert_called_once_with(
            ts.transcribe_incident, "inc-1", "u/1/v.m4a"
        )

    def test_photo_only_report_queues_nothing(self):
        bg = MagicMock()
        ts.schedule(bg, "inc-1", ["u/1/a.jpg"])
        bg.add_task.assert_not_called()

    def test_no_attachments_queues_nothing(self):
        bg = MagicMock()
        ts.schedule(bg, "inc-1", None)
        bg.add_task.assert_not_called()


class TestCategorySurvivesRetriage:
    """The resident's own selection is an assertion, not a guess.

    triage() treats a tapped category differently from a model prediction —
    SR005B and the SR010/SR011 fail-safes both hinge on it. Re-scoring the
    transcript without it can lower a severity the resident already justified.
    """

    def test_category_is_passed_back_in(self, engine):
        db = _db_with(_row(incident_category="medical_trauma"))
        with patch.object(ts, "get_supabase", return_value=db), \
             patch.object(ts.triage_service, "triage", return_value=None) as tri:
            ts.transcribe_incident("inc-1", "u/1/a.m4a")
        assert tri.call_args.kwargs["incident_category"] is not None
        assert tri.call_args.kwargs["incident_category"].value == "medical_trauma"

    def test_retired_category_does_not_lose_the_transcript(self, engine):
        # migration 019 retired hazmat and missing_person; an old row must
        # still get its words.
        db = _db_with(_row(incident_category="hazmat"))
        with patch.object(ts, "get_supabase", return_value=db), \
             patch.object(ts.triage_service, "triage", return_value=None) as tri:
            ts.transcribe_incident("inc-1", "u/1/a.m4a")
        assert tri.call_args.kwargs["incident_category"] is None
        db.table.return_value.update.assert_called_once()


# ── engine loading ─────────────────────────────────────────────────────────
#
# These never build a real recogniser. Downloading half a gigabyte of weights
# inside a unit test would make the suite depend on a network and on a model
# host staying up, and the thing worth asserting is the opposite anyway: that
# a recogniser which cannot be built leaves the API serving exactly as it does
# with none installed.

from app.services import asr_engines


class TestEngineLoading:
    def test_unknown_engine_is_none_not_an_exception(self):
        assert asr_engines.load("whisper-xxl-that-does-not-exist") is None

    def test_a_failing_build_is_none(self, monkeypatch):
        def boom(*_a, **_k):
            raise RuntimeError("no weights, no network, no disk")
        monkeypatch.setattr(asr_engines, "FasterWhisperEngine", boom)
        assert asr_engines.load("faster-whisper-small") is None

    def test_registering_none_leaves_the_service_unavailable(self):
        asr_engines.load("nonsense")
        ts.register_engine(None)
        assert ts.is_available() is False
        assert ts.status()["available"] is False
