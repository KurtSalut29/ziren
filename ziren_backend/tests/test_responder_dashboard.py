"""The responder's own figures, position reporting, and access to the audio.

Three things added because they were missing rather than because they were
asked for individually:

  - /responder/location, the endpoint migration 011's own header says would
    exist and never did. `users.location` shipped indexed and empty, so
    /map/data has rendered an empty responder layer since the day it was built.
  - /responder/dashboard, so a responder can see what is on them without
    counting a list.
  - /responder/queue/{id}/media, so the crew driving to the scene can hear the
    recording the dispatcher has been able to play since Phase 6.

Run with: pytest tests/test_responder_dashboard.py -v
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import responder_service

client = TestClient(app)

RESPONDER_UUID = "00000000-0000-0000-0000-0000000000aa"
OTHER_UUID = "00000000-0000-0000-0000-0000000000bb"
INCIDENT_UUID = str(uuid4())


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


def _call(method, path, service_db, body=None):
    with patch("app.core.dependencies.get_supabase", return_value=_auth_responder()), \
         patch("app.services.responder_service.get_supabase", return_value=service_db):
        fn = getattr(client, method)
        kwargs = {"headers": {"Authorization": "Bearer token"}}
        if body is not None:
            kwargs["json"] = body
        return fn(path, **kwargs)


# ── Location ────────────────────────────────────────────────

class TestLocation:
    def _db(self, updated=True):
        result = MagicMock()
        result.data = [{"id": RESPONDER_UUID}] if updated else []
        db = MagicMock()
        db.table.return_value.update.return_value \
            .eq.return_value.eq.return_value.execute.return_value = result
        return db

    def test_a_position_is_written(self):
        db = self._db()
        r = _call("patch", "/responder/location", db,
                  {"latitude": 11.5, "longitude": 124.4})
        assert r.status_code == 200, r.json()

    def test_it_is_written_as_srid_qualified_wkt(self):
        """migration 011 declares GEOMETRY(POINT, 4326).

        An unqualified WKT string is SRID 0, which Postgres refuses against a
        typed column rather than coercing — so leaving the SRID off turns every
        ping into a 22023 that only shows up against a real database. Note the
        order too: WKT is POINT(longitude latitude), the opposite of how the
        request names them.
        """
        db = self._db()
        _call("patch", "/responder/location", db,
              {"latitude": 11.5, "longitude": 124.4})
        payload = db.table.return_value.update.call_args[0][0]
        assert payload["location"] == "SRID=4326;POINT(124.4 11.5)"

    def test_only_the_responders_own_row_is_touched(self):
        db = self._db()
        _call("patch", "/responder/location", db,
              {"latitude": 11.5, "longitude": 124.4})
        # Two eq() calls: the id from the token, and role = responder.
        eq_args = [c.args for c in db.table.return_value.update.return_value.eq.call_args_list]
        assert ("id", RESPONDER_UUID) in eq_args

    @pytest.mark.parametrize(
        "body",
        [
            {"latitude": 91, "longitude": 0},
            {"latitude": -91, "longitude": 0},
            {"latitude": 0, "longitude": 181},
            {"latitude": 0, "longitude": -181},
        ],
    )
    def test_out_of_range_coordinates_are_refused(self, body):
        r = _call("patch", "/responder/location", self._db(), body)
        assert r.status_code == 422

    def test_the_service_guards_the_range_too(self):
        """The signature's bounds are the friendly error; this is the real one,
        and it has to hold for any future caller that skips the router."""
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc:
            responder_service.update_location(RESPONDER_UUID, 200.0, 0.0)
        assert exc.value.status_code == 422

    def test_requires_auth(self):
        r = client.patch("/responder/location", json={"latitude": 0, "longitude": 0})
        assert r.status_code in (401, 403)


# ── Dashboard ───────────────────────────────────────────────

def _stats_db(active, closed):
    """db whose first execute() returns `active` and second returns `closed`."""
    active_result = MagicMock()
    active_result.data = active
    closed_result = MagicMock()
    closed_result.data = closed

    chain_active = MagicMock()
    chain_active.execute.return_value = active_result
    chain_closed = MagicMock()
    chain_closed.execute.return_value = closed_result

    db = MagicMock()
    sel = db.table.return_value.select.return_value
    sel.eq.return_value.in_.return_value = chain_active
    sel.eq.return_value.in_.return_value.gte.return_value.limit.return_value = chain_closed
    return db


class TestDashboard:
    def test_counts_only_this_responders_work(self):
        db = _stats_db(
            active=[
                {"id": "1", "severity": "critical", "status": "en_route",
                 "created_at": "2026-01-01T00:00:00+00:00", "dispatched_at": None},
                {"id": "2", "severity": "low", "status": "arrived",
                 "created_at": "2026-01-01T00:00:00+00:00", "dispatched_at": None},
            ],
            closed=[],
        )
        with patch("app.services.responder_service.get_supabase", return_value=db):
            out = responder_service.get_dashboard(RESPONDER_UUID)

        assert out["active_count"] == 2
        assert out["active_critical"] == 1
        assert out["en_route_count"] == 1
        assert out["on_scene_count"] == 1

        # Scoped by the id from the token, never from a request body.
        eq_args = [
            c.args
            for c in db.table.return_value.select.return_value.eq.call_args_list
        ]
        assert ("assigned_responder_id", RESPONDER_UUID) in eq_args

    def test_the_median_is_a_median_not_a_mean(self):
        """One incident that ran overnight because a road was cut drags a mean
        far enough to make a good month look bad. Five closures at 10, 10, 10,
        10 and 600 minutes: the median is 10, the mean is 128."""
        closed = [
            {"id": str(i), "severity": "low", "status": "resolved",
             "created_at": "2026-01-01T00:00:00+00:00",
             "dispatched_at": "2026-01-01T00:00:00+00:00",
             "resolved_at": f"2026-01-01T{h:02d}:{m:02d}:00+00:00"}
            for i, (h, m) in enumerate([(0, 10), (0, 10), (0, 10), (0, 10), (10, 0)])
        ]
        db = _stats_db(active=[], closed=closed)
        with patch("app.services.responder_service.get_supabase", return_value=db):
            out = responder_service.get_dashboard(RESPONDER_UUID)
        assert out["median_response_minutes"] == pytest.approx(10.0)

    def test_the_clock_starts_at_dispatch_not_at_the_call(self):
        """The minutes a report waited in a dispatcher's queue before reaching
        this responder are not theirs to answer for."""
        closed = [{
            "id": "1", "severity": "high", "status": "resolved",
            "created_at": "2026-01-01T00:00:00+00:00",
            "dispatched_at": "2026-01-01T01:00:00+00:00",
            "resolved_at": "2026-01-01T01:20:00+00:00",
        }]
        db = _stats_db(active=[], closed=closed)
        with patch("app.services.responder_service.get_supabase", return_value=db):
            out = responder_service.get_dashboard(RESPONDER_UUID)
        assert out["median_response_minutes"] == pytest.approx(20.0)

    def test_a_cancelled_assignment_is_not_a_closure(self):
        """Cancelled means nobody attended. Counting it as work done would
        flatter the figure and hide the fact that nothing happened."""
        closed = [
            {"id": "1", "severity": "low", "status": "cancelled",
             "created_at": "2026-01-01T00:00:00+00:00",
             "dispatched_at": "2026-01-01T00:00:00+00:00",
             "resolved_at": "2026-01-01T00:05:00+00:00"},
        ]
        db = _stats_db(active=[], closed=closed)
        with patch("app.services.responder_service.get_supabase", return_value=db):
            out = responder_service.get_dashboard(RESPONDER_UUID)
        assert out["resolved_period"] == 0
        assert out["median_response_minutes"] is None

    def test_no_history_gives_null_not_zero(self):
        """Zero minutes would congratulate a brand-new account for a response
        time it has never posted."""
        db = _stats_db(active=[], closed=[])
        with patch("app.services.responder_service.get_supabase", return_value=db):
            out = responder_service.get_dashboard(RESPONDER_UUID)
        assert out["median_response_minutes"] is None
        assert out["oldest_waiting_minutes"] is None

    def test_a_malformed_timestamp_does_not_take_the_dashboard_down(self):
        closed = [{
            "id": "1", "severity": "low", "status": "resolved",
            "created_at": "not a date", "dispatched_at": "also not",
            "resolved_at": "nope",
        }]
        db = _stats_db(active=[], closed=closed)
        with patch("app.services.responder_service.get_supabase", return_value=db):
            out = responder_service.get_dashboard(RESPONDER_UUID)
        assert out["resolved_period"] == 1
        assert out["median_response_minutes"] is None


# ── Attachments ─────────────────────────────────────────────

class TestIncidentMedia:
    def _db(self, row):
        result = MagicMock()
        result.data = row
        db = MagicMock()
        db.table.return_value.select.return_value \
            .eq.return_value.maybe_single.return_value.execute.return_value = result
        db.storage.from_.return_value.create_signed_url.return_value = {
            "signedURL": "https://example.test/signed"
        }
        return db

    def test_someone_elses_incident_is_refused(self):
        db = self._db({
            "id": INCIDENT_UUID,
            "media_urls": ["a/b.m4a"],
            "assigned_responder_id": OTHER_UUID,
        })
        r = _call("get", f"/responder/queue/{INCIDENT_UUID}/media", db)
        assert r.status_code == 403

    def test_the_voice_note_comes_back_typed_as_audio(self):
        db = self._db({
            "id": INCIDENT_UUID,
            "media_urls": ["u/report.m4a", "u/scene.jpg"],
            "assigned_responder_id": RESPONDER_UUID,
        })
        r = _call("get", f"/responder/queue/{INCIDENT_UUID}/media", db)
        assert r.status_code == 200, r.json()
        kinds = {item["kind"] for item in r.json()}
        assert kinds == {"audio", "image"}

    def test_one_unsignable_object_does_not_lose_the_others(self):
        """A crew that cannot get one attachment must still get the rest —
        and a null url renders as unavailable rather than vanishing, so a
        recording nobody can hear is visible instead of silent."""
        db = self._db({
            "id": INCIDENT_UUID,
            "media_urls": ["u/broken.m4a", "u/ok.m4a"],
            "assigned_responder_id": RESPONDER_UUID,
        })
        db.storage.from_.return_value.create_signed_url.side_effect = [
            Exception("gone"),
            {"signedURL": "https://example.test/ok"},
        ]
        r = _call("get", f"/responder/queue/{INCIDENT_UUID}/media", db)
        body = r.json()
        assert len(body) == 2
        assert body[0]["url"] is None
        assert body[1]["url"] == "https://example.test/ok"

    def test_missing_incident_is_404(self):
        r = _call("get", f"/responder/queue/{INCIDENT_UUID}/media", self._db(None))
        assert r.status_code == 404
