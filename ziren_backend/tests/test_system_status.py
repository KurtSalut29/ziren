"""
system_status_service + /system-status router — Task 15 of the Super Admin
plan.

Covers:
  - a healthy backend reports every check operational
  - one failing check (e.g. Database down) reports "down" for that check
    ONLY, while every other check still reports operational — the whole
    point of this page, and the reason each check is wrapped individually
    rather than the list being wrapped in one try/except
  - provincial_admin-only access

Run: pytest tests/test_system_status.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import system_status_service

client = TestClient(app)

PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000014"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000012"


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


def _healthy_db():
    db = MagicMock()
    db.table.return_value.select.return_value.limit.return_value.execute.return_value = MagicMock()
    db.auth.admin.list_users.return_value = []
    db.storage.list_buckets.return_value = []
    return db


def test_all_checks_operational_when_everything_works():
    db = _healthy_db()
    with patch("app.services.system_status_service.get_supabase", return_value=db), \
         patch("app.services.triage_service.status", return_value={"model_loaded": True}):
        checks = system_status_service.check_all()

    assert len(checks) == 8
    assert all(c["status"] == "operational" for c in checks)


def test_one_failing_check_does_not_affect_the_others():
    db = _healthy_db()
    # Database (and everything sharing its exact query shape: Incident/
    # Notification/Map/Realtime, which all call db.table(...).select(...)
    # .limit(1).execute()) fails -- Authentication, AI/NLP and File Storage
    # do not share that call shape, so they stay healthy and prove the
    # per-check isolation.
    db.table.return_value.select.return_value.limit.return_value.execute.side_effect = RuntimeError("connection refused")

    with patch("app.services.system_status_service.get_supabase", return_value=db), \
         patch("app.services.triage_service.status", return_value={"model_loaded": True}):
        checks = system_status_service.check_all()

    by_name = {c["name"]: c for c in checks}
    assert by_name["Database"]["status"] == "down"
    assert "connection refused" in by_name["Database"]["detail"]
    assert by_name["Authentication"]["status"] == "operational"
    assert by_name["AI/NLP Service"]["status"] == "operational"
    assert by_name["File Storage"]["status"] == "operational"


def test_ai_nlp_check_fails_when_triage_model_not_loaded():
    db = _healthy_db()
    with patch("app.services.system_status_service.get_supabase", return_value=db), \
         patch("app.services.triage_service.status", return_value={"model_loaded": False, "error": "artifact missing"}):
        checks = system_status_service.check_all()

    ai_check = next(c for c in checks if c["name"] == "AI/NLP Service")
    assert ai_check["status"] == "down"
    assert ai_check["detail"] == "artifact missing"


def test_router_forbidden_for_agency_admin():
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(AGENCY_ADMIN_UUID, "agency_admin")):
        resp = client.get("/system-status/", headers={"Authorization": "Bearer token"})
    assert resp.status_code == 403


def test_router_reports_all_operational_flag():
    db = _healthy_db()
    with patch("app.core.dependencies.get_supabase", return_value=_auth_db(PROVINCIAL_ADMIN_UUID, "provincial_admin")), \
         patch("app.services.system_status_service.get_supabase", return_value=db), \
         patch("app.services.triage_service.status", return_value={"model_loaded": True}):
        resp = client.get("/system-status/", headers={"Authorization": "Bearer token"})

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["all_operational"] is True
    assert len(body["checks"]) == 8


# ── /system-status/config ────────────────────────────────────────────────

def test_config_is_provincial_only_and_reads_real_values():
    from unittest.mock import patch
    from fastapi.testclient import TestClient
    from app.main import app
    from app.core.dependencies import require_provincial_admin
    from app.services import dispatch_service, responder_ack

    app.dependency_overrides[require_provincial_admin] = lambda: {"id": "u", "role": "provincial_admin"}
    try:
        resp = TestClient(app).get("/system-status/config")
    finally:
        app.dependency_overrides.pop(require_provincial_admin, None)

    assert resp.status_code == 200, resp.text
    body = resp.json()
    # Read from the code that enforces them, so they can never drift.
    assert body["limits"]["live_queue_max"] == dispatch_service.QUEUE_MAX
    assert body["limits"]["records_page_max"] == dispatch_service.HISTORY_PAGE_MAX
    assert body["ack_deadline_seconds"]["critical"] == responder_ack.deadline_seconds("critical")
    assert body["ack_deadline_seconds"]["unscored"] == responder_ack.deadline_seconds(None)
    assert 0 < body["triage"]["confidence_flag_threshold"] <= 1
    assert body["password_policy"]["min_length"] == 8


def test_config_is_refused_to_an_agency_admin():
    from unittest.mock import MagicMock, patch
    from fastapi.testclient import TestClient
    from app.main import app

    db = MagicMock()
    user = MagicMock(); user.id = "u"
    db.auth.get_user.return_value = MagicMock(user=user)
    prof = MagicMock()
    prof.data = {"id": "u", "email": "a@x.ph", "full_name": "A", "role": "agency_admin",
                 "approval_status": "not_required", "agency_id": "ag", "badge_id": None, "is_verified": True}
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = prof
    with patch("app.core.dependencies.get_supabase", return_value=db):
        resp = TestClient(app).get("/system-status/config", headers={"Authorization": "Bearer t"})
    assert resp.status_code == 403
