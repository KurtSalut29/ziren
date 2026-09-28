"""
/users — User profile and management endpoints.

Routes:
  GET  /me                                  — Any role: fetch own full profile
  PATCH /me                                 — Any role: update own non-sensitive profile fields
  GET  /agency/responders                   — Agency Admin (own agency) / Provincial Admin (own agency_type): list Responders
  PATCH /agency/responders/{id}/approval    — Agency Admin / Provincial Admin: approve or reject a Responder
  GET  /agency/responders/{id}              — Agency Admin / Provincial Admin: view a single Responder profile
  GET  /provincial/agency-admins            — Provincial Admin: list Agency Admin accounts of their own agency_type
  POST /provincial/agency-admins            — Provincial Admin: create an Agency Admin account (own agency_type)
  PATCH /provincial/agency-admins/{id}      — Provincial Admin: deactivate or reassign an Agency Admin (own agency_type)
  GET  /provincial/directory                — Provincial Admin: account directory (own agency_type, all roles, filterable)
  GET  /barangays                           — Admin: barangay reference list for place filters
  GET  /provincial/counts                   — Provincial Admin: standing totals (own agency_type; counts only, no rows)
  POST /verification/residents/bulk         — Admin: one decision applied to many residents
"""

from datetime import datetime, timedelta, timezone
from typing import Literal

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, EmailStr, field_validator
from typing import Optional

from app.core.config import settings
from app.core.dependencies import assert_agency_scope, get_current_user, require_role
from app.models.user import UserProfile, UpdateProfileRequest, MessageResponse
from app.services import user_service, audit_service
from app.core.rate_limit import limiter
from app.db.supabase_client import get_supabase, new_supabase_client

log = structlog.get_logger()
router = APIRouter()

_admin_only            = Depends(require_role("agency_admin", "provincial_admin"))
_provincial_admin_only = Depends(require_role("provincial_admin"))


def _agency_ids_for_type(db, agency_type: str | None) -> list[str]:
    """
    Two-step lookup: a Provincial Admin's agency_type -> every `agencies.id`
    it covers. Same pattern as dispatch_service._agency_ids_for_type and
    stations.py's list_stations — this router's agency_admin/responder rows
    key off agency_id, not agency_type.
    """
    if not agency_type:
        return []
    rows = db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
    return [row["id"] for row in rows]


# ── Self-service profile ──────────────────────────────────────

@router.get("/me", response_model=UserProfile)
def get_my_profile(
    current_user: dict = Depends(get_current_user),
):
    """
    Return the authenticated user's full profile.
    Includes Phase 10.5 fields: phone, barangay, preferred_language,
    notification preferences, emergency contacts, availability (Responders).
    """
    return user_service.get_my_profile(user_id=str(current_user["id"]))


@router.patch("/me", response_model=UserProfile)
def update_my_profile(
    body: UpdateProfileRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Update the authenticated user's own profile fields.

    Only non-sensitive fields are updatable here:
      full_name, phone_number, barangay, municipality_address,
      preferred_language, push_notifications_enabled,
      emergency_contact_name, emergency_contact_number.

    Role, approval_status, agency_id, badge_id are admin-only — this
    endpoint cannot change them, and the service layer enforces this.
    """
    return user_service.update_my_profile(
        user_id=str(current_user["id"]),
        request=body,
    )


class ChangePasswordRequest(BaseModel):
    new_password: str
    # Required of the two admin roles (see change_my_password). Optional in the
    # model because a resident or responder on the mobile app changes theirs
    # without it, and this endpoint has always served them too.
    current_password: str | None = None

    @field_validator("new_password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        # Same rule RegisterRequest enforces at signup — one password policy,
        # not two that could quietly drift apart.
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters.")
        if not any(c.isupper() for c in v):
            raise ValueError("Password must contain at least one uppercase letter.")
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit.")
        return v


_ADMIN_ROLES = ("agency_admin", "provincial_admin")


def _client_context(request: Request) -> dict:
    """Where a request came from, for the audit trail. Informational only.

    X-Forwarded-For is whatever the caller (or the dashboard's own proxy) put
    there, so it is a label for a person reading the log, not a fact to trust.
    """
    forwarded = request.headers.get("x-forwarded-for")
    ip = forwarded.split(",")[0].strip() if forwarded else (
        request.client.host if request.client else None
    )
    return {"ip": ip, "user_agent": request.headers.get("user-agent")}


def _record_security_event(request: Request, user: dict, action: str, label: str | None = None) -> None:
    """Write an auth.* audit row for an ADMIN account. Never raises.

    Admin accounts only: those are the ones whose sign-ins and password changes
    matter to whoever audits the console. A resident's every login on the mobile
    app would bury the log for no reader.
    """
    if user.get("role") not in _ADMIN_ROLES:
        return
    audit_service.record(
        actor=user,
        action=action,
        target_type="session",
        target_id=str(user.get("id")),
        target_label=label or user.get("email"),
        metadata=_client_context(request),
        agency_type=user.get("agency_type"),
    )


@router.post("/me/change-password", response_model=MessageResponse)
@limiter.limit("5/minute")
def change_my_password(
    request: Request,
    body: ChangePasswordRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Any role: set a new password for the authenticated account.

    ADMINS MUST PROVE THEY KNOW THE OLD ONE. This endpoint used to accept the
    bearer token alone as proof of identity, which means anyone holding a
    session — a borrowed or unlocked workstation, a token lifted from a browser
    — could set a new password and lock the real owner out, with nothing asked.
    For an Agency or Provincial Admin, who can dispatch crews, that is exactly
    the account worth protecting. The current password is checked against
    Supabase with a throwaway client (so it cannot disturb the shared one's
    session) and a wrong guess is a 400. Rate-limited, since this is now a
    password-guessing surface for someone holding a stolen token.

    Residents and responders on the mobile app are unchanged: it does not send
    the current password, and requiring it would break them.

    Uses the admin API with the caller's OWN id (never any other user's), the
    identical call accept_invite already makes to set a password from an invite.
    """
    if current_user.get("role") in _ADMIN_ROLES:
        if not body.current_password:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Enter your current password to change it.",
            )
        if body.current_password == body.new_password:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your new password must be different from the current one.",
            )
        try:
            new_supabase_client().auth.sign_in_with_password(
                {"email": current_user.get("email"), "password": body.current_password}
            )
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your current password is incorrect.",
            )

    db = get_supabase()
    try:
        db.auth.admin.update_user_by_id(str(current_user["id"]), {"password": body.new_password})
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not change password: {e}",
        )
    _record_security_event(request, current_user, "auth.password_changed")
    return MessageResponse(message="Password changed.")


# ── Account security: overview, activity, sessions ───────────────────────

@router.get("/me/security")
def get_my_security(current_user: dict = Depends(get_current_user)):
    """
    The facts a security check-up needs, for the caller's own account.

    From Supabase Auth: whether the email is confirmed and when this account
    last signed in. From the audit trail: when the password was last changed —
    Supabase does not record that, so it is read from the auth.password_changed
    rows this app writes, and is null for a password set before they existed.
    Every part is best-effort: a lookup that fails leaves its field null instead
    of failing the panel.
    """
    db = get_supabase()
    uid = str(current_user["id"])
    out: dict = {
        "email": current_user.get("email"),
        "role": current_user.get("role"),
        "email_confirmed": None,
        "last_sign_in_at": None,
        "account_created_at": current_user.get("created_at"),
        "last_password_change": None,
    }
    try:
        auth_user = db.auth.admin.get_user_by_id(uid).user
        out["email_confirmed"] = bool(getattr(auth_user, "email_confirmed_at", None))
        last = getattr(auth_user, "last_sign_in_at", None)
        out["last_sign_in_at"] = last.isoformat() if hasattr(last, "isoformat") else last
    except Exception:
        log.warning("users.security_lookup_failed", user_id=uid, exc_info=True)
    try:
        rows = (
            db.table("audit_logs")
            .select("created_at")
            .eq("actor_id", uid)
            .eq("action", "auth.password_changed")
            .order("created_at", desc=True)
            .limit(1)
            .execute()
            .data
        ) or []
        out["last_password_change"] = rows[0]["created_at"] if rows else None
    except Exception:
        log.warning("users.password_audit_lookup_failed", user_id=uid, exc_info=True)
    return out


@router.get("/me/activity")
def get_my_activity(
    kind: Literal["all", "auth"] = Query("all", description="`auth` = sign-ins and security events only"),
    limit: int = Query(30, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    """
    The caller's OWN recorded activity, newest first — and only theirs.

    Every row is filtered to actor_id = the caller; there is no parameter that
    widens it, so this cannot become a way to read anyone else's trail. It is
    what Login & Devices shows as sign-in history and what Privacy shows as
    "what Ziren has recorded about you".
    """
    db = get_supabase()
    query = (
        db.table("audit_logs")
        .select("id, action, target_type, target_label, metadata, created_at")
        .eq("actor_id", str(current_user["id"]))
        .order("created_at", desc=True)
        .limit(limit)
    )
    if kind == "auth":
        query = query.like("action", "auth.%")
    return {"items": query.execute().data or []}


class RevokeSessionsRequest(BaseModel):
    # `others` ends every session except the one making this request;
    # `global` ends them all, this one included.
    scope: Literal["others", "global"]


@router.post("/me/sessions/revoke", response_model=MessageResponse)
def revoke_my_sessions(
    request: Request,
    body: RevokeSessionsRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Sign the caller's account out of other devices, or all of them.

    Supabase identifies the session to keep by the JWT it is handed, so the
    caller's own bearer token is passed straight through. An access token that
    was already issued stays valid until it expires (about half an hour) — what
    this ends is the ability to REFRESH, so a stolen session dies at its next
    renewal instead of lasting a week. The response says so.
    """
    token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    try:
        get_supabase().auth.admin.sign_out(token, body.scope)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not end the sessions: {e}",
        )
    _record_security_event(
        request, current_user, "auth.sessions_revoked",
        label="all devices" if body.scope == "global" else "other devices",
    )
    return MessageResponse(
        message=(
            "Signed out everywhere." if body.scope == "global"
            else "Signed out of every other device."
        )
    )


@router.get("/me/support-contacts")
def get_my_support_contacts(current_user: dict = Depends(get_current_user)):
    """
    Who to ask for help, drawn from real accounts rather than a hard-coded list.

    An Agency Admin's first line is the Provincial Admin of their own agency
    type; everyone is also given their own agency's published contact details.
    A Provincial Admin has no one above them in the console, so their list of
    people is empty and the dashboard says so.
    """
    db = get_supabase()
    agency_type = current_user.get("agency_type")
    people: list[dict] = []
    if current_user.get("role") == "agency_admin" and agency_type:
        people = (
            db.table("users")
            .select("full_name, email, phone_number")
            .eq("role", "provincial_admin")
            .eq("agency_type", agency_type)
            .execute()
            .data
        ) or []

    agency: dict | None = None
    agency_id = current_user.get("agency_id")
    if agency_id:
        rows = (
            db.table("agencies")
            .select("name, agency_type, municipality, contact_number, email")
            .eq("id", str(agency_id))
            .limit(1)
            .execute()
            .data
        ) or []
        agency = rows[0] if rows else None

    return {"provincial_admins": people, "agency": agency}


# ── Agency Admin — Responder management ─────────────────────

class ApprovalRequest(BaseModel):
    approval_status: str   # "approved" | "rejected"
    rejection_reason: str | None = None


@router.get("/agency/responders")
def list_agency_responders(
    current_user: dict = _admin_only,
):
    """
    Agency Admin: list all Responders belonging to their agency.
    Provincial Admin: list Responders of every agency of their own
    agency_type (province-wide within that type).

    Returns: id, full_name, email, badge_id, approval_status, availability,
             is_verified, created_at, current_status, current_incident
    """
    db = get_supabase()
    role       = current_user.get("role")
    agency_id  = current_user.get("agency_id")

    if role == "agency_admin" and not agency_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Your account has no agency_id set. Contact a Provincial Admin.",
        )

    query = (
        db.table("users")
        # agency_id + the agencies(...) join are new: an agency_admin's own
        # roster never needed to say which agency a row belongs to (it is
        # always theirs), but a provincial_admin's response spans every
        # agency of their type, and the Verification page's cross-agency
        # Responders tab has no other way to show which station a pending
        # responder belongs to.
        .select(
            "id, email, full_name, badge_id, approval_status, availability, "
            "is_verified, created_at, agency_id, agencies(name, agency_type, municipality)"
        )
        .eq("role", "responder")
    )

    if role == "agency_admin":
        query = query.eq("agency_id", str(agency_id))
    elif role == "provincial_admin":
        agency_ids = _agency_ids_for_type(db, current_user.get("agency_type"))
        query = query.in_("agency_id", agency_ids)

    result = query.order("created_at", desc=False).execute()
    responders = result.data or []

    # Agency Admin spec Section 7: "immediately know who can respond" — a
    # derived current_status per responder, so the roster doesn't require
    # cross-referencing the duty flag against whatever incident happens to
    # reference their id. Approval status stays separate: current_status is
    # only meaningful for someone who could actually be dispatched.
    #
    # "Unavailable" (spec's sixth state, e.g. on break) has no signal in this
    # schema distinct from off_duty — the account only tracks a binary
    # on_duty/off_duty flag — so it is never produced here rather than
    # fabricated from nothing.
    on_duty_ids = [r["id"] for r in responders if r.get("approval_status") == "approved" and r.get("availability") == "on_duty"]
    active_by_responder: dict[str, dict] = {}
    if on_duty_ids:
        active_rows = (
            db.table("incidents")
            .select("id, status, incident_category, location_address, assigned_responder_id")
            .in_("assigned_responder_id", on_duty_ids)
            .in_("status", ["dispatched", "en_route", "arrived"])
            .execute()
            .data or []
        )
        for row in active_rows:
            active_by_responder[str(row["assigned_responder_id"])] = row

    _STATUS_BY_INCIDENT = {"dispatched": "assigned", "en_route": "en_route", "arrived": "on_scene"}
    for r in responders:
        if r.get("approval_status") != "approved":
            r["current_status"] = None
            r["current_incident"] = None
            continue
        if r.get("availability") != "on_duty":
            r["current_status"] = "offline"
            r["current_incident"] = None
            continue
        active = active_by_responder.get(str(r["id"]))
        if active:
            r["current_status"] = _STATUS_BY_INCIDENT.get(active["status"], "assigned")
            r["current_incident"] = {
                "id": active["id"],
                "incident_category": active.get("incident_category"),
                "location_address": active.get("location_address"),
            }
        else:
            r["current_status"] = "available"
            r["current_incident"] = None

    return responders


@router.get("/agency/responders/{responder_id}")
def get_responder_profile(
    responder_id: str,
    current_user: dict = _admin_only,
):
    """
    Agency Admin: view a single Responder's profile.
    Validates that the Responder belongs to the Admin's agency.
    """
    db = get_supabase()

    # agency_id is fetched for the scope check below, not for the response.
    # It was previously left out of this projection, so .data.get("agency_id")
    # returned None, never matched the caller's agency, and every Agency Admin
    # was refused their OWN responders with 403. Anything this handler reads
    # off the row has to be listed here.
    #
    # maybe_single(), not single(): PostgREST answers a single-object request
    # with PGRST116 when the filter matches nothing, and postgrest-py raises
    # APIError rather than returning data=None — which made the 404 below dead
    # code and turned an unknown id into a 500.
    result = (
        db.table("users")
        .select(
            "id, email, full_name, badge_id, agency_id, approval_status, "
            "availability, is_verified, phone_number, created_at"
        )
        .eq("id", responder_id)
        .eq("role", "responder")
        .maybe_single()
        .execute()
    )

    if not result or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Responder not found.")

    responder = result.data

    # Agency Admin: can only see own agency. Provincial Admin: any agency of
    # their own agency_type. assert_agency_scope's str(... or "") handling
    # covers the NULL-agency_id case for both.
    if current_user.get("role") in ("agency_admin", "provincial_admin"):
        assert_agency_scope(current_user, str(responder.get("agency_id") or ""))

    return responder


@router.patch("/agency/responders/{responder_id}/approval")
def update_responder_approval(
    responder_id: str,
    body: ApprovalRequest,
    current_user: dict = _admin_only,
):
    """
    Agency Admin: approve or reject a pending Responder account.

    - approval_status must be "approved" or "rejected"
    - Only affects Responders in the Admin's own agency
    - Cannot change role, agency_id, or badge_id — only approval_status
    - Writes are enforced by the RLS "users: agency_admin approves own responders" policy

    Every change is attributable via the JWT-verified dispatcher_id on the connection.
    """
    if body.approval_status not in ("approved", "rejected"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="approval_status must be 'approved' or 'rejected'.",
        )

    db = get_supabase()

    # Verify the Responder belongs to this Admin's agency
    check = (
        db.table("users")
        .select("id, role, agency_id, approval_status")
        .eq("id", responder_id)
        .single()
        .execute()
    )

    if not check.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Responder not found.")

    user = check.data

    if user.get("role") != "responder":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only Responder accounts can be approved/rejected.",
        )

    if current_user.get("role") in ("agency_admin", "provincial_admin"):
        assert_agency_scope(current_user, str(user.get("agency_id") or ""))

    result = (
        db.table("users")
        .update({"approval_status": body.approval_status})
        .eq("id", responder_id)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update approval status.",
        )

    import structlog
    log = structlog.get_logger()
    log.info(
        "admin.responder_approval_updated",
        responder_id=responder_id,
        new_status=body.approval_status,
        acting_admin_id=str(current_user["id"]),
    )

    return {
        "responder_id": responder_id,
        "approval_status": body.approval_status,
        "updated_by": str(current_user["id"]),
    }


# ── Provincial Admin — Agency Admin management ────────────────

class CreateAgencyAdminRequest(BaseModel):
    email: EmailStr
    full_name: str
    agency_id: str


class UpdateAgencyAdminRequest(BaseModel):
    is_active: Optional[bool] = None
    agency_id: Optional[str] = None


class ReviewAccessRequest(BaseModel):
    """Provincial Admin's decision on a pending access request."""
    action: str                      # 'approve' | 'reject'
    note:   Optional[str] = None


@router.get("/provincial/agency-admins")
def list_agency_admins(
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: list Agency Admin accounts of every agency of their
    own agency_type.
    Returns id, email, full_name, agency_id, is_verified, created_at,
    plus the agency name/type joined from the agencies table.
    """
    db = get_supabase()
    agency_ids = _agency_ids_for_type(db, current_user.get("agency_type"))
    result = (
        db.table("users")
        .select("id, email, full_name, agency_id, is_verified, approval_status, created_at, agencies(name, agency_type, municipality)")
        .eq("role", "agency_admin")
        .in_("agency_id", agency_ids)
        .order("created_at", desc=False)
        .execute()
    )
    return result.data or []


@router.get("/provincial/access-requests")
def list_access_requests(
    status_filter: str = "pending",
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: list Agency Admin access requests, scoped to agencies
    of their own agency_type, from the dashboard's Request Access page.

    Without this the requests were being stored and never surfaced — the
    intake half of the flow shipped while the review half did not, so an
    applicant waited on a decision nobody could see they needed to make.
    """
    db = get_supabase()
    agency_ids = _agency_ids_for_type(db, current_user.get("agency_type"))
    query = (
        db.table("access_requests")
        .select(
            "id, full_name, email, position, agency_id, status, "
            "created_at, reviewed_at, review_note, "
            "agencies(name, agency_type, municipality)"
        )
        .in_("agency_id", agency_ids)
        .order("created_at", desc=True)
    )
    if status_filter != "all":
        query = query.eq("status", status_filter)

    return query.execute().data or []


@router.patch("/provincial/access-requests/{request_id}")
def review_access_request(
    request_id: str,
    body: ReviewAccessRequest,
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: approve or reject a pending access request for an
    agency of their own agency_type.

    Approving provisions the Agency Admin through the same invite path as
    POST /provincial/agency-admins — the account is created unverified and
    the applicant sets their own password from the Supabase invite. The
    request row is only marked approved after the account exists, so a
    failed invite leaves it pending and retryable rather than silently
    closed.
    """
    import structlog
    log = structlog.get_logger()

    if body.action not in ("approve", "reject"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="action must be 'approve' or 'reject'.",
        )

    db = get_supabase()

    existing = (
        db.table("access_requests")
        .select("id, full_name, email, agency_id, status")
        .eq("id", request_id)
        .single()
        .execute()
    )
    if not existing.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Access request not found.",
        )

    req = existing.data
    if req["status"] != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"This request was already {req['status']}.",
        )

    # Scope check: this request's agency must be of the caller's own
    # agency_type — otherwise a PNP Provincial Admin could approve a BFP
    # access request and provision an agency_admin outside their remit.
    assert_agency_scope(current_user, str(req.get("agency_id") or ""))

    if body.action == "approve":
        # Reuses the existing provisioning path rather than duplicating it —
        # that endpoint is the only sanctioned way an agency_admin is created.
        created = create_agency_admin(
            CreateAgencyAdminRequest(
                email=req["email"],
                full_name=req["full_name"],
                agency_id=str(req["agency_id"]),
            ),
            current_user=current_user,
        )

        db.table("access_requests").update(
            {
                "status": "approved",
                "reviewed_by": str(current_user["id"]),
                "reviewed_at": "now()",
                "review_note": body.note,
            }
        ).eq("id", request_id).execute()

        log.info(
            "provincial_admin.access_request_approved",
            request_id=request_id,
            acting_provincial_admin=str(current_user["id"]),
        )
        return {"status": "approved", "account": created}

    db.table("access_requests").update(
        {
            "status": "rejected",
            "reviewed_by": str(current_user["id"]),
            "reviewed_at": "now()",
            "review_note": body.note,
        }
    ).eq("id", request_id).execute()

    log.info(
        "provincial_admin.access_request_rejected",
        request_id=request_id,
        acting_provincial_admin=str(current_user["id"]),
    )
    return {"status": "rejected"}


@router.post("/provincial/agency-admins", status_code=status.HTTP_201_CREATED)
def create_agency_admin(
    body: CreateAgencyAdminRequest,
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: create a new Agency Admin account of their own agency_type.
    Agency Admin accounts cannot self-register (enforced in RegisterRequest),
    so this is the only creation path.
    """
    import structlog
    log = structlog.get_logger()

    db = get_supabase()

    # Verify agency exists
    agency_check = (
        db.table("agencies")
        .select("id, name, agency_type")
        .eq("id", body.agency_id)
        .single()
        .execute()
    )
    if not agency_check.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Agency not found.",
        )

    # A Provincial Admin may only provision Agency Admins for their own
    # agency_type — same rule stations.py's create_station applies to new
    # stations. Without this a PNP Provincial Admin could invite an Agency
    # Admin into a BFP station, which is not a decision that agency_type
    # is theirs to make.
    if agency_check.data["agency_type"] != current_user.get("agency_type"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only create Agency Admins for your own agency type.",
        )

    # Does this email already have an account?
    #
    # Checked here rather than letting the invite fail, because Supabase
    # answers with "A user with this email address has already been
    # registered" — technically true, and useless to whoever is reviewing.
    # It does not say which account, what role it holds, or what to do next.
    #
    # Note this check is deliberately absent from the public
    # POST /auth/access-request. Telling an anonymous caller that an address is
    # taken would let them enumerate which officials already hold accounts.
    # A Provincial Admin reviewing a request has already earned the right to know.
    existing = (
        db.table("users")
        .select("id, role, full_name")
        .ilike("email", body.email)
        .limit(1)
        .execute()
    )
    if existing.data:
        found = existing.data[0]
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"{body.email} already has a Ziren account "
                f"({found.get('role')}). An invite cannot be sent to an "
                "address that is already registered — reject this request, or "
                "ask the applicant to reapply with their own work email."
            ),
        )

    # Send invite email via Supabase Auth
    try:
        auth_response = db.auth.admin.invite_user_by_email(
            body.email,
            options={
                "data": {
                    "full_name": body.full_name,
                    "role": "agency_admin",
                    "agency_id": body.agency_id,
                },
                # Configurable — see Settings.dashboard_base_url. Hardcoding
                # this sent invitees to a port the dashboard does not serve,
                # and to "localhost" as resolved by whatever device opened the
                # email (a phone, in practice).
                "redirect_to": settings.accept_invite_url,
            },
        )
    except Exception as e:
        detail = str(e)
        # An auth.users row can exist without a public.users profile — the
        # insert below runs after this call, so any earlier failure between the
        # two leaves exactly that orphan. The pre-check above reads profiles,
        # so it cannot see one, and the invite is where it surfaces.
        if "already been registered" in detail:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"{body.email} already exists in Supabase Auth but has no "
                    "Ziren profile. This is a half-provisioned account from an "
                    "interrupted invite. A Provincial Admin must delete the auth "
                    "user in the Supabase dashboard before this address can be "
                    "invited again."
                ),
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not send invite: {detail}",
        )

    new_uid = auth_response.user.id

    # UPSERT, not INSERT — and the distinction is the whole bug this replaced.
    #
    # invite_user_by_email() above created the auth.users row, which fires the
    # AFTER INSERT trigger public.handle_new_auth_user(). That trigger has
    # ALREADY written the public.users profile by the time we get here. The
    # original plain .insert() therefore hit the same primary key and died:
    #
    #     23505  duplicate key value violates unique constraint "users_pkey"
    #
    # which escaped as an unhandled 500, so approving an access request failed
    # every time for any address not already in public.users.
    #
    # There is a second half to it. The trigger enforces a role allow-list —
    # anything outside ('resident','responder') is forced to 'resident' — so
    # the row it just created says 'resident', not 'agency_admin'. That
    # allow-list is a deliberate security control and the ONLY chokepoint
    # shared by the FastAPI and mobile registration paths, so it stays exactly
    # as it is: it exists to stop CLIENT-supplied roles. This endpoint is
    # server-side, already gated behind require_role("provincial_admin"), and is
    # the sanctioned provisioning path — so it corrects the row afterwards
    # rather than weakening the trigger. Without this the account would be
    # created, but as a resident, and the applicant would accept an invite
    # into an account with none of the access they were approved for.
    profile_row = {
        "id": str(new_uid),
        "email": body.email,
        "full_name": body.full_name,
        "role": "agency_admin",
        "agency_id": body.agency_id,
        "approval_status": "not_required",
        "is_verified": False,   # until they accept the invite
    }

    upsert_result = db.table("users").upsert(profile_row).execute()

    if not upsert_result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Invite sent but profile write failed.",
        )
    insert_result = upsert_result

    log.info(
        "provincial_admin.agency_admin_invited",
        new_user_id=str(new_uid),
        agency_id=body.agency_id,
        acting_provincial_admin=str(current_user["id"]),
    )

    audit_service.record(
        actor=current_user,
        action="agency_admin.created",
        target_type="user",
        target_id=str(new_uid),
        target_label=body.full_name,
        new={"agency_id": body.agency_id, "role": "agency_admin"},
        metadata={"notify_body": f"{body.full_name} invited as Agency Admin for {agency_check.data['name']}."},
        agency_type=agency_check.data["agency_type"],
    )

    return {**insert_result.data[0], "invite_sent": True}


@router.patch("/provincial/agency-admins/{user_id}")
def update_agency_admin(
    user_id: str,
    body: UpdateAgencyAdminRequest,
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: deactivate (is_active=False) or reassign (agency_id) an Agency Admin of their own agency_type.
    Cannot change role or email — those are immutable after creation.
    """
    import structlog
    log = structlog.get_logger()

    db = get_supabase()

    # Verify target is an agency_admin
    check = (
        db.table("users")
        .select("id, role, agency_id")
        .eq("id", user_id)
        .single()
        .execute()
    )
    if not check.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    if check.data.get("role") != "agency_admin":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only Agency Admin accounts can be updated via this endpoint.",
        )

    # This Agency Admin's CURRENT agency must be of the caller's own
    # agency_type — a PNP Provincial Admin has no business deactivating or
    # reassigning a BFP Agency Admin.
    assert_agency_scope(current_user, str(check.data.get("agency_id") or ""))

    updates: dict = {}
    if body.is_active is not None:
        updates["is_verified"] = body.is_active  # is_verified doubles as active flag
    if body.agency_id is not None:
        # Verify new agency exists AND is of the caller's own agency_type —
        # otherwise this would let a Provincial Admin move an Agency Admin
        # OUT of their remit into an agency they have no authority over.
        agency_check = (
            db.table("agencies")
            .select("id, agency_type")
            .eq("id", body.agency_id)
            .single()
            .execute()
        )
        if not agency_check.data:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Agency not found.")
        if agency_check.data["agency_type"] != current_user.get("agency_type"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only reassign Agency Admins within your own agency type.",
            )
        updates["agency_id"] = body.agency_id

    if not updates:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No updatable fields provided.",
        )

    result = (
        db.table("users")
        .update(updates)
        .eq("id", user_id)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Update failed.",
        )

    log.info(
        "provincial_admin.agency_admin_updated",
        target_user_id=user_id,
        updates=updates,
        acting_provincial_admin=str(current_user["id"]),
    )

    target_label = result.data[0].get("full_name") or user_id
    if "is_verified" in updates:
        audit_service.record(
            actor=current_user,
            action="account.reactivated" if updates["is_verified"] else "account.deactivated",
            target_type="user",
            target_id=user_id,
            target_label=target_label,
            previous={"is_verified": not updates["is_verified"]},
            new={"is_verified": updates["is_verified"]},
            agency_type=current_user.get("agency_type"),
        )
    if "agency_id" in updates:
        audit_service.record(
            actor=current_user,
            action="agency_admin.assigned",
            target_type="user",
            target_id=user_id,
            target_label=target_label,
            previous={"agency_id": check.data.get("agency_id")},
            new={"agency_id": updates["agency_id"]},
            agency_type=current_user.get("agency_type"),
        )

    return result.data[0]


# ── Provincial Admin — Account directory ─────────────────────

@router.get("/provincial/directory")
def cross_agency_directory(
    role: Optional[str] = Query(None, description="Filter by role: responder | agency_admin | resident"),
    agency_id: Optional[str] = Query(None, description="Filter by agency UUID"),
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: account directory, scoped to their own agency_type.
    Returns all users (all roles) with optional role and agency_id filters.
    Joins agency name/type for context.
    Excludes provincial_admin accounts from the listing.
    """
    db = get_supabase()
    own_agency_ids = _agency_ids_for_type(db, current_user.get("agency_type"))

    if agency_id:
        # An explicit ?agency_id must itself be one of the caller's own
        # agency_type — otherwise a PNP Provincial Admin could still reach a
        # BFP agency's roster just by naming its id directly.
        assert_agency_scope(current_user, agency_id)

    query = (
        db.table("users")
        # Address fields added: the directory could say what someone IS and
        # never where they are, so an LGU console covering eight municipalities
        # and a hundred and twenty barangays could only ever list the province
        # as one flat roll.
        #
        # A resident carries their own address. Responders and agency admins
        # usually do not — their place is their agency's municipality, which is
        # a different fact and must not be silently merged into the same field.
        # Both travel, and the client says which it is showing.
        .select(
            "id, email, full_name, role, agency_id, approval_status, "
            "availability, is_verified, created_at, "
            "municipality_address, purok_sitio, "
            "barangays(name, municipality), "
            "agencies(name, agency_type, municipality)"
        )
        .neq("role", "provincial_admin")
        .order("created_at", desc=True)
    )

    if role:
        if role not in ("responder", "agency_admin", "resident"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="role must be one of: responder, agency_admin, resident",
            )
        query = query.eq("role", role)

    if agency_id:
        query = query.eq("agency_id", agency_id)
    else:
        # No explicit agency_id filter: scope to the caller's own
        # agency_type, but keep residents visible — they carry no agency_id
        # at all (Type B, see migration 034), and excluding every NULL
        # agency_id row here would silently drop every resident from their
        # own directory.
        ids_csv = ",".join(own_agency_ids) if own_agency_ids else "00000000-0000-0000-0000-000000000000"
        query = query.or_(f"agency_id.is.null,agency_id.in.({ids_csv})")

    result = query.execute()
    rows = result.data or []

    # Flatten, matching list_verification_queue: a nested one-row object is
    # awkward for every consumer and the client only ever wants the name.
    for row in rows:
        barangay = row.pop("barangays", None)
        row["barangay"] = barangay.get("name") if isinstance(barangay, dict) else None

    return rows


# ── Barangay reference (for place filters) ───────────────────

@router.get("/barangays")
def list_barangays(
    current_user: dict = _admin_only,
):
    """
    Every barangay in the province, with its municipality.

    Read from the reference table migration 012 added, NOT derived from the
    addresses accounts happen to carry. That difference is the point: deriving
    the list from existing users would offer only the places somebody has
    already registered from, so a barangay with no accounts would be missing
    from the filter -- and "nobody here yet" is exactly what an administrator
    is looking for when they check it.

    The names are the best-effort transcription migration 012 warns about;
    rows with psgc_code NULL have not been checked against the PSA list.
    """
    db = get_supabase()
    result = (
        db.table("barangays")
        .select("name, municipality, psgc_code")
        .order("municipality", desc=False)
        .order("name", desc=False)
        .execute()
    )
    return result.data or []


# ── Platform totals (Provincial Admin overview) ───────────────

# How far back the overview's standing-total trend lines reach.
_TREND_WINDOW_DAYS = 14

@router.get("/provincial/counts")
def platform_counts(
    current_user: dict = _provincial_admin_only,
):
    """
    Standing totals for the Provincial Admin overview: people and infrastructure.

    Scoped to the caller's own agency_type for everything with an agency
    dimension (responders, stations, agencies). Residents are the one
    exception, left unscoped — a resident carries no agency_id at all
    (Type B, see migration 034's header), so "PNP's residents" is not a
    question this data model can answer, and scoping it would just make
    every Provincial Admin's resident counts read zero.

    Counts only. Every query is `count="exact", head=True`, so PostgREST
    returns the number in the Content-Range header and NO rows at all.

    That is the whole point of this endpoint existing. The dashboard could
    have derived these from /provincial/directory, but that returns every
    user row — email, full name, agency, verification state — and the
    overview polls. Shipping the province's entire resident list across the
    wire every fifteen seconds to display three integers is not a trade
    worth making, whatever the row count is today.

    Sub-counts are included because the totals alone answer very little. How
    many responders exist matters far less than how many are on duty right
    now, and that is one extra count, not one extra table scan of rows.
    """
    db = get_supabase()
    own_agency_type = current_user.get("agency_type")
    own_agency_ids = _agency_ids_for_type(db, own_agency_type)

    def _count(table: str, build) -> int:
        q = db.table(table).select("id", count="exact", head=True)
        return build(q).execute().count or 0

    residents = _count("users", lambda q: q.eq("role", "resident"))
    # verification_level >= 2 is what decide_verification writes on approval.
    # is_verified is NOT the same flag and lags behind it on some rows.
    residents_verified = _count(
        "users", lambda q: q.eq("role", "resident").gte("verification_level", 2)
    )

    responders = _count(
        "users", lambda q: q.eq("role", "responder").in_("agency_id", own_agency_ids)
    )
    responders_on_duty = _count(
        "users",
        lambda q: q.eq("role", "responder").eq("availability", "on_duty").in_("agency_id", own_agency_ids),
    )
    # Pending accounts are the ones an Agency Admin still has to act on, so
    # they are worth surfacing separately from the roster size.
    responders_pending = _count(
        "users",
        lambda q: q.eq("role", "responder").eq("approval_status", "pending").in_("agency_id", own_agency_ids),
    )

    stations = _count(
        "stations", lambda q: q.eq("is_active", True).in_("agency_id", own_agency_ids)
    )
    agencies = _count(
        "agencies", lambda q: q.eq("is_active", True).eq("agency_type", own_agency_type)
    )
    # An agency with no station cannot receive a dispatch — reports routed to
    # it have nowhere to land. Counted here so the overview can say so.
    station_agency_ids = {
        r["agency_id"]
        for r in (
            db.table("stations")
            .select("agency_id")
            .eq("is_active", True)
            .in_("agency_id", own_agency_ids)
            .execute()
            .data
            or []
        )
    }

    # When each recent account/station was created — the only history these
    # totals have, and what the overview's trend lines are walked back from
    # (total now, minus what arrived after each earlier day). Timestamps rather
    # than a pre-bucketed series so the dashboard buckets by the operator's own
    # calendar day, the same way it does for every incident series. Only the
    # trend window is fetched, capped, and only one column — never a row.
    since = (datetime.now(timezone.utc) - timedelta(days=_TREND_WINDOW_DAYS)).isoformat()

    def _recent(table: str, build) -> list[str]:
        q = db.table(table).select("created_at").gte("created_at", since).limit(2000)
        return [r["created_at"] for r in (build(q).execute().data or []) if r.get("created_at")]

    recent = {
        "residents": _recent("users", lambda q: q.eq("role", "resident")),
        "responders": _recent(
            "users", lambda q: q.eq("role", "responder").in_("agency_id", own_agency_ids)
        ),
        "stations": _recent(
            "stations", lambda q: q.eq("is_active", True).in_("agency_id", own_agency_ids)
        ),
    }

    return {
        "residents": residents,
        "residents_verified": residents_verified,
        "responders": responders,
        "responders_on_duty": responders_on_duty,
        "responders_pending": responders_pending,
        "stations": stations,
        "agencies": agencies,
        "agencies_with_a_station": len(station_agency_ids),
        "recent": recent,
    }


# ── Agencies list (for admin UI selectors) ───────────────────

@router.get("/agencies-list")
def list_agencies(
    current_user: dict = _admin_only,
):
    """
    Agency Admin / Provincial Admin: list all active agencies.
    Used to populate agency selectors in the dashboard UI.
    Returns id, name, agency_type, municipality.
    """
    db = get_supabase()
    result = (
        db.table("agencies")
        .select("id, name, agency_type, municipality")
        .eq("is_active", True)
        .order("agency_type", desc=False)
        .execute()
    )
    return result.data or []


@router.get("/agencies-list/public")
def list_agencies_public():
    """Public: list active agencies for signup form."""
    db = get_supabase()
    result = (
        db.table("agencies")
        .select("id, name, agency_type, municipality")
        .eq("is_active", True)
        .order("agency_type", desc=False)
        .execute()
    )
    return result.data or []


# ============================================================
# Resident identity verification
#
# The counterpart to /agency/responders/{id}/approval, for residents. The two
# are deliberately separate endpoints rather than one generic "approve user":
# they decide different things. A responder approval grants ACCESS -- the
# ability to see every incident in a municipality. A resident verification
# grants no access at all; it only raises a confidence signal a dispatcher
# reads. Collapsing them into one route would make it far too easy to
# accidentally hand a resident endpoint the power of the responder one.
# ============================================================

class VerificationDecision(BaseModel):
    approve: bool
    # Which document actually convinced the reviewer. Constrained to the
    # verification_method CHECK in migration 012.
    method: Optional[str] = None
    # Retention: migration 015 is explicit that the scan exists to be checked
    # once. Defaults to purging; an admin can keep it only deliberately.
    purge_images: bool = True


@router.get("/verification/residents")
def list_resident_verifications(
    municipality: Optional[str] = Query(None),
    include_decided: bool = Query(False),
    limit: int = Query(50, ge=1, le=200),
    priority_only: bool = Query(
        False,
        description="Only submissions carrying a review signal — a duplicate ID "
                    "number, a filed report, or an SOS warning.",
    ),
    current_user: dict = _admin_only,
):
    """
    Residents who have submitted an ID and are waiting for a decision.

    Oldest first — this is a queue of people waiting, not an activity feed.

    Every row carries `review_flags`, which say why a human should look. With
    `priority_only`, rows carrying none of those signals are dropped: at a
    thousand waiting residents the queue is unreviewable one at a time, and
    reviewing exhaustively is mostly wasted effort, because verification is
    metadata a dispatcher reads and never a permission — see migration 012.
    """
    return user_service.list_verification_queue(
        municipality=municipality,
        include_decided=include_decided,
        limit=limit,
        priority_only=priority_only,
        current_user=current_user,
    )


@router.get("/verification/residents/{user_id}")
def get_resident_verification(
    user_id: str,
    current_user: dict = _admin_only,
):
    """
    One submission, with short-lived signed URLs for the ID scan and selfie.

    The URLs last five minutes and are minted per request. The bucket is
    private and has no public URL; responders cannot read it at all.
    """
    return user_service.get_verification_detail(user_id, current_user=current_user)


class BulkVerificationDecision(BaseModel):
    """The same decision, applied to several residents."""
    user_ids: list[str]
    approve: bool
    method: Optional[str] = None
    purge_images: bool = True


@router.post("/verification/residents/bulk")
def decide_resident_verifications_bulk(
    body: BulkVerificationDecision,
    current_user: dict = _admin_only,
):
    """
    Approve or reject several submissions at once.

    `method` is REQUIRED on approval and is the honesty of this endpoint. It
    records what convinced the reviewer, and a batch is only defensible when
    the same sentence is true of every account in it -- "these all passed phone
    OTP" is such a sentence; "I examined four hundred government IDs" is not.
    The server cannot tell those apart, so it insists the claim be stated
    rather than defaulted.

    Not a transaction. Each row commits independently and the response names
    the ones that failed, because a bad id in position 400 must not discard
    the 399 correct decisions before it.
    """
    if not body.user_ids:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No residents selected.",
        )

    allowed_methods = {"phone_otp", "barangay_official", "pwd_id", "government_id"}
    if body.approve and body.method not in allowed_methods:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"method must be one of: {', '.join(sorted(allowed_methods))}.",
        )

    return user_service.decide_verification_bulk(
        body.user_ids,
        approve=body.approve,
        method=body.method,
        reviewer_id=str(current_user.get("id")),
        purge_images=body.purge_images,
        current_user=current_user,
    )


@router.patch("/verification/residents/{user_id}")
def decide_resident_verification(
    user_id: str,
    body: VerificationDecision,
    current_user: dict = _admin_only,
):
    """
    Record the decision. Approving sets verification_level 2.

    This NEVER changes what the resident can do. An unverified resident can
    report an emergency exactly like a verified one — see migration 012.
    """
    allowed_methods = {"phone_otp", "barangay_official", "pwd_id", "government_id"}
    if body.approve and body.method not in allowed_methods:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"method must be one of: {', '.join(sorted(allowed_methods))}.",
        )

    return user_service.decide_verification(
        user_id,
        approve=body.approve,
        method=body.method,
        reviewer_id=str(current_user.get("id")),
        purge_images=body.purge_images,
        current_user=current_user,
    )


# ============================================================
# Provincial Admin — account status (Accounts module, spec Section 5)
#
# Residents have no existing suspend/deactivate/reactivate control anywhere
# in the app. is_verified already exists on every resident row as a TRUST
# INDICATOR a dispatcher reads (see dispatch_service.get_incident_detail_admin,
# which returns it alongside sos_warning_count for exactly that reason) — it
# is not a permission and never has been. Toggling it here is the same
# convention update_agency_admin already uses ("is_verified doubles as active
# flag"), extended to residents rather than inventing a second mechanism.
#
# IMPORTANT: this does NOT gate incident reporting. The actual anti-abuse
# control is sos_suspended_until (set by POST /dispatch/queue/{id}/flag-false-
# sos), a separate mechanism this endpoint does not touch. An account
# "suspended" here can still report an emergency exactly like any other
# resident — migration 012's founding rule for this whole area of the schema.
# ============================================================

class ResidentStatusRequest(BaseModel):
    is_active: bool


@router.patch("/provincial/residents/{user_id}/status")
def update_resident_status(
    user_id: str,
    body: ResidentStatusRequest,
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: suspend/deactivate (is_active=False) or reactivate
    (is_active=True) a resident account's standing.

    Deliberately NOT scoped by agency_type, unlike every other Type A
    endpoint on this router — a resident carries no agency_id/agency_type
    of their own at all (see migration 034's header: "resident-ids storage
    ... isn't agency-specific"), so there is no agency dimension here to
    scope against. All 3 Provincial Admins share this control exactly the
    way they already share identity verification.

    Purely a status flag dispatchers see — see the module note above for why
    this never blocks emergency reporting.
    """
    db = get_supabase()

    check = db.table("users").select("id, role, full_name").eq("id", user_id).single().execute()
    if not check.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    if check.data.get("role") != "resident":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only resident accounts can be updated via this endpoint.",
        )

    result = (
        db.table("users")
        .update({"is_verified": body.is_active})
        .eq("id", user_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Update failed.")

    audit_service.record(
        actor=current_user,
        action="account.reactivated" if body.is_active else "account.suspended",
        target_type="user",
        target_id=user_id,
        target_label=check.data.get("full_name"),
        previous={"is_verified": not body.is_active},
        new={"is_verified": body.is_active},
    )

    return result.data[0]


class ResponderReassignRequest(BaseModel):
    agency_id: str


@router.patch("/provincial/responders/{user_id}/reassign")
def reassign_responder(
    user_id: str,
    body: ResponderReassignRequest,
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: move a Responder to a different agency/station,
    restricted to stations of their OWN agency_type on both ends.

    Reassigning a PNP responder to a BFP station was never meaningful — a
    Responder's role-specific training, equipment and dispatch eligibility
    are all agency-type-bound, so "move them to a different agency" only
    ever made sense within one type. Under the old cross-agency Super Admin
    model this had no guard because the actor's own scope covered
    everything anyway; now that the actor is agency_type-scoped, the FROM
    and TO agencies both have to be checked explicitly, or a Provincial
    Admin could still walk a responder out of every agency_type's remit by
    naming an out-of-scope agency_id directly.

    Suspending or reactivating a Responder is a separate, already-existing
    action — PATCH /agency/responders/{id}/approval (approved/rejected),
    which a Provincial Admin can already call. This endpoint is only the
    reassignment half, mirroring update_agency_admin's agency_id branch but
    for the responder role.
    """
    db = get_supabase()

    check = db.table("users").select("id, role, full_name, agency_id").eq("id", user_id).single().execute()
    if not check.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    if check.data.get("role") != "responder":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Only responder accounts can be reassigned via this endpoint.",
        )

    # FROM: the responder's current agency must be of the caller's own
    # agency_type.
    assert_agency_scope(current_user, str(check.data.get("agency_id") or ""))

    agency_check = db.table("agencies").select("id, agency_type").eq("id", body.agency_id).single().execute()
    if not agency_check.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Agency not found.")

    # TO: the destination agency must ALSO be of the caller's own
    # agency_type — moving a responder OUT of their agency_type is exactly
    # the case this endpoint must refuse.
    if agency_check.data["agency_type"] != current_user.get("agency_type"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only reassign Responders within your own agency type.",
        )

    result = (
        db.table("users")
        .update({"agency_id": body.agency_id})
        .eq("id", user_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Update failed.")

    audit_service.record(
        actor=current_user,
        action="responder.reassigned",
        target_type="user",
        target_id=user_id,
        target_label=check.data.get("full_name"),
        previous={"agency_id": check.data.get("agency_id")},
        new={"agency_id": body.agency_id},
        agency_type=current_user.get("agency_type"),
    )

    return result.data[0]
