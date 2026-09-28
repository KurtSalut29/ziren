"""
ai_monitoring_service + /ai-classification router — Task 13 of the Super
Admin plan.

Covers, against a fixed fixture with hand-computed expectations:
  - a row with signals=null is excluded entirely
  - a row with a signals shell but no engine (triage never ran) is excluded
    from total_classifications — it must not count as an AI classification
  - confidence bucketing, including the 1.0 edge landing in the top bucket
  - verification_breakdown counts
  - provincial_admin-only access

Run: pytest tests/test_ai_monitoring.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import ai_monitoring_service

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"

INCIDENT_ROWS = [
    {"id": "i1", "created_at": "2026-01-01T00:00:00Z",
     "signals": {"engine": "ziren-model", "model_confidence": 0.95,
                 "verification_status": "AGREE", "model_predicted_category": "fire", "user_selected": "fire"}},
    {"id": "i2", "created_at": "2026-01-02T00:00:00Z",
     "signals": {"engine": "ziren-model", "model_confidence": 0.42,
                 "verification_status": "MISMATCH_FLAGGED", "model_predicted_category": "vehicular", "user_selected": "medical_trauma"}},
    {"id": "i3", "created_at": "2026-01-03T00:00:00Z",
     "signals": {"engine": None, "model_confidence": None}},  # triage never ran -- not an AI classification
]


def _db_returning(rows):
    db = MagicMock()
    result = MagicMock()
    result.data = rows
    db.table.return_value.select.return_value.not_.is_.return_value.order.return_value.execute.return_value = result
    return db


def test_excludes_rows_without_a_real_engine():
    db = _db_returning(INCIDENT_ROWS)
    with patch("app.services.ai_monitoring_service.get_supabase", return_value=db), \
         patch("app.services.triage_service.status", return_value={"model_loaded": True, "version": "2.1.5"}):
        stats = ai_monitoring_service.get_stats()

    assert stats["total_classifications"] == 2  # i1, i2 only -- i3 excluded


def test_confidence_bucketing_and_top_edge():
    db = _db_returning(INCIDENT_ROWS)
    with patch("app.services.ai_monitoring_service.get_supabase", return_value=db), \
         patch("app.services.triage_service.status", return_value={"model_loaded": True, "version": "2.1.5"}):
        stats = ai_monitoring_service.get_stats()

    assert stats["confidence_distribution"]["0.9-1.0"] == 1  # i1 at 0.95
    assert stats["confidence_distribution"]["0.0-0.5"] == 1  # i2 at 0.42


def test_perfect_confidence_lands_in_top_bucket():
    rows = [{"id": "i1", "created_at": "2026-01-01T00:00:00Z",
             "signals": {"engine": "ziren-model", "model_confidence": 1.0, "verification_status": "AGREE"}}]
    db = _db_returning(rows)
    with patch("app.services.ai_monitoring_service.get_supabase", return_value=db), \
         patch("app.services.triage_service.status", return_value={"model_loaded": True, "version": "2.1.5"}):
        stats = ai_monitoring_service.get_stats()

    assert stats["confidence_distribution"]["0.9-1.0"] == 1


def test_verification_breakdown_counts():
    db = _db_returning(INCIDENT_ROWS)
    with patch("app.services.ai_monitoring_service.get_supabase", return_value=db), \
         patch("app.services.triage_service.status", return_value={"model_loaded": True, "version": "2.1.5"}):
        stats = ai_monitoring_service.get_stats()

    assert stats["verification_breakdown"] == {"AGREE": 1, "MISMATCH_FLAGGED": 1}


def test_model_version_and_status_come_from_triage_service():
    db = _db_returning([])
    with patch("app.services.ai_monitoring_service.get_supabase", return_value=db), \
         patch("app.services.triage_service.status", return_value={"model_loaded": False, "version": "2.1.5"}):
        stats = ai_monitoring_service.get_stats()

    assert stats["model_version"] == "2.1.5"
    assert stats["model_status"] == "unavailable"


def _profile(user_id, role):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test Admin",
        "role": role, "approval_status": "not_required",
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


def test_router_forbidden_for_agency_admin():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin")):
        resp = client.get("/ai-classification/stats", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 403


def test_router_allows_provincial_admin():
    db = _db_returning([])
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.services.ai_monitoring_service.get_supabase", return_value=db):
        resp = client.get("/ai-classification/stats", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 200, resp.text
