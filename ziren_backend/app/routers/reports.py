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
from app.services import printable_reports, report_service

router = APIRouter()


@router.get("/")
def list_report_types(current_user: dict = Depends(require_admin)):
    types = (
        report_service.AGENCY_ADMIN_REPORT_TYPES
        if current_user.get("role") == "agency_admin"
        else report_service.REPORT_TYPES
    )
    return {"report_types": list(types), "formats": list(report_service.FORMATS)}


# ── The two printable documents Reports & Export offers ──────────────────
# Registered BEFORE /{report_type} so neither name is swallowed as a report
# type. See app/services/printable_reports.py.

@router.get("/incident_records")
def incident_records(
    format: str = Query("pdf", description="pdf, csv or xlsx"),
    start_date: str | None = Query(None, description="Bare date (YYYY-MM-DD). Omitted means all-time."),
    end_date: str | None = Query(None, description="Bare date (YYYY-MM-DD), inclusive. Omitted means all-time."),
    status_filter: str | None = Query(None, alias="status", description="open, resolved or cancelled"),
    severity: str | None = Query(None, description="critical, high, medium or low"),
    current_user: dict = Depends(require_admin),
):
    """The Incident Records Report — scoped exactly like Incident Records."""
    content, filename, media_type = printable_reports.build_incident_records(
        current_user, format,
        start_date=start_date, end_date=end_date, status_filter=status_filter, severity=severity,
    )
    return _file(content, filename, media_type)


@router.get("/narrative_reports")
def narrative_reports(
    ids: str = Query(..., description="Comma-separated incident ids, at most 50."),
    current_user: dict = Depends(require_admin),
):
    """Selected narrative reports as one printable PDF with a cover page."""
    content, filename, media_type = printable_reports.build_narrative_bundle(current_user, ids.split(","))
    return _file(content, filename, media_type)


def _file(content: bytes, filename: str, media_type: str) -> Response:
    # inline, not attachment: the dashboard previews and prints these in the
    # browser; its download button names the file itself.
    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )


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
