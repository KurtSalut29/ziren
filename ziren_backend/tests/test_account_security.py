"""Account security — what Settings → Account & Security, Login & Devices and
Privacy stand on.

Properties worth pinning:

  1. An ADMIN cannot change their password on a bearer token alone: they must
     supply the current one, it is verified, and a wrong or unchanged one is a
     400 before anything is written. Residents and responders (mobile) are
     unchanged.
  2. Sign-ins and password changes of admin accounts are audited; a resident's
     are not.
  3. /me/activity is the caller's OWN trail and nobody else's — there is no way
     to widen it.
  4. Revoking sessions passes the caller's own token and the requested scope
     through to Supabase, and is audited.
  5. Best-effort lookups (/me/security) degrade to null fields rather than
     failing the panel.

Run with: pytest tests/test_account_security.py -v
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.routers.auth import _record_admin_sign_in

client = TestClient(app)

USER_UUID = "00000000-0000-0000-0000-0000000000aa"
AUTH = {"Authorization": "Bearer my-own-token"}


def _profile(role="agency_admin", agency_type="BFP"):
    return {
        "id": USER_UUID, "email": "admin@example.com", "full_name": "Test Admin",
        "role": role, "approval_status": "not_required",
        "agency_id": "ag-1", "agency_type": agency_type, "badge_id": None,
        "is_verified": True, "created_at": "2026-01-01T00:00:00+00:00",
    }


def _db(role="agency_admin", agency_type="BFP"):
    """A Supabase double that authenticates the caller as USER_UUID."""
    auth_user = MagicMock()
    auth_user.id = USER_UUID
    got = MagicMock()
    got.user = auth_user
    profile = MagicMock()
    profile.data = _profile(role, agency_type)
    db = MagicMock()
    db.auth.get_user.return_value = got
    db.table.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = profile
    return db


def _call(method, path, db, *, json=None, verifier=None, headers=AUTH):
    """Run a request with every Supabase seam patched, returning (response, audit_mock)."""
    verifier = verifier or MagicMock()
    with patch("app.core.dependencies.get_supabase", return_value=db), \
         patch("app.routers.users.get_supabase", return_value=db), \
         patch("app.routers.users.new_supabase_client", return_value=verifier), \
         patch("app.routers.users.audit_service.record") as record:
        resp = client.request(method, path, json=json, headers=headers)
    return resp, record, verifier


# ── 1. Changing a password ───────────────────────────────────────────────

class TestAdminMustProveTheOldPassword:
    def test_no_current_password_is_refused_before_anything_is_written(self):
        db = _db()
        resp, record, verifier = _call(
            "POST", "/users/me/change-password", db, json={"new_password": "NewPassword1"},
        )
        assert resp.status_code == 400
        assert "current password" in resp.json()["detail"].lower()
        assert not db.auth.admin.update_user_by_id.called
        assert not verifier.auth.sign_in_with_password.called

    def test_a_wrong_current_password_is_refused(self):
        db = _db()
        verifier = MagicMock()
        verifier.auth.sign_in_with_password.side_effect = RuntimeError("Invalid login credentials")
        resp, record, _ = _call(
            "POST", "/users/me/change-password", db, verifier=verifier,
            json={"new_password": "NewPassword1", "current_password": "wrong-guess"},
        )
        assert resp.status_code == 400
        assert "incorrect" in resp.json()["detail"].lower()
        assert not db.auth.admin.update_user_by_id.called
        record.assert_not_called()

    def test_the_current_password_is_checked_against_the_callers_own_email(self):
        db = _db()
        resp, _, verifier = _call(
            "POST", "/users/me/change-password", db,
            json={"new_password": "NewPassword1", "current_password": "OldPassword1"},
        )
        assert resp.status_code == 200, resp.text
        verifier.auth.sign_in_with_password.assert_called_once_with(
            {"email": "admin@example.com", "password": "OldPassword1"}
        )

    def test_a_correct_current_password_changes_it_and_audits_it(self):
        db = _db()
        resp, record, _ = _call(
            "POST", "/users/me/change-password", db,
            json={"new_password": "NewPassword1", "current_password": "OldPassword1"},
        )
        assert resp.status_code == 200
        db.auth.admin.update_user_by_id.assert_called_once_with(USER_UUID, {"password": "NewPassword1"})
        assert record.call_args.kwargs["action"] == "auth.password_changed"
        # The verification used a throwaway client, so the shared one's session
        # is untouched.
        assert not db.auth.sign_in_with_password.called

    def test_reusing_the_same_password_is_refused(self):
        db = _db()
        resp, _, _ = _call(
            "POST", "/users/me/change-password", db,
            json={"new_password": "SamePassword1", "current_password": "SamePassword1"},
        )
        assert resp.status_code == 400
        assert "different" in resp.json()["detail"].lower()
        assert not db.auth.admin.update_user_by_id.called

    def test_provincial_admin_is_held_to_the_same_rule(self):
        db = _db(role="provincial_admin")
        resp, _, _ = _call(
            "POST", "/users/me/change-password", db, json={"new_password": "NewPassword1"},
        )
        assert resp.status_code == 400


class TestMobileUsersAreUnchanged:
    @pytest.mark.parametrize("role", ["resident", "responder"])
    def test_no_current_password_needed(self, role):
        db = _db(role=role, agency_type=None)
        resp, record, verifier = _call(
            "POST", "/users/me/change-password", db, json={"new_password": "NewPassword1"},
        )
        assert resp.status_code == 200, resp.text
        db.auth.admin.update_user_by_id.assert_called_once()
        assert not verifier.auth.sign_in_with_password.called
        # A resident's password change is not an admin audit event.
        record.assert_not_called()


# ── 2. Sign-in auditing ──────────────────────────────────────────────────

def _login_result(role):
    result = MagicMock()
    result.user.role = MagicMock(value=role)
    result.user.id = USER_UUID
    result.user.full_name = "Test Admin"
    result.user.email = "admin@example.com"
    result.user.agency_type = "BFP"
    return result


def _request(forwarded=None):
    req = MagicMock()
    headers = {"user-agent": "Mozilla/5.0 (Windows NT 10.0) Chrome/120"}
    if forwarded:
        headers["x-forwarded-for"] = forwarded
    req.headers.get.side_effect = lambda k, d=None: headers.get(k, d)
    req.client.host = "10.1.2.3"
    return req


class TestSignInAudit:
    @pytest.mark.parametrize("role", ["agency_admin", "provincial_admin"])
    def test_admin_sign_ins_are_recorded(self, role):
        with patch("app.routers.auth.audit_service.record") as record:
            _record_admin_sign_in(_request(), _login_result(role))
        kw = record.call_args.kwargs
        assert kw["action"] == "auth.login"
        assert kw["actor"]["id"] == USER_UUID
        assert kw["agency_type"] == "BFP"
        assert kw["metadata"]["user_agent"].startswith("Mozilla")

    @pytest.mark.parametrize("role", ["resident", "responder"])
    def test_a_residents_login_is_not(self, role):
        with patch("app.routers.auth.audit_service.record") as record:
            _record_admin_sign_in(_request(), _login_result(role))
        record.assert_not_called()

    def test_the_forwarded_address_wins_over_the_proxy_own(self):
        with patch("app.routers.auth.audit_service.record") as record:
            _record_admin_sign_in(_request(forwarded="203.0.113.7, 10.0.0.1"), _login_result("agency_admin"))
        assert record.call_args.kwargs["metadata"]["ip"] == "203.0.113.7"

    def test_without_a_forwarded_header_the_connection_address_is_used(self):
        with patch("app.routers.auth.audit_service.record") as record:
            _record_admin_sign_in(_request(), _login_result("agency_admin"))
        assert record.call_args.kwargs["metadata"]["ip"] == "10.1.2.3"


# ── 3. Activity is the caller's own ──────────────────────────────────────

def _activity_db(rows):
    db = _db()
    q = MagicMock()
    for name in ("select", "eq", "order", "limit", "like"):
        getattr(q, name).return_value = q
    q.execute.return_value = MagicMock(data=rows)
    real_table = db.table

    def table(name):
        return q if name == "audit_logs" else real_table(name)

    db.table = table
    return db, q


class TestActivityIsOwnOnly:
    def test_it_is_filtered_to_the_callers_own_id(self):
        db, q = _activity_db([{"id": "1", "action": "auth.login"}])
        resp, _, _ = _call("GET", "/users/me/activity", db)
        assert resp.status_code == 200
        assert resp.json()["items"][0]["action"] == "auth.login"
        eq_calls = [c.args for c in q.eq.call_args_list]
        assert ("actor_id", USER_UUID) in eq_calls

    def test_no_query_parameter_can_change_whose_trail_it_is(self):
        db, q = _activity_db([])
        _call("GET", f"/users/me/activity?actor_id=someone-else&user_id=x", db)
        eq_calls = [c.args for c in q.eq.call_args_list]
        assert ("actor_id", USER_UUID) in eq_calls
        assert not any(args[1] == "someone-else" for args in eq_calls)

    def test_auth_kind_narrows_to_security_events(self):
        db, q = _activity_db([])
        _call("GET", "/users/me/activity?kind=auth", db)
        q.like.assert_called_once_with("action", "auth.%")

    def test_the_default_shows_everything_of_their_own(self):
        db, q = _activity_db([])
        _call("GET", "/users/me/activity", db)
        q.like.assert_not_called()

    def test_the_page_size_is_capped(self):
        db, _ = _activity_db([])
        resp, _, _ = _call("GET", "/users/me/activity?limit=5000", db)
        assert resp.status_code == 422


# ── 4. Revoking sessions ─────────────────────────────────────────────────

class TestRevokeSessions:
    @pytest.mark.parametrize("scope", ["others", "global"])
    def test_the_callers_own_token_and_the_scope_go_to_supabase(self, scope):
        db = _db()
        resp, record, _ = _call("POST", "/users/me/sessions/revoke", db, json={"scope": scope})
        assert resp.status_code == 200, resp.text
        db.auth.admin.sign_out.assert_called_once_with("my-own-token", scope)
        assert record.call_args.kwargs["action"] == "auth.sessions_revoked"

    def test_an_unknown_scope_is_refused(self):
        db = _db()
        resp, _, _ = _call("POST", "/users/me/sessions/revoke", db, json={"scope": "everyone-else"})
        assert resp.status_code == 422
        assert not db.auth.admin.sign_out.called

    def test_a_supabase_failure_is_400_not_500(self):
        db = _db()
        db.auth.admin.sign_out.side_effect = RuntimeError("down")
        resp, _, _ = _call("POST", "/users/me/sessions/revoke", db, json={"scope": "others"})
        assert resp.status_code == 400


# ── 5. Security overview degrades, it does not fail ──────────────────────

class TestSecurityOverview:
    def test_it_reports_what_supabase_knows(self):
        db = _db()
        last = MagicMock()
        last.isoformat.return_value = "2026-09-19T03:00:00+00:00"
        db.auth.admin.get_user_by_id.return_value.user = MagicMock(
            email_confirmed_at="2026-01-01", last_sign_in_at=last,
        )
        resp, _, _ = _call("GET", "/users/me/security", db)
        body = resp.json()
        assert resp.status_code == 200
        assert body["email_confirmed"] is True
        assert body["last_sign_in_at"] == "2026-09-19T03:00:00+00:00"
        assert body["email"] == "admin@example.com"

    def test_a_failed_lookup_leaves_nulls_and_still_answers(self):
        db = _db()
        db.auth.admin.get_user_by_id.side_effect = RuntimeError("auth down")
        resp, _, _ = _call("GET", "/users/me/security", db)
        assert resp.status_code == 200
        assert resp.json()["email_confirmed"] is None
        assert resp.json()["last_sign_in_at"] is None


# ── 6. Support contacts ──────────────────────────────────────────────────

class TestSupportContacts:
    def test_an_agency_admin_is_pointed_at_their_own_types_provincial_admins(self):
        db = _db()
        people_q = MagicMock()
        for name in ("select", "eq", "limit"):
            getattr(people_q, name).return_value = people_q
        people_q.execute.return_value = MagicMock(data=[{"full_name": "P. Admin", "email": "p@x.ph", "phone_number": None}])
        agency_q = MagicMock()
        for name in ("select", "eq", "limit"):
            getattr(agency_q, name).return_value = agency_q
        agency_q.execute.return_value = MagicMock(data=[{"name": "BFP Naval", "contact_number": "053-1"}])
        real = db.table

        # The users table is also what authenticates the caller, so route by call
        # order: the first users query is the auth lookup, the second is ours.
        calls = {"users": 0}

        def table(name):
            if name == "agencies":
                return agency_q
            if name == "users":
                calls["users"] += 1
                return real(name) if calls["users"] == 1 else people_q
            return real(name)

        db.table = table
        resp, _, _ = _call("GET", "/users/me/support-contacts", db)
        assert resp.status_code == 200, resp.text
        assert resp.json()["provincial_admins"][0]["full_name"] == "P. Admin"
        assert resp.json()["agency"]["name"] == "BFP Naval"
        eq_calls = [c.args for c in people_q.eq.call_args_list]
        assert ("role", "provincial_admin") in eq_calls
        assert ("agency_type", "BFP") in eq_calls

    def test_a_provincial_admin_has_no_one_above_them(self):
        db = _db(role="provincial_admin")
        agency_q = MagicMock()
        for name in ("select", "eq", "limit"):
            getattr(agency_q, name).return_value = agency_q
        agency_q.execute.return_value = MagicMock(data=[])
        real = db.table
        db.table = lambda n: agency_q if n == "agencies" else real(n)
        resp, _, _ = _call("GET", "/users/me/support-contacts", db)
        assert resp.status_code == 200
        assert resp.json()["provincial_admins"] == []
