"""
/auth — Authentication endpoints with rate limiting.

All endpoints here are public (no auth required to reach them),
but rate-limited to prevent brute-force and spam abuse.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, field_validator

from app.core.config import settings
from app.models.user import (
    AccessRequestCreate,
    AuthResponse,
    AuthTokens,
    LoginRequest,
    MessageResponse,
    RegisterRequest,
)
from app.core.rate_limit import limiter
from app.services import audit_service, auth_service, face_match_service

router = APIRouter()
_bearer = HTTPBearer()


def _record_admin_sign_in(request: Request, result: AuthResponse) -> None:
    user = result.user
    role = getattr(user.role, "value", user.role)
    if role not in ("agency_admin", "provincial_admin"):
        return
    forwarded = request.headers.get("x-forwarded-for")
    ip = forwarded.split(",")[0].strip() if forwarded else (
        request.client.host if request.client else None
    )
    audit_service.record(
        actor={"id": str(user.id), "role": role, "full_name": user.full_name},
        action="auth.login",
        target_type="session",
        target_id=str(user.id),
        target_label=user.email,
        metadata={"ip": ip, "user_agent": request.headers.get("user-agent")},
        agency_type=user.agency_type,
    )


class ResetPasswordRequest(BaseModel):
    """The recovery token from an emailed link, and the password to set."""

    access_token: str
    password: str

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        # The same policy RegisterRequest and ChangePasswordRequest enforce -
        # one password rule, not three that could drift apart.
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters.")
        if not any(c.isupper() for c in v):
            raise ValueError("Password must contain at least one uppercase letter.")
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit.")
        return v


class FaceMatchRequest(BaseModel):
    """Two aligned face crops, base64 of raw 112x112x3 RGB.

    Not images. The handset has already detected and aligned both faces with
    ML Kit, so what travels is pixels — see face_match_service for why that is
    the shape rather than JPEG.
    """

    id_face: str
    selfie_face: str
    #: Which crop alignment made these (face_match_service.ALIGN_VERSION).
    #: Absent from app builds before 2026-10-08, whose crops were not faces.
    align: int = 1


@router.post("/accept-invite", response_model=AuthResponse)
@limiter.limit("10/minute")
def accept_invite(request: Request, body: dict):
    """
    Accept an invite and set a password.
    Body: { "access_token": "...", "password": "..." }
    """
    access_token = body.get("access_token", "")
    password = body.get("password", "")
    if not access_token or not password:
        from fastapi import HTTPException, status
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="access_token and password are required.",
        )
    return auth_service.accept_invite(access_token, password)


@router.post("/register", response_model=AuthResponse, status_code=201)
@limiter.limit(settings.rate_limit_login)
def register(request: Request, body: RegisterRequest):
    """
    Register a new citizen account.
    Dispatcher/admin accounts must be created by an agency_admin.
    """
    return auth_service.register_user(body)


@router.post(
    "/access-request",
    response_model=MessageResponse,
    status_code=201,
)
@limiter.limit("5/hour")
def request_access(request: Request, body: AccessRequestCreate):
    """
    Record an Agency Admin's request for a dashboard account.

    This is the endpoint the dashboard's "Request Access" page should call.
    It previously posted to /register with role='agency_admin', which the
    privileged-role validator rejects — so the page had been failing for every
    applicant with "Self-registration as 'agency_admin' is not permitted."

    Nothing is provisioned here. A Provincial Admin reviews the request and
    calls POST /users/provincial/agency-admins to create the account and
    send the invite.

    Rate limited per hour rather than per minute: a genuine applicant submits
    once, so a tighter window only ever punishes someone retrying after a
    connection drop.
    """
    return auth_service.create_access_request(body)


@router.post("/login", response_model=AuthResponse)
@limiter.limit(settings.rate_limit_login)
def login(request: Request, body: LoginRequest):
    """
    Login with email + password.
    Returns access token (30 min) and refresh token (7 days).
    """
    result = auth_service.login_user(body)
    # An admin sign-in is an auditable event, and it is what Login & Devices
    # shows the account owner as their sign-in history. Recorded for admin
    # roles only, and never allowed to fail the login (audit_service.record
    # swallows its own errors).
    _record_admin_sign_in(request, result)
    return result


@router.post("/refresh", response_model=AuthTokens)
def refresh(body: dict):
    """Exchange a refresh token for a new access token."""
    refresh_token = body.get("refresh_token", "")
    return auth_service.refresh_session(refresh_token)


@router.post("/logout", response_model=MessageResponse)
def logout(credentials: HTTPAuthorizationCredentials = Depends(_bearer)):
    """Invalidate the current session."""
    return auth_service.logout_user(credentials.credentials)


@router.post("/password-reset", response_model=MessageResponse)
@limiter.limit("5/minute")
def request_password_reset(request: Request, body: dict):
    """
    Send a password reset email.
    Always returns success to prevent email enumeration.
    """
    email = body.get("email", "")
    return auth_service.request_password_reset(email)


@router.post("/reset-password", response_model=MessageResponse)
@limiter.limit("10/minute")
def reset_password(request: Request, body: ResetPasswordRequest):
    """
    Finish a password reset started from the emailed link.
    Body: { "access_token": "<recovery token from the link>", "password": "..." }
    """
    return auth_service.reset_password(body.access_token, body.password)


@router.post("/face-match")
@limiter.limit("12/minute")
def face_match(request: Request, body: FaceMatchRequest):
    """Does the selfie look like the photo on the ID?

    PUBLIC, AND IT HAS TO BE.

    This runs during registration, at the selfie step, which is before signUp
    has been called — there is no account yet and therefore no token. Deferring
    the check until after the account exists would mean the person finds out
    they photographed the wrong card once the form is already submitted, which
    is precisely the "come back in three days, an admin rejected you" loop this
    feature exists to remove.

    So it is rate-limited instead, at a rate a real registration cannot reach:
    a person retaking a selfie a few times uses three or four calls, and twelve
    a minute from one address is already far past that. There is nothing to
    enumerate here — the endpoint reads no database, returns nothing about any
    account, and its whole output is one number about two images the caller
    already has.

    Returns 200 with verdict "unavailable" when the model is not installed on
    this deployment, NOT an error. That is a supported state: the reviewing
    admin compares the photographs by eye exactly as they did before. A 503
    would make the client render it as a failure and tell the person something
    is broken when nothing is.
    """
    if body.align < face_match_service.ALIGN_VERSION:
        # An app build whose crops were the whole photo, not the face: any
        # score would be a number about nothing. Unavailable, so the admin
        # compares by eye - the supported state, not an error.
        return {
            "model": face_match_service.MODEL_NAME,
            "threshold_match": face_match_service.MATCH_AT,
            "threshold_no_match": face_match_service.NO_MATCH_BELOW,
            "score": None,
            "verdict": "unavailable",
            "available": False,
            "message": face_match_service.describe("unavailable", None),
        }
    try:
        result = face_match_service.compare(body.id_face, body.selfie_face)
    except ValueError as exc:
        # A malformed crop is the caller's bug, and saying which field and what
        # length is the difference between a five-minute fix and an afternoon.
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        )

    result["message"] = face_match_service.describe(
        result["verdict"], result.get("score")
    )
    return result
