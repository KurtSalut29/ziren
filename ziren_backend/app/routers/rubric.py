"""
Rubric config router — Phase 5.3.

All endpoints require agency_admin or provincial_admin role.
Agency Admins are additionally scoped to their own agency_type:
  - read/write only their own agency's configs and audit log
  - cannot activate a config for a different agency
Provincial Admin is scoped to their own agency_type too, just at the
provincial level (every station of that type) rather than one station.

Endpoint surface:
  GET    /rubric/{agency_type}/configs              — list all versions
  POST   /rubric/{agency_type}/configs              — upload new version
  GET    /rubric/{agency_type}/configs/active       — get active config (with rules)
  GET    /rubric/{agency_type}/configs/{config_id}  — get specific version (with rules)
  POST   /rubric/{agency_type}/configs/{config_id}/activate — activate a version
  GET    /rubric/{agency_type}/audit-log            — audit trail
  POST   /rubric/evaluate                           — evaluate signals (internal/test)
  GET    /rubric/health                             — health probe

Security:
  - require_role("agency_admin", "provincial_admin") on every endpoint
  - _assert_agency_scope() additionally blocks agency_admin/provincial_admin
    from accessing a different agency_type's resources — role check alone
    is insufficient
  - /rubric/evaluate is also admin-only (not public) so rubric logic
    is not externally queryable by unauthenticated clients
"""

from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.dependencies import get_current_user, require_role
from app.db.supabase_client import get_supabase
from app.models.rubric import (
    AgencyType,
    RubricAuditLogResponse,
    RubricConfigActivateRequest,
    RubricConfigDetailResponse,
    RubricConfigResponse,
    RubricConfigUploadRequest,
    RubricEvaluationResult,
)
from app.services import rubric_service, audit_service

log = structlog.get_logger()
router = APIRouter()

# ── Reusable dependency: admin role required ──────────────────────────────────
_admin_dep = Depends(require_role("agency_admin", "provincial_admin"))


# ── Scope enforcement helper ──────────────────────────────────────────────────

def _assert_agency_scope(current_user: dict, agency_type: AgencyType) -> None:
    """
    Raises HTTP 403 if an agency_admin or provincial_admin attempts to access
    a different agency_type's resources.

    agency_admin's agency_type is resolved by joining their agency_id to the
    agencies table — this lookup was done at auth time and is in the profile.
    We store agency_id (UUID) on the user, not agency_type string, so we need
    the agencies table. For the router this is done via a DB lookup on the
    profile's agency_id. provincial_admin carries agency_type directly on
    their profile — no agency_id, no lookup needed.

    Called on every endpoint that takes {agency_type} as a path param.
    """
    role = current_user.get("role")

    if role == "provincial_admin":
        user_agency_type = current_user.get("agency_type")
        if user_agency_type != agency_type.value:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    f"You are the Provincial Admin for {user_agency_type}. "
                    f"You cannot access {agency_type.value} rubric configuration."
                ),
            )
        return

    # agency_admin: resolve their agency_type from their agency_id
    user_agency_id = current_user.get("agency_id")
    if not user_agency_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has no agency assigned. Contact your Provincial Admin.",
        )

    db = get_supabase()
    agency_row = (
        db.table("agencies")
        .select("agency_type")
        .eq("id", str(user_agency_id))
        .single()
        .execute()
    )
    if not agency_row.data:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your agency record could not be found.",
        )

    user_agency_type = agency_row.data.get("agency_type")
    if user_agency_type != agency_type.value:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"You are an Agency Admin for {user_agency_type}. "
                f"You cannot access {agency_type.value} rubric configuration."
            ),
        )


# =============================================================================
# Config endpoints
# =============================================================================

@router.get(
    "/{agency_type}/configs",
    response_model=list[RubricConfigResponse],
    summary="List all rubric config versions for an agency",
)
def list_configs(
    agency_type: AgencyType,
    current_user: dict = _admin_dep,
):
    """
    Returns all config versions for the agency, newest first.
    Rules are omitted from this list — use the detail endpoint to fetch rules.
    """
    _assert_agency_scope(current_user, agency_type)
    db = get_supabase()
    configs = rubric_service.list_configs(agency_type, db)
    return [_config_to_response(c) for c in configs]


@router.post(
    "/{agency_type}/configs",
    response_model=RubricConfigDetailResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a new rubric config version (does not activate automatically)",
)
def upload_config(
    agency_type: AgencyType,
    body: RubricConfigUploadRequest,
    current_user: dict = _admin_dep,
):
    """
    Store a new rule-set version for the agency.
    The new version is NOT activated automatically — use the /activate endpoint.
    This two-step design prevents accidental activation of an untested config.

    A config_created audit record is written atomically with the config row.
    """
    _assert_agency_scope(current_user, agency_type)
    db = get_supabase()

    try:
        config = rubric_service.upload_config(
            agency_type=agency_type,
            request=body,
            actor_id=str(current_user["id"]),
            db=db,
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )

    log.info(
        "rubric.router.config_uploaded",
        agency_type=agency_type.value,
        version=config.version,
        actor_id=current_user["id"],
    )
    return _config_to_detail_response(config)


@router.get(
    "/{agency_type}/configs/active",
    response_model=RubricConfigDetailResponse,
    summary="Get the currently active rubric config (includes rules)",
)
def get_active_config(
    agency_type: AgencyType,
    current_user: dict = _admin_dep,
):
    """
    Returns the active config with its full rule list.
    Returns 404 if no config has been activated yet (seed fallback is in use).
    """
    _assert_agency_scope(current_user, agency_type)
    db = get_supabase()
    config = rubric_service.get_active_config(agency_type, db)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                f"No active rubric config found for {agency_type.value}. "
                "The engine is using the bundled seed file as a fallback. "
                "Upload and activate a config to make it authoritative."
            ),
        )
    return _config_to_detail_response(config)


@router.get(
    "/{agency_type}/configs/{config_id}",
    response_model=RubricConfigDetailResponse,
    summary="Get a specific rubric config version (includes rules)",
)
def get_config(
    agency_type: AgencyType,
    config_id: UUID,
    current_user: dict = _admin_dep,
):
    """Returns a specific config version with its full rule list."""
    _assert_agency_scope(current_user, agency_type)
    db = get_supabase()
    config = rubric_service.get_config_by_id(str(config_id), db)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Rubric config {config_id} not found.",
        )
    if config.agency_type != agency_type:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Rubric config {config_id} not found for {agency_type.value}.",
        )
    return _config_to_detail_response(config)


@router.post(
    "/{agency_type}/configs/{config_id}/activate",
    response_model=RubricConfigDetailResponse,
    summary="Activate a rubric config version (deactivates the current active one)",
)
def activate_config(
    agency_type: AgencyType,
    config_id: UUID,
    body: RubricConfigActivateRequest,
    current_user: dict = _admin_dep,
):
    """
    Activate a config version for the agency.
    The currently active version is automatically deactivated.
    Both the deactivation and activation are written to the audit log.
    The in-process cache is invalidated so the next evaluate() uses the new rules.
    """
    _assert_agency_scope(current_user, agency_type)
    db = get_supabase()

    # In addition to rubric_audit_log (rubric_service.activate_config below),
    # this also lands in the general audit_logs table so System Governance's
    # Configuration History and Audit Logs (that agency's Provincial Admin)
    # show rubric activations alongside every other administrative action.
    # Written before the activation: no record, no activation (finding #6).
    with audit_service.action(
        actor=current_user,
        action="rubric.activated",
        target_type="rubric_config",
        target_id=str(config_id),
        agency_type=agency_type.value,
    ) as entry:
        try:
            config = rubric_service.activate_config(
                agency_type=agency_type,
                config_id=str(config_id),
                actor_id=str(current_user["id"]),
                reason=body.reason,
                db=db,
            )
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(exc),
            )
        except RuntimeError as exc:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=str(exc),
            )
        entry.target_label = f"{agency_type.value} v{config.version}"
        entry.new = {"version": config.version, "agency_type": agency_type.value}
        entry.metadata = {"notify_body": f"{agency_type.value} severity rules activated: v{config.version}."}

    log.info(
        "rubric.router.config_activated",
        agency_type=agency_type.value,
        version=config.version,
        config_id=str(config_id),
        actor_id=current_user["id"],
    )

    return _config_to_detail_response(config)


# =============================================================================
# Audit log endpoint
# =============================================================================

@router.get(
    "/{agency_type}/audit-log",
    response_model=list[RubricAuditLogResponse],
    summary="Get the rubric change and fallback audit log for an agency",
)
def get_audit_log(
    agency_type: AgencyType,
    limit: int = Query(default=50, ge=1, le=200),
    current_user: dict = _admin_dep,
):
    """
    Returns audit log entries for the agency, newest first.
    Includes both human-initiated config changes and system fallback events.
    """
    _assert_agency_scope(current_user, agency_type)
    db = get_supabase()
    rows = rubric_service.get_audit_log(agency_type, limit=limit, db=db)
    return rows


# =============================================================================
# Evaluation endpoint (admin-only)
# =============================================================================

@router.post(
    "/evaluate",
    response_model=RubricEvaluationResult,
    summary="Evaluate a signal payload against an agency rubric (admin/test only)",
)
def evaluate_signals(
    agency_type: AgencyType,
    signals: dict,
    current_user: dict = _admin_dep,
):
    """
    Run the rubric engine against a submitted signal dict and return the result.

    This endpoint is admin-only — rubric logic must not be queryable by
    unauthenticated or resident/responder-role clients.

    Primary uses:
      1. Testing: verify a signal payload produces the expected severity
         without submitting a real incident.
      2. Dashboard: Phase 6A incident detail view calls this to show the
         suggested severity before the dispatcher confirms.
      3. Development: validate mocked signal payloads during Phase 4 blockage.
    """
    _assert_agency_scope(current_user, agency_type)
    db = get_supabase()
    result = rubric_service.evaluate(signals, agency_type, db)
    return result


# =============================================================================
# Health probe
# =============================================================================

@router.get("/health", tags=["rubric"])
def rubric_health():
    """Rubric router health probe."""
    return {"status": "ok", "component": "rubric-engine", "phase": "5.3"}


# =============================================================================
# Response serialisation helpers
# =============================================================================

def _config_to_response(config) -> RubricConfigResponse:
    return RubricConfigResponse(
        id=config.id,
        agency_type=config.agency_type,
        version=config.version,
        is_active=config.is_active,
        created_by=config.created_by,
        activated_by=config.activated_by,
        activated_at=config.activated_at,
        created_at=config.created_at,
    )


def _config_to_detail_response(config) -> RubricConfigDetailResponse:
    return RubricConfigDetailResponse(
        id=config.id,
        agency_type=config.agency_type,
        version=config.version,
        is_active=config.is_active,
        created_by=config.created_by,
        activated_by=config.activated_by,
        activated_at=config.activated_at,
        created_at=config.created_at,
        rules=config.rules,
    )
