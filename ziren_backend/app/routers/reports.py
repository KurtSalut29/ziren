"""
/reports — Provincial Admin's Reports & Export (spec Section 16), and Agency
Admin's Agency Reports (Agency Admin spec Section 14) over the same
endpoints — an agency_admin is restricted to AGENCY_ADMIN_REPORT_TYPES and
every report they generate is scoped to their own agency_id; a
provincial_admin sees all report types, each scoped to their own
agency_type (migration 034) wherever that report has a per-agency cut at
all (see AGENCY_ADMIN_REPORT_TYPES's own comment in report_service.py for
the three that don't).
"""

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Response, status

from app.core.dependencies import require_admin
from app.services import report_service

router = APIRouter()


@router.get("/")
def list_report_types(current_user: dict = Depends(require_admin)):
    types = (
        report_service.AGENCY_ADMIN_REPORT_TYPES
        if current_user.get("role") == "agency_admin"
        else report_service.REPORT_TYPES
    )
    return {"report_types": list(types), "formats": list(report_service.FORMATS)}


@router.get("/{report_type}")
def download_report(
    report_type: str = Path(..., description=f"One of: {', '.join(report_service.REPORT_TYPES)}"),
    format: str = Query("csv", description=f"One of: {', '.join(report_service.FORMATS)}"),
    start_date: str | None = Query(
        None, description="Bare date (YYYY-MM-DD). Omitted means all-time.",
    ),
    end_date: str | None = Query(
        None, description="Bare date (YYYY-MM-DD), inclusive of the whole day. Omitted means all-time.",
    ),
    current_user: dict = Depends(require_admin),
):
    is_agency_admin = current_user.get("role") == "agency_admin"
    allowed_types = report_service.AGENCY_ADMIN_REPORT_TYPES if is_agency_admin else report_service.REPORT_TYPES

    if report_type not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown report_type. Must be one of: {', '.join(allowed_types)}",
        )
    if format not in report_service.FORMATS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown format. Must be one of: {', '.join(report_service.FORMATS)}",
        )

    agency_id = current_user.get("agency_id") if is_agency_admin else None
    agency_type = current_user.get("agency_type") if not is_agency_admin else None
    content, filename, media_type = report_service.build_report(
        report_type, format, agency_id=agency_id, agency_type=agency_type,
        start_date=start_date, end_date=end_date,
    )
    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
