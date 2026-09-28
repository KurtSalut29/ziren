"""
GET /users/agency/responders — derived `current_status` (Agency Admin spec
Section 7: Responder Availability).

Before this, the roster carried only the account-level on_duty/off_duty flag;
a dispatcher had to cross-reference that against whichever incident happened
to reference a responder's id to know if they were actually free. These
tests cover the derivation: offline / available / assigned / en_route /
on_scene, and that a responder awaiting approval gets no status at all.
"""

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"
ADMIN_ID = "d0000004-0000-0000-0000-000000000004"


def _auth_db():
    """
    A DB double for the get_current_user dependency itself — it decodes the
    bearer token via db.auth.get_user() and fetches the profile via
    db.table("users")...single(), the same pattern test_analytics.py and
    test_reports.py use. Patching get_current_user directly does not work:
    the router's Depends(get_current_user) captured the real function object
    at decoration time, so only patching what THAT function calls takes effect.
    """
    mock_user = MagicMock()
    mock_user.id = ADMIN_ID
    mock_get = MagicMock()
    mock_get.user = mock_user
    profile = MagicMock()
    profile.data = {
        "id": ADMIN_ID, "email": "admin@bfp.gov.ph", "full_name": "Test Admin",
        "role": "agency_admin", "approval_status": "not_required",
        "agency_id": AGENCY_ID, "badge_id": None, "is_verified": True,
    }
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


def _responder(id_, availability="on_duty", approval_status="approved"):
    return {
        "id": id_, "email": f"{id_}@bfp.gov.ph", "full_name": f"Responder {id_}",
        "badge_id": None, "approval_status": approval_status, "availability": availability,
        "is_verified": True, "created_at": "2026-08-01T00:00:00Z", "agency_id": AGENCY_ID,
        "agencies": {"name": "BFP Naval", "agency_type": "BFP", "municipality": "Naval"},
    }


def _db(responders, active_incidents):
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "users":
            # .select(...).eq("role", "responder").eq("agency_id", ...).order(...).execute()
            m.select.return_value.eq.return_value.eq.return_value.order.return_value.execute.return_value.data = responders
        elif name == "incidents":
            m.select.return_value.in_.return_value.in_.return_value.execute.return_value.data = active_incidents
        return m

    db.table.side_effect = table
    return db


def _get():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db()):
        return client.get("/users/agency/responders", headers={"Authorization": "Bearer token"})


def test_off_duty_responder_is_offline():
    db = _db([_responder("r1", availability="off_duty")], [])
    with patch("app.routers.users.get_supabase", return_value=db):
        resp = _get()
    assert resp.status_code == 200, resp.text
    row = resp.json()[0]
    assert row["current_status"] == "offline"
    assert row["current_incident"] is None


def test_on_duty_with_no_active_incident_is_available():
    db = _db([_responder("r1")], [])
    with patch("app.routers.users.get_supabase", return_value=db):
        resp = _get()
    row = resp.json()[0]
    assert row["current_status"] == "available"
    assert row["current_incident"] is None


def test_on_duty_dispatched_is_assigned():
    active = [{"id": "inc-1", "status": "dispatched", "incident_category": "fire",
               "location_address": "Brgy. Example", "assigned_responder_id": "r1"}]
    db = _db([_responder("r1")], active)
    with patch("app.routers.users.get_supabase", return_value=db):
        resp = _get()
    row = resp.json()[0]
    assert row["current_status"] == "assigned"
    assert row["current_incident"] == {"id": "inc-1", "incident_category": "fire", "location_address": "Brgy. Example"}


def test_on_duty_en_route_and_arrived_map_correctly():
    active = [
        {"id": "inc-1", "status": "en_route", "incident_category": "fire", "location_address": None, "assigned_responder_id": "r1"},
        {"id": "inc-2", "status": "arrived", "incident_category": "medical_trauma", "location_address": None, "assigned_responder_id": "r2"},
    ]
    db = _db([_responder("r1"), _responder("r2")], active)
    with patch("app.routers.users.get_supabase", return_value=db):
        resp = _get()
    rows = {r["id"]: r for r in resp.json()}
    assert rows["r1"]["current_status"] == "en_route"
    assert rows["r2"]["current_status"] == "on_scene"


def test_pending_responder_has_no_current_status():
    db = _db([_responder("r1", approval_status="pending")], [])
    with patch("app.routers.users.get_supabase", return_value=db):
        resp = _get()
    row = resp.json()[0]
    assert row["current_status"] is None
    assert row["current_incident"] is None
