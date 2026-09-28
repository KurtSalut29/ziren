"""
GET /stations/?include_inactive — Super Admin only; ignored for Agency Admin.

Task 8 of the Super Admin plan: the Agencies page needs a way to find and
reactivate a deactivated station, and until this the endpoint always filtered
is_active=True unconditionally.

Run: pytest tests/test_stations_admin.py -v
"""

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

PROVINCIAL_ADMIN_UUID  = "00000000-0000-0000-0000-000000000014"
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


def _list_db():
    """
    A station-list mock whose .eq() stays on ONE node however many times it's
    chained — the handler calls .eq() zero, one, or two times depending on
    role/flag (is_active, then agency_id), and a plain MagicMock would give
    each chained call a NEW child mock, leaving .execute() on the deepest one
    unconfigured and returning an unconfigured MagicMock for `.data` instead
    of the fixture below.

    A Provincial Admin's request additionally resolves their own agency_type
    to a list of agency ids via a SEPARATE two-step lookup
    (table("agencies").select("id").eq("agency_type", ...).execute()) before
    the station list is even queried — a different node from order_mock,
    configured here too so that lookup doesn't fall through to an
    unconfigured mock.
    """
    db = MagicMock()
    result = MagicMock()
    result.data = [{"id": "s1", "name": "Station", "is_active": False, "agency_id": AGENCY_UUID, "agencies": {}}]

    order_mock = db.table.return_value.select.return_value.order.return_value
    order_mock.eq.return_value = order_mock
    order_mock.in_.return_value = order_mock
    order_mock.execute.return_value = result

    agency_ids_result = MagicMock()
    agency_ids_result.data = [{"id": AGENCY_UUID}]
    db.table.return_value.select.return_value.eq.return_value.execute.return_value = agency_ids_result

    return db, order_mock


def test_provincial_admin_with_include_inactive_skips_the_is_active_filter():
    db, order_mock = _list_db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)), \
         patch("app.routers.stations.get_supabase", return_value=db):
        resp = client.get("/stations/?include_inactive=true", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200, resp.text
    eq_calls = [c.args for c in order_mock.eq.call_args_list]
    assert ("is_active", True) not in eq_calls


def test_agency_admin_include_inactive_is_ignored():
    db, order_mock = _list_db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_UUID)), \
         patch("app.routers.stations.get_supabase", return_value=db):
        resp = client.get("/stations/?include_inactive=true", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200, resp.text
    eq_calls = [c.args for c in order_mock.eq.call_args_list]
    assert ("is_active", True) in eq_calls
    assert ("agency_id", AGENCY_UUID) in eq_calls


def test_default_still_filters_to_active_only():
    db, order_mock = _list_db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)), \
         patch("app.routers.stations.get_supabase", return_value=db):
        resp = client.get("/stations/", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200, resp.text
    eq_calls = [c.args for c in order_mock.eq.call_args_list]
    assert ("is_active", True) in eq_calls
