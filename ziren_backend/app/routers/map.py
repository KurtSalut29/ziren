"""
/map — Map data endpoint for the dispatcher dashboard.

Returns a single bundled response with:
  - incidents:          active incidents with lat/lng + severity + agency context
  - coverage_polygons:  agency jurisdiction boundaries as GeoJSON
  - responders:         on-duty responders with last-known location (if set)

Scoping:
  - Agency Admin: sees only their own agency's incidents and responders.
    Coverage polygons for all agencies are always returned (they are
    public reference data — knowing where BFP Naval patrols doesn't
    compromise incident data).
  - Provincial Admin: sees every agency of their own agency_type
    (province-wide within that one type).

The RLS policies from migration 010 enforce agency scoping at the DB
layer. The service key used by FastAPI bypasses RLS, so scope is
enforced here in the service logic — consistent with how dispatch_service
and responder_service work.

Geometry note:
  Supabase/PostgREST returns PostGIS geometry columns as GeoJSON objects
  automatically. No ST_AsGeoJSON() calls needed — we pass them through.

Routes:
  GET /map/data   — Bundled map data (incidents + polygons + responders)
"""

from datetime import datetime, timedelta, timezone

import structlog
from fastapi import APIRouter, Depends, Query

from app.core.dependencies import require_role
from app.db.supabase_client import get_supabase

log = structlog.get_logger()
router = APIRouter()

_admin_only = Depends(require_role("agency_admin", "provincial_admin"))

_ACTIVE_STATUSES   = ["received", "processing", "dispatched", "en_route", "arrived"]
_HISTORY_STATUSES  = ["resolved", "cancelled"]


@router.get("/data")
def get_map_data(
    view: str = Query(
        "operational",
        description=(
            "operational (default, unchanged): active incidents — the Agency "
            "Admin's dispatch map. network: no incidents, just stations/"
            "responders/polygons — the Provincial Admin's Ziren Network Map "
            "(spec Section 7A). history: resolved/cancelled incidents only, "
            "no operational route data — the Provincial Admin's Incident "
            "History Map (spec Section 7B)."
        ),
    ),
    days: int = Query(90, ge=1, le=365, description="history view only — how far back to look"),
    current_user: dict = _admin_only,
):
    """
    Returns collections for the dashboard map:

    incidents:
      id, lat, lng, severity, suggested_severity, status,
      sos_flagged, agency_type, agency_id, report_text (truncated),
      created_at

    coverage_polygons:
      agency_id, agency_type, municipality, name,
      geojson (the raw GeoJSON Polygon object from Supabase)

    responders:
      id, full_name, badge_id, availability, agency_type,
      lat, lng (null if no location set yet)

    Agency Admin receives data scoped to their own agency_id, and `view` is
    ignored for them — they always get the operational (active-incidents) map.
    Provincial Admin receives data scoped to every agency of their own
    agency_type (province-wide within that type) and may pass `view`.
    """
    db = get_supabase()
    role      = current_user.get("role")
    agency_id = current_user.get("agency_id")
    is_admin  = role == "agency_admin"
    is_provincial_admin = role == "provincial_admin"

    # Two-step lookup (same pattern as dispatch_service._agency_ids_for_type):
    # a Provincial Admin's agency_type -> every `agencies.id` it covers.
    # Resolved once and reused for both the incidents and responders queries.
    own_agency_ids: list[str] = []
    if is_provincial_admin:
        own_agency_ids = [
            row["id"] for row in (
                db.table("agencies")
                .select("id")
                .eq("agency_type", current_user.get("agency_type"))
                .execute()
                .data or []
            )
        ]

    # An Agency Admin's map is always operational — view is a Provincial
    # Admin concept (they have no single dispatch map to switch away from).
    effective_view = "operational" if is_admin else view

    # ── 1. Incidents ──────────────────────────────────────────
    incidents = []
    if effective_view == "network":
        # The Ziren Network Map is about where the province's registered
        # entities ARE, not what is currently happening — no incidents at all.
        pass
    else:
        inc_query = (
            db.table("incidents")
            .select(
                "id, location, severity, status, sos_flagged, created_at, resolved_at, "
                "report_text, assigned_agency_id, "
                "stations(agencies(id, agency_type, name))"
            )
            .not_.is_("location", "null")   # only incidents with GPS coordinates
        )
        if effective_view == "history":
            since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
            inc_query = inc_query.in_("status", _HISTORY_STATUSES).gte("created_at", since)
        else:
            inc_query = inc_query.in_("status", _ACTIVE_STATUSES)

        if is_admin:
            inc_query = inc_query.eq("assigned_agency_id", str(agency_id))
        elif is_provincial_admin:
            inc_query = inc_query.in_("assigned_agency_id", own_agency_ids)

        inc_result = inc_query.execute()
        for row in (inc_result.data or []):
            loc = row.get("location") or {}
            coords = loc.get("coordinates") if isinstance(loc, dict) else None
            if not coords or len(coords) < 2:
                continue  # skip if geometry malformed

            agency_info = (row.get("stations") or {})
            if isinstance(agency_info, dict):
                agency_info = agency_info.get("agencies") or {}
            else:
                agency_info = {}

            incidents.append({
                "id":                 row["id"],
                "lng":                coords[0],
                "lat":                coords[1],
                "severity":           row.get("severity"),
                "status":             row.get("status"),
                "sos_flagged":        row.get("sos_flagged", False),
                "agency_type":        agency_info.get("agency_type"),
                "agency_id":          row.get("assigned_agency_id"),
                "report_text":        (row.get("report_text") or "")[:120],
                "created_at":         row.get("created_at"),
                "resolved_at":        row.get("resolved_at"),
                # The history view is explicitly NOT a dispatch map — no
                # station-to-incident route is computed or returned here, in
                # either view. Stated as a field rather than left implicit, so
                # a frontend consumer never has to wonder whether it was
                # omitted by accident.
                "route": None,
            })

    # ── 2. Coverage polygons ──────────────────────────────────
    # Always return all agency polygons — they are public jurisdiction
    # boundaries, not sensitive data. Scoping them to the admin's own
    # agency would make the map confusing (can't see adjacent areas).
    poly_query = (
        db.table("agencies")
        .select("id, name, agency_type, municipality, coverage_area")
        .eq("is_active", True)
        .not_.is_("coverage_area", "null")
    )
    poly_result = poly_query.execute()
    coverage_polygons = []
    for row in (poly_result.data or []):
        geojson = row.get("coverage_area")
        if not geojson:
            continue
        coverage_polygons.append({
            "agency_id":    row["id"],
            "name":         row["name"],
            "agency_type":  row["agency_type"],
            "municipality": row["municipality"],
            "geojson":      geojson,   # already a GeoJSON dict from Supabase
        })

    # ── 3. Responders with location ───────────────────────────
    resp_query = (
        db.table("users")
        .select(
            "id, full_name, badge_id, availability, location, agency_id, "
            "agencies(agency_type)"
        )
        .eq("role", "responder")
        .eq("approval_status", "approved")
        .eq("availability", "on_duty")
    )
    if is_admin:
        resp_query = resp_query.eq("agency_id", str(agency_id))
    elif is_provincial_admin:
        resp_query = resp_query.in_("agency_id", own_agency_ids)

    resp_result = resp_query.execute()
    responders = []
    for row in (resp_result.data or []):
        loc = row.get("location")
        lat, lng = None, None
        if isinstance(loc, dict):
            coords = loc.get("coordinates")
            if coords and len(coords) >= 2:
                lng, lat = coords[0], coords[1]

        agency_info = row.get("agencies") or {}
        responders.append({
            "id":           row["id"],
            "full_name":    row.get("full_name"),
            "badge_id":     row.get("badge_id"),
            "availability": row.get("availability"),
            "agency_type":  agency_info.get("agency_type") if isinstance(agency_info, dict) else None,
            "lat":          lat,
            "lng":          lng,
        })

    # ── 4. Stations ───────────────────────────────────────────
    #
    # A station is where an agency ACTUALLY IS, at surveyed coordinates a few
    # metres apart — BFP, PNP and MDRRMO in Naval sit on three distinct
    # points. That is worth contrasting with coverage_polygons above, which
    # migration 002 seeded as one 8km rectangle per municipality shared
    # verbatim by all three of its agencies. The polygon is a placeholder
    # standing in for a boundary nobody has drawn yet; the station is a fact.
    #
    # Not scoped to the admin's own agency. Knowing where the neighbouring
    # station sits is exactly what an adjacent-municipality incident needs,
    # and a station's address is public information in any case.
    st_result = (
        db.table("stations")
        .select("id, name, address, location, agency_id, agencies(agency_type, municipality, name)")
        .eq("is_active", True)
        .execute()
    )
    stations = []
    for row in (st_result.data or []):
        loc = row.get("location")
        if not isinstance(loc, dict):
            continue
        coords = loc.get("coordinates")
        if not coords or len(coords) < 2:
            # No coordinates means nothing to pin. Counted by the overview
            # tile instead of drawn at (0, 0) in the Gulf of Guinea.
            continue
        agency_info = row.get("agencies") or {}
        stations.append({
            "id":           row["id"],
            "name":         row.get("name"),
            "address":      row.get("address"),
            "agency_type":  agency_info.get("agency_type"),
            "agency_name":  agency_info.get("name"),
            "municipality": agency_info.get("municipality"),
            "lng":          coords[0],
            "lat":          coords[1],
        })

    log.info(
        "map.data_fetched",
        role=role,
        view=effective_view,
        incidents=len(incidents),
        coverage_polygons=len(coverage_polygons),
        responders=len(responders),
        stations=len(stations),
    )

    return {
        "incidents":         incidents,
        "coverage_polygons": coverage_polygons,
        "responders":        responders,
        "stations":          stations,
    }
