"""
/analytics — Provincial Admin's System Analytics module (spec Section 9):
long-term trend analysis, distinct from the Dashboard's current-state view.

Provincial Admin only, scoped to their own agency_type. Agency Admin's
Agency Analytics (spec Section 13) was this same module scoped to the
caller's own agency — removed as not worth keeping for this deployment; an
agency_admin now gets 403 on both routes below, same as they always have on
/users.
"""

from fastapi import APIRouter, Depends, Query

from app.core.dependencies import require_provincial_admin
from app.services import analytics_service

router = APIRouter()


@router.get("/incidents")
def get_incident_analytics(
    period: str = Query("month", pattern="^(day|month|year)$"),
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    current_user: dict = Depends(require_provincial_admin),
):
    return analytics_service.incident_analytics(
        period, date_from, date_to, agency_type=current_user.get("agency_type"),
    )


@router.get("/users")
def get_user_analytics(current_user: dict = Depends(require_provincial_admin)):
    return analytics_service.user_analytics(agency_type=current_user.get("agency_type"))
