"""
Shared FastAPI dependency functions.

Role is always read from public.users — never trusted from JWT claims.
"""

import hashlib
import threading
import time

import structlog
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from gotrue.errors import AuthRetryableError

from app.core.config import settings
from app.db.supabase_client import get_supabase, new_supabase_client

_bearer = HTTPBearer()
log = structlog.get_logger()

# ── Who is this token? Asked once, then remembered for a moment ──────────────
#
# THE DASHBOARD WAS SLOW BECAUSE OF THIS FUNCTION, NOT BECAUSE OF THE DASHBOARD.
#
# Every authenticated request used to pay for two round trips to Supabase before
# doing any of its own work: a brand-new client, a fresh TLS connection and
# auth.get_user(token) - the token check - and then a PostgREST read of the
# caller's own profile row. Measured from the machine that runs the backend:
#
#     /users/me          ~800-1100 ms      /notifications/    ~1000-1300 ms
#     /dispatch/queue    ~900 ms           /stations/         ~800-900 ms
#
# and 404s, which never reach it, in 4 ms. Almost all of that is these two
# calls. A dashboard page fires five to eight requests at once, the browser runs
# six at a time, so opening Settings took about four seconds - on a console
# where, as its operators put it, every second counts.
#
# The answer to "who is this token" does not change from one request to the next
# a moment later, so it is kept for a few seconds. A stale answer can only be
# stale by that long: role and approval are still read from public.users, never
# from the token, they are just not re-read for every request in a burst. A
# sign-out forgets its token at once (see forget_token); a suspension or role
# change takes effect within the TTL.
_USER_CACHE_TTL_S = 20.0
_USER_CACHE_MAX = 512
_user_cache: dict[str, tuple[float, dict]] = {}
_user_locks: dict[str, threading.Lock] = {}
_user_cache_guard = threading.Lock()


def _token_key(token: str) -> str:
    # Hashed, so the cache never holds a usable credential.
    return hashlib.sha256(token.encode()).hexdigest()


def _cached_profile(key: str) -> dict | None:
    with _user_cache_guard:
        entry = _user_cache.get(key)
        if entry and entry[0] > time.monotonic():
            return dict(entry[1])
        if entry:
            del _user_cache[key]
    return None


def _store_profile(key: str, profile: dict) -> None:
    with _user_cache_guard:
        if len(_user_cache) >= _USER_CACHE_MAX:
            now = time.monotonic()
            for k in [k for k, (exp, _) in _user_cache.items() if exp <= now]:
                del _user_cache[k]
            if len(_user_cache) >= _USER_CACHE_MAX:
                _user_cache.clear()  # a flood of distinct tokens: start over
        _user_cache[key] = (time.monotonic() + _USER_CACHE_TTL_S, dict(profile))


def _lock_for(key: str) -> threading.Lock:
    with _user_cache_guard:
        if len(_user_locks) > _USER_CACHE_MAX * 4:
            _user_locks.clear()
        return _user_locks.setdefault(key, threading.Lock())


def forget_token(token: str | None) -> None:
    """Drop one token's cached identity - called on sign-out."""
    if not token:
        return
    with _user_cache_guard:
        _user_cache.pop(_token_key(token), None)


def clear_user_cache() -> None:
    """Forget every cached identity. Tests call this between cases."""
    with _user_cache_guard:
        _user_cache.clear()
        _user_locks.clear()


# The dev-admin identity, resolved once per process. Dev-only path, but
# get_current_user runs on every request and this must not become a DB
# round-trip per call.
_DEV_ADMIN_CACHE: dict | None = None

# Kept only as a last-resort identity when the users table has no
# provincial_admin to borrow. See the warning in _resolve_dev_admin_profile.
_DEV_ADMIN_PHANTOM_ID = "00000000-0000-0000-0000-000000000099"

# The dev bypass has to pick SOME agency_type for its synthetic/borrowed
# identity when no real provincial_admin row exists to borrow from. PNP is
# an arbitrary but stable choice — dev-only, never reachable in production.
_DEV_ADMIN_DEFAULT_AGENCY_TYPE = "PNP"


def _resolve_dev_admin_profile() -> dict:
    """
    Resolve the DEV_ADMIN_EMAIL bypass to a REAL public.users row.

    Why this exists
    ---------------
    The bypass used to return a hardcoded synthetic profile whose id
    (00000000-…-099) has no row in public.users. Reads were fine, so the
    dashboard looked healthy — but every write that records *who acted* stores
    that id into a UUID column with a foreign key to public.users, and Postgres
    rejected all of them:

        23503  Key (reviewed_by)=(00000000-…-099) is not present in table "users"
               violates foreign key constraint "access_requests_reviewed_by_fkey"

    That is not specific to access requests; it is every audited write the dev
    admin can reach (dispatch_log.dispatcher_id, reviewed_by, …). The failure
    also surfaced as an unhandled 500, which — see the CORS note in main.py —
    reached the browser as "Failed to fetch", pointing whoever was debugging at
    CORS and a supposedly-down backend instead of a foreign key.

    A development shortcut is allowed to skip password checking. It is not
    allowed to invent an identity the database cannot honour, because that
    turns a convenience into a class of bug that only ever reproduces in dev.
    """
    global _DEV_ADMIN_CACHE
    if _DEV_ADMIN_CACHE is not None:
        return _DEV_ADMIN_CACHE

    log = structlog.get_logger()
    db = get_supabase()

    # Prefer a real account that actually matches DEV_ADMIN_EMAIL.
    row = (
        db.table("users")
        .select("id, email, full_name, role, approval_status, agency_id, agency_type, badge_id, is_verified")
        .eq("email", settings.dev_admin_email)
        .limit(1)
        .execute()
    ).data

    # Otherwise borrow the longest-standing real provincial_admin. The
    # bypass's whole purpose is "log me in as an admin without a password",
    # and any provincial_admin is equivalent for that.
    if not row:
        row = (
            db.table("users")
            .select("id, email, full_name, role, approval_status, agency_id, agency_type, badge_id, is_verified")
            .eq("role", "provincial_admin")
            .order("created_at", desc=False)
            .limit(1)
            .execute()
        ).data
        if row:
            log.warning(
                "auth.dev_admin_borrowed_identity",
                dev_admin_email=settings.dev_admin_email,
                acting_as=row[0]["email"],
                detail="No users row matches DEV_ADMIN_EMAIL; acting as this "
                       "provincial_admin so audited writes satisfy their foreign keys.",
            )

    if row:
        _DEV_ADMIN_CACHE = dict(row[0])
        return _DEV_ADMIN_CACHE

    # No provincial_admin exists at all. Return the phantom so the app still
    # boots and reads still work, but say plainly that writes will fail —
    # silence here is what made the original bug so hard to place.
    log.error(
        "auth.dev_admin_no_real_user",
        dev_admin_email=settings.dev_admin_email,
        detail="No provincial_admin in public.users. Falling back to a synthetic "
               "id; any write recording the acting user WILL fail with FK 23503.",
    )
    _DEV_ADMIN_CACHE = {
        "id":              _DEV_ADMIN_PHANTOM_ID,
        "email":           settings.dev_admin_email,
        "full_name":       "Dev Admin",
        "role":            "provincial_admin",
        "approval_status": "not_required",
        "agency_id":       None,
        "agency_type":     _DEV_ADMIN_DEFAULT_AGENCY_TYPE,
        "badge_id":        None,
        "is_verified":     True,
    }
    return _DEV_ADMIN_CACHE


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> dict:
    """
    Validates the Bearer token and returns the user's full profile row
    from public.users (role + approval_status included).

    In development with DEV_ADMIN_EMAIL set, a token prefixed with
    "dev-admin-token-" is accepted without hitting Supabase Auth,
    and a synthetic provincial_admin profile is returned directly.

    Raises HTTP 401 if token is missing, expired, or invalid.
    """
    token = credentials.credentials

    # ── Dev admin bypass ─────────────────────────────────────
    # Only active when ENVIRONMENT=development and DEV_ADMIN_EMAIL is set.
    # Mirrors the bypass in auth_service.login_user so that the fake
    # token issued at login is also accepted by protected endpoints.
    if (
        settings.environment == "development"
        and settings.dev_admin_email
        and token.startswith("dev-admin-token-")
    ):
        # Resolves to a REAL public.users row so that audited writes satisfy
        # their foreign keys — see _resolve_dev_admin_profile for the failure
        # this replaced.
        return _resolve_dev_admin_profile()

    # ── Normal path ──────────────────────────────────────────
    # One validation per token at a time. A page load sends several requests
    # with the same token in the same instant; letting each run its own two
    # Supabase round trips is the very stampede the cache exists to remove.
    key = _token_key(token)
    hit = _cached_profile(key)
    if hit is not None:
        return hit
    with _lock_for(key):
        hit = _cached_profile(key)
        if hit is not None:
            return hit
        profile = _load_profile(token)
        _store_profile(key, profile)
        return dict(profile)


def _load_profile(token: str) -> dict:
    """Validate the token with Supabase and read the caller's profile row.

    The uncached half of get_current_user - see the note above _USER_CACHE_TTL_S.
    """
    # ── Validate via Supabase ────────────────────────────────
    db = get_supabase()

    # ONE retry, and only for AuthRetryableError — gotrue's own name for a
    # transient failure reaching Supabase's auth server (a dropped HTTP/2
    # connection, a timeout), as opposed to the server actually answering
    # "this token is bad". Observed live: a request would fail with
    # `AuthRetryableError: ConnectionTerminated` and this endpoint reported
    # it to the client identically to a genuinely expired token — "Invalid
    # or expired token." A resident or responder reading that message has
    # no way to tell "your session is dead, log in again" apart from "the
    # backend's connection to Supabase hiccuped for a moment", and only one
    # of those is actually true here. Any other exception (a real rejection
    # from Supabase, a malformed token) is not retried — retrying a genuine
    # rejection just delays the same 401 by one round trip.
    #
    # new_supabase_client() FOR THE VALIDATION CALL, NOT THE SHARED `db` —
    # this dependency runs on every protected request, several of them
    # concurrently on every dashboard page load (users/me, dispatch/queue,
    # dispatch/distress, ... all fire in parallel). Live logs on 2026-09-15
    # showed the exact same endpoint flapping between 200 and 401 seconds
    # apart on an unchanged, unexpired token — not a one-time failure that
    # cleared up, but continuous flakiness for as long as the session ran.
    # auth.get_user(token) is supposed to be a stateless check of the token
    # it's given, but calling it concurrently, from many requests at once,
    # on the ONE client object every other endpoint also shares for its
    # service-role authorization, is exactly the class of bug
    # new_supabase_client's docstring already describes for sign-in and
    # (see auth_service.refresh_session / logout_user) refresh and sign-out
    # — this is the same shared-mutable-client problem hitting a fourth
    # call site. A fresh, throwaway client per validation is never a party
    # to that contention, at the cost of one extra client construction per
    # request — negligible next to a dispatch console that logs itself out.
    last_error: Exception | None = None
    for attempt in range(2):
        try:
            result = new_supabase_client().auth.get_user(token)
            if not result or not result.user:
                raise ValueError("No user")
            last_error = None
            break
        except AuthRetryableError as e:
            last_error = e
            log.warning(
                "auth.retryable_error",
                attempt=attempt + 1,
                error=str(e),
            )
            continue
        except Exception as e:
            last_error = e
            break

    if last_error is not None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # THE 401 BELOW WAS UNREACHABLE, AND IT BROKE EVERY ENDPOINT.
    #
    # PostgREST's single() raises PGRST116 ("Cannot coerce the result to a
    # single JSON object") when a query matches zero rows — it never returns
    # an empty result. So `if not profile.data` could not fire, and the error
    # escaped into the middleware as a 500.
    #
    # The cost is out of all proportion to the typo. This dependency runs
    # before EVERY authenticated endpoint, so an account that authenticates
    # successfully but has no public.users row makes the whole API return 500
    # — /incidents/my, /responder/queue, /users/me, all of it. The phone shows
    # a signed-in user whose every screen is broken, and the log says
    # "Internal Server Error" without ever mentioning a profile. That is what
    # happens to an account created before migration 013's trigger existed.
    #
    # WHY THIS CATCHES RATHER THAN SWITCHING TO maybe_single().
    #
    # maybe_single() is the tidier call and is what user_service.get_my_profile
    # uses. Here it would change the shape of the query chain that this
    # dependency's test doubles are built around — eighty tests across the
    # suite mock `.select().eq().single().execute()` — and rewriting all of
    # them to fix a zero-row branch would be a large diff over the auth path
    # of a working system. The narrow catch below is the same behaviour with
    # no blast radius.
    #
    # The check is deliberately specific. A bare `except Exception` here would
    # turn a genuine database outage into "your account has no profile", which
    # sends whoever is debugging to look at the wrong thing entirely.
    try:
        profile = (
            db.table("users")
            .select("id, email, full_name, role, approval_status, agency_id, agency_type, badge_id, is_verified")
            .eq("id", str(result.user.id))
            .single()
            .execute()
        )
    except Exception as exc:
        if "PGRST116" not in str(exc):
            raise
        profile = None

    if profile is None or not profile.data:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            # Names which of the two things is wrong. "Invalid or expired
            # token" would send the user to sign in again, and signing in
            # again cannot fix this — the token is fine, the account is
            # half-created.
            detail=(
                "Your sign-in worked, but this account has no profile record. "
                "Contact an administrator to have it created."
            ),
        )

    return profile.data


def require_role(*roles: str):
    """
    Raises HTTP 403 if the current user's role is not in the allowed list.

    Usage:
        @router.post("/", dependencies=[Depends(require_role("agency_admin", "provincial_admin"))])
    """
    def _check(current_user: dict = Depends(get_current_user)) -> dict:
        if current_user.get("role") not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Role '{current_user.get('role')}' is not permitted to perform this action.",
            )
        return current_user

    return _check


def require_approved_responder(
    current_user: dict = Depends(get_current_user),
) -> dict:
    """
    Blocks Responder-only actions until the account is approved.

    Raises HTTP 403 if:
    - role is not 'responder'
    - approval_status is not 'approved'

    Usage:
        @router.post("/on-duty", dependencies=[Depends(require_approved_responder)])
    """
    if current_user.get("role") != "responder":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action is only available to Responders.",
        )
    if current_user.get("approval_status") != "approved":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your Responder account is pending approval by your Agency Admin. "
                   "You will be notified when your badge ID has been verified.",
        )
    return current_user


#: Shorthand for the common `Depends(require_role("provincial_admin"))` case.
#: Equivalent to `require_role("provincial_admin")` — new routers should
#: prefer this name for readability.
require_provincial_admin = require_role("provincial_admin")

#: Either admin role. Used by modules a Provincial Admin sees across every
#: station of their own agency_type, and Agency Admin sees scoped to their
#: one station (Analytics, Reports) — the route itself stays open to both;
#: the SERVICE layer is what narrows an agency_admin's result to
#: `current_user["agency_id"]`, and a provincial_admin's result to
#: `current_user["agency_type"]`.
require_admin = require_role("agency_admin", "provincial_admin")


def assert_agency_scope(current_user: dict, agency_id: str) -> None:
    """
    Raise HTTP 403 if the current user is trying to act outside their own
    scope. agency_admin must match `agency_id` exactly (one station).
    provincial_admin must match the target agency_id's `agency_type` (any
    station of their own agency type, resolved via a lookup — a
    provincial_admin has no single `agency_id` of their own).

    A shared version for routers added after this point (audit, agencies,
    analytics, geographic, governance, ai_classification, search). Existing
    per-router copies (`_assert_agency_write_scope` in stations.py,
    `_assert_agency_scope` in rubric.py) are NOT touched here — they work,
    and consolidating them is a separate, lower-value refactor.
    """
    role = current_user.get("role")
    if role == "provincial_admin":
        db = get_supabase()
        target = (
            db.table("agencies")
            .select("agency_type")
            .eq("id", agency_id)
            .limit(1)
            .execute()
        ).data
        if target and target[0]["agency_type"] == current_user.get("agency_type"):
            return
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only act on your own agency type's records.",
        )
    if str(current_user.get("agency_id") or "") != str(agency_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only act on your own agency's records.",
        )
