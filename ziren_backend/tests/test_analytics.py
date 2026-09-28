"""
analytics_service — Task 12 of the Super Admin plan.

Covers, against small fixed fixtures with hand-computed expectations:
  - incident_analytics: period bucketing, by_agency/by_type/by_municipality,
    resolved_vs_unresolved, avg_resolution_minutes (and the empty-dataset
    case, which must not divide by zero)
  - user_analytics: total_by_role, registration_trend, by_municipality/barangay
  - agency_analytics: resolution_rate, avg_response_minutes, avg_resolution_minutes
  - provincial_admin-only access on the router

Run: pytest tests/test_analytics.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import analytics_service

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"


AGENCY_UUID = "00000000-0000-0000-0000-000000000099"


def _profile(user_id, role, agency_id=None):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": role, "approval_status": "not_required",
        "agency_id": agency_id, "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id, role, agency_id=None):
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user
    profile = MagicMock()
    profile.data = _profile(user_id, role, agency_id)
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


# ── incident_analytics ──────────────────────────────────────────────────

INCIDENT_FIXTURE = [
    {"id": "i1", "status": "resolved", "incident_category": "fire",
     "created_at": "2026-01-05T00:00:00+00:00", "resolved_at": "2026-01-05T01:00:00+00:00",
     "stations": {"agencies": {"agency_type": "BFP", "municipality": "Naval", "name": "BFP Naval"}}},
    {"id": "i2", "status": "resolved", "incident_category": "fire",
     "created_at": "2026-01-10T00:00:00+00:00", "resolved_at": "2026-01-10T02:00:00+00:00",
     "stations": {"agencies": {"agency_type": "BFP", "municipality": "Naval", "name": "BFP Naval"}}},
    {"id": "i3", "status": "dispatched", "incident_category": "medical_trauma",
     "created_at": "2026-02-01T00:00:00+00:00", "resolved_at": None,
     "stations": {"agencies": {"agency_type": "PNP", "municipality": "Caibiran", "name": "PNP Caibiran"}}},
    {"id": "i4", "status": "cancelled", "incident_category": "vehicular",
     "created_at": "2026-02-02T00:00:00+00:00", "resolved_at": None,
     "stations": None},
]


def _db_returning(rows):
    db = MagicMock()
    result = MagicMock()
    result.data = rows
    db.table.return_value.select.return_value.execute.return_value = result
    db.table.return_value.select.return_value.neq.return_value.execute.return_value = result
    # Agency-scoped calls chain one more .eq(...) before .execute() — same
    # fixture rows, whether or not a caller actually applies the filter, since
    # the mock does not really filter anything.
    db.table.return_value.select.return_value.eq.return_value.execute.return_value = result
    # _responder_workload's chain: .eq(...).not_.is_(...).execute().
    empty = MagicMock()
    empty.data = []
    db.table.return_value.select.return_value.eq.return_value.not_.is_.return_value.execute.return_value = empty
    return db


def test_incident_analytics_matches_the_fixture_by_hand():
    db = _db_returning(INCIDENT_FIXTURE)
    with patch("app.services.analytics_service.get_supabase", return_value=db):
        result = analytics_service.incident_analytics(period="month")

    assert result["total"] == 4
    assert result["by_period"] == [{"bucket": "2026-01", "count": 2}, {"bucket": "2026-02", "count": 2}]
    assert result["by_agency"] == {"BFP": 2, "PNP": 1}
    assert result["by_municipality"] == {"Naval": 2, "Caibiran": 1}
    assert result["by_type"] == {"fire": 2, "medical_trauma": 1, "vehicular": 1}
    assert result["resolved_vs_unresolved"] == {"resolved": 2, "unresolved": 2}
    # (60 + 120) / 2 = 90 minutes
    assert result["avg_resolution_minutes"] == 90.0


def test_incident_analytics_day_period_buckets_by_date():
    db = _db_returning(INCIDENT_FIXTURE)
    with patch("app.services.analytics_service.get_supabase", return_value=db):
        result = analytics_service.incident_analytics(period="day")

    buckets = {row["bucket"]: row["count"] for row in result["by_period"]}
    assert buckets == {"2026-01-05": 1, "2026-01-10": 1, "2026-02-01": 1, "2026-02-02": 1}


def test_incident_analytics_empty_dataset_does_not_divide_by_zero():
    db = _db_returning([])
    with patch("app.services.analytics_service.get_supabase", return_value=db):
        result = analytics_service.incident_analytics()

    assert result["total"] == 0
    assert result["avg_resolution_minutes"] is None
    assert result["resolved_vs_unresolved"] == {"resolved": 0, "unresolved": 0}


# ── user_analytics ───────────────────────────────────────────────────────

USER_FIXTURE = [
    {"id": "u1", "role": "resident", "created_at": "2026-01-15T00:00:00+00:00",
     "barangays": {"name": "Caraycaray", "municipality": "Naval"}},
    {"id": "u2", "role": "resident", "created_at": "2026-01-20T00:00:00+00:00",
     "barangays": {"name": "Caraycaray", "municipality": "Naval"}},
    {"id": "u3", "role": "responder", "created_at": "2026-02-01T00:00:00+00:00", "barangays": None},
    {"id": "u4", "role": "agency_admin", "created_at": "2026-02-05T00:00:00+00:00", "barangays": None},
]


def test_user_analytics_matches_the_fixture_by_hand():
    db = _db_returning(USER_FIXTURE)
    with patch("app.services.analytics_service.get_supabase", return_value=db):
        result = analytics_service.user_analytics()

    assert result["total_by_role"] == {"resident": 2, "responder": 1, "agency_admin": 1}
    assert result["registration_trend"]["resident"] == [{"month": "2026-01", "count": 2}]
    assert result["registration_trend"]["responder"] == [{"month": "2026-02", "count": 1}]
    assert result["by_municipality"] == {"Naval": 2}
    assert result["by_barangay"] == {"Naval / Caraycaray": 2}


# ── agency_analytics ─────────────────────────────────────────────────────

AGENCY_FIXTURE = [
    {"id": "i1", "status": "resolved",
     "created_at": "2026-01-01T00:00:00+00:00", "dispatched_at": "2026-01-01T00:10:00+00:00",
     "resolved_at": "2026-01-01T01:10:00+00:00",
     "stations": {"agencies": {"agency_type": "BFP", "name": "BFP Naval"}}},
    {"id": "i2", "status": "cancelled",
     "created_at": "2026-01-02T00:00:00+00:00", "dispatched_at": None, "resolved_at": None,
     "stations": {"agencies": {"agency_type": "BFP", "name": "BFP Naval"}}},
]


def test_agency_analytics_matches_the_fixture_by_hand():
    db = _db_returning(AGENCY_FIXTURE)
    with patch("app.services.analytics_service.get_supabase", return_value=db):
        result = analytics_service.agency_analytics()

    bfp = result["BFP"]
    assert bfp["incidents_handled"] == 2
    assert bfp["resolved"] == 1
    assert bfp["cancelled"] == 1
    assert bfp["resolution_rate"] == 0.5
    assert bfp["avg_response_minutes"] == 10.0
    assert bfp["avg_resolution_minutes"] == 70.0


# ── router ───────────────────────────────────────────────────────────────

def test_router_forbidden_for_agency_admin_on_users():
    """/users stays Provincial Admin only — Agency Admin has no cross-agency user data."""
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_UUID)):
        resp = client.get("/analytics/users", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 403


def test_router_forbidden_for_agency_admin_on_incidents():
    """
    /analytics/incidents was also Agency Admin's Agency Analytics (spec
    Section 13), scoped to their own agency_id, until that dashboard
    feature was removed as not worth keeping. Both /analytics routes are
    now provincial_admin-only, same as /users always was.
    """
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_UUID)):
        resp = client.get("/analytics/incidents", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 403


def test_router_allows_provincial_admin():
    db = _db_returning([])
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.services.analytics_service.get_supabase", return_value=db):
        resp = client.get("/analytics/incidents", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
