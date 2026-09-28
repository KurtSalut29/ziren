"""/ai-classification — Provincial Admin's read-only AI & Classification Monitoring (spec Section 12)."""

from fastapi import APIRouter, Depends

from app.core.dependencies import require_provincial_admin
from app.services import ai_monitoring_service

router = APIRouter()


@router.get("/stats")
def get_stats(current_user: dict = Depends(require_provincial_admin)):
    """
    Scoped to the caller's own agency_type — a PNP Provincial Admin sees
    how the model is doing on PNP-assigned incidents only, not the whole
    province, mirroring every other Type A module (see migration 034).
    """
    return ai_monitoring_service.get_stats(agency_type=current_user.get("agency_type"))
