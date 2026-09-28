"""
GET /audit-logs/ — Provincial Admin's audit trail (own agency_type +
platform-wide rows).

Covers:
  - 403 for resident, responder, agency_admin
  - 200 for provincial_admin
  - query params are forwarded to the correct Supabase filter chain calls
  - the {items, total} response shape

Run: pytest tests/test_audit_router.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

RESIDENT_UUID     = "00000000-0000-0000-0000-000000000010"
RESPONDER_UUID    = "00000000-0000-0000-0000-000000000011"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"
PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"


def _profile(user_id, role):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": role, "approval_status": "not_required" if role != "responder" else "approved",
        "agency_id": None, "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id, role):
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user

    profile = MagicMock()
    profile.data = _profile(user_id, role)

    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


def _call(role, user_id, query=""):
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(user_id, role)):
        return client.get(f"/audit-logs/{query}", headers={"Authorization": "Bearer token"})


@pytest.mark.parametrize("role,user_id", [
    ("resident", RESIDENT_UUID),
    ("responder", RESPONDER_UUID),
    ("agency_admin", AGENCY_ADMIN_UUID),
])
def test_non_provincial_admin_roles_are_forbidden(role, user_id):
    resp = _call(role, user_id)
    assert resp.status_code == 403


def test_provincial_admin_can_list_audit_logs():
    query_result = MagicMock()
    query_result.data = [{"id": "row-1", "action": "station.created"}]
    query_result.count = 1

    query_db = MagicMock()
    chain = query_db.table.return_value.select.return_value.order.return_value
    chain.range.return_value.execute.return_value = query_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.routers.audit.get_supabase", return_value=query_db):
        resp = client.get("/audit-logs/", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200
    body = resp.json()
    assert body == {"items": [{"id": "row-1", "action": "station.created"}], "total": 1}


def test_query_params_are_forwarded_as_filters():
    query_result = MagicMock()
    query_result.data = []
    query_result.count = 0

    query_db = MagicMock()
    order_mock = query_db.table.return_value.select.return_value.order.return_value
    # Every filter method returns the same mock so we can inspect all calls on it.
    order_mock.eq.return_value = order_mock
    order_mock.gte.return_value = order_mock
    order_mock.lte.return_value = order_mock
    order_mock.range.return_value.execute.return_value = query_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.routers.audit.get_supabase", return_value=query_db):
        resp = client.get(
            "/audit-logs/?actor_id=a1&target_type=station&action=station.created"
            "&date_from=2026-01-01&date_to=2026-01-31",
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200
    eq_calls = [c.args for c in order_mock.eq.call_args_list]
    assert ("actor_id", "a1") in eq_calls
    assert ("target_type", "station") in eq_calls
    assert ("action", "station.created") in eq_calls
    order_mock.gte.assert_called_with("created_at", "2026-01-01")
    # NOT the bare "2026-01-31" — see test_date_to_is_extended_to_the_end_of_its_day
    # for why a bare date here would silently exclude almost the whole day.
    order_mock.lte.assert_called_with("created_at", "2026-01-31T23:59:59.999999")


def test_date_to_is_extended_to_the_end_of_its_day():
    """
    A bare 'YYYY-MM-DD' `date_to`, compared with `.lte` as-is, means "created_at
    <= midnight at the START of that day" — a Provincial Admin filtering
    "To: 2026-01-31" would see none of that day's own entries, only ones from
    before it. The route must extend it to the last instant of that day.
    """
    query_result = MagicMock()
    query_result.data = []
    query_result.count = 0

    query_db = MagicMock()
    order_mock = query_db.table.return_value.select.return_value.order.return_value
    order_mock.gte.return_value = order_mock
    order_mock.lte.return_value = order_mock
    order_mock.range.return_value.execute.return_value = query_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.routers.audit.get_supabase", return_value=query_db):
        resp = client.get(
            "/audit-logs/?date_to=2026-01-31",
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200
    order_mock.lte.assert_called_with("created_at", "2026-01-31T23:59:59.999999")


def test_date_to_with_a_time_already_is_left_alone():
    """A caller that already sent a full ISO datetime (not just a bare date)
    is trusted as-is — only a bare date gets extended to end-of-day."""
    query_result = MagicMock()
    query_result.data = []
    query_result.count = 0

    query_db = MagicMock()
    order_mock = query_db.table.return_value.select.return_value.order.return_value
    order_mock.gte.return_value = order_mock
    order_mock.lte.return_value = order_mock
    order_mock.range.return_value.execute.return_value = query_result

    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.routers.audit.get_supabase", return_value=query_db):
        resp = client.get(
            "/audit-logs/?date_to=2026-01-31T10:00:00%2B00:00",
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200
    order_mock.lte.assert_called_with("created_at", "2026-01-31T10:00:00+00:00")
