"""
/stations — Station, coverage-area, and agency-settings management endpoints.

Routes:
  GET    /                            — Admin: list stations (own agency / own agency_type / all)
  GET    /{station_id}                — Admin: get a single station with full coverage polygon
  PATCH  /{station_id}/coverage       — Agency Admin (own agency) / Provincial Admin (own agency_type): update coverage polygon
  GET    /agencies/{agency_id}        — Agency Admin (own) / Provincial Admin (own agency_type): get agency profile + settings
  GET    /agencies/{agency_id}/overview — Agency Admin (own) / Provincial Admin (own agency_type): live station/responder/incident counts
  PATCH  /agencies/{agency_id}        — Agency Admin (own) / Provincial Admin (own agency_type): update agency profile + notification_rules
  POST   /                            — Provincial Admin: add a new station to an existing agency of their own agency_type
  PATCH  /{station_id}/location       — Agency Admin (own) / Provincial Admin (own agency_type): move a station to a point
  PATCH  /{station_id}/deactivate     — Provincial Admin: deactivate a station of their own agency_type (soft-delete)
  PATCH  /{station_id}/activate       — Provincial Admin: reactivate a deactivated station of their own agency_type
"""

from datetime import datetime, timezone

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, field_validator
from typing import Any, Optional

from app.core.dependencies import get_current_user, require_role
from app.db.supabase_client import get_supabase
from app.services import audit_service

log = structlog.get_logger()
router = APIRouter()

_admin_only            = Depends(require_role("agency_admin", "provincial_admin"))
_provincial_admin_only = Depends(require_role("provincial_admin"))


# ── List stations ─────────────────────────────────────────────

@router.get("/")
def list_stations(
    include_inactive: bool = False,
    current_user: dict = _admin_only,
):
    """
    Agency Admin: list stations belonging to their agency.
    Provincial Admin: list every station of their own agency_type
    (PNP/BFP/MDRRMO) across the province.

    Returns station id, name, address, agency info, and whether a
    coverage_area polygon is defined (has_coverage boolean).
    The raw polygon geometry is NOT returned here — use GET /{id} for that.

    `include_inactive` is Provincial Admin only (silently ignored for an
    Agency Admin caller) — the Agency Management page needs a way to find
    and reactivate a deactivated station, and until now nothing in the
    dashboard could even list one: GET /stations/ always filtered
    is_active=True, so a deactivated station simply vanished with no way
    back short of a direct database edit.
    """
    db = get_supabase()
    role = current_user.get("role")
    agency_id = current_user.get("agency_id")
    agency_type = current_user.get("agency_type")

    query = (
        db.table("stations")
        .select(
            # `location` added: the list drives the coverage page, where each
            # station now carries a pin editor. Without it every station reads
            # as unplaced, and the editor opens on an empty map having thrown
            # away the coordinates it was meant to correct.
            "id, name, address, location, is_active, created_at, updated_at, "
            "agency_id, agencies(id, name, agency_type, municipality, coverage_area)"
        )
        .order("agency_id", desc=False)
    )

    if not (include_inactive and role == "provincial_admin"):
        query = query.eq("is_active", True)

    if role == "agency_admin":
        if not agency_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your account has no agency_id set. Contact your Provincial Admin.",
            )
        query = query.eq("agency_id", str(agency_id))
    elif role == "provincial_admin":
        if not agency_type:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your account has no agency_type set. Contact the platform administrator.",
            )
        agency_ids = [
            row["id"] for row in (
                db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
            )
        ]
        query = query.in_("agency_id", agency_ids)

    result = query.execute()
    rows = result.data or []

    # Annotate each station with has_coverage derived from the agency polygon
    for row in rows:
        agency = row.get("agencies") or {}
        row["has_coverage"] = agency.get("coverage_area") is not None

    return rows


# ── Get single station ────────────────────────────────────────

@router.get("/{station_id}")
def get_station(
    station_id: str,
    current_user: dict = _admin_only,
):
    """
    Get a single station including the agency's coverage_area polygon
    serialised as a GeoJSON-compatible coordinate list.

    Agency Admin: only their own agency's stations.
    Provincial Admin: any station of their own agency_type.
    """
    db = get_supabase()

    result = (
        db.table("stations")
        .select(
            "id, name, address, is_active, agency_id, "
            "agencies(id, name, agency_type, municipality, coverage_area)"
        )
        .eq("id", station_id)
        .single()
        .execute()
    )

    if not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Station not found.")

    row = result.data
    role = current_user.get("role")

    if role == "agency_admin":
        if str(row.get("agency_id") or "") != str(current_user.get("agency_id") or ""):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This station does not belong to your agency.",
            )
    elif role == "provincial_admin":
        station_agency_type = (row.get("agencies") or {}).get("agency_type")
        if station_agency_type != current_user.get("agency_type"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This station does not belong to your agency type.",
            )

    return row


# ── Update coverage polygon ───────────────────────────────────

class CoverageUpdateRequest(BaseModel):
    """
    Polygon coordinates as a list of [lng, lat] pairs (GeoJSON order).
    Must have at least 4 points (first == last to close the ring).
    Pass null/empty list to clear the coverage polygon.
    """
    coordinates: Optional[list[list[float]]] = None

    @field_validator("coordinates")
    @classmethod
    def validate_polygon(cls, v: Optional[list[list[float]]]) -> Optional[list[list[float]]]:
        if v is None or len(v) == 0:
            return None  # clearing the polygon is allowed
        if len(v) < 4:
            raise ValueError("A polygon ring must have at least 4 coordinate pairs (first == last).")
        for pair in v:
            if len(pair) != 2:
                raise ValueError("Each coordinate must be [longitude, latitude].")
            lng, lat = pair
            if not (-180 <= lng <= 180):
                raise ValueError(f"Longitude {lng} is out of range [-180, 180].")
            if not (-90 <= lat <= 90):
                raise ValueError(f"Latitude {lat} is out of range [-90, 90].")
        # Auto-close the ring if first != last
        if v[0] != v[-1]:
            v = v + [v[0]]
        return v


@router.patch("/{station_id}/coverage")
def update_coverage(
    station_id: str,
    body: CoverageUpdateRequest,
    current_user: dict = _admin_only,
):
    """
    Update (or clear) the coverage_area polygon for the agency that owns
    this station.

    The polygon is stored on the `agencies` table (one polygon per agency),
    not on the station itself — all stations belonging to the same agency
    share the same coverage polygon. This endpoint updates the agency's
    coverage_area via the station as the entry point.

    Agency Admin: only their own agency.
    Provincial Admin: any agency of their own agency_type.

    Security: RLS policy "agencies: admin updates own agency" enforces
    agency scope at the DB level as a second layer.
    """
    import structlog
    log = structlog.get_logger()

    db = get_supabase()

    # Resolve the agency_id for this station
    station_result = (
        db.table("stations")
        .select("id, agency_id")
        .eq("id", station_id)
        .single()
        .execute()
    )
    if not station_result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Station not found.")

    target_agency_id = str(station_result.data["agency_id"])

    # Agency Admin scope check
    if current_user.get("role") == "agency_admin":
        if target_agency_id != str(current_user.get("agency_id") or ""):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This station does not belong to your agency.",
            )

    # Build WKT polygon string or NULL
    if body.coordinates:
        coord_str = ", ".join(f"{lng} {lat}" for lng, lat in body.coordinates)
        wkt = f"POLYGON(({coord_str}))"
        update_payload = {"coverage_area": f"SRID=4326;{wkt}"}
    else:
        update_payload = {"coverage_area": None}

    result = (
        db.table("agencies")
        .update(update_payload)
        .eq("id", target_agency_id)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update coverage area.",
        )

    log.info(
        "admin.coverage_area_updated",
        agency_id=target_agency_id,
        station_id=station_id,
        cleared=body.coordinates is None,
        acting_admin_id=str(current_user["id"]),
    )

    return {
        "station_id": station_id,
        "agency_id": target_agency_id,
        "coverage_updated": True,
        "cleared": body.coordinates is None,
    }


# =============================================================================
# Agency profile & settings endpoints (Phase 6A.5)
# =============================================================================

class AgencyProfileUpdateRequest(BaseModel):
    """
    Fields an Agency Admin can update on their own agency record.
    Provincial Admin can update any agency of their own agency_type.
    coverage_area is intentionally excluded — use the /coverage endpoint.
    """
    name:               Optional[str]        = None
    municipality:       Optional[str]        = None
    contact_number:     Optional[str]        = None
    email:              Optional[str]        = None
    notification_rules: Optional[dict[str, Any]] = None

    @field_validator("notification_rules")
    @classmethod
    def validate_notification_rules(cls, v: Optional[dict]) -> Optional[dict]:
        if v is None:
            return v
        allowed_keys = {"critical", "high", "medium", "low"}
        for k, val in v.items():
            if k not in allowed_keys:
                raise ValueError(f"notification_rules key '{k}' not allowed. Use: critical, high, medium, low.")
            if not isinstance(val, bool):
                raise ValueError(f"notification_rules['{k}'] must be a boolean.")
        return v


@router.get("/agencies/{agency_id}")
def get_agency_profile(
    agency_id: str,
    current_user: dict = _admin_only,
):
    """
    Get the full agency profile including notification_rules and contact info.

    Agency Admin: only their own agency (scope enforced below).
    Provincial Admin: any agency of their own agency_type.
    """
    _assert_agency_write_scope(current_user, agency_id)

    db = get_supabase()
    result = (
        db.table("agencies")
        .select("id, name, agency_type, municipality, province, region, contact_number, email, is_active, notification_rules, created_at, updated_at")
        .eq("id", agency_id)
        .single()
        .execute()
    )

    if not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Agency not found.")

    return result.data


@router.get("/agencies/{agency_id}/overview")
def get_agency_overview(
    agency_id: str,
    current_user: dict = _admin_only,
):
    """
    Live counts for Settings > Agency Information: how many stations and
    responders this agency has, and today's incident load.

    Same _count(table, head=True) pattern as /users/provincial/counts — a
    Content-Range count from PostgREST, no rows actually transferred.

    Agency Admin: only their own agency. Provincial Admin: any agency of
    their own agency_type.
    """
    _assert_agency_write_scope(current_user, agency_id)
    db = get_supabase()

    def _count(table: str, build) -> int:
        q = db.table(table).select("id", count="exact", head=True)
        return build(q).execute().count or 0

    today_start = (
        datetime.now(timezone.utc)
        .replace(hour=0, minute=0, second=0, microsecond=0)
        .isoformat()
    )

    return {
        "stations": _count("stations", lambda q: q.eq("agency_id", agency_id)),
        "responders": _count(
            "users", lambda q: q.eq("agency_id", agency_id).eq("role", "responder")
        ),
        # received/processing/dispatched are open; resolved/cancelled are not.
        "active_incidents": _count(
            "incidents",
            lambda q: q.eq("assigned_agency_id", agency_id)
                       .in_("status", ["received", "processing", "dispatched"]),
        ),
        "resolved_today": _count(
            "incidents",
            lambda q: q.eq("assigned_agency_id", agency_id)
                       .eq("status", "resolved")
                       .gte("resolved_at", today_start),
        ),
    }


@router.patch("/agencies/{agency_id}")
def update_agency_profile(
    agency_id: str,
    body: AgencyProfileUpdateRequest,
    current_user: dict = _admin_only,
):
    """
    Update agency profile fields.

    Agency Admin: only their own agency.
    Provincial Admin: any agency of their own agency_type.
    Immutable fields (agency_type, province, region) are not accepted here.

    Security: RLS policy "agencies: admin updates own agency" also enforces
    scope at the DB level as a second layer.
    """
    _assert_agency_write_scope(current_user, agency_id)

    db = get_supabase()

    updates: dict = {}
    if body.name is not None:
        updates["name"] = body.name
    if body.municipality is not None:
        updates["municipality"] = body.municipality
    if body.contact_number is not None:
        updates["contact_number"] = body.contact_number
    if body.email is not None:
        updates["email"] = body.email
    if body.notification_rules is not None:
        updates["notification_rules"] = body.notification_rules

    if not updates:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No updatable fields provided.",
        )

    result = (
        db.table("agencies")
        .update(updates)
        .eq("id", agency_id)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Update failed.",
        )

    log.info(
        "admin.agency_profile_updated",
        agency_id=agency_id,
        fields=list(updates.keys()),
        acting_admin_id=str(current_user["id"]),
    )

    return result.data[0]


# =============================================================================
# Station management endpoints (Phase 6A.5 — Provincial Admin only)
# =============================================================================

class CreateStationRequest(BaseModel):
    """Body for POST /stations/ — Provincial Admin only, scoped to their own agency_type."""
    agency_id:  str
    name:       str
    address:    Optional[str] = None
    latitude:   Optional[float] = None
    longitude:  Optional[float] = None

    @field_validator("latitude")
    @classmethod
    def validate_lat(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and not (-90 <= v <= 90):
            raise ValueError(f"Latitude {v} is out of range [-90, 90].")
        return v

    @field_validator("longitude")
    @classmethod
    def validate_lng(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and not (-180 <= v <= 180):
            raise ValueError(f"Longitude {v} is out of range [-180, 180].")
        return v


@router.post("/")
def create_station(
    body: CreateStationRequest,
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: add a new station to an existing agency of their own
    agency_type. The station is active by default.
    """
    db = get_supabase()

    # Verify agency exists
    agency_check = (
        db.table("agencies")
        .select("id, name, agency_type")
        .eq("id", body.agency_id)
        .single()
        .execute()
    )
    if not agency_check.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Agency not found.")

    if agency_check.data["agency_type"] != current_user.get("agency_type"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only add stations to your own agency type.",
        )

    payload: dict = {
        "agency_id": body.agency_id,
        "name": body.name,
        "address": body.address,
        "is_active": True,
    }

    if body.latitude is not None and body.longitude is not None:
        payload["location"] = f"SRID=4326;POINT({body.longitude} {body.latitude})"

    result = (
        db.table("stations")
        .insert(payload)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create station.",
        )

    log.info(
        "provincial_admin.station_created",
        station_id=result.data[0].get("id"),
        agency_id=body.agency_id,
        acting_provincial_admin=str(current_user["id"]),
    )

    audit_service.record(
        actor=current_user,
        action="station.created",
        target_type="station",
        target_id=result.data[0]["id"],
        target_label=body.name,
        new=payload,
        metadata={"notify_body": f"New station '{body.name}' added to {agency_check.data['name']}."},
        agency_type=agency_check.data["agency_type"],
    )

    return result.data[0]


# ── Station location ──────────────────────────────────────────

class StationLocationRequest(BaseModel):
    """
    Where a station physically is.

    Both fields required — unlike CreateStationRequest, where a station may
    legitimately be filed before anyone has its coordinates. Half a coordinate
    is never a valid update: it would move a station to the equator or the
    prime meridian while looking like a partial edit.
    """
    latitude:  float
    longitude: float

    @field_validator("latitude")
    @classmethod
    def validate_lat(cls, v: float) -> float:
        if not (-90 <= v <= 90):
            raise ValueError(f"Latitude {v} is out of range [-90, 90].")
        return v

    @field_validator("longitude")
    @classmethod
    def validate_lng(cls, v: float) -> float:
        if not (-180 <= v <= 180):
            raise ValueError(f"Longitude {v} is out of range [-180, 180].")
        return v


@router.patch("/{station_id}/location")
def update_station_location(
    station_id: str,
    body: StationLocationRequest,
    current_user: dict = _admin_only,
):
    """
    Move a station to an exact point.

    Agency Admin: their own agency's stations. Provincial Admin: any station
    of their own agency_type.

    Deliberately NOT provincial-admin-only, unlike creating or deactivating
    a station. Who exists on the roster is a provincial decision; where a
    station physically stands is something the people who work there know
    better than anyone in a provincial office, and until now nothing in the
    app could correct it — coordinates could only be typed once, at creation,
    by a Provincial Admin, and never touched again.

    The range check here is correctness, not plausibility. A point outside
    Biliran is almost certainly a mistake, but that judgement belongs to the
    client, which can show the operator where the pin landed; a bounding box
    hard-coded in the API would silently refuse a legitimate edge case with
    no way to see why.
    """
    db = get_supabase()

    station = (
        db.table("stations")
        .select("id, name, agency_id")
        .eq("id", station_id)
        .maybe_single()
        .execute()
    )
    if not station or not station.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Station not found."
        )

    _assert_agency_write_scope(current_user, str(station.data["agency_id"]))

    result = (
        db.table("stations")
        .update({"location": f"SRID=4326;POINT({body.longitude} {body.latitude})"})
        .eq("id", station_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update the station location.",
        )

    log.info(
        "admin.station_location_updated",
        station_id=station_id,
        agency_id=str(station.data["agency_id"]),
        lat=body.latitude,
        lng=body.longitude,
        acting_admin_id=str(current_user.get("id")),
    )

    return {
        "station_id": station_id,
        "name": station.data.get("name"),
        "latitude": body.latitude,
        "longitude": body.longitude,
    }


@router.patch("/{station_id}/deactivate")
def deactivate_station(
    station_id: str,
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: soft-deactivate a station of their own agency_type
    (sets is_active = False). The station record is retained for audit
    purposes. Deactivated stations are hidden from the coverage and list
    views.
    """
    db = get_supabase()

    check = (
        db.table("stations")
        .select("id, name, agency_id, is_active, agencies(agency_type)")
        .eq("id", station_id)
        .single()
        .execute()
    )
    if not check.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Station not found.")

    station_agency_type = (check.data.get("agencies") or {}).get("agency_type")
    if station_agency_type != current_user.get("agency_type"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only manage stations of your own agency type.",
        )

    if not check.data["is_active"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Station is already deactivated.",
        )

    result = (
        db.table("stations")
        .update({"is_active": False})
        .eq("id", station_id)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to deactivate station.",
        )

    log.info(
        "provincial_admin.station_deactivated",
        station_id=station_id,
        agency_id=check.data["agency_id"],
        acting_provincial_admin=str(current_user["id"]),
    )

    audit_service.record(
        actor=current_user,
        action="station.deactivated",
        target_type="station",
        target_id=station_id,
        target_label=check.data.get("name"),
        previous={"is_active": True},
        new={"is_active": False},
        agency_type=station_agency_type,
    )

    return {"station_id": station_id, "is_active": False, "deactivated": True}


@router.patch("/{station_id}/activate")
def activate_station(
    station_id: str,
    current_user: dict = _provincial_admin_only,
):
    """
    Provincial Admin: reactivate a previously deactivated station of their
    own agency_type.

    Mirrors deactivate_station exactly — the spec's Agency Management module
    calls for both directions, and only deactivate existed before.
    """
    db = get_supabase()

    check = (
        db.table("stations")
        .select("id, name, agency_id, is_active, agencies(agency_type)")
        .eq("id", station_id)
        .single()
        .execute()
    )
    if not check.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Station not found.")

    station_agency_type = (check.data.get("agencies") or {}).get("agency_type")
    if station_agency_type != current_user.get("agency_type"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only manage stations of your own agency type.",
        )

    if check.data["is_active"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Station is already active.",
        )

    result = (
        db.table("stations")
        .update({"is_active": True})
        .eq("id", station_id)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to activate station.",
        )

    log.info(
        "provincial_admin.station_activated",
        station_id=station_id,
        agency_id=check.data["agency_id"],
        acting_provincial_admin=str(current_user["id"]),
    )

    audit_service.record(
        actor=current_user,
        action="station.activated",
        target_type="station",
        target_id=station_id,
        target_label=check.data.get("name"),
        previous={"is_active": False},
        new={"is_active": True},
        agency_type=station_agency_type,
    )

    return {"station_id": station_id, "is_active": True, "activated": True}


# =============================================================================
# Scope helper (shared by coverage + settings endpoints)
# =============================================================================

def _assert_agency_write_scope(current_user: dict, agency_id: str) -> None:
    """
    Raises HTTP 403 if an agency_admin tries to write to a different agency,
    or a provincial_admin tries to write to an agency outside their own
    agency_type.
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
            detail="You can only manage settings for your own agency type.",
        )

    user_agency_id = str(current_user.get("agency_id") or "")
    if user_agency_id != agency_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only manage settings for your own agency.",
        )
