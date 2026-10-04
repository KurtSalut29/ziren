"""A responder's own emergency: panic, the no-movement check, and clearing.

Evaluator finding #26 asked for coverage of important backend paths. These
were among the least covered (responder_ops_service sat at 51%) and are the
ones a crew in trouble depends on.

Run with: pytest tests/test_responder_safety.py -v
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import responder_ops_service as ops
from tests.audit_helpers import patch_audit_action

ADMIN = {"id": "a1", "role": "agency_admin", "agency_id": "ag-1", "full_name": "Admin"}


def _iso(minutes_ago: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).isoformat()


class _Q:
    """A chainable query double that returns `data` and records filters."""

    def __init__(self, data=None, raise_on_execute=None):
        self.data, self.raise_on_execute, self.calls = data, raise_on_execute, []

    def __getattr__(self, name):
        def call(*args, **kwargs):
            self.calls.append((name, args))
            return self
        return call

    @property
    def not_(self):
        return self

    def execute(self):
        if self.raise_on_execute:
            raise self.raise_on_execute
        return MagicMock(data=self.data)


def _incident(rid, last_seen):
    return {
        "id": f"inc-{rid}", "dispatched_at": _iso(30), "assigned_responder_id": rid,
        "assigned_agency_id": "ag-1",
        "users": {"id": rid, "full_name": f"R{rid}", "badge_id": "B", "phone_number": "0917",
                  "location": {"type": "Point", "coordinates": [124.4, 11.56]},
                  "location_updated_at": last_seen},
    }


# ── the no-movement check ────────────────────────────────────

def test_a_crew_quiet_for_more_than_twelve_minutes_en_route_is_raised():
    q = _Q([_incident("old", _iso(20)), _incident("fresh", _iso(3)), _incident("never", None)])
    db = MagicMock()
    db.table.return_value = q
    out = ops._stale_responders(db, ADMIN)
    assert [r["responder_id"] for r in out] == ["old"]
    assert out[0]["id"].startswith("stale:"), "not a real row: the console must not offer to clear it"
    assert out[0]["latitude"] == 11.56
    assert ("eq", ("status", "en_route")) in q.calls
    assert ("eq", ("assigned_agency_id", "ag-1")) in q.calls, "an agency admin sees their own crews only"


# ── the open list ────────────────────────────────────────────

def test_real_presses_come_first_and_survive_a_failed_inference():
    press = {"id": "d1", "responder_id": "r1", "agency_id": "ag-1", "kind": "panic",
             "location": None, "note": None, "raised_at": _iso(1),
             "users": {"full_name": "R1", "badge_id": "B1", "phone_number": "0917"}}
    db = MagicMock()
    db.table.side_effect = lambda name: _Q([press]) if name == "responder_distress" else _Q(
        raise_on_execute=RuntimeError("timeout"))
    with patch.object(ops, "get_supabase", return_value=db):
        rows = ops.list_open_distress(ADMIN)
    assert [r["id"] for r in rows] == ["d1"]
    assert rows[0]["responder_name"] == "R1"


# ── raising ──────────────────────────────────────────────────

def test_a_panic_press_is_never_refused_for_missing_details():
    q = _Q([{"id": "d1"}])
    db = MagicMock()
    db.table.return_value = q
    with patch.object(ops, "get_supabase", return_value=db):
        out = ops.raise_distress("r1", None, kind="nonsense", latitude=11.5, longitude=124.4)
    assert out == {"id": "d1"}
    payload = next(args[0] for name, args in q.calls if name == "insert")
    assert payload["kind"] == "panic"
    assert payload["location"] == "SRID=4326;POINT(124.4 11.5)"


def test_a_press_that_could_not_be_stored_tells_them_to_use_the_radio():
    db = MagicMock()
    db.table.return_value = _Q([])
    with patch.object(ops, "get_supabase", return_value=db), pytest.raises(HTTPException) as exc:
        ops.raise_distress("r1", "ag-1")
    assert exc.value.status_code == 503 and "radio" in exc.value.detail


# ── clearing ─────────────────────────────────────────────────

def _clear_db(row):
    q = _Q(row)
    db = MagicMock()
    db.table.return_value = q
    return db, q


def test_clearing_records_who_and_why_and_is_audited():
    db, q = _clear_db({"id": "d1", "agency_id": "ag-1", "cleared_at": None})
    with patch.object(ops, "get_supabase", return_value=db), \
         patch.object(ops, "assert_agency_scope"), patch_audit_action() as audit:
        out = ops.clear_distress("d1", ADMIN, note="  Radioed, they are fine ")
    assert out["already_cleared"] is False
    update = next(args[0] for name, args in q.calls if name == "update")
    assert update["cleared_by"] == "a1" and update["clear_note"] == "Radioed, they are fine"
    assert audit.call_args.kwargs["action"] == "responder.distress_cleared"


def test_clearing_twice_is_harmless():
    db, _ = _clear_db({"id": "d1", "agency_id": "ag-1", "cleared_at": "2026-10-05T00:00:00+00:00"})
    with patch.object(ops, "get_supabase", return_value=db), patch.object(ops, "assert_agency_scope"):
        assert ops.clear_distress("d1", ADMIN)["already_cleared"] is True


def test_another_agencys_signal_cannot_be_cleared():
    db, q = _clear_db({"id": "d1", "agency_id": "ag-2", "cleared_at": None})
    with patch.object(ops, "get_supabase", return_value=db), \
         patch.object(ops, "assert_agency_scope", side_effect=HTTPException(status_code=403, detail="no")), \
         pytest.raises(HTTPException) as exc:
        ops.clear_distress("d1", ADMIN)
    assert exc.value.status_code == 403
    assert not any(name == "update" for name, _ in q.calls)


def test_an_unknown_signal_is_not_found():
    db, _ = _clear_db(None)
    with patch.object(ops, "get_supabase", return_value=db), pytest.raises(HTTPException) as exc:
        ops.clear_distress("nope", ADMIN)
    assert exc.value.status_code == 404


# ── hazards on the way to a scene ────────────────────────────

def _hazard(hid, lat, lng, radius_m=300):
    return {"id": hid, "location": {"type": "Point", "coordinates": [lng, lat]}, "radius_m": radius_m,
            "hazard_type": "road_impassable", "note": "Bridge out", "created_at": _iso(60)}


def test_hazards_near_a_scene_are_found_nearest_first_and_far_ones_left_out():
    db = MagicMock()
    db.table.return_value = _Q([
        _hazard("far", 11.80, 124.40),          # ~26 km away
        _hazard("close", 11.566, 124.403),      # ~170 m away
        _hazard("mid", 11.575, 124.403),        # ~1.2 km away
        {"id": "broken", "location": None, "radius_m": 300, "hazard_type": "other", "note": "x"},
    ])
    near = ops.hazards_near(11.5645, 124.4031, db=db)
    ids = [h["id"] for h in near]
    assert "far" not in ids and "broken" not in ids
    assert ids[0] == "close"
    assert near == sorted(near, key=lambda h: h["distance_km"])


def test_a_scene_inside_a_wide_hazard_counts_even_beyond_the_search_radius():
    db = MagicMock()
    db.table.return_value = _Q([_hazard("flood", 11.60, 124.40, radius_m=5000)])  # ~4 km, radius 5 km
    assert [h["id"] for h in ops.hazards_near(11.5645, 124.4031, radius_km=1.0, db=db)] == ["flood"]


@pytest.mark.parametrize("kwargs,reason", [
    ({"hazard_type": "dragons"}, "Unknown hazard type"),
    ({"note": "   "}, "needs a note"),
    ({"radius_m": 0}, "between 1 and 5000"),
    ({"radius_m": 6000}, "between 1 and 5000"),
])
def test_a_hazard_needs_a_known_type_a_note_and_a_sane_radius(kwargs, reason):
    args = {"latitude": 11.5, "longitude": 124.4, "hazard_type": "road_impassable", "note": "Bridge out",
            "radius_m": 300, **kwargs}
    with pytest.raises(HTTPException) as exc:
        ops.create_hazard({"id": "r1", "agency_id": "ag-1"}, **args)
    assert exc.value.status_code == 422 and reason in exc.value.detail


def test_a_responders_hazard_stays_with_their_agency():
    q = _Q([{"id": "h1"}])
    db = MagicMock()
    db.table.return_value = q
    with patch.object(ops, "get_supabase", return_value=db):
        ops.create_hazard({"id": "r1", "agency_id": "ag-1"}, 11.5, 124.4, "road_impassable", " Bridge out ")
    payload = next(args[0] for name, args in q.calls if name == "insert")
    assert payload["agency_id"] == "ag-1" and payload["note"] == "Bridge out"


# ── mutual aid from the scene ────────────────────────────────

@pytest.mark.parametrize("agency,reason,detail", [
    ("COAST_GUARD", "Need boats", "Unknown agency"),
    ("MDRRMO", "   ", "Say what you need"),
])
def test_a_backup_request_names_a_known_agency_and_a_need(agency, reason, detail):
    with pytest.raises(HTTPException) as exc:
        ops.request_backup("inc-1", "r1", agency, reason)
    assert exc.value.status_code == 422 and detail in exc.value.detail


def test_a_backup_request_becomes_a_linked_incident_for_the_nearest_station():
    parent = {"id": "inc-1", "report_text": "House fire", "severity": "high",
              "location": {"type": "Point", "coordinates": [124.4031, 11.5645]},
              "location_address": "Naval", "landmark_note": None, "incident_category": "fire",
              "assigned_responder_id": "r1", "assigned_agency_id": "ag-bfp", "backup_of_incident_id": None}
    inserted = {}

    class Incidents(_Q):
        def insert(self, payload):
            inserted.update(payload)
            self.data = [{"id": "child-1", **payload}]
            return self

    db = MagicMock()
    db.table.side_effect = lambda name: {
        "incidents": Incidents(),
        "users": _Q({"full_name": "Juan", "badge_id": "BFP-7"}),
    }.get(name, _Q([]))
    with patch.object(ops, "get_supabase", return_value=db), \
         patch.object(ops, "_load_assigned", return_value=parent), \
         patch.object(ops, "_nearest_station_of_type", return_value={"id": "st-m", "agency_id": "ag-mdrrmo"}):
        ops.request_backup("inc-1", "r1", "mdrrmo", "Two injured, need an ambulance")

    assert inserted["backup_of_incident_id"] == "inc-1"
    assert inserted["assigned_agency_id"] == "ag-mdrrmo"
    assert inserted["severity"] == "high", "inherits the parent's severity, not re-triaged"
    assert "Juan (BFP-7)" in inserted["report_text"] and "ambulance" in inserted["report_text"]


def test_a_backup_of_a_backup_goes_through_the_dispatcher():
    parent = {"id": "inc-2", "backup_of_incident_id": "inc-1", "location": None}
    db = MagicMock()
    with patch.object(ops, "get_supabase", return_value=db), \
         patch.object(ops, "_load_assigned", return_value=parent), pytest.raises(HTTPException) as exc:
        ops.request_backup("inc-2", "r1", "PNP", "Crowd control")
    assert exc.value.status_code == 422 and "dispatcher" in exc.value.detail
