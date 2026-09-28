"""
geographic_service.get_overview() and /geographic router — Task 11 of the
Super Admin plan.

Covers:
  - resident count is scoped to the barangay_ids in the chosen municipality
  - responder count matches via their agency's municipality
  - incident aggregation (types, resolved/active, monthly buckets) matches
    hand-computed expectations against a small fixed fixture
  - provincial_admin-only access on the router

Run: pytest tests/test_geographic.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import geographic_service

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"


AGENCY_UUID = "00000000-0000-0000-0000-000000000099"


def _profile(user_id, role, agency_id=None, agency_type=None):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": role, "approval_status": "not_required",
        "agency_id": agency_id, "agency_type": agency_type, "badge_id": None, "is_verified": True,
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


def _mock_service_db():
    """
    Fixture: Naval has 2 barangays (Caraycaray, Larrazabal), 3 residents
    total (2 in Caraycaray, 1 in Larrazabal, 1 more in a DIFFERENT
    municipality's barangay that must NOT be counted), 2 responders (one at
    a Naval-municipality agency, one elsewhere), one BFP station in Naval,
    and 4 incidents: 2 resolved handled by the Naval station (Jan, Feb), 1
    active (dispatched) handled by the Naval station (Feb), and 1 resolved
    handled by a station in a different municipality (must NOT be counted).
    """
    db = MagicMock()

    barangays_result = MagicMock()
    barangays_result.data = [
        {"id": "brgy-1", "name": "Caraycaray", "municipality": "Naval"},
        {"id": "brgy-2", "name": "Larrazabal", "municipality": "Naval"},
    ]

    residents_result = MagicMock()
    residents_result.count = 3  # 2 in brgy-1, 1 in brgy-2 -- this IS the filtered count

    responder_rows = MagicMock()
    responder_rows.data = [
        {"id": "r1", "agencies": {"municipality": "Naval"}},
        {"id": "r2", "agencies": {"municipality": "Caibiran"}},
    ]

    station_rows = MagicMock()
    station_rows.data = [
        {"id": "st-1", "name": "BFP Naval", "agency_id": "a1",
         "agencies": {"name": "BFP Naval", "agency_type": "BFP", "municipality": "Naval"}},
        {"id": "st-2", "name": "PNP Caibiran", "agency_id": "a2",
         "agencies": {"name": "PNP Caibiran", "agency_type": "PNP", "municipality": "Caibiran"}},
    ]

    incident_rows = MagicMock()
    incident_rows.data = [
        {"id": "i1", "status": "resolved", "incident_category": "fire",
         "created_at": "2026-01-05T00:00:00Z", "stations": {"agencies": {"municipality": "Naval"}}},
        {"id": "i2", "status": "resolved", "incident_category": "fire",
         "created_at": "2026-02-01T00:00:00Z", "stations": {"agencies": {"municipality": "Naval"}}},
        {"id": "i3", "status": "dispatched", "incident_category": "medical_trauma",
         "created_at": "2026-02-10T00:00:00Z", "stations": {"agencies": {"municipality": "Naval"}}},
        {"id": "i4", "status": "resolved", "incident_category": "fire",
         "created_at": "2026-02-15T00:00:00Z", "stations": {"agencies": {"municipality": "Caibiran"}}},
    ]

    empty_result = MagicMock()
    empty_result.data = []
    empty_result.count = 0

    def table(name):
        m = MagicMock()
        if name == "barangays":
            # Sensitive to the actual municipality argument, unlike a plain
            # MagicMock — needed so "a municipality with no barangays on
            # file" is distinguishable from Naval in the tests below.
            def eq_effect(_field, value):
                node = MagicMock()
                result = barangays_result if value == "Naval" else empty_result
                node.execute.return_value = result
                node.eq.return_value.execute.return_value = result
                return node
            m.select.return_value.eq.side_effect = eq_effect
        elif name == "users":
            # Both the resident-count query (.select().eq().in_().execute(), count="exact")
            # and the responder-list query (.select().eq().execute()) go through "users".
            m.select.return_value.eq.return_value.in_.return_value.execute.return_value = residents_result
            m.select.return_value.eq.return_value.execute.return_value = responder_rows
        elif name == "stations":
            m.select.return_value.eq.return_value.execute.return_value = station_rows
        elif name == "incidents":
            m.select.return_value.execute.return_value = incident_rows
        return m

    db.table.side_effect = table
    return db


def test_list_municipalities_carries_resident_counts_for_default_selection():
    """
    The dashboard picks its default municipality by resident_count, not
    alphabetical order, so this field has to be right: Almeria (0 residents)
    must not look busier than Naval (2 residents) just because it sorts first.
    """
    db = MagicMock()

    def table(name):
        m = MagicMock()
        if name == "barangays":
            m.select.return_value.execute.return_value.data = [
                {"id": "brgy-1", "municipality": "Naval"},
                {"id": "brgy-2", "municipality": "Naval"},
                {"id": "brgy-3", "municipality": "Almeria"},
            ]
        elif name == "users":
            m.select.return_value.eq.return_value.execute.return_value.data = [
                {"barangay_id": "brgy-1"},
                {"barangay_id": "brgy-1"},
                {"barangay_id": "brgy-2"},
                {"barangay_id": "unknown-barangay"},
            ]
        return m

    db.table.side_effect = table
    with patch("app.services.geographic_service.get_supabase", return_value=db):
        result = geographic_service.list_municipalities()

    assert result == [
        {"name": "Almeria", "resident_count": 0},
        {"name": "Naval", "resident_count": 3},
    ]


def test_overview_counts_match_the_fixture_by_hand():
    db = _mock_service_db()
    with patch("app.services.geographic_service.get_supabase", return_value=db):
        overview = geographic_service.get_overview("Naval")

    assert overview["registered_residents"] == 3
    assert overview["registered_responders"] == 1  # only r1, at a Naval-municipality agency
    assert [s["agency_type"] for s in overview["agency_stations"]] == ["BFP"]
    assert overview["nearby_agencies"] == ["BFP — BFP Naval"]
    assert overview["incident_count"] == 3  # i1, i2, i3 -- i4 is a different municipality
    assert overview["incident_types"] == {"fire": 2, "medical_trauma": 1}
    assert overview["resolved_incidents"] == 2
    assert overview["active_incidents"] == 1
    assert overview["historical_activity"] == [
        {"month": "2026-01", "count": 1},
        {"month": "2026-02", "count": 2},
    ]


def test_overview_with_no_matching_barangay_returns_zero_residents():
    db = _mock_service_db()
    with patch("app.services.geographic_service.get_supabase", return_value=db):
        overview = geographic_service.get_overview("SomewhereElse")

    assert overview["registered_residents"] == 0
    assert overview["incident_count"] == 0
    assert overview["historical_activity"] == []


def test_router_forbidden_for_resident():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db("00000000-0000-0000-0000-000000000010", "resident")):
        resp = client.get("/geographic/overview?municipality=Naval", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 403


def test_router_allows_provincial_admin():
    db = _mock_service_db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.services.geographic_service.get_supabase", return_value=db):
        resp = client.get("/geographic/overview?municipality=Naval", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
    assert resp.json()["registered_residents"] == 3


# ── Agency Admin's Operational Area (Agency Admin spec Section 16) ────────

def test_agency_admin_overview_ignores_client_municipality_and_scopes_to_agency():
    """
    An Agency Admin's Operational Area is always their own agency's
    municipality — a crafted `municipality` query param must not override it,
    and get_overview must receive their agency_id so incident figures are
    scoped to their own agency, not everyone sharing that municipality.
    """
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_UUID)), \
         patch("app.routers.geographic.geographic_service.agency_municipality", return_value="Naval"), \
         patch("app.routers.geographic.geographic_service.get_overview", return_value={"stub": True}) as get_overview:
        resp = client.get("/geographic/overview?municipality=SomewhereElse", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
    get_overview.assert_called_once_with("Naval", None, agency_id=AGENCY_UUID, agency_type=None)


def test_provincial_admin_overview_scopes_to_own_agency_type():
    """
    A Provincial Admin's incident figures are scoped to their own
    agency_type (migration 034) — they may browse any municipality, but
    get_overview must receive their agency_type so a PNP Provincial Admin
    never sees BFP/MDRRMO incidents just because a station of theirs shares
    a municipality with one.
    """
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin", agency_type="PNP")), \
         patch("app.routers.geographic.geographic_service.get_overview", return_value={"stub": True}) as get_overview:
        resp = client.get("/geographic/overview?municipality=Naval", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
    get_overview.assert_called_once_with("Naval", None, agency_id=None, agency_type="PNP")


def test_agency_admin_overview_422_when_agency_has_no_municipality():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_UUID)), \
         patch("app.routers.geographic.geographic_service.agency_municipality", return_value=None):
        resp = client.get("/geographic/overview?municipality=Naval", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 422


def test_agency_admin_municipalities_returns_only_their_own():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_UUID)), \
         patch("app.routers.geographic.geographic_service.agency_municipality", return_value="Naval"), \
         patch(
             "app.routers.geographic.geographic_service.list_municipalities",
             return_value=[{"name": "Almeria", "resident_count": 0}, {"name": "Naval", "resident_count": 3}],
         ):
        resp = client.get("/geographic/municipalities", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
    assert resp.json() == [{"name": "Naval", "resident_count": 3}]
