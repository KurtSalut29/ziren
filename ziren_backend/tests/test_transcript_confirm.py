"""The resident tells us whether we heard them right.

This is the only certainty in the pipeline. Measured on real recordings from a
real handset, the recogniser runs at 51% word error rate on Waray, and the one
clip that came out nearly perfect still lost the child left inside a burning
house. The person standing at the scene knows what they said; nothing else in
the system does.

So the rules these protect are about trust, not correctness:
  * the report is already saved before any of this, and stays saved
  * the reporter's wording outranks the machine's guess at it, always
  * a dispatcher who has already acted is never overwritten
  * both halves of the pair are kept, because that is labelled Waray speech
"""
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import incident_service as svc


REPORTER = "11111111-1111-1111-1111-111111111111"
INCIDENT = "33333333-3333-3333-3333-333333333333"
STATION  = "44444444-4444-4444-4444-444444444444"
OTHER = "22222222-2222-2222-2222-222222222222"


def _row(**over):
    base = {
        "id": INCIDENT,
        "reporter_id": REPORTER,
        "station_id": STATION,
        "report_text": "Sunog / Fire — na ay sunog didi sa amon balay",
        "status": "received",
        "severity": "high",
        "location_address": None,
        "submitted_via": "internet",
        "created_at": "2026-08-31T00:00:00+00:00",
        "updated_at": "2026-08-31T00:00:00+00:00",
        "incident_category": "fire",
        "wizard_answers": None,
        "overlap_agencies": None,
        "landmark_note": None,
        "signals": {
            "engine": "ziren-model",
            "transcript": {
                "text": "na ay sunog didi sa amon balay",
                "engine": "faster-whisper-small",
                "engine_version": "ct2",
            },
        },
    }
    base.update(over)
    return base


def _db(row):
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value \
        .single.return_value.execute.return_value.data = row
    return db


def _update_payload(db):
    return db.table.return_value.update.call_args[0][0]


class TestConfirmedAsHeard:
    def test_marks_confirmed_without_touching_the_text(self):
        db = _db(_row())
        with patch.object(svc, "get_supabase", return_value=db):
            svc.confirm_transcript(INCIDENT, REPORTER)
        payload = _update_payload(db)
        assert payload["signals"]["transcript"]["confirmed_by_reporter"] is True
        # Agreeing is not an edit.
        assert "report_text" not in payload
        assert "severity" not in payload

    def test_blank_correction_counts_as_agreement(self):
        db = _db(_row())
        with patch.object(svc, "get_supabase", return_value=db):
            svc.confirm_transcript(INCIDENT, REPORTER, corrected_text="   ")
        assert _update_payload(db)["signals"]["transcript"][
            "confirmed_by_reporter"] is True

    def test_agreement_is_allowed_even_after_dispatch(self):
        # It changes nothing a dispatcher is acting on — it only records that
        # the transcript was right, which is a label worth having.
        db = _db(_row(status="dispatched"))
        with patch.object(svc, "get_supabase", return_value=db):
            svc.confirm_transcript(INCIDENT, REPORTER)
        db.table.return_value.update.assert_called_once()


class TestCorrection:
    def test_the_reporters_words_replace_the_machines(self):
        db = _db(_row())
        said = "naay sunog didi sa amon balay duha ka tawo an naipit sa sulod"
        with patch.object(svc, "get_supabase", return_value=db), \
             patch.object(svc.triage_service, "triage", return_value=None):
            svc.confirm_transcript(INCIDENT, REPORTER, corrected_text=said)
        assert _update_payload(db)["report_text"] == said

    def test_both_halves_are_kept(self):
        # The pair (what the machine heard, what was actually said) is labelled
        # Waray emergency speech — the data whose absence caused the problem.
        db = _db(_row())
        with patch.object(svc, "get_supabase", return_value=db), \
             patch.object(svc.triage_service, "triage", return_value=None):
            svc.confirm_transcript(INCIDENT, REPORTER, corrected_text="totoo ito")
        t = _update_payload(db)["signals"]["transcript"]
        assert t["text"] == "na ay sunog didi sa amon balay"   # heard
        assert t["corrected_to"] == "totoo ito"                # said
        assert t["confirmed_by_reporter"] is False

    def test_severity_is_recomputed_from_the_correction(self):
        db = _db(_row())
        triaged = {
            "severity": MagicMock(value="critical"),
            "signals": {"engine": "ziren-model", "signals": {"entrapment": True}},
            "agencies": ["BFP"],
        }
        with patch.object(svc, "get_supabase", return_value=db), \
             patch.object(svc.triage_service, "triage", return_value=triaged):
            svc.confirm_transcript(INCIDENT, REPORTER, corrected_text="naipit")
        assert _update_payload(db)["severity"] == "critical"

    def test_the_reporters_category_is_carried_into_the_retriage(self):
        db = _db(_row(incident_category="medical_trauma"))
        with patch.object(svc, "get_supabase", return_value=db), \
             patch.object(svc.triage_service, "triage", return_value=None) as tri:
            svc.confirm_transcript(INCIDENT, REPORTER, corrected_text="nagdugo")
        assert tri.call_args.kwargs["incident_category"].value == "medical_trauma"

    def test_an_uncategorised_report_still_saves_the_correction(self):
        # Not "a retired category": migration 019 rewrote hazmat and
        # missing_person rows to `other` and kept the original in
        # wizard_answers.retired_category, so no live row carries a dead enum
        # value. The real case is a report the resident never categorised.
        db = _db(_row(incident_category=None))
        with patch.object(svc, "get_supabase", return_value=db), \
             patch.object(svc.triage_service, "triage", return_value=None) as tri:
            svc.confirm_transcript(INCIDENT, REPORTER, corrected_text="nagdugo")
        assert tri.call_args.kwargs["incident_category"] is None
        db.table.return_value.update.assert_called_once()


class TestGuards:
    def test_another_resident_cannot_touch_it(self):
        db = _db(_row())
        with patch.object(svc, "get_supabase", return_value=db):
            with pytest.raises(HTTPException) as e:
                svc.confirm_transcript(INCIDENT, OTHER, corrected_text="mine now")
        assert e.value.status_code == 403
        db.table.return_value.update.assert_not_called()

    def test_a_missing_incident_is_404(self):
        db = _db(None)
        with patch.object(svc, "get_supabase", return_value=db):
            with pytest.raises(HTTPException) as e:
                svc.confirm_transcript(INCIDENT, REPORTER)
        assert e.value.status_code == 404

    @pytest.mark.parametrize("status", ["dispatched", "resolved", "cancelled"])
    def test_a_dispatcher_at_work_is_never_overwritten(self, status):
        # They have read the report and, if it mattered, listened to the
        # recording. Rewriting it underneath them is worse than leaving it.
        db = _db(_row(status=status))
        with patch.object(svc, "get_supabase", return_value=db):
            with pytest.raises(HTTPException) as e:
                svc.confirm_transcript(INCIDENT, REPORTER, corrected_text="new")
        assert e.value.status_code == 409
        db.table.return_value.update.assert_not_called()


# ── the response must actually carry the transcript ────────────────────────
#
# It did not. TriageSignals declared its fields explicitly and Pydantic drops
# an undeclared key when serialising, so `transcript` was written to the
# column, stored correctly, and deleted from every API response. The confirm
# screen polled for forty seconds for words the server was throwing away, then
# told the resident we could not write down what they said — while the
# transcript sat in the database.

from app.models.incident import TriageSignals


class TestSignalsSurviveSerialisation:
    def test_transcript_is_not_dropped(self):
        m = TriageSignals(**{
            "engine": "ziren-model",
            "transcript": {"text": "na ay sunog didi", "engine": "fw-small"},
        })
        assert m.model_dump()["transcript"]["text"] == "na ay sunog didi"

    def test_a_key_from_a_later_release_is_kept(self):
        # What the class docstring has always promised. It was true on the way
        # in and false on the way out.
        m = TriageSignals(**{"engine": "ziren-model", "some_future_field": 7})
        assert m.model_dump()["some_future_field"] == 7

    def test_the_incident_response_carries_it(self):
        db = _db(_row())
        with patch.object(svc, "get_supabase", return_value=db):
            out = svc.confirm_transcript(INCIDENT, REPORTER)
        assert out.signals is not None
        assert out.signals.transcript["confirmed_by_reporter"] is True


# ── the dispatcher's correction ────────────────────────────────────────────
#
# The resident is asked first, on the screen that opens right after they
# report. But a bad transcript comes from someone who was panicking, and they
# are the least likely to stand in front of an emergency proofreading it. The
# dispatcher is playing the audio anyway and has a minute.

from app.services import dispatch_service as dsvc

AGENCY = "55555555-5555-5555-5555-555555555555"


def _dispatcher(role="agency_admin", agency=AGENCY):
    return {"id": "d-1", "role": role, "agency_id": agency}


def _drow(**over):
    base = _row(assigned_agency_id=AGENCY)
    base.pop("location_address", None)
    base.update(over)
    return base


class TestDispatcherCorrection:
    def test_replaces_the_text(self):
        db = _db(_drow(severity=None))
        with patch.object(dsvc, "get_supabase", return_value=db), \
             patch.object(dsvc.triage_service, "triage", return_value=None):
            dsvc.correct_transcript(
                INCIDENT, _dispatcher(), corrected_text="naay sunog sa balay")
        assert _update_payload(db)["report_text"] == "naay sunog sa balay"

    def test_a_hand_set_severity_is_never_recomputed(self):
        # A dispatcher's severity is a decision. Re-running a classifier over
        # it would quietly undo their judgement.
        db = _db(_drow(severity="critical"))
        with patch.object(dsvc, "get_supabase", return_value=db), \
             patch.object(dsvc.triage_service, "triage") as tri:
            dsvc.correct_transcript(
                INCIDENT, _dispatcher(), corrected_text="something else")
        tri.assert_not_called()
        assert "severity" not in _update_payload(db)

    def test_an_untriaged_incident_is_rescored(self):
        db = _db(_drow(severity=None))
        triaged = {
            "severity": MagicMock(value="critical"),
            "signals": {"engine": "ziren-model", "signals": {"entrapment": True}},
            "agencies": ["BFP"],
        }
        with patch.object(dsvc, "get_supabase", return_value=db), \
             patch.object(dsvc.triage_service, "triage", return_value=triaged):
            dsvc.correct_transcript(
                INCIDENT, _dispatcher(), corrected_text="naipit ang bata")
        assert _update_payload(db)["severity"] == "critical"

    def test_both_halves_are_kept_and_attributed(self):
        db = _db(_drow(severity=None))
        with patch.object(dsvc, "get_supabase", return_value=db), \
             patch.object(dsvc.triage_service, "triage", return_value=None):
            dsvc.correct_transcript(
                INCIDENT, _dispatcher(), corrected_text="totoo ito")
        t = _update_payload(db)["signals"]["transcript"]
        assert t["text"] == "na ay sunog didi sa amon balay"
        assert t["corrected_to"] == "totoo ito"
        assert t["corrected_by"] == "dispatcher"

    def test_another_agency_is_refused(self):
        db = _db(_drow())
        with patch.object(dsvc, "get_supabase", return_value=db):
            with pytest.raises(HTTPException) as e:
                dsvc.correct_transcript(
                    INCIDENT,
                    _dispatcher(agency="66666666-6666-6666-6666-666666666666"),
                    corrected_text="not mine")
        assert e.value.status_code == 403
        db.table.return_value.update.assert_not_called()

    def test_an_empty_correction_is_refused(self):
        db = _db(_drow())
        with patch.object(dsvc, "get_supabase", return_value=db):
            with pytest.raises(HTTPException) as e:
                dsvc.correct_transcript(INCIDENT, _dispatcher(), corrected_text="  ")
        assert e.value.status_code == 400
