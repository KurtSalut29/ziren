"""
Password reset from an emailed link.

The old flow sent the email with no redirect, so the link opened the project's
Site URL with the recovery tokens in the fragment, and the dashboard had no page
that read them: the link went nowhere. Covered here:

  * the email is aimed at the dashboard's /reset-password page
  * the reset endpoint accepts a token that came from an emailed link and refuses
    one from an ordinary password sign-in (which would sidestep change-password's
    current-password rule)
  * the password policy is the same one registration enforces
"""

import base64
import json
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.core.config import settings
from app.main import app
from app.services import auth_service

client = TestClient(app)

USER_ID = "00000000-0000-0000-0000-0000000000bb"


def _jwt(*methods):
    def b64(obj):
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()

    payload = {"sub": USER_ID, "amr": [{"method": m, "timestamp": 1} for m in methods]}
    return f"{b64({'alg': 'HS256'})}.{b64(payload)}.sig"


def _db(user_ok=True):
    db = MagicMock()
    db.auth.get_user.return_value = MagicMock(user=MagicMock(id=USER_ID)) if user_ok else None
    return db


# ── the email ────────────────────────────────────────────────────────────────

def test_the_reset_email_points_at_the_dashboards_reset_page():
    db = _db()
    with patch("app.services.auth_service.get_supabase", return_value=db):
        auth_service.request_password_reset("person@example.com")

    email, options = db.auth.reset_password_for_email.call_args.args
    assert email == "person@example.com"
    assert options["redirect_to"] == settings.reset_password_url
    assert settings.reset_password_url.endswith("/reset-password")


def test_asking_for_a_reset_never_reveals_whether_the_account_exists():
    db = _db()
    db.auth.reset_password_for_email.side_effect = RuntimeError("user not found")
    with patch("app.services.auth_service.get_supabase", return_value=db):
        result = auth_service.request_password_reset("nobody@example.com")
    assert "If an account exists" in result.message


# ── the token ────────────────────────────────────────────────────────────────

def test_a_recovery_link_token_sets_the_password():
    db = _db()
    with patch("app.services.auth_service.get_supabase", return_value=db):
        result = auth_service.reset_password(_jwt("otp"), "NewPassw0rd")

    db.auth.admin.update_user_by_id.assert_called_once_with(USER_ID, {"password": "NewPassw0rd"})
    assert "updated" in result.message.lower()


def test_an_ordinary_sign_in_token_cannot_be_used_to_reset():
    db = _db()
    with patch("app.services.auth_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            auth_service.reset_password(_jwt("password"), "NewPassw0rd")
    assert exc.value.status_code == 400
    db.auth.admin.update_user_by_id.assert_not_called()


def test_an_expired_or_forged_token_is_rejected():
    db = _db()
    db.auth.get_user.side_effect = RuntimeError("invalid JWT")
    with patch("app.services.auth_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            auth_service.reset_password(_jwt("otp"), "NewPassw0rd")
    assert exc.value.status_code == 400
    assert "expired" in exc.value.detail


def test_a_token_that_is_not_a_jwt_is_rejected():
    db = _db()
    with patch("app.services.auth_service.get_supabase", return_value=db):
        with pytest.raises(HTTPException) as exc:
            auth_service.reset_password("not-a-jwt", "NewPassw0rd")
    assert exc.value.status_code == 400


# ── the route and the password policy ────────────────────────────────────────

@pytest.mark.parametrize("weak", ["short1A", "alllowercase1", "NoDigitsHere"])
def test_a_weak_password_is_refused_before_any_supabase_call(weak):
    with patch("app.services.auth_service.get_supabase") as get_db:
        response = client.post("/auth/reset-password", json={"access_token": _jwt("otp"), "password": weak})
    assert response.status_code == 422
    get_db.assert_not_called()


def test_the_route_resets_with_a_valid_link_token():
    db = _db()
    with patch("app.services.auth_service.get_supabase", return_value=db):
        response = client.post(
            "/auth/reset-password", json={"access_token": _jwt("otp"), "password": "NewPassw0rd"},
        )
    assert response.status_code == 200
    assert "updated" in response.json()["message"].lower()
