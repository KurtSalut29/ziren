"""
/governance — System Governance (spec Section 11).

Severity Configuration is deliberately absent here — it's the existing
/rubric router, unchanged. This router only covers the pieces that were
genuinely new: read-only incident configuration, the two system_config
policy groups, and configuration history.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel

from app.core.dependencies import require_provincial_admin
from app.services import governance_service

router = APIRouter()


@router.get("/incident-configuration")
def get_incident_configuration(current_user: dict = Depends(require_provincial_admin)):
    return governance_service.get_incident_configuration()


class PolicyUpdateRequest(BaseModel):
    value: dict


@router.get("/account-policies")
def get_account_policies(current_user: dict = Depends(require_provincial_admin)):
    return governance_service.get_policy("account_policies")


@router.patch("/account-policies")
def update_account_policies(body: PolicyUpdateRequest, current_user: dict = Depends(require_provincial_admin)):
    try:
        return governance_service.update_policy("account_policies", body.value, current_user)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))


@router.get("/notification-policies")
def get_notification_policies(current_user: dict = Depends(require_provincial_admin)):
    return governance_service.get_policy("notification_policies")


@router.patch("/notification-policies")
def update_notification_policies(body: PolicyUpdateRequest, current_user: dict = Depends(require_provincial_admin)):
    try:
        return governance_service.update_policy("notification_policies", body.value, current_user)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))


@router.get("/configuration-history")
def get_configuration_history(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(require_provincial_admin),
):
    return governance_service.get_configuration_history(limit, offset)
