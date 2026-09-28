"""
report_service + /reports router — Task 17 of the Super Admin plan.

Covers, parametrized across all 10 report types x 3 formats (30 combinations):
  - the response has non-empty bytes and the right Content-Type
  - for CSV specifically, the header row matches the expected columns

Plus: unknown report_type / format both 422, and provincial_admin-only access.

Run: pytest tests/test_reports.py -v
"""

import csv
import io
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import report_service

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"

EXPECTED_HEADERS = {
    "monthly_incidents":      ["Month", "Incident Count"],
    "agency_performance":     ["Agency", "Handled", "Resolved", "Cancelled", "Resolution Rate", "Avg Response (min)", "Avg Resolution (min)"],
    "municipality_incidents": ["Municipality", "Incident Count"],
    "barangay_incidents":     ["Barangay", "Incident Count"],
    "resident_registrations": ["Barangay", "Registered Residents"],
    "responders":             ["Name", "Badge ID", "Agency", "Approval Status", "Availability"],
    "incident_resolution":    ["Incident ID", "Agency", "Reported At", "Resolved At", "Resolution Time (min)"],
    "severity_breakdown":     ["Severity", "Incident Count", "Share of Total"],
    "sla_compliance":         ["Severity", "Target (min)", "Dispatched On Time", "Dispatched Late", "Still Awaiting Dispatch", "Compliance Rate"],
    "flagged_reports":        ["Incident ID", "Type", "Reason", "Reporter", "Agency", "Date"],
}


AGENCY_UUID = "00000000-0000-0000-0000-000000000099"


def _profile(user_id, role, agency_id=None):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test Admin",
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


def _empty_everywhere_db():
    """
    A DB mock where any query chain, however it's built, resolves to an
    empty result. Every chainable method returns the SAME node, so a report
    builder can call .select().eq().order().execute() or .select().execute()
    or anything in between without needing a bespoke mock per report type.
    """
    empty = MagicMock()
    empty.data = []

    chain = MagicMock()
    for method in ("select", "eq", "neq", "in_", "gte", "lte", "limit", "order", "not_"):
        getattr(chain, method).return_value = chain
    chain.is_.return_value = chain
    chain.execute.return_value = empty

    db = MagicMock()
    db.table.return_value = chain
    return db


@pytest.mark.parametrize("report_type", report_service.REPORT_TYPES)
@pytest.mark.parametrize("fmt", report_service.FORMATS)
def test_every_report_type_and_format_produces_a_file(report_type, fmt):
    db = _empty_everywhere_db()
    with patch("app.services.report_service.get_supabase", return_value=db), \
         patch("app.services.analytics_service.get_supabase", return_value=db):
        content, filename, media_type = report_service.build_report(report_type, fmt)

    assert len(content) > 0
    expected_media = {"csv": "text/csv", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "pdf": "application/pdf"}
    assert media_type == expected_media[fmt]
    assert filename.endswith(f".{fmt}")


@pytest.mark.parametrize("report_type", report_service.REPORT_TYPES)
def test_csv_header_matches_expected_columns(report_type):
    db = _empty_everywhere_db()
    with patch("app.services.report_service.get_supabase", return_value=db), \
         patch("app.services.analytics_service.get_supabase", return_value=db):
        content, _, _ = report_service.build_report(report_type, "csv")

    reader = csv.reader(io.StringIO(content.decode("utf-8")))
    header = next(reader)
    assert header == EXPECTED_HEADERS[report_type]


def test_unknown_report_type_is_422():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")):
        resp = client.get("/reports/not_a_real_report", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 422


def test_unknown_format_is_422():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")):
        resp = client.get("/reports/monthly_incidents?format=docx", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 422


def test_router_forbidden_for_agency_admin_on_province_wide_report():
    """
    municipality_incidents has no per-agency cut and stays out of
    AGENCY_ADMIN_REPORT_TYPES — Agency Admin gets a 422 (unknown report_type
    for their role), not the underlying province-wide data.
    """
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_UUID)):
        resp = client.get("/reports/municipality_incidents", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 422


@pytest.mark.parametrize("report_type", report_service.AGENCY_ADMIN_REPORT_TYPES)
def test_router_allows_agency_admin_on_agency_scoped_reports(report_type):
    db = _empty_everywhere_db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_UUID)), \
         patch("app.services.report_service.get_supabase", return_value=db), \
         patch("app.services.analytics_service.get_supabase", return_value=db):
        resp = client.get(f"/reports/{report_type}", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text


def test_list_report_types_is_narrower_for_agency_admin():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin", AGENCY_UUID)):
        resp = client.get("/reports/", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
    assert set(resp.json()["report_types"]) == set(report_service.AGENCY_ADMIN_REPORT_TYPES)


def test_router_allows_provincial_admin_and_sets_content_disposition():
    db = _empty_everywhere_db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.routers.reports.report_service.build_report", return_value=(b"a,b\n1,2", "monthly_incidents_2026-01-01.csv", "text/csv")):
        resp = client.get("/reports/monthly_incidents", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200, resp.text
    assert "attachment" in resp.headers["content-disposition"]
    assert "monthly_incidents_2026-01-01.csv" in resp.headers["content-disposition"]
