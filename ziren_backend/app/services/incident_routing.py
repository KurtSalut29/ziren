"""
incident_routing — which station a report goes to, whether a point is inside a
station's coverage, and where the reporter stood when reporting from elsewhere.

Split out of incident_service (evaluator finding #23, 2026-10-05). Each
function takes the caller's database client rather than creating one.
incident_service re-exports every name, so existing imports keep working.
"""

import structlog
from fastapi import HTTPException, status
from supabase import Client
from app.models.incident import IncidentSubmitRequest
from app.services.incident_rows import _distance_km, _parse_point

log = structlog.get_logger()


def check_coverage(
    station_id: str,
    lat: float,
    lng: float,
    db: "Client",
) -> dict:
    """
    PostGIS check: is (lat, lng) inside the coverage_area polygon of
    the agency that owns station_id?

    Returns:
        {
          "within_coverage": bool,
          "station_name": str,
          "agency_type": str,
          "municipality": str,
          "distance_km": float | None  — approx distance from station point
        }

    Used by the mobile app to show a mismatch warning on the report form.
    Never blocks submission — informational only.
    """
    try:
        # Single query: join station → agency, check ST_Within + get ST_Distance
        result = db.rpc(
            "check_station_coverage",
            {
                "p_station_id": station_id,
                "p_lat":        lat,
                "p_lng":        lng,
            },
        ).execute()

        if result.data:
            row = result.data[0]
            return {
                "within_coverage": bool(row.get("within_coverage", False)),
                "station_name":    row.get("station_name", ""),
                "agency_type":     row.get("agency_type", ""),
                "municipality":    row.get("municipality", ""),
                "distance_km":     row.get("distance_km"),
            }
    except Exception as e:
        log.warning("coverage_check.failed", station_id=station_id, error=str(e))

    # On any error, return within_coverage=True (fail-open — don't block reporter)
    return {
        "within_coverage": True,
        "station_name":    "",
        "agency_type":     "",
        "municipality":    "",
        "distance_km":     None,
    }


# Columns added by migration 042 — where the REPORTER stood when the incident
# is somewhere else. See IncidentSubmitRequest.reported_from_elsewhere.
REPORTER_LOCATION_COLUMNS = ("reported_from_elsewhere", "reporter_location", "reporter_address")


def _reporter_location(request: IncidentSubmitRequest) -> dict | None:
    """The reporter's own position, as incident columns — or None when the
    reporter is at the incident (the usual case), so nothing extra is written."""
    if not request.reported_from_elsewhere:
        return None
    cols: dict = {"reported_from_elsewhere": True}
    if request.reporter_latitude is not None and request.reporter_longitude is not None:
        cols["reporter_location"] = f"POINT({request.reporter_longitude} {request.reporter_latitude})"
    if request.reporter_address:
        cols["reporter_address"] = request.reporter_address
    return cols


def _is_missing_reporter_column(exc: Exception) -> bool:
    text = str(exc).lower()
    return any(c in text for c in REPORTER_LOCATION_COLUMNS) and (
        "column" in text or "pgrst204" in text or "42703" in text or "schema cache" in text
    )


def _resolve_nearest_station(
    db: Client,
    latitude: float | None,
    longitude: float | None,
    agency_type_hint: str | None = None,
) -> tuple[str, str, str, str, str]:
    """
    Returns (station_id, agency_id, station_name, agency_type, municipality)
    for the station nearest to the given coordinates.

    If coordinates are unavailable, falls back to the Naval MDRRMO station
    (closest thing to a provincial-level catch-all).

    agency_type_hint (e.g. "BFP"/"PNP"/"MDRRMO") narrows the candidate pool to
    that agency before picking nearest, when at least one such station has a
    known location. Without it — the SOS default before this parameter
    existed — the nearest station of ANY agency wins, which is how a medical
    SOS could end up routed to the nearest fire station purely because it was
    geographically closer than the nearest MDRRMO post. A hint that matches no
    station falls back to the unfiltered pool rather than failing: a report at
    the wrong desk still reaches a dispatcher, who can reassign it.

    Phase 9 will replace this with a proper PostGIS coverage-area query
    (ST_Within / ST_DWithin against agencies.coverage_area).
    For now: fetches all active stations with known coordinates and picks the
    closest by geodesic distance in Python - Vincenty's formula on the WGS-84
    ellipsoid (app.core.geo), not the spherical Haversine this used to be, which
    is up to half a percent long going north-south at Biliran's latitude.
    """
    # NOTE the `agencies!inner(...)` embed. PostgREST does NOT filter parent
    # rows by a condition on an embedded resource unless the embed is an INNER
    # join — with a plain `agencies(...)` embed it returns every active station
    # and merely sets `agencies` to null on the ones that don't match. Combined
    # with .limit(1) that silently returned an arbitrary station (in practice
    # "BFP Naval Main Station") with agencies=None, so a GPS-less SOS was
    # routed to the wrong agency and reported blank agency metadata back to
    # the reporter. Do not remove the `!inner`.
    FALLBACK_STATION_QUERY = (
        db.table("stations")
        .select("id, agency_id, name, location, agencies!inner(agency_type, municipality, name)")
        .eq("is_active", True)
        .eq("agencies.municipality", "Naval")
        .eq("agencies.agency_type", "MDRRMO")
        .limit(1)
    )

    if latitude is None or longitude is None:
        # No GPS — use Naval MDRRMO as default
        result = FALLBACK_STATION_QUERY.execute()
        if result.data:
            return _extract_station_tuple(result.data[0])
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not resolve a station. No location provided and fallback unavailable.",
        )

    # Fetch all active stations (PostGIS lookup will replace this in Phase 9)
    all_stations = (
        db.table("stations")
        .select("id, agency_id, name, location, agencies(agency_type, municipality, name)")
        .eq("is_active", True)
        .execute()
    )

    if not all_stations.data:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No stations available. Please try again.",
        )

    # Prefer stations of the hinted agency type, same rule the mobile app's
    # NearestStationResolver.agencyFor already applies client-side for the
    # category-tile flow — a hint that matches nothing falls through to the
    # full pool rather than failing (see the docstring above).
    candidate_pool = all_stations.data
    if agency_type_hint:
        scoped = [
            row for row in candidate_pool
            if (row.get("agencies") or {}).get("agency_type") == agency_type_hint
        ]
        if scoped:
            candidate_pool = scoped

    # Find nearest by geodesic distance
    best = None
    best_dist = float("inf")
    for row in candidate_pool:
        loc = row.get("location")
        if not loc:
            continue
        # Supabase returns PostGIS POINT as a WKT or GeoJSON string
        s_lat, s_lon = _parse_point(loc)
        if s_lat is None:
            continue
        dist = _distance_km(latitude, longitude, s_lat, s_lon)
        if dist < best_dist:
            best_dist = dist
            best = row

    if best is None:
        # All stations have null location — use Naval MDRRMO fallback
        result = FALLBACK_STATION_QUERY.execute()
        if result.data:
            return _extract_station_tuple(result.data[0])
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not resolve a nearby station.",
        )

    return _extract_station_tuple(best)


def _extract_station_tuple(row: dict) -> tuple[str, str, str, str, str]:
    """
    Extract (station_id, agency_id, station_name, agency_type, municipality).

    A missing `agencies` embed is treated as a hard error rather than being
    coerced to empty strings. The previous `row.get("agencies") or {}` silently
    turned a mis-built query into agency_type="" / municipality="", which is
    how a PostgREST embedded-filter bug went unnoticed: the SOS path kept
    returning 201 while routing the report to the wrong agency and telling the
    reporter their station had no agency name. Failing loudly here means a
    query regression surfaces immediately instead of corrupting dispatch data.
    """
    agency = row.get("agencies")
    if not agency:
        log.error(
            "station.agency_embed_missing",
            station_id=row.get("id"),
            station_name=row.get("name"),
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not determine the responding agency for this report. Please try again.",
        )
    return (
        row["id"],
        row["agency_id"],
        row["name"],
        agency.get("agency_type", ""),
        agency.get("municipality", ""),
    )
