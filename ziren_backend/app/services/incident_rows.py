"""
incident_rows — turning stored incident rows into responses, and the small
geometry and time helpers that does.

Split out of incident_service (evaluator finding #23, 2026-10-05): none of this
touches the database, so it reads and tests on its own. incident_service
re-exports every name, so existing imports keep working.
"""

import structlog
from datetime import datetime, timezone
from fastapi import status
from app.core import geo
from app.models.incident import IncidentResponse

log = structlog.get_logger()


def _distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Shortest distance in kilometres between two points on the WGS-84 ellipsoid.

    The one distance function the backend's routing, ETA and hazard lookups share
    (responder_ops_service imports it), so two screens can never disagree about
    the same trip. It used to be the spherical Haversine, and the name
    `_haversine` said so; see app.core.geo for why it is not any more.
    """
    return geo.geodesic_km(lat1, lon1, lat2, lon2)


def _parse_point(location) -> tuple[float | None, float | None]:
    """
    Parse a PostGIS POINT value returned by Supabase.
    Supabase may return WKT ('POINT(lon lat)') or a GeoJSON dict.
    Returns (latitude, longitude) or (None, None) on failure.
    """
    try:
        if isinstance(location, dict):
            # GeoJSON: {"type": "Point", "coordinates": [lon, lat]}
            coords = location.get("coordinates", [])
            if len(coords) >= 2:
                return float(coords[1]), float(coords[0])
        if isinstance(location, str) and location.upper().startswith("POINT"):
            # WKT: POINT(lon lat)
            inner = location.strip()[6:-1]   # strip 'POINT(' and ')'
            parts = inner.split()
            if len(parts) == 2:
                return float(parts[1]), float(parts[0])
    except Exception:
        pass
    return None, None


def _parse_dt(value: str | None) -> datetime:
    """Parse an ISO8601 timestamp string into a timezone-aware datetime."""
    if not value:
        return datetime.min.replace(tzinfo=timezone.utc)
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def _row_to_response(row: dict) -> IncidentResponse:
    return IncidentResponse(
        id=row["id"],
        reporter_id=row["reporter_id"],
        station_id=row.get("station_id"),
        report_text=row["report_text"],
        location_address=row.get("location_address"),
        # WAS HARDCODED None, BOTH OF THEM.
        #
        # Every incident this endpoint has ever returned came back with no
        # coordinates, and the map filters its pins on exactly that:
        # MapProvider.plottableIncidents keeps only incidents where
        # latitude != null. So the incident layer has been empty since the
        # day it was written — on 29 real incidents in this database, zero
        # had a latitude — and an empty layer looks identical to a quiet
        # province. Nothing errored, nothing logged, and there was nothing
        # on the map to tap.
        latitude=_lat_of(row),
        longitude=_lng_of(row),
        status=row["status"],
        severity=row.get("severity"),
        suggested_agency_id=row.get("suggested_agency_id"),
        assigned_agency_id=row.get("assigned_agency_id"),
        signals=row.get("signals"),
        signals_confidence=row.get("signals_confidence"),
        submitted_via=row.get("submitted_via", "internet"),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
        dispatched_at=row.get("dispatched_at"),
        resolved_at=row.get("resolved_at"),
        withdrawn_at=row.get("withdrawn_at"),
        review_status=row.get("review_status"),
        reviewed_at=row.get("reviewed_at"),
        rejection_reason=row.get("rejection_reason"),
        clarification_note=row.get("clarification_note"),
        clarification_requested_at=row.get("clarification_requested_at"),
        incident_category=row.get("incident_category"),
        wizard_answers=row.get("wizard_answers"),
        overlap_agencies=row.get("overlap_agencies"),
        landmark_note=row.get("landmark_note"),
        victim_relationship=row.get("victim_relationship"),
        nlp_review_needed=row.get("nlp_review_needed", False),
        # Only meaningful while a crew is actually en route. The column keeps
        # its last value after they arrive, and showing "about 4 minutes" to
        # someone the fire truck is already standing in front of would be
        # worse than showing nothing.
        eta_minutes=(
            row.get("eta_minutes") if row.get("status") == "en_route" else None
        ),
        eta_updated_at=(
            row.get("eta_updated_at") if row.get("status") == "en_route" else None
        ),
        responding_agency=_agency_type_of(row),
    )


def _coords_of(row: dict) -> tuple[float | None, float | None]:
    """(lat, lng) from the PostGIS `location` column.

    PostgREST hands geometry back as a GeoJSON object, and GeoJSON orders its
    pair [LONGITUDE, LATITUDE] — the opposite of how every screen in this
    product names them. Getting that backwards does not error; it puts the
    incident in the sea off Somalia, which is at least obvious. Silently
    dropping the column, which is what used to happen here, is not.

    Falls back to the WKT parser for the shape PostgREST does not normalise.
    """
    geo = row.get("location")
    if isinstance(geo, dict):
        pair = geo.get("coordinates")
        if isinstance(pair, (list, tuple)) and len(pair) >= 2:
            try:
                return float(pair[1]), float(pair[0])
            except (TypeError, ValueError):
                return None, None
        return None, None
    if geo:
        return _parse_point(geo)
    return None, None


def _lat_of(row: dict) -> float | None:
    return _coords_of(row)[0]


def _lng_of(row: dict) -> float | None:
    return _coords_of(row)[1]


def _agency_type_of(row: dict) -> str | None:
    """The agency attending, as a plain string for the reporter.

    The reporter is told BFP / PNP / MDRRMO and nothing more. Not the
    responder's name, not their number: a resident does not need a crew
    member's identity to be reassured that somebody is coming, and handing it
    out invites direct contact that routes around the dispatcher.
    """
    embed = row.get("agencies")
    if isinstance(embed, dict):
        return embed.get("agency_type")
    if isinstance(embed, list) and embed:
        first = embed[0]
        if isinstance(first, dict):
            return first.get("agency_type")
    return None
