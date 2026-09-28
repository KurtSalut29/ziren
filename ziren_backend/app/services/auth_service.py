"""
Auth service — all authentication logic lives here.

Uses Supabase Auth for credential management and public.users
for role/profile/approval data.
"""

import structlog
from fastapi import HTTPException, status
from supabase import Client

from app.core.config import settings
from app.core.dependencies import forget_token
from app.db.supabase_client import get_supabase, new_supabase_client
from app.services import notification_service
from app.models.user import (
    AccessRequestCreate,
    ApprovalStatus,
    AuthResponse,
    AuthTokens,
    LoginRequest,
    MessageResponse,
    RegisterRequest,
    UserProfile,
    UserRole,
)

log = structlog.get_logger()

ACCESS_TOKEN_EXPIRES_IN = 3600  # seconds


def _build_auth_response(supabase_session, user_row: dict) -> AuthResponse:
    # provincial_admin carries agency_type directly on the row (no agency_id
    # to join through). agency_admin and responder carry no such column —
    # theirs only exists on the agencies row their agency_id points at, which
    # is why _fetch_user_profile now joins it in. This constructor bypasses
    # UserProfile.model_validate's agencies-join flattening (it builds the
    # model directly), so without this fallback an agency_admin's
    # login/accept-invite response reported agency_type=None even though the
    # database had it set on the agency — the dashboard's "Signed in as
    # Agency Admin" badge had nothing to put in front of "Admin".
    agencies = user_row.get("agencies") or {}
    agency_type = user_row.get("agency_type") or agencies.get("agency_type")
    return AuthResponse(
        user=UserProfile(
            id=user_row["id"],
            email=user_row["email"],
            full_name=user_row["full_name"],
            role=UserRole(user_row["role"]),
            approval_status=ApprovalStatus(user_row["approval_status"]),
            agency_id=user_row.get("agency_id"),
            agency_type=agency_type,
            badge_id=user_row.get("badge_id"),
            is_verified=user_row["is_verified"],
            created_at=user_row["created_at"],
        ),
        tokens=AuthTokens(
            access_token=supabase_session.access_token,
            refresh_token=supabase_session.refresh_token,
            token_type="bearer",
            expires_in=ACCESS_TOKEN_EXPIRES_IN,
        ),
    )


def register_user(request: RegisterRequest) -> AuthResponse:
    """
    Register a new Resident or Responder account.

    - Resident: no agency/badge required, approval_status = not_required
    - Responder: agency_id + badge_id required, approval_status = pending
    - Agency Admin / Provincial Admin: blocked — must be created by an administrator

    SECURITY: the privileged-role rejection below is a second line of defense.
    RegisterRequest already rejects these roles at validation time (422). This
    guard exists because this docstring previously claimed the block existed
    while no code enforced it, which allowed an unauthenticated caller to
    provision a verified Provincial Admin account. Keep BOTH layers.
    """
    # Defense in depth — never trust that the model layer is still intact.
    if request.role in (UserRole.agency_admin, UserRole.provincial_admin):
        log.warning(
            "auth.privileged_self_registration_blocked",
            email=request.email,
            attempted_role=request.role.value,
        )
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Self-registration as '{request.role.value}' is not permitted. "
                "Administrator accounts must be provisioned by a Provincial Admin."
            ),
        )

    db: Client = get_supabase()

    # Determine approval_status for the new account
    approval_status = (
        ApprovalStatus.pending
        if request.role == UserRole.responder
        else ApprovalStatus.not_required
    )

    # Only resident/responder can reach this point — neither is auto-verified.
    is_verified = False

    try:
        result = db.auth.sign_up({
            "email": request.email,
            "password": request.password,
            "options": {
                "data": {
                    "full_name":       request.full_name,
                    "role":            request.role.value,
                    "agency_id":       str(request.agency_id) if request.agency_id else None,
                    "badge_id":        request.badge_id,
                    "approval_status": approval_status.value,
                }
            },
        })
    except Exception as e:
        error_msg = str(e).lower()
        if "already registered" in error_msg or "already exists" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this email already exists.",
            )
        log.error("auth.register_failed", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registration failed. Please check your input and try again.",
        )

    if not result.user or not result.session:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registration failed. Please verify your email to continue.",
        )

    # Update extra fields not covered by the DB trigger.
    # NOTE: there is deliberately no agency_admin / provincial_admin branch here.
    # Those roles cannot reach this line (rejected above and at the model
    # layer). The previous code had branches that set is_verified=True for
    # them, which is what turned the missing validation into a fully
    # provisioned administrator account. Do not re-add them.
    extra: dict = {}
    if request.role == UserRole.responder:
        extra = {
            "agency_id":       str(request.agency_id),
            "badge_id":        request.badge_id.strip(),
            "approval_status": ApprovalStatus.pending.value,
        }

    if extra:
        db.table("users").update(extra).eq("id", str(result.user.id)).execute()

    user_row = _fetch_user_profile(db, str(result.user.id))
    log.info("auth.registered", user_id=str(result.user.id), role=request.role.value)

    if request.role == UserRole.responder and request.agency_id:
        try:
            notification_service.create_for_agency_role(
                str(request.agency_id), "agency_admin",
                type_="responder.registered",
                title="New responder account awaiting approval",
                body=request.full_name,
                link="/responders",
            )
        except Exception:
            log.error("auth.responder_notify_failed", user_id=str(result.user.id), exc_info=True)

    return _build_auth_response(result.session, user_row)



def create_access_request(request: AccessRequestCreate) -> MessageResponse:
    """
    Record a request for an Agency Admin dashboard account.

    Creates NOTHING in auth.users or public.users — the row lands in
    public.access_requests and is inert until a Provincial Admin provisions
    the account through POST /users/provincial/agency-admins.

    The response is intentionally identical whether the request was stored or
    silently ignored as a duplicate. Telling an anonymous caller "that email
    already has a pending request" would turn this endpoint into a way to
    enumerate which officials have applied.
    """
    db: Client = get_supabase()

    generic = MessageResponse(
        message=(
            "Your access request has been submitted. A Provincial Admin will "
            "review it and you will receive an email if it is approved."
        )
    )

    # The agency must exist. A request pointing at nothing cannot be actioned,
    # and this is the one thing worth failing loudly on because the dashboard
    # populates the dropdown from the same table.
    agency = (
        db.table("agencies")
        .select("id")
        .eq("id", str(request.agency_id))
        .limit(1)
        .execute()
    )
    if not agency.data:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="That agency was not found. Pick one from the list and try again.",
        )

    try:
        db.table("access_requests").insert(
            {
                "full_name": request.full_name,
                "email": str(request.email).lower(),
                "position": request.position,
                "agency_id": str(request.agency_id),
                "status": "pending",
            }
        ).execute()
        log.info(
            "auth.access_request_created",
            agency_id=str(request.agency_id),
        )
    except Exception as e:
        # Unique index on (lower(email)) WHERE status='pending' — a repeat
        # submission is a duplicate, not an error the applicant can act on.
        detail = str(e)
        if "access_requests_one_pending_per_email" in detail:
            log.info("auth.access_request_duplicate_ignored")
            return generic

        log.warning("auth.access_request_failed", error=detail)

        # A missing table or a missing GRANT is a deployment fault, not a blip.
        # Telling the applicant to "try again shortly" sends them into a retry
        # loop that can never succeed and hides the real cause from whoever
        # could fix it — which is exactly what happened when 012 and 016
        # created their tables without granting service_role (see 017).
        permanent = (
            "42501" in detail            # permission denied — missing GRANT
            or "PGRST205" in detail      # table not exposed / not found
            or "42P01" in detail         # relation does not exist
            or "does not exist" in detail
        )
        if permanent:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    "Access requests are not set up on this server yet. "
                    "Retrying will not help — please contact your Provincial Admin."
                ),
            )

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not submit your request right now. Please try again shortly.",
        )

    return generic


def login_user(request: LoginRequest) -> AuthResponse:
    """
    Authenticate and return tokens + profile.
    Raises HTTP 401 on bad credentials.
    """
    # Dev-only hardcoded admin bypass — skips Supabase Auth entirely.
    # Only active when ENVIRONMENT=development and DEV_ADMIN_EMAIL is set.
    if (
        settings.environment == "development"
        and settings.dev_admin_email
        and request.email == settings.dev_admin_email
        and request.password == settings.dev_admin_password
    ):
        import uuid
        from app.core.dependencies import _resolve_dev_admin_profile

        # Must be the SAME identity get_current_user hands to request handlers.
        # These two halves previously each hardcoded a synthetic id that had no
        # public.users row, so every audited write by the dev admin failed on a
        # foreign key — see _resolve_dev_admin_profile for the full account.
        # Resolving through one shared function is what keeps them honest.
        profile = _resolve_dev_admin_profile()
        log.info("auth.dev_admin_login", email=request.email, acting_as=profile["email"])

        class _FakeSession:
            access_token  = "dev-admin-token-" + str(uuid.uuid4())
            refresh_token = "dev-admin-refresh-" + str(uuid.uuid4())

        return AuthResponse(
            user=UserProfile(
                id=profile["id"],
                email=profile["email"],
                full_name=profile.get("full_name") or "Dev Admin",
                role=UserRole.provincial_admin,
                approval_status=ApprovalStatus.not_required,
                agency_id=profile.get("agency_id"),
                agency_type=profile.get("agency_type"),
                badge_id=profile.get("badge_id"),
                is_verified=True,
                created_at="2025-01-01T00:00:00+00:00",
            ),
            tokens=AuthTokens(
                access_token=_FakeSession.access_token,
                refresh_token=_FakeSession.refresh_token,
                token_type="bearer",
                expires_in=ACCESS_TOKEN_EXPIRES_IN,
            ),
        )

    db: Client = get_supabase()

    # Fresh client for the sign-in — see new_supabase_client(). Doing this on
    # the singleton left it authorized as the last user who logged in, for the
    # rest of the process, which silently broke later admin calls.
    try:
        result = new_supabase_client().auth.sign_in_with_password({
            "email":    request.email,
            "password": request.password,
        })
    except Exception:
        log.warning("auth.login_failed", email=request.email[:3] + "***")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not result.session:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_row = _fetch_user_profile(db, str(result.user.id))
    log.info("auth.login_success", user_id=str(result.user.id))
    return _build_auth_response(result.session, user_row)


def refresh_session(refresh_token: str) -> AuthTokens:
    # new_supabase_client(), not get_supabase() — same reason as login_user's:
    # auth.refresh_session() sets a session on the client it is called on,
    # exactly like sign_in_with_password() does (see new_supabase_client's
    # docstring). Calling it on the shared singleton replaces the service
    # role's own authorization with whichever user last refreshed, for
    # every other request sharing that client for the rest of the process.
    #
    # This was the actual cause of "the dashboard signs back out
    # immediately after logging in", found 2026-09-15: a token validated by
    # get_current_user right after login could be checked against a
    # singleton some earlier /auth/refresh call had already reauthorized as
    # a DIFFERENT session, so the validation flapped between working and
    # not depending on what had touched the shared client most recently —
    # not the fresh token being bad, the client checking it being unreliable.
    try:
        result = new_supabase_client().auth.refresh_session(refresh_token)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return AuthTokens(
        access_token=result.session.access_token,
        refresh_token=result.session.refresh_token,
        token_type="bearer",
        expires_in=ACCESS_TOKEN_EXPIRES_IN,
    )


def logout_user(access_token: str) -> MessageResponse:
    # A signed-out token must stop working now, not when its cached identity
    # would have expired on its own.
    forget_token(access_token)
    # Same reasoning as refresh_session above — sign_out() acts on the
    # client's own session state, so it runs on a fresh client rather than
    # the shared singleton every other request depends on.
    try:
        new_supabase_client().auth.sign_out()
    except Exception:
        pass
    return MessageResponse(message="Logged out successfully.")


def request_password_reset(email: str) -> MessageResponse:
    """Always returns success to prevent email enumeration.

    The link is aimed at the dashboard's /reset-password page explicitly. It
    used to carry no redirect at all, so Supabase sent the person to the
    project's Site URL with the recovery tokens in the URL fragment - and the
    dashboard had no page that read them, so the emailed link opened a page
    that could not reset anything (and, on any device that was not the dev
    machine, a `localhost` that was not there).
    """
    db: Client = get_supabase()
    try:
        db.auth.reset_password_for_email(
            email, {"redirect_to": settings.reset_password_url}
        )
    except Exception as e:
        log.warning("auth.password_reset_error", error=str(e))
    return MessageResponse(
        message="If an account exists for this email, a password reset link has been sent."
    )


_RESET_LINK_INVALID = (
    "This reset link is invalid or has expired. Request a new one and use it "
    "as soon as it arrives."
)


def _token_came_from_an_emailed_link(access_token: str) -> bool:
    """True when the session behind this JWT was opened by a one-time link.

    Supabase records how a session began in the token's `amr` claim: a password
    sign-in says `password`, a recovery or invite link says `otp`. The reset
    endpoint only accepts the second kind. Without the check any signed-in
    person's ordinary session token could be sent here to set a new password
    without the current one - which is exactly the rule change-password makes
    an Agency Admin satisfy.

    The signature is not re-verified here; get_user() has already done that
    by the time this is called.
    """
    import base64
    import json

    try:
        payload_b64 = access_token.split(".")[1]
        payload_b64 += "=" * (-len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64))
    except Exception:
        return False
    methods = {
        str(a.get("method")) for a in (payload.get("amr") or []) if isinstance(a, dict)
    }
    return bool(methods & {"otp", "recovery"})


def reset_password(access_token: str, new_password: str) -> MessageResponse:
    """Set a new password from the recovery token in an emailed reset link.

    Returns a plain confirmation rather than a session on purpose: after a
    reset the person signs in with the new password like any other visit, which
    also means this endpoint never hands out a session.
    """
    db: Client = get_supabase()

    try:
        user_resp = db.auth.get_user(access_token)
    except Exception as e:
        log.warning("auth.reset_token_rejected", error=str(e))
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=_RESET_LINK_INVALID)

    if not user_resp or not user_resp.user or not _token_came_from_an_emailed_link(access_token):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=_RESET_LINK_INVALID)

    user_id = str(user_resp.user.id)
    try:
        db.auth.admin.update_user_by_id(user_id, {"password": new_password})
    except Exception as e:
        log.warning("auth.reset_failed", user_id=user_id, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Could not set the new password. Try again, or request a new link.",
        )

    log.info("auth.password_reset_completed", user_id=user_id)
    return MessageResponse(message="Your password has been updated. You can now sign in.")


def accept_invite(access_token: str, new_password: str) -> AuthResponse:
    """
    Exchange an invite access_token for a session and set the user's password.
    Marks is_verified=True in public.users.
    """
    db: Client = get_supabase()

    # Validate the invite token.
    #
    # This used to call exchange_code_for_session({"auth_code": access_token}),
    # which is the PKCE flow and expects a short-lived authorization code from
    # a `?code=` query parameter. Supabase invite links do not use PKCE here —
    # /auth/v1/verify redirects with the tokens in the URL FRAGMENT:
    #
    #     .../accept-invite#access_token=eyJ…&refresh_token=…&type=invite
    #
    # and the accept-invite page reads access_token out of that fragment. So
    # the endpoint was being handed a JWT and asked to treat it as an auth
    # code. Supabase rejected every one of them with
    #
    #     invalid request: both auth code and code verifier should be non-empty
    #
    # which the bare `except Exception` below flattened into "Invalid or
    # expired invite link." — blaming the applicant's link for a flow mismatch
    # on our side. No invite could ever be accepted.
    #
    # get_user() is the correct primitive for a JWT: it verifies the signature
    # and expiry server-side and returns the user it belongs to.
    try:
        user_resp = db.auth.get_user(access_token)
    except Exception as e:
        log.warning("auth.invite_token_rejected", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired invite link.",
        )

    if not user_resp or not user_resp.user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired invite link.",
        )

    user_id = str(user_resp.user.id)
    user_email = user_resp.user.email

    # Set the user's chosen password
    try:
        db.auth.admin.update_user_by_id(user_id, {"password": new_password})
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not set password: {e}",
        )

    # Mark as verified
    db.table("users").update({"is_verified": True}).eq("id", user_id).execute()

    # Sign in with the credentials just set, so the caller gets a normal
    # session rather than the invite token (which is single-purpose).
    #
    # Deliberately on a FRESH client, not `db`: signing in rewrites that
    # client's authorization for the rest of the process, and `db` is the
    # service-key singleton every admin call depends on.
    try:
        result = new_supabase_client().auth.sign_in_with_password(
            {"email": user_email, "password": new_password}
        )
    except Exception as e:
        # The password IS set at this point, so this is recoverable by simply
        # logging in. Say that rather than implying the invite failed.
        log.warning("auth.invite_signin_failed", user_id=user_id, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Your password was set, but automatic sign-in failed. "
                   "Please sign in with your new password.",
        )

    user_row = _fetch_user_profile(db, user_id)
    log.info("auth.invite_accepted", user_id=user_id)
    return _build_auth_response(result.session, user_row)


def _fetch_user_profile(db: Client, user_id: str) -> dict:
    # agencies(agency_type) joined in for agency_admin/responder, who carry
    # no agency_type column of their own — see the comment on
    # _build_auth_response's agency_type= line for why a login/accept-invite
    # response was reporting "Agency Admin" with no BFP/PNP/MDRRMO for every
    # such account.
    result = (
        db.table("users")
        .select("*, agencies(agency_type)")
        .eq("id", user_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found.",
        )
    return result.data
