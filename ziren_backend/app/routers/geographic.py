"""
/geographic — Provincial Admin's province-wide Geographic Overview (spec
Section 8), and Agency Admin's Operational Area (Agency Admin spec
Section 16) over the same two endpoints. An Agency Admin cannot browse the
province: /municipalities returns only their own agency's municipality, and
/overview ignores whatever `municipality` they pass and substitutes it —
their view is locked to where their agency actually operates, and its
incident figures are scoped to their own agency rather than everyone who
happens to share that municipality. A Provincial Admin CAN browse every
municipality (their view is genuinely province-wide), but /overview's
incident figures are still scoped to their own agency_type — a PNP
Provincial Admin looking at Naval sees PNP incidents there, not BFP's or
MDRRMO's too (migration 034).
"""

from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.dependencies import require_admin
from app.services import geographic_service, operational_area_service

router = APIRouter()


@router.get("/municipalities")
def get_municipalities(current_user: dict = Depends(require_admin)):
    if current_user.get("role") == "agency_admin":
        municipality = geographic_service.agency_municipality(current_user.get("agency_id"))
        if not municipality:
            return []
        all_munis = {m["name"]: m for m in geographic_service.list_municipalities()}
        own = all_munis.get(municipality, {"name": municipality, "resident_count": 0})
        return [own]
    return geographic_service.list_municipalities()


@router.get("/overview")
def get_overview(
    municipality: str = Query(...),
    barangay: str | None = Query(None),
    current_user: dict = Depends(require_admin),
):
    if not municipality.strip():
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="municipality is required.")

    agency_id = None
    agency_type = None
    if current_user.get("role") == "agency_admin":
        agency_id = current_user.get("agency_id")
        own_municipality = geographic_service.agency_municipality(agency_id)
        if not own_municipality:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Your agency has no municipality on file.",
            )
        # Never trust the client's municipality for this role — an Agency
        # Admin's Operational Area is always their own, regardless of what a
        # crafted request asks for.
        municipality = own_municipality
    elif current_user.get("role") == "provincial_admin":
        agency_type = current_user.get("agency_type")

    return geographic_service.get_overview(municipality, barangay, agency_id=agency_id, agency_type=agency_type)


@router.get("/operational-area")
def get_operational_area(
    municipality: str | None = Query(None, max_length=80),
    barangay: str | None = Query(None, max_length=80),
    days: int = Query(30, ge=0, le=3650, description="Look-back window in days; 0 means all time."),
    date_from: date | None = Query(None, description="First day of a chosen range, YYYY-MM-DD in Philippine time. Give with date_to; overrides days."),
    date_to: date | None = Query(None, description="Last day of a chosen range (included). Give with date_from."),
    current_user: dict = Depends(require_admin),
):
    """
    The whole Operational Area screen in one payload — see
    operational_area_service for what is in it and what each figure means.

    Scoping is decided HERE, from the caller's role, and never from the request:
      - Agency Admin: the municipality is their agency's own (whatever they pass
        is ignored), and every incident/responder figure is their own agency's.
      - Provincial Admin: picks any municipality (required), and incident/
        responder figures are those of their own agency_type — the same rule as
        every other module (migration 034).

    A chosen range (`date_from` + `date_to`, both days included) replaces the
    rolling `days` window. It must have both ends, start no later than it ends,
    not start in the future, and stay under ten years; an end date in the future
    is clamped to today.
    """
    if (date_from is None) != (date_to is None):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Give both date_from and date_to, or neither.",
        )
    if date_from is not None and date_to is not None:
        if date_from > date_to:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="The start date is after the end date.",
            )
        today = datetime.now(operational_area_service.PH_TZ).date()
        if date_from > today:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="The start date is in the future.",
            )
        date_to = min(date_to, today)
        if (date_to - date_from).days + 1 > 3650:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="A range can be at most 3650 days long.",
            )

    role = current_user.get("role")
    agency_id = None
    agency_type = None

    if role == "agency_admin":
        agency_id = current_user.get("agency_id")
        own = geographic_service.agency_municipality(agency_id) if agency_id else None
        if not own:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Your agency has no municipality on file.",
            )
        municipality = own
    else:
        agency_type = current_user.get("agency_type")
        if not agency_type:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Your account has no agency type on file.",
            )
        if not municipality or not municipality.strip():
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="municipality is required.")

    if barangay and barangay.strip():
        known = {operational_area_service.normalise_place(b["name"])
                 for b in operational_area_service.list_barangays(municipality)}
        if operational_area_service.normalise_place(barangay) not in known:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"'{barangay}' is not a barangay of {municipality}.",
            )
    else:
        barangay = None

    return operational_area_service.get_operational_area(
        municipality=municipality, days=days, barangay=barangay,
        agency_id=agency_id, agency_type=agency_type,
        date_from=date_from, date_to=date_to,
    )
