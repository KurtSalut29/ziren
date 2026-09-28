"""
POST /users/me/change-password — Task 18 of the Super Admin plan.

Covers (all as an Agency Admin, who since Settings v2 must supply the CURRENT
password too — the rule itself is pinned in test_account_security.py):
  - a valid new password calls admin.update_user_by_id with the CALLER's
    own id and succeeds
  - a weak password is rejected at the model boundary (422), before any
    Supabase call
  - a Supabase-side failure surfaces as 400, not a 500

Run: pytest tests/test_change_password.py -v
"""

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

USER_UUID = "00000000-0000-0000-0000-0000000000aa"


def _profile(user_id):
    return {
        "id": user_id, "email": "test@example.com", "full_name": "Test User",
        "role": "agency_admin", "approval_status": "not_required",
        "agency_id": None, "badge_id": None, "is_verified": True,
    }


def _auth_db(user_id):
    mock_user = MagicMock()
    mock_user.id = user_id
    mock_get = MagicMock()
    mock_get.user = mock_user
    profile = MagicMock()
    profile.data = _profile(user_id)
    db = MagicMock()
    db.auth.get_user.return_value = mock_get
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


def test_valid_password_change_targets_the_callers_own_id():
    db = _auth_db(USER_UUID)
    with patch("app.core.dependencies.get_supabase", return_value=db), \
         patch("app.routers.users.get_supabase", return_value=db), \
         patch("app.routers.users.new_supabase_client", return_value=MagicMock()), \
         patch("app.routers.users.audit_service.record"):
        resp = client.post(
            "/users/me/change-password",
            json={"new_password": "NewPassword1", "current_password": "OldPassword1"},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 200, resp.text
    db.auth.admin.update_user_by_id.assert_called_once_with(USER_UUID, {"password": "NewPassword1"})


def test_weak_password_is_422_before_any_supabase_call():
    db = _auth_db(USER_UUID)
    with patch("app.core.dependencies.get_supabase", return_value=db), \
         patch("app.routers.users.get_supabase", return_value=db), \
         patch("app.routers.users.new_supabase_client", return_value=MagicMock()), \
         patch("app.routers.users.audit_service.record"):
        resp = client.post(
            "/users/me/change-password",
            json={"new_password": "short", "current_password": "OldPassword1"},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 422
    assert not db.auth.admin.update_user_by_id.called


def test_supabase_failure_is_400_not_500():
    db = _auth_db(USER_UUID)
    db.auth.admin.update_user_by_id.side_effect = RuntimeError("service unavailable")
    with patch("app.core.dependencies.get_supabase", return_value=db), \
         patch("app.routers.users.get_supabase", return_value=db), \
         patch("app.routers.users.new_supabase_client", return_value=MagicMock()), \
         patch("app.routers.users.audit_service.record"):
        resp = client.post(
            "/users/me/change-password",
            json={"new_password": "NewPassword1", "current_password": "OldPassword1"},
            headers={"Authorization": "Bearer token"},
        )

    assert resp.status_code == 400
