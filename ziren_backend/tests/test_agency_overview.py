"""
GET /stations/agencies/{id}/overview — live counts for Settings > Agency
Information (stations, responders, active incidents, resolved today).

Run: pytest tests/test_agency_overview.py -v
"""

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

AGENCY_ID = "a0000001-0000-0000-0000-000000000001"
OTHER_AGENCY_ID = "b0000002-0000-0000-0000-000000000002"
AGENCY_ADMIN_UUID = "d0000004-0000-0000-0000-000000000004"
PROVINCIAL_ADMIN_UUID = "f0000006-0000-0000-0000-000000000006"
PROVINCIAL_ADMIN_AGENCY_TYPE = "BFP"


def _profile(user_id, role, agency_id=None, agency_type=None):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": role, "approval_status": "not_required",
        "agency_id": agency_id, "agency_type": agency_type,
        "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id, role, agency_id=None, agency_type=None):
    mock_user = MagicMock(); mock_user.id = user_id
    mock_get = MagicMock(); mock_get.user = mock_user
    mock_profile = MagicMock(); mock_profile.data = _profile(user_id, role, agency_id, agency_type)

    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = mock_profile
    return db


def _counts_db(stations: int, responders: int, active: int, resolved_today: int, scope_agency_type: str | None = None):
    """
    The four counts chain a different number of filters before .execute()
    (one .eq() for stations, two for responders, .eq()+.in_() for active,
    .eq()+.eq()+.gte() for resolved_today) — so .eq()/.in_()/.gte() are all
    made to return the SAME node regardless of how many are chained, and
    every call path lands on one shared .execute(), keyed by call ORDER via
    side_effect for the four separate _count() invocations.

    scope_agency_type, when given, also configures the .limit(1).execute()
    chain _assert_agency_write_scope's provincial_admin branch uses to
    resolve the target agency_id's own agency_type — this mock is patched
    onto app.routers.stations.get_supabase, the same module
    _assert_agency_write_scope calls get_supabase() from.
    """
    db = MagicMock()
    chain = db.table.return_value.select.return_value
    chain.eq.return_value = chain
    chain.in_.return_value = chain
    chain.gte.return_value = chain

    results = []
    for n in (stations, responders, active, resolved_today):
        r = MagicMock()
        r.count = n
        results.append(r)
    chain.execute.side_effect = results

    if scope_agency_type:
        scope_lookup = MagicMock()
        scope_lookup.data = [{"agency_type": scope_agency_type}]
        chain.limit.return_value.execute.return_value = scope_lookup
    return db


def test_agency_admin_sees_own_agency_counts():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_ID)), \
         patch("app.routers.stations.get_supabase", return_value=_counts_db(7, 24, 6, 12)):
        resp = client.get(
            f"/stations/agencies/{AGENCY_ID}/overview",
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 200, resp.text
    assert resp.json() == {
        "stations": 7, "responders": 24, "active_incidents": 6, "resolved_today": 12,
    }


def test_agency_admin_forbidden_from_other_agency():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_ID)):
        resp = client.get(
            f"/stations/agencies/{OTHER_AGENCY_ID}/overview",
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 403


def test_provincial_admin_sees_any_agency_of_their_own_type():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)), \
         patch("app.routers.stations.get_supabase", return_value=_counts_db(3, 10, 1, 2, scope_agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)):
        resp = client.get(
            f"/stations/agencies/{OTHER_AGENCY_ID}/overview",
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 200, resp.text
    assert resp.json()["stations"] == 3


def test_provincial_admin_forbidden_from_other_agency_type():
    """
    Migration 034's rescoping: a Provincial Admin oversees ONE agency_type
    province-wide, not every agency the way the old super_admin did. An
    agency of a DIFFERENT type must still be refused.
    """
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", agency_type=PROVINCIAL_ADMIN_AGENCY_TYPE)), \
         patch("app.routers.stations.get_supabase", return_value=_counts_db(3, 10, 1, 2, scope_agency_type="PNP")):
        resp = client.get(
            f"/stations/agencies/{OTHER_AGENCY_ID}/overview",
            headers={"Authorization": "Bearer token"},
        )
    assert resp.status_code == 403


def test_requires_auth():
    resp = client.get(f"/stations/agencies/{AGENCY_ID}/overview")
    assert resp.status_code == 403
