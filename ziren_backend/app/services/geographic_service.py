"""
geographic_service — province-wide geographic aggregation for Provincial
Admin's Geographic Overview module (spec Section 8, replacing the removed
Coverage Areas feature).

Aggregation happens in Python over fetched rows rather than a new Postgres
RPC function — this project covers one province, so the row counts involved
(users, stations, incidents) are small enough that fetching and counting in
the application layer is simpler to write, test, and read than a SQL
function, and there is no performance case for one yet. System Analytics
(analytics_service) follows the same approach for the same reason.

Two facts about the schema shape this whole module's design:

  - Residents carry their own barangay_id (a real FK), so "registered
    residents in barangay X" is a direct filter.
  - Responders and stations do NOT carry a barangay — a responder's place is
    their AGENCY's municipality (a courser fact: which municipality they
    serve, not where they live), and a station's place is likewise its
    agency's municipality column. Incidents are attributed to a municipality
    the same way, via the station that was assigned to handle them —
    incidents have no municipality of their own, only a station_id, and the
    station's agency carries the municipality. This means an incident is
    counted under "the municipality of the station that handled it", not
    necessarily where it physically occurred — the schema has no per-incident
    geocoding finer than that. Stated here once rather than re-derived at
    every call site below.
"""

from collections import Counter
from typing import Any

from app.db.supabase_client import get_supabase


def list_municipalities() -> list[dict[str, Any]]:
    """
    Every municipality with at least one barangay on file, alphabetically,
    each carrying its registered-resident count. The dashboard uses the count
    to default to a municipality that actually has data — alphabetical order
    put "Almeria" (0 residents) ahead of "Naval" (where the province's real
    activity is) on every first visit, making the whole feature look empty.
    """
    db = get_supabase()
    barangay_rows = db.table("barangays").select("id, municipality").execute().data or []
    municipality_by_barangay = {
        row["id"]: row["municipality"] for row in barangay_rows if row.get("municipality")
    }
    municipalities = sorted(set(municipality_by_barangay.values()))

    resident_rows = (
        db.table("users").select("barangay_id").eq("role", "resident").execute().data or []
    )
    counts = Counter(
        municipality_by_barangay[r["barangay_id"]]
        for r in resident_rows
        if r.get("barangay_id") in municipality_by_barangay
    )

    return [{"name": m, "resident_count": counts.get(m, 0)} for m in municipalities]


def agency_municipality(agency_id: str) -> str | None:
    """The one municipality an agency operates from — Agency Admin's Operational
    Area (Agency Admin spec Section 16) is always locked to this, never a
    free pick across the province."""
    db = get_supabase()
    result = (
        db.table("agencies").select("municipality").eq("id", agency_id).maybe_single().execute()
    )
    return (result.data or {}).get("municipality") if result else None


def get_overview(
    municipality: str,
    barangay: str | None = None,
    agency_id: str | None = None,
    agency_type: str | None = None,
) -> dict[str, Any]:
    """
    Everything Geographic Overview shows for one municipality, optionally
    narrowed to one barangay within it.

    agency_id scopes "incidents" to that ONE agency's own incidents — Agency
    Admin's Operational Area. agency_type scopes "incidents" to every agency
    of that agency_type — Provincial Admin's province-wide view, narrowed to
    their own agency_type (migration 034), the same way every other Type A
    module is. Passing neither would hand an Agency Admin (or a
    misconfigured caller) another agency's incident counts just for sharing
    a municipality with them — every caller of this function must pass one
    or the other; the router enforces that by role.

    agency_stations / nearby_agencies stay unscoped by design (both existed
    before agency_id scoping and were never agency_id-scoped either) — they
    answer "who else has a presence here", informational for every admin
    role, not an access-control surface.
    """
    db = get_supabase()

    barangay_query = db.table("barangays").select("id, name, municipality").eq("municipality", municipality)
    if barangay:
        barangay_query = barangay_query.eq("name", barangay)
    barangay_rows = barangay_query.execute().data or []
    barangay_ids = [row["id"] for row in barangay_rows]

    # ── Registered residents ──────────────────────────────────
    registered_residents = 0
    if barangay_ids:
        result = (
            db.table("users")
            .select("id", count="exact")
            .eq("role", "resident")
            .in_("barangay_id", barangay_ids)
            .execute()
        )
        registered_residents = result.count or 0

    # ── Registered responders (via their agency's municipality) ────────
    # A barangay-level narrowing can't apply here — see the module docstring:
    # a responder's place is their agency's municipality, nothing finer.
    responder_rows = (
        db.table("users")
        .select("id, agencies(municipality)")
        .eq("role", "responder")
        .execute()
        .data or []
    )
    registered_responders = sum(
        1 for r in responder_rows if (r.get("agencies") or {}).get("municipality") == municipality
    )

    # ── Agency stations serving this municipality ("nearby agencies" is
    # read as "agencies with a presence here" — the schema has no distance
    # computation to rank truly nearby-but-outside agencies by) ─────────
    station_rows = (
        db.table("stations")
        .select("id, name, agency_id, agencies(name, agency_type, municipality)")
        .eq("is_active", True)
        .execute()
        .data or []
    )
    stations_here = [
        s for s in station_rows if (s.get("agencies") or {}).get("municipality") == municipality
    ]
    nearby_agencies = sorted({
        s["agencies"]["agency_type"] + " — " + s["agencies"]["name"]
        for s in stations_here if s.get("agencies")
    })

    # ── Incidents handled by this municipality's stations ──────────────
    incident_query = db.table("incidents").select(
        "id, status, incident_category, created_at, assigned_agency_id, "
        "stations(agencies(municipality))"
    )
    if agency_id:
        incident_query = incident_query.eq("assigned_agency_id", agency_id)
    elif agency_type:
        # Two-step lookup: no agency_type column on incidents/stations
        # themselves, only on agencies — same pattern as dispatch_service's
        # agency-type-scoped queries.
        type_agency_ids = [
            row["id"] for row in (
                db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
            )
        ]
        incident_query = incident_query.in_("assigned_agency_id", type_agency_ids)
    incident_rows = incident_query.execute().data or []
    local_incidents = [
        i for i in incident_rows
        if ((i.get("stations") or {}).get("agencies") or {}).get("municipality") == municipality
    ]

    incident_types = dict(Counter(i.get("incident_category") or "other" for i in local_incidents))
    resolved_incidents = sum(1 for i in local_incidents if i.get("status") == "resolved")
    active_incidents = sum(
        1 for i in local_incidents
        if i.get("status") in ("received", "processing", "dispatched", "en_route", "arrived")
    )
    # Year-month buckets, oldest first — the same shape a simple line chart wants.
    monthly = Counter((i.get("created_at") or "")[:7] for i in local_incidents if i.get("created_at"))
    historical_activity = [
        {"month": month, "count": count} for month, count in sorted(monthly.items())
    ]

    return {
        "municipality": municipality,
        "barangay": barangay,
        "registered_residents": registered_residents,
        "registered_responders": registered_responders,
        "agency_stations": [
            {"id": s["id"], "name": s["name"], "agency_type": s["agencies"]["agency_type"]}
            for s in stations_here
        ],
        "nearby_agencies": nearby_agencies,
        "incident_count": len(local_incidents),
        "incident_types": incident_types,
        "resolved_incidents": resolved_incidents,
        "active_incidents": active_incidents,
        "historical_activity": historical_activity,
    }
