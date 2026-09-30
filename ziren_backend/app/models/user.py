"""
User Pydantic models — request/response schemas for auth endpoints.
"""

from enum import Enum
from uuid import UUID
from datetime import date, datetime

from pydantic import BaseModel, EmailStr, field_validator


# Accessibility vocabulary shared by the profile model and the mobile client.
# Module-level rather than a class attribute: Pydantic v2 turns any
# underscore-prefixed class attribute into a ModelPrivateAttr, which is not a
# set and cannot be used in a validator.
DISABILITY_TYPES = frozenset({
    "visual", "hearing", "speech", "mobility", "intellectual", "psychosocial",
})

CONTACT_MODES = frozenset({"any", "sms_only", "app_only", "voice_ok"})

# IDs a resident may offer to reach verification_level 2. The LGU-issued ones
# additionally prove Biliran residency, because an LGU only issues to its own
# residents — a passport proves identity but not where the holder lives.
LGU_ISSUED_ID_TYPES = frozenset({
    "barangay_id", "voters_id", "pwd_id", "senior_citizen_id",
})
NATIONAL_ID_TYPES = frozenset({
    "philsys", "umid", "drivers_license", "passport",
    "postal_id", "philhealth", "sss", "tin",
})
VALID_ID_TYPES = LGU_ISSUED_ID_TYPES | NATIONAL_ID_TYPES


class UserRole(str, Enum):
    resident         = "resident"
    responder        = "responder"
    agency_admin     = "agency_admin"
    provincial_admin = "provincial_admin"


class ApprovalStatus(str, Enum):
    not_required = "not_required"
    pending      = "pending"
    approved     = "approved"
    rejected     = "rejected"


# ── Request models ──────────────────────────────────────────

class RegisterRequest(BaseModel):
    email:     EmailStr
    password:  str
    full_name: str
    role:      UserRole = UserRole.resident

    # Responder-only fields
    agency_id: UUID | None = None   # required if role == responder
    badge_id:  str | None = None    # required if role == responder

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters.")
        if not any(c.isupper() for c in v):
            raise ValueError("Password must contain at least one uppercase letter.")
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit.")
        return v

    @field_validator("full_name")
    @classmethod
    def full_name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Full name is required.")
        return v.strip()

    # Roles that may NEVER be obtained through public self-registration.
    # Agency Admins are created by a Provincial Admin via
    # /users/provincial/agency-admins; Provincial Admins are provisioned
    # out-of-band. Listing them here means the rejection happens at the
    # request boundary, before any account is created.
    _SELF_REGISTRATION_BLOCKED = (UserRole.agency_admin, UserRole.provincial_admin)

    @field_validator("role")
    @classmethod
    def block_privileged_self_registration(cls, v: "UserRole") -> "UserRole":
        """
        Reject privileged-role self-registration at validation time (422).

        SECURITY: without this, POST /auth/register accepted
        role='provincial_admin' from an unauthenticated caller and
        provisioned a fully verified admin account. The service-layer
        docstring claimed these roles were "blocked" but no code enforced
        it. Do not remove this validator.
        """
        if v in (UserRole.agency_admin, UserRole.provincial_admin):
            raise ValueError(
                f"Self-registration as '{v.value}' is not permitted. "
                "Administrator accounts must be provisioned by a Provincial Admin."
            )
        return v

    def model_post_init(self, __context) -> None:  # type: ignore[override]
        """Cross-field validation after all fields are set."""
        if self.role in (UserRole.responder, UserRole.agency_admin):
            if not self.agency_id:
                raise ValueError("agency_id is required for Responder and Agency Admin registration.")
        if self.role == UserRole.responder:
            if not self.badge_id or not self.badge_id.strip():
                raise ValueError("badge_id is required for Responder registration.")


class AccessRequestCreate(BaseModel):
    """
    An Agency Admin asking to be given a dashboard account.

    Deliberately carries NO password. This is a request, not a registration —
    it grants nothing on its own. A Provincial Admin approves it via
    POST /users/provincial/agency-admins, which creates the account and sends
    a Supabase invite; the applicant sets their own password on /accept-invite.

    The dashboard used to post these to /auth/register with role='agency_admin'
    instead, which the privileged-role validator above rejects outright.
    """
    full_name: str
    email:     EmailStr
    agency_id: UUID
    position:  str | None = None

    @field_validator("full_name")
    @classmethod
    def full_name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Full name is required.")
        return v.strip()


class AccessRequestResponse(BaseModel):
    id:         UUID
    full_name:  str
    email:      str
    position:   str | None
    agency_id:  UUID
    status:     str
    created_at: datetime


class LoginRequest(BaseModel):
    email:    EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


# ── Response models ─────────────────────────────────────────

class UserProfile(BaseModel):
    id:              UUID
    email:           str
    full_name:       str
    role:            UserRole
    approval_status: ApprovalStatus
    agency_id:       UUID | None
    badge_id:        str | None
    is_verified:     bool
    created_at:      datetime
    # For agency_admin/responder, denormalised from the agencies join. For
    # provincial_admin, read directly off users.agency_type (no agency_id to
    # join through — see model_validate below, which never overwrites a
    # value already present on the raw row). None for resident.
    agency_type:     str | None = None
    # The station's own name, e.g. "BFP Naval Station". Carried because a
    # responder's profile has to show WHICH unit they belong to, and
    # agency_id is a UUID nobody can verify is theirs.
    agency_name:     str | None = None
    agency_municipality: str | None = None
    # Responder spec Section 21 — read-only "who do I call" info, never
    # editable from this endpoint.
    agency_contact_number: str | None = None
    # Phase 10.5 — Resident profile fields
    phone_number:               str | None = None
    barangay:                   str | None = None
    municipality_address:       str | None = None
    preferred_language:         str | None = None
    push_notifications_enabled: bool       = True
    emergency_contact_name:     str | None = None
    emergency_contact_number:   str | None = None
    # How the account stands: warnings on record, and the end of a suspension
    # from reporting (a date in the past is not a suspension). See
    # resident_account_service.
    sos_warning_count:          int | None = 0
    sos_suspended_until:        datetime | None = None
    # Phase 012 — structured residency.
    # verification_level is tiered trust: 0 unverified, 1 phone-verified,
    # 2 resident-verified. It is shown to dispatchers as reporter credibility
    # and MUST NOT be used to gate incident submission.
    barangay_id:                UUID | None = None
    verification_level:         int        = 0
    verification_method:        str | None = None
    valid_id_type:              str | None = None
    valid_id_number:            str | None = None
    # Phase 012 — accessibility. Carried through to the responding crew.
    is_pwd:                     bool       = False
    pwd_id_number:              str | None = None
    disability_types:           list[str]  = []
    accessibility_notes:        str | None = None
    preferred_contact_mode:     str        = "any"
    verified_at:                datetime | None = None

    # Phase 033 -- self-service profile avatar. A signed URL, minted fresh on
    # every fetch (see user_service._signed_url) -- never the raw avatar_path,
    # which is a storage key into a private bucket and has no reason to reach
    # the client. None until the user uploads a picture; the app falls back
    # to initials.
    avatar_url:                 str | None = None

    # Phase 020 -- structured identity, consent record, verification evidence.
    #
    # The image paths are deliberately ABSENT from this model. They are storage
    # keys into a private bucket and are only ever handed out as short-lived
    # signed URLs, to verifying admins, through the verification endpoints.
    # Putting them on the profile a user fetches for themselves would widen
    # their exposure for no gain.
    first_name:                 str | None = None
    middle_name:                str | None = None
    last_name:                  str | None = None
    name_suffix:                str | None = None
    date_of_birth:              date | None = None
    sex:                        str | None = None
    purok_sitio:                str | None = None
    street_address:             str | None = None
    residency_proof_type:       str | None = None
    liveness_method:            str | None = None
    terms_accepted_at:          datetime | None = None
    terms_version:              str | None = None
    privacy_version:            str | None = None
    consent_locale:             str | None = None
    rank_or_position:           str | None = None
    unit_assignment:            str | None = None
    date_joined:                date | None = None

    @classmethod
    def model_validate(cls, obj, *args, **kwargs):  # type: ignore[override]
        """
        Flatten Supabase's nested join dicts before normal validation runs.

        agencies: {"agencies": {"agency_type": "BFP"}} -> agency_type="BFP"

        barangays: {"barangays": {"name": "Larrazabal"}} -> barangay="Larrazabal"

        The barangay flattening fixes a field that had been blank on every
        account created since migration 012. That migration replaced the
        free-text `barangay` column with `barangay_id`, an FK into the
        reference table -- but this endpoint kept reading the old column, and
        registration only ever writes the new one. So the mobile profile
        screen asked for `barangay`, got NULL, and showed nothing. Only
        pre-012 accounts still displayed an address, which is why it looked
        like the field worked.

        The FK wins when present; the legacy column is the fallback so
        pre-012 accounts keep rendering.
        """
        if isinstance(obj, dict):
            obj = dict(obj)

            agencies = obj.pop("agencies", None)
            if isinstance(agencies, dict):
                obj["agency_type"] = agencies.get("agency_type")
                obj["agency_name"] = agencies.get("name")
                obj["agency_municipality"] = agencies.get("municipality")
                obj["agency_contact_number"] = agencies.get("contact_number")
            else:
                obj.setdefault("agency_type", None)

            barangays = obj.pop("barangays", None)
            if isinstance(barangays, dict) and barangays.get("name"):
                obj["barangay"] = barangays["name"]
                # municipality_address is entered by hand at registration and
                # can drift from the barangay's real municipality. The
                # reference table is authoritative, so prefer it.
                if barangays.get("municipality"):
                    obj["municipality_address"] = barangays["municipality"]

        return super().model_validate(obj, *args, **kwargs)


class AuthTokens(BaseModel):
    access_token:  str
    refresh_token: str
    token_type:    str = "bearer"
    expires_in:    int  # seconds


class AuthResponse(BaseModel):
    user:   UserProfile
    tokens: AuthTokens


class MessageResponse(BaseModel):
    message: str


# ── Phase 10.5 — Profile update request ─────────────────────

class UpdateProfileRequest(BaseModel):
    """
    Resident can update their own non-sensitive profile fields.
    Role, approval_status, agency_id, badge_id are NOT updatable here —
    those are admin-only fields enforced at the RLS level.
    """
    full_name:                  str | None = None
    phone_number:               str | None = None
    barangay:                   str | None = None
    barangay_id:                UUID | None = None
    municipality_address:       str | None = None
    preferred_language:         str | None = None
    push_notifications_enabled: bool | None = None
    emergency_contact_name:     str | None = None
    emergency_contact_number:   str | None = None
    # Accessibility is self-service: a resident may correct these at any time
    # without an admin. verification_level is deliberately absent — it is a
    # trust signal assigned by the system and frozen by RLS (migration 012).
    is_pwd:                     bool | None = None
    pwd_id_number:              str | None = None
    disability_types:           list[str] | None = None
    accessibility_notes:        str | None = None
    preferred_contact_mode:     str | None = None
    # A resident may submit or correct their own ID. verification_level stays
    # frozen by RLS — an admin raises it after checking the physical card.
    valid_id_type:              str | None = None
    valid_id_number:            str | None = None
    # The client uploads directly to the private "avatars" bucket with its own
    # JWT (storage RLS scopes writes to <auth.uid()>/...), then calls this
    # endpoint with the resulting path so it lands on the row. Never a URL —
    # see UserProfile.avatar_url for how it comes back out.
    avatar_path:                str | None = None

    @field_validator("valid_id_type")
    @classmethod
    def valid_id_type_known(cls, v: str | None) -> str | None:
        if v is not None and v not in VALID_ID_TYPES:
            raise ValueError(
                f"valid_id_type must be one of: {', '.join(sorted(VALID_ID_TYPES))}."
            )
        return v

    @field_validator("preferred_contact_mode")
    @classmethod
    def valid_contact_mode(cls, v: str | None) -> str | None:
        if v is not None and v not in CONTACT_MODES:
            raise ValueError(
                f"preferred_contact_mode must be one of: {', '.join(sorted(CONTACT_MODES))}."
            )
        return v

    @field_validator("disability_types")
    @classmethod
    def valid_disability_types(cls, v: list[str] | None) -> list[str] | None:
        if v is None:
            return None
        unknown = set(v) - DISABILITY_TYPES
        if unknown:
            raise ValueError(
                f"Unknown disability_types: {sorted(unknown)}. "
                f"Allowed: {sorted(DISABILITY_TYPES)}."
            )
        return v

    @field_validator("full_name")
    @classmethod
    def full_name_not_blank(cls, v: str | None) -> str | None:
        if v is not None and not v.strip():
            raise ValueError("Full name cannot be blank.")
        return v.strip() if v else None

    @field_validator("preferred_language")
    @classmethod
    def valid_language(cls, v: str | None) -> str | None:
        if v is not None and v not in ("Filipino", "English", "Bisaya", "Waray"):
            raise ValueError("preferred_language must be one of: Filipino, English, Bisaya, Waray.")
        return v
