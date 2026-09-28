"""
Regression tests for the Agency Admin access-request flow.

Background — the defect these guard against:

Week 1 added `RegisterRequest.block_privileged_self_registration`, which
rejects role='agency_admin' at POST /auth/register. That validator is correct
and closed a real privilege-escalation hole.

But the dashboard's "Request Access" page posted to exactly that endpoint with
role='agency_admin'. So from the moment the fix landed, every applicant saw:

    Self-registration as 'agency_admin' is not permitted.

The page had always been wrong — it promised "a Super Admin will review your
request" while attempting to mint a privileged account immediately. The
security fix only made the contradiction visible. Nobody noticed because the
suite tested the validator, not the flow the dashboard actually used.

The lesson worth keeping: a fix that makes a previously-succeeding call fail
needs its callers checked. Rejecting the request was the correct behaviour and
still broke a user-facing page.
"""

import inspect
import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]


# ── The privileged-role block must stay ───────────────────────────────────────

def test_register_still_rejects_agency_admin():
    """The Week 1 fix is not being loosened to repair the page."""
    from app.models.user import RegisterRequest

    with pytest.raises(Exception) as exc:
        RegisterRequest(
            email="admin@bfp.gov.ph",
            password="Password1",
            full_name="Test Admin",
            role="agency_admin",
            agency_id="a0000001-0000-0000-0000-000000000001",
        )
    assert "not permitted" in str(exc.value)


# ── The dashboard must no longer call it that way ─────────────────────────────

def test_dashboard_signup_does_not_post_privileged_role():
    """
    The page must not send role='agency_admin' to /auth/register. This is the
    exact line that produced the error message users were seeing.
    """
    page = REPO / "ziren_dashboard" / "app" / "(auth)" / "signup" / "page.tsx"
    if not page.exists():
        pytest.skip("ziren_dashboard not present in this checkout")

    src = page.read_text(encoding="utf-8")

    # Strip comments first: the file explains the old bug in prose, and a
    # naive substring search would match the explanation rather than the code.
    code = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)

    assert "role:" not in code, (
        "Request Access must not submit a role at all. The account is "
        "provisioned by a Provincial Admin via /users/provincial/agency-admins."
    )
    assert "agency_admin" not in code
    assert "/auth/access-request" in code, (
        "Request Access should post to /auth/access-request."
    )
    assert "/auth/register" not in code


def test_dashboard_signup_collects_no_password():
    """
    A request is not an account, so it must not collect a password. The
    applicant sets one from the Supabase invite on /accept-invite.
    """
    page = REPO / "ziren_dashboard" / "app" / "(auth)" / "signup" / "page.tsx"
    if not page.exists():
        pytest.skip("ziren_dashboard not present in this checkout")

    src = page.read_text(encoding="utf-8")
    assert "Set a password" not in src
    assert "autoComplete=\"new-password\"" not in src


# ── The new endpoint's contract ───────────────────────────────────────────────

def test_access_request_model_has_no_password_or_role():
    """Nothing about this payload may confer privilege."""
    from app.models.user import AccessRequestCreate

    fields = set(AccessRequestCreate.model_fields)
    assert "password" not in fields
    assert "role" not in fields
    assert {"full_name", "email", "agency_id"} <= fields


def test_access_request_creates_no_account():
    """
    The service must write only to access_requests. If it ever touches
    auth.users or public.users it has become the very thing the validator
    blocks.
    """
    from app.services import auth_service

    src = inspect.getsource(auth_service.create_access_request)

    assert 'table("access_requests")' in src
    assert "auth.admin" not in src, "An access request must not create an auth user."
    assert "sign_up" not in src
    assert 'table("users")' not in src


def test_access_request_response_does_not_leak_existing_applicants():
    """
    A duplicate submission returns the same message as a fresh one. Saying
    "that email already applied" would let an anonymous caller enumerate which
    officials have requested access.
    """
    from app.services import auth_service

    src = inspect.getsource(auth_service.create_access_request)
    assert "generic" in src
    assert "duplicate_ignored" in src


def test_endpoint_is_rate_limited():
    from app.routers import auth as auth_router

    src = inspect.getsource(auth_router)
    block = src[src.index("/access-request"):src.index("def request_access")]
    assert "@limiter.limit" in block


# ── Migration ─────────────────────────────────────────────────────────────────

def test_access_requests_table_grants_nothing_to_anon():
    """
    Submissions go through the API, which rate-limits them. A public INSERT
    policy would hand anyone unbounded writes to this table.
    """
    sql = (
        REPO / "ziren_backend" / "supabase" / "migrations"
        / "016_access_requests.sql"
    ).read_text(encoding="utf-8")

    assert "ENABLE ROW LEVEL SECURITY" in sql
    assert "FOR INSERT" not in sql, (
        "No INSERT policy: anon must not write directly to access_requests."
    )
    assert "get_my_role() = 'super_admin'" in sql


def test_one_pending_request_per_email():
    sql = (
        REPO / "ziren_backend" / "supabase" / "migrations"
        / "016_access_requests.sql"
    ).read_text(encoding="utf-8")

    assert "access_requests_one_pending_per_email" in sql
    # Scoped to pending so a rejected applicant can reapply.
    assert "WHERE status = 'pending'" in sql


# ── The review half must exist ────────────────────────────────────────────────

def test_provincial_admin_can_list_access_requests():
    """
    The intake endpoint shipped without this, so requests were stored and never
    surfaced — an applicant waited on a decision no Provincial Admin could see
    was pending. A write path with no read path is an unfinished feature.
    """
    from app.routers import users as users_router

    src = inspect.getsource(users_router)
    assert '@router.get("/provincial/access-requests")' in src
    assert '@router.patch("/provincial/access-requests/{request_id}")' in src


def test_approval_reuses_the_single_provisioning_path():
    """
    Approving must call create_agency_admin rather than inserting a user row
    itself. One sanctioned path to an agency_admin account means the invite
    email and the audit log cannot be skipped by a second implementation.
    """
    from app.routers import users as users_router

    src = inspect.getsource(users_router.review_access_request)
    assert "create_agency_admin(" in src
    assert 'table("users").insert' not in src


def test_request_marked_approved_only_after_account_exists():
    """
    The status update must follow provisioning, so a failed invite leaves the
    request pending and retryable instead of silently closed.
    """
    from app.routers import users as users_router

    src = inspect.getsource(users_router.review_access_request)
    assert src.index("create_agency_admin(") < src.index('"status": "approved"')


def test_already_reviewed_request_cannot_be_actioned_twice():
    from app.routers import users as users_router

    src = inspect.getsource(users_router.review_access_request)
    assert "already" in src and "HTTP_409_CONFLICT" in src


# ── Approving an already-registered email ─────────────────────────────────────

def test_existing_account_is_detected_before_the_invite():
    """
    Supabase answers a duplicate invite with "A user with this email address
    has already been registered" — true, and useless to a reviewer. It names
    no account, no role, and no next step. The check must happen first, in
    terms the Super Admin can act on.
    """
    from app.routers import users as users_router

    src = inspect.getsource(users_router.create_agency_admin)
    pre_check = src.index('.ilike("email"')
    invite = src.index("invite_user_by_email")
    assert pre_check < invite, "Check for an existing account before inviting."
    assert "HTTP_409_CONFLICT" in src


def test_orphaned_auth_user_gets_a_specific_message():
    """
    An auth.users row can exist with no public.users profile, so the profile
    pre-check cannot see it. That case must still explain itself rather than
    echoing the raw Supabase string.
    """
    from app.routers import users as users_router

    src = inspect.getsource(users_router.create_agency_admin)
    assert "already been registered" in src
    assert "half-provisioned" in src


def test_public_endpoint_does_not_reveal_existing_accounts():
    """
    The account-exists check belongs to the Super Admin review path only.
    Surfacing it at the public endpoint would let an anonymous caller
    enumerate which officials already hold accounts.
    """
    from app.services import auth_service

    src = inspect.getsource(auth_service.create_access_request)
    assert 'table("users")' not in src
    assert "already has a Ziren account" not in src
