"""
analytics_service — long-term trend analysis for Provincial Admin's System
Analytics module (spec Section 9). Unlike the Dashboard (current state),
this module looks across time.

Same approach as geographic_service: fetch rows once, aggregate in Python
with collections.Counter/defaultdict. One province's worth of incidents and
users is small enough that this is simpler to write and test than a SQL
function — see geographic_service's module docstring for the fuller
rationale, which applies here unchanged.

Pragmatic cut: incidents have no barangay of their own (only a free-text
location_address and a station_id) — "by_barangay" for incidents is not
attempted here for the same reason geographic_service only attributes
incidents to a municipality via their assigned station. User growth by
barangay IS meaningful (residents carry a real barangay_id) and is included.
"""

from collections import Counter, defaultdict
from datetime import datetime
from typing import Any

from app.db.supabase_client import get_supabase


def _bucket_key(iso_timestamp: str, period: str) -> str:
    if period == "year":
        return iso_timestamp[:4]
    if period == "day":
        return iso_timestamp[:10]
    return iso_timestamp[:7]  # month, the default


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _inclusive_end(date_to: str | None) -> str | None:
    """
    date_to arrives as a bare 'YYYY-MM-DD' from an <input type="date">.
    Comparing it with .lte() as-is means "at or before midnight AT THE START
    of that day" — excluding every row from the day itself after 00:00,
    which is the one day a caller who picked that date almost certainly
    meant to include. dispatch_service.py's own _date_window solves the same
    problem a different way (an exclusive upper bound one day later); this
    one stays a simple inclusive bound since every caller here already uses
    .lte(). A value that already carries a time (a full ISO timestamp, not a
    bare date) is left alone rather than double-appended.
    """
    if date_to and "T" not in date_to:
        return f"{date_to}T23:59:59.999999"
    return date_to


def incident_analytics(
    period: str = "month",
    date_from: str | None = None,
    date_to: str | None = None,
    agency_id: str | None = None,
    agency_type: str | None = None,
) -> dict[str, Any]:
    """
    agency_id scopes every figure to incidents ASSIGNED TO that one agency —
    Agency Admin's Agency Analytics (spec Section 13) reuses this rather than
    duplicating the aggregation, the same incidents just pre-filtered to one
    agency instead of the whole province.

    agency_type scopes to every agency of that type — a Provincial Admin's
    own agency_type, resolved via the same two-step agencies lookup
    dispatch_service._agency_ids_for_type uses. Mutually exclusive with
    agency_id in practice (one caller passes one or the other, never both).
    """
    if period not in ("day", "month", "year"):
        period = "month"

    db = get_supabase()
    query = db.table("incidents").select(
        "id, status, severity, incident_category, created_at, resolved_at, "
        "stations(agencies(agency_type, municipality, name))"
    )
    if date_from:
        query = query.gte("created_at", date_from)
    if date_to:
        query = query.lte("created_at", _inclusive_end(date_to))
    if agency_id:
        query = query.eq("assigned_agency_id", agency_id)
    elif agency_type:
        agency_ids = [
            row["id"] for row in (
                db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
            )
        ]
        query = query.in_("assigned_agency_id", agency_ids)
    rows = query.execute().data or []

    by_period: Counter[str] = Counter()
    by_municipality: Counter[str] = Counter()
    by_agency: Counter[str] = Counter()
    by_type: Counter[str] = Counter()
    by_severity: Counter[str] = Counter()
    resolved = 0
    resolution_minutes: list[float] = []

    for row in rows:
        created_at = row.get("created_at")
        if created_at:
            by_period[_bucket_key(created_at, period)] += 1

        agency_info = (row.get("stations") or {}).get("agencies") or {}
        if agency_info.get("municipality"):
            by_municipality[agency_info["municipality"]] += 1
        if agency_info.get("agency_type"):
            by_agency[agency_info["agency_type"]] += 1

        by_type[row.get("incident_category") or "other"] += 1
        by_severity[row.get("severity") or "untriaged"] += 1

        if row.get("status") == "resolved":
            resolved += 1
            created = _parse_dt(created_at)
            finished = _parse_dt(row.get("resolved_at"))
            if created and finished:
                resolution_minutes.append((finished - created).total_seconds() / 60)

    total = len(rows)
    avg_resolution_minutes = (
        round(sum(resolution_minutes) / len(resolution_minutes), 1) if resolution_minutes else None
    )

    return {
        "total": total,
        "by_period": [{"bucket": k, "count": v} for k, v in sorted(by_period.items())],
        "by_municipality": dict(by_municipality),
        "by_agency": dict(by_agency),
        "by_type": dict(by_type),
        "by_severity": dict(by_severity),
        "resolved_vs_unresolved": {"resolved": resolved, "unresolved": total - resolved},
        "avg_resolution_minutes": avg_resolution_minutes,
    }


def user_analytics(
    date_from: str | None = None,
    date_to: str | None = None,
    agency_type: str | None = None,
) -> dict[str, Any]:
    """
    date_from/date_to filter by REGISTRATION date — with a range given, this
    answers "who signed up in this period", not the all-time cumulative
    total the no-range call answers. Both are legitimate readings of "user
    analytics"; which one a caller gets is just whether they passed a range.

    agency_type scopes agency_admin/responder rows to a Provincial Admin's
    own agency_type — residents are left unscoped regardless, the same
    Type B carve-out migration 034 documents for resident data: a resident
    has no agency_id at all, so "which agency_type's residents" is not a
    question this data model can answer, and pretending otherwise would
    just make a Provincial Admin's resident count silently read zero.
    Filtered in Python (not the query) because the type lives on the joined
    `agencies` row, one hop from where role/agency_id already are.
    """
    db = get_supabase()
    query = (
        db.table("users")
        .select("id, role, created_at, agency_id, barangays(name, municipality), agencies(agency_type)")
        .neq("role", "provincial_admin")
    )
    if date_from:
        query = query.gte("created_at", date_from)
    if date_to:
        query = query.lte("created_at", _inclusive_end(date_to))
    rows = query.execute().data or []

    if agency_type:
        rows = [
            row for row in rows
            if row.get("role") == "resident"
            or (row.get("agencies") or {}).get("agency_type") == agency_type
        ]

    registration_by_month: dict[str, Counter[str]] = defaultdict(Counter)
    by_municipality: Counter[str] = Counter()
    by_barangay: Counter[str] = Counter()

    for row in rows:
        role = row.get("role") or "unknown"
        created_at = row.get("created_at")
        if created_at:
            registration_by_month[role][created_at[:7]] += 1

        barangay_info = row.get("barangays")
        if isinstance(barangay_info, dict) and barangay_info.get("municipality"):
            by_municipality[barangay_info["municipality"]] += 1
            by_barangay[f"{barangay_info['municipality']} / {barangay_info['name']}"] += 1

    registration_trend = {
        role: [{"month": m, "count": c} for m, c in sorted(months.items())]
        for role, months in registration_by_month.items()
    }

    return {
        "total_by_role": dict(Counter(r.get("role") or "unknown" for r in rows)),
        "registration_trend": registration_trend,
        "by_municipality": dict(by_municipality),
        "by_barangay": dict(by_barangay),
    }


def _responder_workload(agency_id: str) -> list[dict[str, Any]]:
    """How many incidents each of the agency's responders has handled.

    Spec Section 13 lists this alongside resolution rate and response time —
    it is the one figure only Agency Admin's SCOPED view needs, since a
    province-wide responder-workload list across every agency would be a
    roster, not an analytic.
    """
    db = get_supabase()
    rows = (
        db.table("incidents")
        .select("assigned_responder_id, users!incidents_assigned_responder_id_fkey(full_name)")
        .eq("assigned_agency_id", agency_id)
        .not_.is_("assigned_responder_id", "null")
        .execute()
        .data or []
    )
    counts: Counter[str] = Counter()
    for row in rows:
        responder = row.get("users") or {}
        name = responder.get("full_name") if isinstance(responder, dict) else None
        if name:
            counts[name] += 1
    return [
        {"responder": name, "incidents_handled": count}
        for name, count in sorted(counts.items(), key=lambda kv: -kv[1])
    ]


def agency_analytics(
    agency_id: str | None = None,
    agency_type: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
) -> dict[str, Any]:
    """
    agency_id scopes the aggregation to one agency's own incidents and adds
    `responder_workload` — Agency Admin's Agency Analytics (spec Section 13).

    agency_type scopes to every agency of that type — a Provincial Admin's
    own agency_type (migration 034). per_agency is already keyed by
    agency_type (not by individual agency), so this naturally collapses to
    one key, the same plain shape as the fully-unscoped call below (no
    `responder_workload` wrapper — that stays Agency Admin-only, one
    station's roster, not meaningful across many stations).

    Without either, this is the fully-unscoped per-agency-type comparison
    and the shape is unchanged from before.
    """
    db = get_supabase()
    query = (
        db.table("incidents")
        .select(
            "id, status, created_at, dispatched_at, resolved_at, "
            "stations(agencies(agency_type, name))"
        )
    )
    if agency_id:
        query = query.eq("assigned_agency_id", agency_id)
    elif agency_type:
        type_agency_ids = [
            row["id"] for row in (
                db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
            )
        ]
        query = query.in_("assigned_agency_id", type_agency_ids)
    if date_from:
        query = query.gte("created_at", date_from)
    if date_to:
        query = query.lte("created_at", _inclusive_end(date_to))
    rows = query.execute().data or []

    per_agency: dict[str, dict[str, Any]] = defaultdict(lambda: {
        "handled": 0, "resolved": 0, "cancelled": 0,
        "response_minutes": [], "resolution_minutes": [],
    })

    for row in rows:
        agency_info = (row.get("stations") or {}).get("agencies") or {}
        agency = agency_info.get("agency_type")
        if not agency:
            continue
        bucket = per_agency[agency]
        bucket["handled"] += 1

        created = _parse_dt(row.get("created_at"))
        dispatched = _parse_dt(row.get("dispatched_at"))
        resolved = _parse_dt(row.get("resolved_at"))

        if row.get("status") == "resolved":
            bucket["resolved"] += 1
            if created and resolved:
                bucket["resolution_minutes"].append((resolved - created).total_seconds() / 60)
        elif row.get("status") == "cancelled":
            bucket["cancelled"] += 1

        if created and dispatched:
            bucket["response_minutes"].append((dispatched - created).total_seconds() / 60)

    def _avg(values: list[float]) -> float | None:
        return round(sum(values) / len(values), 1) if values else None

    result = {
        agency: {
            "incidents_handled":       b["handled"],
            "resolved":                b["resolved"],
            "cancelled":               b["cancelled"],
            "resolution_rate":         round(b["resolved"] / b["handled"], 3) if b["handled"] else None,
            "avg_response_minutes":    _avg(b["response_minutes"]),
            "avg_resolution_minutes":  _avg(b["resolution_minutes"]),
        }
        for agency, b in per_agency.items()
    }
    if agency_id:
        # A different shape on purpose: the unscoped call's plain
        # agency_type -> stats dict is read by Object.entries() on the
        # Provincial Admin analytics page, and a "responder_workload" key mixed into
        # that same dict would render as a fourth, malformed "agency" card.
        # The scoped caller (Agency Admin's own page) reads this shape
        # instead and never sees the unscoped one.
        return {"agency": result, "responder_workload": _responder_workload(agency_id)}
    return result
