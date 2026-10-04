"""Evaluator findings #1-#3 (ISO / white-box review, 2026-10-05).

  #1  Resident photos/videos never appeared on the admin dashboard.
  #2  A responder's latest GPS position did not show on the admin side.
  #3  The responder app said "attachment" but could not open it.

The backend half of each: the admin media list carries the crew's scene photos
as well as the resident's, each tagged with where it came from; the incident
detail carries the assigned responder's last position and its age; and the
responder's own dashboard returns the duty state the server holds, so the app
can resume reporting position after a restart.

Run with: pytest tests/test_media_and_location_flow.py -v
"""

from unittest.mock import MagicMock, patch

from app.services import dispatch_service, responder_service

RESPONDER_UUID = "00000000-0000-0000-0000-0000000000aa"


# ── #1: admin media list ────────────────────────────────────

def _media_db(row):
    db = MagicMock()
    result = MagicMock()
    result.data = row
    db.table.return_value.select.return_value.eq.return_value \
        .single.return_value.execute.return_value = result
    db.storage.from_.return_value.create_signed_url.side_effect = (
        lambda path, ttl: {"signedURL": f"https://signed/{path}"}
    )
    return db


class TestAdminMedia:
    def test_photos_videos_and_scene_photos_are_all_returned(self):
        db = _media_db({
            "id": "inc-1",
            "assigned_agency_id": "agency-1",
            "media_urls": ["u/1/a.jpg", "u/1/b.mp4", "u/1/c.m4a"],
            "scene_media_urls": ["r/inc-1/d.jpg"],
        })
        with patch("app.services.dispatch_service.get_supabase", return_value=db):
            items = dispatch_service.get_incident_media(
                "inc-1", {"role": "agency_admin", "agency_id": "agency-1"}
            )

        by_path = {i["path"]: i for i in items}
        assert by_path["u/1/a.jpg"]["kind"] == "image"
        assert by_path["u/1/b.mp4"]["kind"] == "video"
        assert by_path["u/1/c.m4a"]["kind"] == "audio"
        assert {by_path[p]["source"] for p in ("u/1/a.jpg", "u/1/b.mp4", "u/1/c.m4a")} == {"reporter"}
        # The crew's photos used to be stored and never signed for anyone.
        assert by_path["r/inc-1/d.jpg"]["source"] == "scene"
        assert all(i["url"] for i in items)

    def test_one_unsignable_file_does_not_hide_the_rest(self):
        db = _media_db({
            "id": "inc-1", "assigned_agency_id": "agency-1",
            "media_urls": ["u/1/gone.jpg", "u/1/ok.jpg"], "scene_media_urls": None,
        })

        def sign(path, ttl):
            if "gone" in path:
                raise RuntimeError("Object not found")
            return {"signedURL": f"https://signed/{path}"}

        db.storage.from_.return_value.create_signed_url.side_effect = sign
        with patch("app.services.dispatch_service.get_supabase", return_value=db):
            items = dispatch_service.get_incident_media(
                "inc-1", {"role": "agency_admin", "agency_id": "agency-1"}
            )
        assert [i["url"] is None for i in items] == [True, False]


# ── #2: the assigned responder's position on the incident ───

class TestResponderPosition:
    def test_point_and_age_come_out_flat(self):
        responder = {
            "full_name": "R",
            "badge_id": "B-1",
            "location": {"type": "Point", "coordinates": [124.4, 11.56]},
            "location_updated_at": "2026-10-05T01:02:03+00:00",
        }
        pos = dispatch_service._responder_position(responder)
        assert pos == {"lat": 11.56, "lng": 124.4, "updated_at": "2026-10-05T01:02:03+00:00"}
        # The raw geometry does not ride along on the responder object.
        assert "location" not in responder and "location_updated_at" not in responder

    def test_no_position_yet_is_none(self):
        assert dispatch_service._responder_position(
            {"full_name": "R", "location": None, "location_updated_at": None}
        ) is None
        assert dispatch_service._responder_position(None) is None


# ── #2: duty state read back on the responder's dashboard ───

def _dashboard_db(availability):
    db = MagicMock()
    sel = db.table.return_value.select.return_value
    empty = MagicMock()
    empty.data = []
    sel.eq.return_value.in_.return_value.execute.return_value = empty
    sel.eq.return_value.in_.return_value.gte.return_value.limit.return_value \
        .execute.return_value = empty
    me = MagicMock()
    me.data = {"availability": availability} if availability is not None else None
    sel.eq.return_value.maybe_single.return_value.execute.return_value = me
    return db


class TestDutyStateOnDashboard:
    def test_on_duty_is_returned(self):
        with patch("app.services.responder_service.get_supabase", return_value=_dashboard_db("on_duty")):
            out = responder_service.get_dashboard(RESPONDER_UUID)
        assert out["availability"] == "on_duty"

    def test_off_duty_is_returned(self):
        with patch("app.services.responder_service.get_supabase", return_value=_dashboard_db("off_duty")):
            out = responder_service.get_dashboard(RESPONDER_UUID)
        assert out["availability"] == "off_duty"

    def test_unreadable_is_none_not_a_guess(self):
        """None, so the app keeps what it shows instead of flipping a
        responder off duty because one read failed."""
        with patch("app.services.responder_service.get_supabase", return_value=_dashboard_db(None)):
            out = responder_service.get_dashboard(RESPONDER_UUID)
        assert out["availability"] is None


# ── #2: the small position endpoint the incident dialog polls ──

def _position_db(row):
    db = MagicMock()
    result = MagicMock()
    result.data = row
    db.table.return_value.select.return_value.eq.return_value \
        .maybe_single.return_value.execute.return_value = result
    return db


class TestPositionEndpoint:
    ADMIN = {"role": "agency_admin", "agency_id": "agency-1"}

    def test_assigned_responder_with_a_fix(self):
        db = _position_db({
            "id": "inc-1", "assigned_agency_id": "agency-1", "assigned_responder_id": "r-1",
            "responder": {
                "full_name": "Juan",
                "location": {"type": "Point", "coordinates": [124.4, 11.56]},
                "location_updated_at": "2026-10-05T01:02:03+00:00",
            },
        })
        with patch("app.services.dispatch_service.get_supabase", return_value=db):
            out = dispatch_service.get_responder_position("inc-1", self.ADMIN)
        assert out == {
            "responder_id": "r-1", "full_name": "Juan",
            "lat": 11.56, "lng": 124.4, "updated_at": "2026-10-05T01:02:03+00:00",
        }

    def test_assigned_but_never_reported(self):
        db = _position_db({
            "id": "inc-1", "assigned_agency_id": "agency-1", "assigned_responder_id": "r-1",
            "responder": {"full_name": "Juan", "location": None, "location_updated_at": None},
        })
        with patch("app.services.dispatch_service.get_supabase", return_value=db):
            out = dispatch_service.get_responder_position("inc-1", self.ADMIN)
        assert out["lat"] is None and out["full_name"] == "Juan"

    def test_nobody_assigned_is_none(self):
        db = _position_db({
            "id": "inc-1", "assigned_agency_id": "agency-1",
            "assigned_responder_id": None, "responder": None,
        })
        with patch("app.services.dispatch_service.get_supabase", return_value=db):
            assert dispatch_service.get_responder_position("inc-1", self.ADMIN) is None

    def test_another_agencys_incident_is_refused(self):
        from fastapi import HTTPException
        db = _position_db({
            "id": "inc-1", "assigned_agency_id": "agency-2", "assigned_responder_id": "r-1",
            "responder": {"full_name": "Juan", "location": None, "location_updated_at": None},
        })
        with patch("app.services.dispatch_service.get_supabase", return_value=db):
            try:
                dispatch_service.get_responder_position("inc-1", self.ADMIN)
            except HTTPException as e:
                assert e.status_code == 403
            else:
                raise AssertionError("expected 403")


# ── #18: Incident Records' summary counts the whole window ──

class TestWindowCounts:
    def test_one_database_call_with_the_callers_scope(self):
        db = MagicMock()
        db.rpc.return_value.execute.return_value = MagicMock(data={
            "total": 2500, "critical": 833, "resolved": 833, "cancelled": 834,
            "avg_response_minutes": 6.0, "stations_with_incidents": 3,
        })
        out = dispatch_service._window_counts_rpc(
            db, since="2026-09-01T00:00:00+00:00", until=None, status="open", severity=None,
            category=None, station_id=None, record_no=None, agency_ids=["ag-1"],
        )
        name, params = db.rpc.call_args.args
        assert name == "incident_window_counts"
        assert params["p_agency_ids"] == ["ag-1"] and params["p_status"] == "open"
        assert out["total"] == 2500 and out["avg_response_minutes"] == 6.0

    def test_missing_function_means_fall_back(self):
        db = MagicMock()
        db.rpc.return_value.execute.side_effect = Exception("PGRST202 function not found")
        assert dispatch_service._window_counts_rpc(
            db, since=None, until=None, status=None, severity=None, category=None,
            station_id=None, record_no=None, agency_ids=None,
        ) is None

    def test_the_fallback_reads_past_the_first_thousand_rows(self):
        """The unranged reads stopped at PostgREST's 1,000-row cap."""
        rows = [{"created_at": "2026-01-01T00:00:00+00:00", "dispatched_at": "2026-01-01T00:10:00+00:00",
                 "station_id": f"s{i % 7}"} for i in range(2300)]

        class Q:
            def __init__(self):
                self.a, self.b = 0, 10**9
            def select(self, *a, **k): return self
            def eq(self, *a): return self
            @property
            def not_(self): return self
            def is_(self, *a): return self
            def range(self, a, b):
                self.a, self.b = a, b
                return self
            def execute(self):
                return MagicMock(data=rows[self.a:self.b + 1], count=10)

        db = MagicMock()
        db.table.side_effect = lambda name: Q()
        out = dispatch_service._window_counts_fallback(db, lambda q: q, total=2300)
        assert out["avg_response_minutes"] == 10.0
        assert out["stations_with_incidents"] == 7


# ── #13: two dispatchers, one report ──

class TestSimultaneousDispatch:
    """The second of two dispatchers pressing Dispatch on the same report is
    refused, rather than sending a second crew over the first."""

    ADMIN = {"id": "d2", "role": "agency_admin", "agency_id": "ag-1", "full_name": "D2"}

    def _db(self, claimed_rows):
        incident = {"id": "inc-1", "status": "received", "assigned_agency_id": "ag-1",
                    "assigned_responder_id": None, "review_status": "pending", "reporter_id": "u1"}
        responder = {"id": "r1", "full_name": "R", "agency_id": "ag-1", "approval_status": "approved",
                     "availability": "on_duty", "role": "responder"}
        db = MagicMock()

        def table(name):
            t = MagicMock()
            if name == "incidents":
                t.select.return_value.eq.return_value.single.return_value.execute.return_value = MagicMock(data=incident)
                t.update.return_value.eq.return_value.in_.return_value.execute.return_value = MagicMock(data=claimed_rows)
            elif name == "users":
                t.select.return_value.eq.return_value.single.return_value.execute.return_value = MagicMock(data=responder)
            return t

        db.table.side_effect = table
        return db

    def test_the_second_dispatcher_is_told_it_is_taken(self):
        from fastapi import HTTPException
        db = self._db(claimed_rows=[])  # someone else's update already moved it on
        with patch("app.services.dispatch_service.get_supabase", return_value=db), \
             patch.object(dispatch_service, "_write_dispatch_log") as log_write:
            try:
                dispatch_service.assign_responder("inc-1", "r1", "high", "high", None, None, self.ADMIN)
            except HTTPException as e:
                assert e.status_code == 409 and "someone else" in e.detail
            else:
                raise AssertionError("expected 409")
        assert not log_write.called, "no dispatch record for a dispatch that did not happen"

    def test_the_first_dispatcher_gets_the_report(self):
        db = self._db(claimed_rows=[{"id": "inc-1"}])
        with patch("app.services.dispatch_service.get_supabase", return_value=db), \
             patch.object(dispatch_service, "_write_dispatch_log") as log_write, \
             patch.object(dispatch_service, "_tell_reporter"):
            out = dispatch_service.assign_responder("inc-1", "r1", "high", "high", None, None, self.ADMIN)
        assert out["status"] == "dispatched" and log_write.called


def test_a_review_decision_made_a_moment_earlier_by_someone_else_wins():
    """#13: accept and reject pressed together - the slower one is told."""
    from fastapi import HTTPException
    db = MagicMock()
    db.table.return_value.update.return_value.eq.return_value.in_.return_value.execute.return_value = MagicMock(data=[])
    try:
        dispatch_service._claim_review(db, "inc-1", {"review_status": "rejected"})
    except HTTPException as e:
        assert e.status_code == 409 and "Another admin" in e.detail
    else:
        raise AssertionError("expected 409")
    db.table.return_value.update.return_value.eq.return_value.in_.assert_called_with(
        "review_status", ["pending", "clarification_requested"])
