"""
search_service — Global Search (spec Section 18).

Cross-entity search, capped at ~5 results per entity type. Agency Admin
gets results scoped to their own agency, and Provincial Admin to every
agency of their own agency_type, for agency-specific entities (responders/
stations/incidents); residents/municipalities/barangays stay unrestricted
for both roles, since an admin legitimately needs to find any resident who
reported to them.

No human-readable incident reference number exists in this schema yet
(incidents.id is a UUID — see IncidentResponse) — the spec's own example
("INC-2026-00125") assumes a format this project doesn't have. A full UUID
still matches exactly; anything else searches the report text instead (see
_incident_query) — a partial/fuzzy UUID match isn't a capability Postgres
has (uuid has no ILIKE operator, confirmed against the live database while
building this). Generating and displaying a real reference number is a
separate, larger change, out of scope for this plan.
"""

import re
from typing import Any

from app.db.supabase_client import get_supabase

_LIMIT = 5

# A query that (once spaces/hyphens are stripped) is 32 hex characters — the
# only shape an exact incident.id lookup can use. Verified empirically
# against the live database before relying on it: incidents.id is a real
# `uuid` column, and Postgres has no ILIKE operator for uuid — attempting
# one raises 42883 "operator does not exist: uuid ~~* unknown". `.eq()` on a
# full UUID works; a partial/fuzzy match on the id does not exist as a
# capability at all, hence the fallback to report_text below for anything
# that isn't a complete UUID.
_UUID_RE = re.compile(r"^[0-9a-f]{32}$", re.IGNORECASE)


def _agency_ids_for_type(db, agency_type: str | None) -> list[str]:
    """
    Two-step lookup: a Provincial Admin's agency_type -> every `agencies.id`
    it covers. Same pattern as dispatch_service._agency_ids_for_type — every
    entity this module scopes keys off agency_id, not agency_type.
    """
    if not agency_type:
        return []
    rows = db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
    return [row["id"] for row in rows]


def _incident_query(db, query: str, role: str | None, agency_id: str | None, agency_ids: list[str]):
    normalized = query.strip().replace("-", "")
    q = db.table("incidents").select("id, report_text, status, assigned_agency_id")
    if _UUID_RE.match(normalized):
        # Re-hyphenate to canonical UUID form for the equality filter.
        canonical = f"{normalized[0:8]}-{normalized[8:12]}-{normalized[12:16]}-{normalized[16:20]}-{normalized[20:32]}"
        q = q.eq("id", canonical)
    else:
        q = q.ilike("report_text", f"%{query}%")
    if role == "agency_admin" and agency_id:
        q = q.eq("assigned_agency_id", agency_id)
    elif role == "provincial_admin":
        q = q.in_("assigned_agency_id", agency_ids)
    return q.limit(_LIMIT).execute().data or []


def search(query: str, current_user: dict) -> dict[str, list[dict[str, Any]]]:
    db = get_supabase()
    role = current_user.get("role")
    agency_id = str(current_user.get("agency_id")) if current_user.get("agency_id") else None
    # Resolved once and reused across every agency-scoped entity below.
    # Empty for anyone but a provincial_admin, and for a provincial_admin
    # with no matching agencies — either way, `.in_("agency_id", [])`
    # correctly matches nothing rather than silently dropping the filter.
    agency_ids = _agency_ids_for_type(db, current_user.get("agency_type")) if role == "provincial_admin" else []
    like = f"%{query}%"

    # ── Residents — never agency-scoped ─────────────────────────
    residents = (
        db.table("users")
        .select("id, full_name, email")
        .eq("role", "resident")
        .ilike("full_name", like)
        .limit(_LIMIT)
        .execute()
        .data or []
    )

    # ── Responders — Agency Admin sees only their own agency ────
    responder_query = (
        db.table("users")
        .select("id, full_name, badge_id, agency_id")
        .eq("role", "responder")
        .ilike("full_name", like)
        .limit(_LIMIT)
    )
    if role == "agency_admin" and agency_id:
        responder_query = responder_query.eq("agency_id", agency_id)
    elif role == "provincial_admin":
        responder_query = responder_query.in_("agency_id", agency_ids)
    responders = responder_query.execute().data or []

    # ── Agency Admins — a Provincial Admin only sees other admins of their
    # own agency_type meaningfully, but an Agency Admin searching is unlikely
    # to need this; scope it the same way as responders for consistency
    # rather than special-casing it out for one role. ────────────────
    admin_query = (
        db.table("users")
        .select("id, full_name, email, agency_id")
        .eq("role", "agency_admin")
        .ilike("full_name", like)
        .limit(_LIMIT)
    )
    if role == "agency_admin" and agency_id:
        admin_query = admin_query.eq("agency_id", agency_id)
    elif role == "provincial_admin":
        admin_query = admin_query.in_("agency_id", agency_ids)
    agency_admins = admin_query.execute().data or []

    # ── Stations ─────────────────────────────────────────────────
    station_query = (
        db.table("stations")
        .select("id, name, agency_id, agencies(agency_type, name)")
        .ilike("name", like)
        .limit(_LIMIT)
    )
    if role == "agency_admin" and agency_id:
        station_query = station_query.eq("agency_id", agency_id)
    elif role == "provincial_admin":
        station_query = station_query.in_("agency_id", agency_ids)
    stations = station_query.execute().data or []

    # ── Incidents — exact UUID match, or a free-text match over the report
    # itself (see _incident_query and the module docstring for why a
    # partial-UUID match isn't possible here). ──────────────────────
    incidents = _incident_query(db, query, role, agency_id, agency_ids)

    # ── Geography — never agency-scoped ──────────────────────────
    barangay_rows = (
        db.table("barangays")
        .select("id, name, municipality")
        .ilike("name", like)
        .limit(_LIMIT)
        .execute()
        .data or []
    )
    municipalities = sorted({
        row["municipality"] for row in (
            db.table("barangays").select("municipality").ilike("municipality", like).execute().data or []
        )
    })[:_LIMIT]

    return {
        "residents": [
            {"id": r["id"], "label": r["full_name"], "sublabel": r.get("email"), "link": f"/accounts?highlight={r['id']}"}
            for r in residents
        ],
        "responders": [
            {"id": r["id"], "label": r["full_name"], "sublabel": r.get("badge_id"), "link": f"/accounts?highlight={r['id']}"}
            for r in responders
        ],
        "agency_admins": [
            {"id": a["id"], "label": a["full_name"], "sublabel": a.get("email"), "link": "/accounts"}
            for a in agency_admins
        ],
        "stations": [
            {
                "id": s["id"],
                "label": s["name"],
                "sublabel": (s.get("agencies") or {}).get("agency_type"),
                "link": f"/agencies/{s['id']}" if role == "provincial_admin" else "/agencies",
            }
            for s in stations
        ],
        "incidents": [
            {"id": i["id"], "label": (i.get("report_text") or "")[:60], "sublabel": i.get("status"), "link": f"/incidents/{i['id']}"}
            for i in incidents
        ],
        "barangays": [
            {"id": b["id"], "label": b["name"], "sublabel": b["municipality"], "link": "/geographic"}
            for b in barangay_rows
        ],
        "municipalities": [
            {"id": m, "label": m, "sublabel": None, "link": "/geographic"}
            for m in municipalities
        ],
    }
