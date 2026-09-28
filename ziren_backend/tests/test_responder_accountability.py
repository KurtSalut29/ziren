"""Acceptance, refusal and after-action — the responder's half of the loop.

Migration 024 and Phase 6D. Three things that did not exist before, each of
which was a silent failure rather than a missing convenience:

  - ACCEPTANCE. `status = 'dispatched'` meant "a dispatcher pressed a button".
    An assignment sitting on a phone in a locker was indistinguishable from one
    a truck was already rolling on, and the difference surfaced when nobody
    arrived.
  - REFUSAL. _VALID_TRANSITIONS is forward-only, so a crew whose truck would
    not start had no way to say so.
  - OUTCOME. resolve wrote {"status", "resolved_at"} and nothing else, so no
    severity the rubric has ever produced could be checked against what the
    crew actually found.

The deadline arithmetic gets the most tests here because it is the one piece
two screens compute from — the responder's countdown and the dispatcher's
OVERDUE badge — and a disagreement between them is worse than having neither.

Run with: pytest tests/test_responder_accountability.py -v
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import responder_ack

client = TestClient(app)

RESPONDER_UUID = "00000000-0000-0000-0000-0000000000aa"
OTHER_UUID = "00000000-0000-0000-0000-0000000000bb"
INCIDENT_UUID = str(uuid4())

NOW = datetime(2026, 9, 5, 8, 0, 0, tzinfo=timezone.utc)


def _ago(seconds: int) -> str:
    return (NOW - timedelta(seconds=seconds)).isoformat()


# =============================================================================
# The deadline arithmetic — pure, no database
# =============================================================================

class TestAckState:
    def test_an_accepted_incident_reports_accepted(self):
        state = responder_ack.ack_state(
            {"accepted_at": _ago(10), "status": "dispatched",
             "dispatched_at": _ago(30), "severity": "critical"},
            now=NOW,
        )
        assert state["state"] == "accepted"

    def test_inside_the_window_it_is_pending_and_counts_down(self):
        state = responder_ack.ack_state(
            {"accepted_at": None, "status": "dispatched",
             "dispatched_at": _ago(20), "severity": "critical"},
            now=NOW,
        )
        assert state["state"] == "pending"
        assert state["seconds_waiting"] == 20
        assert state["seconds_remaining"] == 40

    def test_past_the_window_it_is_overdue(self):
        state = responder_ack.ack_state(
            {"accepted_at": None, "status": "dispatched",
             "dispatched_at": _ago(61), "severity": "critical"},
            now=NOW,
        )
        assert state["state"] == "overdue"
        assert state["seconds_remaining"] == 0

    def test_the_deadline_scales_with_severity(self):
        """A critical unanswered for 90 seconds is overdue; a medium is not.

        The cost of waiting is not the same at every severity, and a single
        global timeout would either cry wolf on a low-priority call or give a
        critical one too much rope.
        """
        row = {"accepted_at": None, "status": "dispatched", "dispatched_at": _ago(90)}
        assert responder_ack.ack_state({**row, "severity": "critical"}, now=NOW)["state"] == "overdue"
        assert responder_ack.ack_state({**row, "severity": "medium"}, now=NOW)["state"] == "pending"

    def test_an_unscored_incident_gets_the_strictest_deadline(self):
        """severity NULL is "the rubric could not read it", not "low priority".

        Treating an untriaged incident as the most forgiving case is exactly
        backwards: nobody has established that it is safe to wait on.
        """
        assert responder_ack.deadline_seconds(None) == 60
        assert responder_ack.deadline_seconds("critical") == 60
        assert responder_ack.deadline_seconds("medium") == 180

    def test_a_declined_unassigned_incident_reports_declined(self):
        state = responder_ack.ack_state(
            {"accepted_at": None, "declined_at": _ago(5),
             "declined_reason": "vehicle_down", "assigned_responder_id": None,
             "status": "processing", "severity": "high"},
            now=NOW,
        )
        assert state["state"] == "declined"
        assert state["declined_reason"] == "vehicle_down"

    def test_a_reassigned_incident_is_pending_not_still_declined(self):
        """The previous crew's refusal must not follow the incident onto the
        next responder's phone. Once somebody is assigned again, the live
        question is whether THEY have answered."""
        state = responder_ack.ack_state(
            {"accepted_at": None, "declined_at": _ago(300),
             "declined_reason": "vehicle_down",
             "assigned_responder_id": OTHER_UUID,
             "status": "dispatched", "dispatched_at": _ago(10),
             "severity": "high"},
            now=NOW,
        )
        assert state["state"] == "pending"

    def test_a_resolved_incident_nobody_accepted_is_not_reported_as_accepted(self):
        """It really did happen that way, and flattening it to 'accepted' would
        erase the evidence this whole feature exists to collect."""
        state = responder_ack.ack_state(
            {"accepted_at": None, "status": "resolved",
             "dispatched_at": _ago(9000), "severity": "high"},
            now=NOW,
        )
        assert state["state"] == "not_applicable"

    def test_clock_skew_never_produces_a_negative_wait(self):
        """Postgres and the app server do not share a clock. A dispatched_at a
        few seconds in the future must not render as "-3 seconds waiting"."""
        state = responder_ack.ack_state(
            {"accepted_at": None, "status": "dispatched",
             "dispatched_at": (NOW + timedelta(seconds=3)).isoformat(),
             "severity": "critical"},
            now=NOW,
        )
        assert state["seconds_waiting"] == 0
        assert state["state"] == "pending"

    def test_decline_count_survives_into_the_verdict(self):
        """Three refusals on one incident is a coverage problem, and the board
        cannot show it as one unless the count travels with the row."""
        state = responder_ack.ack_state(
            {"accepted_at": None, "status": "dispatched",
             "dispatched_at": _ago(10), "severity": "high", "decline_count": 3},
            now=NOW,
        )
        assert state["decline_count"] == 3

    def test_annotate_attaches_a_verdict_to_every_row(self):
        rows = [
            {"id": "a", "accepted_at": _ago(1), "status": "dispatched"},
            {"id": "b", "accepted_at": None, "status": "dispatched",
             "dispatched_at": _ago(999), "severity": "critical"},
        ]
        responder_ack.annotate(rows, now=NOW)
        assert rows[0]["ack"]["state"] == "accepted"
        assert rows[1]["ack"]["state"] == "overdue"


# =============================================================================
# The endpoints
# =============================================================================

def _auth_responder():
    mock_user = MagicMock()
    mock_user.id = RESPONDER_UUID
    mock_get = MagicMock()
    mock_get.user = mock_user

    profile = MagicMock()
    profile.data = {
        "id": RESPONDER_UUID,
        "email": "responder@example.com",
        "full_name": "Test Responder",
        "role": "responder",
        "approval_status": "approved",
        "agency_id": "agency-1",
        "badge_id": "B-1",
        "is_verified": True,
    }

    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = profile
    return db


def _ops_db(incident: dict):
    """A fake whose `select(...).eq(...).maybe_single().execute()` returns one
    incident row, and whose update chain is inspectable."""
    loaded = MagicMock()
    loaded.data = incident

    db = MagicMock()
    db.table.return_value.select.return_value \
        .eq.return_value.maybe_single.return_value.execute.return_value = loaded
    return db


def _update_payload(db):
    return db.table.return_value.update.call_args[0][0]


def _call(method, path, ops_db, body=None):
    with patch("app.core.dependencies.get_supabase", return_value=_auth_responder()), \
         patch("app.services.responder_ops_service.get_supabase", return_value=ops_db):
        fn = getattr(client, method)
        kwargs = {"headers": {"Authorization": "Bearer token"}}
        if body is not None:
            kwargs["json"] = body
        return fn(path, **kwargs)


class TestAccept:
    def test_accepting_stamps_the_time(self):
        db = _ops_db({
            "id": INCIDENT_UUID, "status": "dispatched", "accepted_at": None,
            "dispatched_at": _ago(20), "assigned_responder_id": RESPONDER_UUID,
        })
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db)
        assert r.status_code == 200, r.json()
        assert r.json()["already_accepted"] is False
        assert _update_payload(db)["accepted_at"] is not None

    def test_accepting_twice_keeps_the_original_timestamp(self):
        """A responder on a bad connection presses this twice. The second press
        must not reset the clock — that would silently corrupt the response-time
        measurement the feature exists to produce."""
        original = _ago(45)
        db = _ops_db({
            "id": INCIDENT_UUID, "status": "dispatched", "accepted_at": original,
            "dispatched_at": _ago(60), "assigned_responder_id": RESPONDER_UUID,
        })
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db)
        assert r.status_code == 200
        assert r.json()["already_accepted"] is True
        assert r.json()["accepted_at"] == original
        db.table.return_value.update.assert_not_called()

    def test_accepting_clears_a_previous_crews_refusal(self):
        db = _ops_db({
            "id": INCIDENT_UUID, "status": "dispatched", "accepted_at": None,
            "dispatched_at": _ago(5), "assigned_responder_id": RESPONDER_UUID,
        })
        _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db)
        payload = _update_payload(db)
        assert payload["declined_at"] is None
        assert payload["declined_reason"] is None
        # ...but NOT the count. It belongs to the incident's whole history.
        assert "decline_count" not in payload

    def test_somebody_elses_incident_is_403(self):
        db = _ops_db({
            "id": INCIDENT_UUID, "status": "dispatched", "accepted_at": None,
            "dispatched_at": _ago(5), "assigned_responder_id": OTHER_UUID,
        })
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db)
        assert r.status_code == 403

    def test_a_missing_incident_is_404_not_500(self):
        empty = MagicMock()
        empty.data = None
        db = MagicMock()
        db.table.return_value.select.return_value \
            .eq.return_value.maybe_single.return_value.execute.return_value = empty
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db)
        assert r.status_code == 404

    def test_maybe_single_returning_none_is_also_404(self):
        """PostgREST's maybe_single() hands back None for zero rows rather than
        a response object. Treating that as a response is how the 404 in
        user_service.get_my_profile became unreachable and surfaced as a 500."""
        db = MagicMock()
        db.table.return_value.select.return_value \
            .eq.return_value.maybe_single.return_value.execute.return_value = None
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db)
        assert r.status_code == 404


class TestDecline:
    def _dispatched(self, decline_count=0):
        return {
            "id": INCIDENT_UUID, "status": "dispatched", "accepted_at": None,
            "decline_count": decline_count,
            "assigned_responder_id": RESPONDER_UUID,
            "assigned_agency_id": "agency-1",
        }

    def test_declining_returns_the_incident_to_the_dispatcher(self):
        db = _ops_db(self._dispatched())
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/decline", db,
                  {"reason": "vehicle_down"})
        assert r.status_code == 200, r.json()
        payload = _update_payload(db)
        assert payload["status"] == "processing"
        assert payload["assigned_responder_id"] is None
        assert payload["declined_reason"] == "vehicle_down"

    def test_the_dispatch_clock_is_reset_for_the_next_crew(self):
        """dispatched_at must be cleared, or the next responder inherits a
        countdown that has already expired and arrives pre-marked OVERDUE."""
        db = _ops_db(self._dispatched())
        _call("post", f"/responder/queue/{INCIDENT_UUID}/decline", db,
              {"reason": "out_of_area"})
        assert _update_payload(db)["dispatched_at"] is None

    def test_the_refusal_count_increments(self):
        db = _ops_db(self._dispatched(decline_count=2))
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/decline", db,
                  {"reason": "insufficient_crew"})
        assert _update_payload(db)["decline_count"] == 3
        assert r.json()["decline_count"] == 3

    def test_an_unknown_reason_is_refused_with_the_allowed_list(self):
        """The CHECK constraint is the real gate, but a 23514 from PostgREST
        reaches the responder as "something went wrong"."""
        db = _ops_db(self._dispatched())
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/decline", db,
                  {"reason": "cant_be_bothered"})
        assert r.status_code == 422
        assert "vehicle_down" in r.json()["detail"]

    @pytest.mark.parametrize("reason", [
        "vehicle_down", "already_committed", "out_of_area",
        "insufficient_crew", "road_impassable", "other",
    ])
    def test_every_documented_reason_is_accepted(self, reason):
        """These six are duplicated between the CHECK constraint and the
        service. If they ever drift, this fails rather than a responder
        discovering it at 2am."""
        db = _ops_db(self._dispatched())
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/decline", db,
                  {"reason": reason})
        assert r.status_code == 200, r.json()

    def test_declining_after_arriving_is_refused(self):
        """That is abandonment, not refusal — it would leave the incident with
        arrival evidence and no responder attached to it."""
        db = _ops_db({**self._dispatched(), "status": "arrived"})
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/decline", db,
                  {"reason": "vehicle_down"})
        assert r.status_code == 422
        assert "dispatcher" in r.json()["detail"].lower()


class TestClose:
    def _arrived(self):
        return {
            "id": INCIDENT_UUID, "status": "arrived", "severity": "critical",
            "assigned_responder_id": RESPONDER_UUID, "dispatched_at": _ago(900),
        }

    def test_closing_records_the_outcome(self):
        db = _ops_db(self._arrived())
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/close", db,
                  {"outcome": "false_alarm", "outcome_notes": "Nobody home."})
        assert r.status_code == 200, r.json()
        payload = _update_payload(db)
        assert payload["status"] == "resolved"
        assert payload["outcome"] == "false_alarm"
        assert payload["resolved_at"] is not None
        assert payload["closed_by"] == RESPONDER_UUID

    def test_a_counted_zero_is_kept_and_not_collapsed_to_null(self):
        """NULL means "not recorded"; 0 means "we counted, nobody was hurt".
        Collapsing them turns every unfilled form into a clean scene."""
        db = _ops_db(self._arrived())
        _call("post", f"/responder/queue/{INCIDENT_UUID}/close", db,
              {"outcome": "handled_on_scene", "casualties_injured": 0})
        payload = _update_payload(db)
        assert payload["casualties_injured"] == 0
        assert payload["casualties_fatal"] is None

    def test_an_unknown_outcome_is_refused(self):
        db = _ops_db(self._arrived())
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/close", db,
                  {"outcome": "sorted_it"})
        assert r.status_code == 422
        assert "false_alarm" in r.json()["detail"]

    def test_closing_without_arriving_is_refused(self):
        """A call you never reached is an 'unable_to_access' decline. Letting it
        close from en_route would put a fabricated arrival into the data the
        rubric is about to be scored against."""
        db = _ops_db({**self._arrived(), "status": "en_route"})
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/close", db,
                  {"outcome": "nobody_found"})
        assert r.status_code == 422

    def test_a_negative_casualty_count_is_refused(self):
        db = _ops_db(self._arrived())
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/close", db,
                  {"outcome": "transported", "casualties_injured": -1})
        assert r.status_code == 422

    @pytest.mark.parametrize("outcome", [
        "handled_on_scene", "transported", "turned_over", "false_alarm",
        "nobody_found", "refused_assistance", "unable_to_access", "other",
    ])
    def test_every_documented_outcome_is_accepted(self, outcome):
        db = _ops_db(self._arrived())
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/close", db,
                  {"outcome": outcome})
        assert r.status_code == 200, r.json()


class TestSceneMedia:
    def test_scene_photos_are_kept_apart_from_the_reporters(self):
        """media_urls is what was known BEFORE anyone arrived. Merging the two
        destroys the only way to tell a reporter's photo of smoke from a crew's
        photo of the room it came from."""
        db = _ops_db({
            "id": INCIDENT_UUID, "assigned_responder_id": RESPONDER_UUID,
            "scene_media_urls": ["existing.jpg"],
        })
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/scene-media", db,
                  {"paths": ["new.jpg"]})
        assert r.status_code == 200, r.json()
        payload = _update_payload(db)
        assert payload["scene_media_urls"] == ["existing.jpg", "new.jpg"]
        assert "media_urls" not in payload

    def test_a_retried_upload_does_not_duplicate_the_photo(self):
        db = _ops_db({
            "id": INCIDENT_UUID, "assigned_responder_id": RESPONDER_UUID,
            "scene_media_urls": ["same.jpg"],
        })
        _call("post", f"/responder/queue/{INCIDENT_UUID}/scene-media", db,
              {"paths": ["same.jpg"]})
        assert _update_payload(db)["scene_media_urls"] == ["same.jpg"]


class TestDistress:
    def test_the_panic_button_works_without_a_gps_fix(self):
        """The worst possible outcome here is a responder pressing this and
        being told their request was invalid."""
        created = MagicMock()
        created.data = [{"id": "d-1", "kind": "panic"}]
        db = MagicMock()
        db.table.return_value.insert.return_value.execute.return_value = created

        r = _call("post", "/responder/distress", db, {})
        assert r.status_code == 201, r.json()
        payload = db.table.return_value.insert.call_args[0][0]
        assert payload["responder_id"] == RESPONDER_UUID
        assert "location" not in payload

    def test_a_location_is_written_as_srid_qualified_wkt(self):
        """GEOMETRY(POINT, 4326). An unqualified WKT string is SRID 0, which
        Postgres refuses rather than coerces — and WKT is POINT(lng lat), the
        opposite order from how the request names them."""
        created = MagicMock()
        created.data = [{"id": "d-1"}]
        db = MagicMock()
        db.table.return_value.insert.return_value.execute.return_value = created

        _call("post", "/responder/distress", db,
              {"latitude": 11.5, "longitude": 124.4})
        payload = db.table.return_value.insert.call_args[0][0]
        assert payload["location"] == "SRID=4326;POINT(124.4 11.5)"


class TestOfflineTimestamps:
    """The offline queue sends the moment the button was pressed.

    Without this the measurement is of the mountain, not the crew: a call
    accepted at 14:02 in a dead zone and synced at 14:40 would be recorded as
    a 38-minute response. With it unbounded, a client could rewrite its own
    performance — so the value is clamped to [dispatched_at, now].

    These tests are anchored to the REAL clock rather than the frozen NOW the
    rest of this file uses. The clamp compares against datetime.now() inside
    the service, so a fixture clock that happens to sit ahead of the wall clock
    makes every fixture timestamp "in the future" and clamps it — which is the
    code working correctly and the test asking the wrong question.
    """

    @staticmethod
    def _real_ago(seconds: int) -> str:
        return (
            datetime.now(timezone.utc) - timedelta(seconds=seconds)
        ).isoformat()

    def _dispatched(self, dispatched_ago=3600):
        return {
            "id": INCIDENT_UUID, "status": "dispatched", "accepted_at": None,
            "dispatched_at": self._real_ago(dispatched_ago),
            "assigned_responder_id": RESPONDER_UUID,
        }

    def test_a_queued_acceptance_keeps_its_own_time(self):
        """The whole point. A press from 30 minutes ago is stored as 30 minutes
        ago, not as the moment coverage came back."""
        db = _ops_db(self._dispatched())
        pressed = self._real_ago(1800)
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db,
                  {"occurred_at": pressed})
        assert r.status_code == 200, r.json()
        stored = datetime.fromisoformat(_update_payload(db)["accepted_at"])
        assert abs((stored - datetime.fromisoformat(pressed)).total_seconds()) < 2

    def test_a_future_timestamp_is_pulled_back_to_now(self):
        """A phone with a fast clock, or a crew that would like a better
        number. Either way the server's own clock is the ceiling."""
        db = _ops_db(self._dispatched())
        future = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
        _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db,
              {"occurred_at": future})
        stored = datetime.fromisoformat(_update_payload(db)["accepted_at"])
        assert stored <= datetime.now(timezone.utc) + timedelta(seconds=5)

    def test_an_acceptance_cannot_predate_its_own_dispatch(self):
        db = _ops_db(self._dispatched())
        _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db,
              {"occurred_at": self._real_ago(99999)})
        stored = datetime.fromisoformat(_update_payload(db)["accepted_at"])
        dispatched = datetime.fromisoformat(
            self._dispatched()["dispatched_at"]
        )
        # Within a couple of seconds of the floor — _dispatched() rebuilds its
        # timestamp from the clock, so the two calls are not bit-identical.
        assert (stored - dispatched).total_seconds() > -2

    def test_an_unparseable_timestamp_falls_back_to_now_rather_than_failing(self):
        """A malformed clock value must never cost a real acceptance."""
        db = _ops_db(self._dispatched())
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db,
                  {"occurred_at": "yesterday-ish"})
        assert r.status_code == 200, r.json()
        assert _update_payload(db)["accepted_at"] is not None

    def test_the_ordinary_online_path_needs_no_body_at_all(self):
        db = _ops_db(self._dispatched())
        r = _call("post", f"/responder/queue/{INCIDENT_UUID}/accept", db)
        assert r.status_code == 200, r.json()
