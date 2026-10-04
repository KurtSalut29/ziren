"""
Phase 1 auth tests — 4-role system.

Mocks Supabase so no real network calls are made during CI.
Run with: pytest tests/test_auth.py -v
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# ── Shared test UUIDs ─────────────────────────────────────────
RESIDENT_UUID     = "00000000-0000-0000-0000-000000000001"
RESPONDER_UUID    = "00000000-0000-0000-0000-000000000002"
AGENCY_ADMIN_UUID = "00000000-0000-0000-0000-000000000003"
PROVINCIAL_ADMIN_UUID = "00000000-0000-0000-0000-000000000004"
AGENCY_UUID       = "aaaaaaaa-0000-0000-0000-000000000001"


# ── Mock builders ─────────────────────────────────────────────

def _mock_supabase_signup(user_id: str, role: str, agency_id=None, badge_id=None,
                           approval_status="not_required"):
    mock_user = MagicMock(); mock_user.id = user_id
    mock_session = MagicMock()
    mock_session.access_token  = "mock_access_token"
    mock_session.refresh_token = "mock_refresh_token"
    mock_result = MagicMock()
    mock_result.user = mock_user; mock_result.session = mock_session

    mock_profile = MagicMock()
    mock_profile.data = {
        "id": user_id, "email": "test@example.com",
        "full_name": "Test User", "role": role,
        "approval_status": approval_status,
        "agency_id": agency_id, "badge_id": badge_id,
        "is_verified": False, "created_at": "2025-01-01T00:00:00+00:00",
    }

    mock_db = MagicMock()
    mock_db.auth.sign_up.return_value = mock_result
    mock_db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = mock_profile
    mock_db.table.return_value.update.return_value \
        .eq.return_value.execute.return_value = MagicMock()
    return mock_db


def _mock_supabase_login(user_id: str, role: str, approval_status="not_required",
                          agency_id=None):
    mock_user = MagicMock(); mock_user.id = user_id
    mock_session = MagicMock()
    mock_session.access_token  = "mock_access_token"
    mock_session.refresh_token = "mock_refresh_token"
    mock_result = MagicMock()
    mock_result.user = mock_user; mock_result.session = mock_session

    mock_profile = MagicMock()
    mock_profile.data = {
        "id": user_id, "email": "test@example.com",
        "full_name": "Test User", "role": role,
        "approval_status": approval_status,
        "agency_id": agency_id, "badge_id": None,
        "is_verified": False,
        "created_at": "2025-01-01T00:00:00+00:00",
    }

    mock_db = MagicMock()
    mock_db.auth.sign_in_with_password.return_value = mock_result
    mock_db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = mock_profile
    return mock_db


def _mock_supabase_get_user(user_id: str, role: str, approval_status="not_required",
                             agency_id=None):
    mock_user = MagicMock(); mock_user.id = user_id
    mock_get = MagicMock(); mock_get.user = mock_user

    mock_profile = MagicMock()
    mock_profile.data = {
        "id": user_id, "email": "test@example.com",
        "full_name": "Test User", "role": role,
        "approval_status": approval_status,
        "agency_id": agency_id, "badge_id": None,
        "is_verified": True,
    }

    mock_db = MagicMock()
    mock_db.auth.get_user.return_value = mock_get
    mock_db.table.return_value.select.return_value \
        .eq.return_value.single.return_value.execute.return_value = mock_profile
    return mock_db


# ── Registration tests ────────────────────────────────────────

def test_register_resident_success():
    with patch("app.services.auth_service.get_supabase",
               return_value=_mock_supabase_signup(RESIDENT_UUID, "resident")):
        r = client.post("/auth/register", json={
            "email": "resident@example.com", "password": "SecurePass1",
            "full_name": "Juan dela Cruz", "role": "resident",
        })
    assert r.status_code == 201
    assert r.json()["user"]["role"] == "resident"
    assert r.json()["user"]["approval_status"] == "not_required"


def test_register_responder_success():
    with patch("app.services.auth_service.get_supabase",
               return_value=_mock_supabase_signup(
                   RESPONDER_UUID, "responder",
                   agency_id=AGENCY_UUID, badge_id="BFP-001",
                   approval_status="pending")):
        r = client.post("/auth/register", json={
            "email": "responder@bfp.gov.ph", "password": "SecurePass1",
            "full_name": "Pedro Responder", "role": "responder",
            "agency_id": AGENCY_UUID, "badge_id": "BFP-001",
        })
    assert r.status_code == 201
    assert r.json()["user"]["role"] == "responder"
    assert r.json()["user"]["approval_status"] == "pending"


def test_register_responder_missing_agency():
    """Responder without agency_id must be rejected."""
    r = client.post("/auth/register", json={
        "email": "responder@example.com", "password": "SecurePass1",
        "full_name": "No Agency", "role": "responder",
        # agency_id and badge_id intentionally omitted
    })
    assert r.status_code == 422


def test_register_responder_missing_badge_id():
    """Responder without badge_id must be rejected."""
    r = client.post("/auth/register", json={
        "email": "responder@example.com", "password": "SecurePass1",
        "full_name": "No Badge", "role": "responder",
        "agency_id": AGENCY_UUID,
        # badge_id intentionally omitted
    })
    assert r.status_code == 422


def test_register_agency_admin_self_register_blocked():
    """Agency Admin accounts cannot be self-registered."""
    r = client.post("/auth/register", json={
        "email": "admin@bfp.gov.ph", "password": "SecurePass1",
        "full_name": "BFP Admin", "role": "agency_admin",
        "agency_id": AGENCY_UUID,
    })
    assert r.status_code == 422


def test_register_provincial_admin_self_register_blocked():
    """Provincial Admin accounts cannot be self-registered."""
    r = client.post("/auth/register", json={
        "email": "provincialadmin@ziren.ph", "password": "SecurePass1",
        "full_name": "Provincial Admin", "role": "provincial_admin",
    })
    assert r.status_code == 422


def test_register_weak_password():
    r = client.post("/auth/register", json={
        "email": "test@example.com", "password": "weak",
        "full_name": "Test", "role": "resident",
    })
    assert r.status_code == 422


def test_register_invalid_email():
    r = client.post("/auth/register", json={
        "email": "not-an-email", "password": "SecurePass1",
        "full_name": "Test", "role": "resident",
    })
    assert r.status_code == 422


# ── Login tests ───────────────────────────────────────────────

def _patch_login(mock_db):
    """
    Patch BOTH client factories login_user uses.

    login_user reads the profile through get_supabase() but performs the
    sign-in through new_supabase_client() — the Week 2 Singleton fix, which
    deliberately keeps user sessions off the shared service-key client. These
    tests patched get_supabase alone, so the sign-in went out to the real
    Supabase project, failed, and was reshaped into a 401 by login_user's
    `except Exception`. Both seams have to be closed or the double covers only
    half the call.
    """
    return (
        patch("app.services.auth_service.get_supabase", return_value=mock_db),
        patch("app.services.auth_service.new_supabase_client", return_value=mock_db),
    )


def test_login_invalid_credentials():
    mock_db = MagicMock()
    mock_db.auth.sign_in_with_password.side_effect = Exception("Invalid credentials")
    shared, fresh = _patch_login(mock_db)
    with shared, fresh:
        r = client.post("/auth/login", json={
            "email": "nobody@example.com", "password": "WrongPass1",
        })
    assert r.status_code == 401
    assert "Invalid email or password" in r.json()["detail"]
    # The 401 must come from the mock's rejection, not from an unpatched
    # factory failing to reach the network. This is the assertion whose
    # absence let the seam drift go unnoticed.
    mock_db.auth.sign_in_with_password.assert_called_once()


def test_login_resident_success():
    mock_db = _mock_supabase_login(RESIDENT_UUID, "resident")
    shared, fresh = _patch_login(mock_db)
    with shared, fresh:
        r = client.post("/auth/login", json={
            "email": "resident@example.com", "password": "SecurePass1",
        })
    assert r.status_code == 200
    assert r.json()["user"]["role"] == "resident"


def test_login_pending_responder_returns_profile():
    """Pending responder can log in — app handles the pending screen client-side."""
    mock_db = _mock_supabase_login(
        RESPONDER_UUID, "responder", approval_status="pending")
    shared, fresh = _patch_login(mock_db)
    with shared, fresh:
        r = client.post("/auth/login", json={
            "email": "responder@bfp.gov.ph", "password": "SecurePass1",
        })
    assert r.status_code == 200
    assert r.json()["user"]["approval_status"] == "pending"


# ── RBAC tests ────────────────────────────────────────────────

def test_resident_cannot_dispatch():
    """Resident token must be rejected by dispatch endpoints (403)."""
    mock_db = _mock_supabase_get_user(RESIDENT_UUID, "resident")
    with patch("app.core.dependencies.get_supabase", return_value=mock_db):
        r = client.post(
            "/dispatch/queue/some-incident/assign",
            headers={"Authorization": "Bearer mock_token"},
            json={"responder_id": "x", "chosen_severity": "high", "severity_confirmed": True},
        )
    assert r.status_code == 403


def test_pending_responder_cannot_dispatch():
    """Pending responder must be blocked (403)."""
    mock_db = _mock_supabase_get_user(
        RESPONDER_UUID, "responder", approval_status="pending")
    with patch("app.core.dependencies.get_supabase", return_value=mock_db):
        r = client.post(
            "/dispatch/queue/some-incident/assign",
            headers={"Authorization": "Bearer mock_token"},
            json={"responder_id": "x", "chosen_severity": "high", "severity_confirmed": True},
        )
    assert r.status_code == 403


def test_agency_admin_can_dispatch():
    """Agency Admin reaches the dispatch endpoint — auth passes (not 403).

    We mock the service layer entirely — this test is only about whether
    the role-check middleware allows the request through, not dispatch logic.
    """
    mock_db = _mock_supabase_get_user(
        AGENCY_ADMIN_UUID, "agency_admin", agency_id=AGENCY_UUID)
    mock_result = {
        "incident_id": "some-incident",
        "responder_id": "x",
        "chosen_severity": "high",
        "was_override": False,
        "status": "dispatched",
        "dispatched_at": "2026-08-01T00:00:00+00:00",
    }
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.dispatch_service.assign_responder", return_value=mock_result):
        r = client.post(
            "/dispatch/queue/some-incident/assign",
            headers={"Authorization": "Bearer mock_token"},
            json={"responder_id": "x", "chosen_severity": "high", "severity_confirmed": True},
        )
    # Auth passes — role check allowed it through (200), not blocked (403)
    assert r.status_code == 200


def test_provincial_admin_cannot_dispatch():
    """A Provincial Admin is refused at the door, before assign_responder runs.

    This test used to assert the opposite, back when /dispatch took one
    dependency for both admin roles, and it passed for the whole time the
    behaviour was wrong.

    A Provincial Admin oversees every station of one agency_type across the
    province and belongs to none of them individually, which makes them the
    wrong person to dispatch in three concrete ways — no responders of their
    own to send, a NULL agency_id that dispatch_log has nowhere to put, and
    every agency-scope guard in dispatch_service written as
    `if role == "agency_admin"` and therefore skipped entirely for them
    unless explicitly given a provincial_admin branch too. See the module
    docstring in app/routers/dispatch.py.

    assign_responder stays patched so that a regression cannot pass by
    reaching the service and failing there for some unrelated reason: the
    assertion is that the ROLE CHECK stops it, and a call that got through
    would return the mocked 200.
    """
    mock_db = _mock_supabase_get_user(PROVINCIAL_ADMIN_UUID, "provincial_admin")
    mock_result = {
        "incident_id": "some-incident",
        "responder_id": "x",
        "chosen_severity": "high",
        "was_override": False,
        "status": "dispatched",
        "dispatched_at": "2026-08-01T00:00:00+00:00",
    }
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.dispatch_service.assign_responder", return_value=mock_result):
        r = client.post(
            "/dispatch/queue/some-incident/assign",
            headers={"Authorization": "Bearer mock_token"},
            json={"responder_id": "x", "chosen_severity": "high", "severity_confirmed": True},
        )
    assert r.status_code == 403


@pytest.mark.parametrize(
    "path, body",
    [
        ("/dispatch/queue/some-incident/override",
         {"chosen_severity": "high", "override_reason": "caller called back"}),
        ("/dispatch/queue/some-incident/resolve", {}),
        ("/dispatch/queue/some-incident/cancel", {"reason": "duplicate report"}),
    ],
)
def test_provincial_admin_cannot_commit_an_agency_to_anything(path, body):
    """The other three dispatch decisions, refused for the same reason.

    Assignment is the one the requirement named, but severity override,
    resolve and cancel are the same kind of act: each writes a dispatch_log
    row that says an agency decided something. A Provincial Admin has no
    single agency to put in that column.
    """
    mock_db = _mock_supabase_get_user(PROVINCIAL_ADMIN_UUID, "provincial_admin")
    with patch("app.core.dependencies.get_supabase", return_value=mock_db):
        r = client.post(path, headers={"Authorization": "Bearer mock_token"}, json=body)
    assert r.status_code == 403


@pytest.mark.parametrize(
    "path",
    ["/dispatch/queue", "/dispatch/activity", "/dispatch/history"],
)
def test_provincial_admin_still_sees_everything(path):
    """The other half of the rule, and the half a role check tends to break.

    "Provincial admin should not assign" is one sentence away from
    "provincial admin cannot use the dispatch console at all". Reads must
    stay open to them — oversight of their own agency_type, province-wide,
    is the entire role. (The SERVICE layer's own agency_type scoping is
    mocked out here entirely — this test is only about the role check, not
    about which incidents come back; see test_queue_ordering.py and
    dispatch_service's own tests for that.)
    """
    mock_db = _mock_supabase_get_user(PROVINCIAL_ADMIN_UUID, "provincial_admin")
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.dispatch_service.get_incident_queue", return_value=[]), \
         patch("app.services.dispatch_service.get_incident_activity", return_value=[]), \
         patch("app.services.dispatch_service.get_incident_history",
               return_value={"items": [], "total": 0}):
        r = client.get(path, headers={"Authorization": "Bearer mock_token"})
    assert r.status_code == 200


def test_dispatch_requires_the_severity_to_be_confirmed():
    """Evaluator finding #4: the severity is a recommendation, and a person
    states they checked it (and its reason) before a crew is sent."""
    mock_db = _mock_supabase_get_user(
        AGENCY_ADMIN_UUID, "agency_admin", agency_id=AGENCY_UUID)
    with patch("app.core.dependencies.get_supabase", return_value=mock_db), \
         patch("app.services.dispatch_service.assign_responder") as assign:
        r = client.post(
            "/dispatch/queue/some-incident/assign",
            headers={"Authorization": "Bearer mock_token"},
            json={"responder_id": "x", "chosen_severity": "high"},
        )
    assert r.status_code == 422
    assert "severity" in r.json()["detail"].lower()
    assert not assign.called
