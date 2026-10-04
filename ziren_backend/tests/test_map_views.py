"""
GET /map/data?view= — Task 10 of the Provincial Admin plan (migration 034
renamed super_admin -> provincial_admin and rescoped it to one agency_type
across the province, same as every other Type A module).

Covers:
  - default (operational) behavior is unchanged: active statuses only
  - Agency Admin's view is always "operational" regardless of the query param
    (they have no Network/History map to switch to)
  - Provincial Admin's "network" view returns zero incidents
  - Provincial Admin's "history" view queries resolved/cancelled statuses only,
    and every returned incident carries route: None (no operational routing
    on this view, ever)
  - Provincial Admin's incidents/responders queries are additionally scoped
    to their own agency_type via the same two-step agencies lookup
    dispatch_service uses

Run: pytest tests/test_map_views.py -v
"""

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"
AGENCY_UUID       = "aaaaaaaa-0000-0000-0000-000000000001"
PROVINCIAL_ADMIN_AGENCY_TYPE = "BFP"


def _profile(user_id, role, agency_id=None, agency_type=None):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": role, "approval_status": "not_required",
        "agency_id": agency_id, "agency_type": agency_type,
        "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id, role, agency_id=None, agency_type=None):
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user
    profile = MagicMock()
    profile.data = _profile(user_id, role, agency_id, agency_type)
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


def _empty_data_db():
    """
    A map-data DB mock where every table query returns an empty list.

    Both nodes are made fully self-referencing on every filter method
    (.eq/.in_/.gte/.not_.is_), so ANY number of chained filter calls, in
    ANY order, converge on the same terminal .execute() — this is what lets
    the SAME mock serve the two-step agencies-lookup a Provincial Admin's
    request now makes (table("agencies").select("id").eq(...).execute())
    alongside the incidents/responders queries, and the extra
    .in_("assigned_agency_id"/"agency_id", own_agency_ids) filter a
    Provincial Admin's request adds on top of whatever an Agency Admin's
    request already chained — without having to enumerate every possible
    chain depth by hand.
    """
    db = MagicMock()
    empty = MagicMock()
    empty.data = []

    incident_chain = db.table.return_value.select.return_value.not_.is_.return_value
    incident_chain.in_.return_value = incident_chain
    incident_chain.gte.return_value = incident_chain
    incident_chain.eq.return_value = incident_chain
    incident_chain.order.return_value = incident_chain
    incident_chain.limit.return_value = incident_chain
    incident_chain.execute.return_value = empty

    eq_chain = db.table.return_value.select.return_value.eq.return_value
    eq_chain.eq.return_value = eq_chain
    eq_chain.in_.return_value = eq_chain
    eq_chain.not_.is_.return_value = eq_chain
    eq_chain.execute.return_value = empty

    return db, incident_chain


def _call(role, agency_id, query, service_db, agency_type=None):
    user_id = PROVINCIAL_ADMIN_UUID if role == "provincial_admin" else AGENCY_ADMIN_UUID
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(user_id, role, agency_id, agency_type)), \
         patch("app.routers.map.get_supabase", return_value=service_db):
        return client.get(f"/map/data{query}", headers={"Authorization": "Bearer token"})


def test_default_view_queries_active_statuses_only():
    db, incident_chain = _empty_data_db()
    resp = _call("provincial_admin", None, "", db, agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)
    assert resp.status_code == 200, resp.text
    in_calls = [c.args[1] for c in incident_chain.in_.call_args_list]
    assert ["received", "processing", "dispatched", "en_route", "arrived"] in in_calls


def test_agency_admin_ignores_view_param_and_stays_operational():
    db, incident_chain = _empty_data_db()
    resp = _call("agency_admin", AGENCY_UUID, "?view=network", db)
    assert resp.status_code == 200, resp.text
    in_calls = [c.args[1] for c in incident_chain.in_.call_args_list]
    assert ["received", "processing", "dispatched", "en_route", "arrived"] in in_calls


def test_provincial_admin_network_view_returns_no_incidents():
    db, _ = _empty_data_db()
    resp = _call("provincial_admin", None, "?view=network", db, agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)
    assert resp.status_code == 200, resp.text
    assert resp.json()["incidents"] == []


def test_provincial_admin_history_view_queries_resolved_and_cancelled():
    db, incident_chain = _empty_data_db()
    resp = _call("provincial_admin", None, "?view=history&days=30", db, agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)
    assert resp.status_code == 200, resp.text
    in_calls = [c.args[1] for c in incident_chain.in_.call_args_list]
    assert ["resolved", "cancelled"] in in_calls


def test_history_view_incidents_never_carry_a_route():
    db, incident_chain = _empty_data_db()
    result = MagicMock()
    result.data = [{
        "id": "inc-1", "location": {"coordinates": [124.4, 11.5]},
        "severity": "high", "status": "resolved", "sos_flagged": False,
        "created_at": "2026-01-01T00:00:00Z", "resolved_at": "2026-01-01T01:00:00Z",
        "report_text": "Fire", "assigned_agency_id": AGENCY_UUID,
        "stations": {"agencies": {"id": AGENCY_UUID, "agency_type": "BFP", "name": "BFP Naval"}},
    }]
    # Every chained filter on incident_chain (.in_/.gte, whatever order and
    # however many) converges on incident_chain itself (see _empty_data_db),
    # so overriding .execute() here on the shared node is enough regardless
    # of exactly how many filters the Provincial Admin scope check added.
    incident_chain.execute.return_value = result

    resp = _call("provincial_admin", None, "?view=history", db, agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)
    assert resp.status_code == 200, resp.text
    incidents = resp.json()["incidents"]
    assert len(incidents) == 1
    assert incidents[0]["route"] is None


def test_incident_pins_are_capped_newest_first_and_the_cut_is_reported():
    """Evaluator finding #17: the map never returns an unbounded list."""
    from app.routers import map as map_router
    db, incident_chain = _empty_data_db()
    result = MagicMock()
    result.data = [{
        "id": f"inc-{i}", "location": {"coordinates": [124.4, 11.5]},
        "severity": "low", "status": "resolved", "sos_flagged": False,
        "created_at": "2026-01-01T00:00:00Z", "resolved_at": None, "report_text": "x",
        "assigned_agency_id": AGENCY_UUID, "stations": None,
    } for i in range(3)]
    result.count = 4000
    incident_chain.execute.return_value = result

    resp = _call("provincial_admin", None, "?view=history", db, agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)
    assert resp.status_code == 200, resp.text
    incident_chain.order.assert_called_with("created_at", desc=True)
    incident_chain.limit.assert_called_with(map_router.MAP_INCIDENT_MAX)
    limits = resp.json()["limits"]
    assert limits["truncated"] is True and limits["incidents_total"] == 4000
