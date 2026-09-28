"""
report_service — Reports & Export (spec Section 16).

Each report type is a `_rows_for` function returning (headers, rows); three
renderers (CSV/XLSX/PDF) turn that into bytes. Reuses analytics_service and
geographic_service for the underlying numbers where they already compute
what a report needs, rather than re-querying from scratch.
"""

import csv
import io
from datetime import datetime
from typing import Any

from app.db.supabase_client import get_supabase
from app.services import analytics_service

REPORT_TYPES = (
    "monthly_incidents", "agency_performance", "municipality_incidents",
    "barangay_incidents", "resident_registrations", "responders", "incident_resolution",
    "severity_breakdown", "sla_compliance", "flagged_reports",
)
FORMATS = ("csv", "xlsx", "pdf")

#: Reports Agency Admin may generate (Agency Admin spec Section 14) — every
#: one scoped to their own agency by build_report's agency_id. The three left
#: out (municipality/barangay/resident_registrations) are province-wide or
#: resident-facing figures with no per-agency cut; Provincial Admin sees all
#: ten, the seven agency-owned ones scoped to their own agency_type via
#: build_report's agency_type (migration 034) — never unscoped.
AGENCY_ADMIN_REPORT_TYPES = (
    "monthly_incidents", "agency_performance", "responders", "incident_resolution",
    "severity_breakdown", "sla_compliance", "flagged_reports",
)

#: Every severity report below counts by, in this fixed worst-first order
#: rather than alphabetical — matches the queue's own GROUP_META ordering
#: (ziren_dashboard/components/incidents/incident-table.tsx) so a report and
#: the live board never disagree about which severity comes first.
_SEVERITY_ORDER = ("critical", "high", "medium", "low")
_SEVERITY_LABEL = {"critical": "Critical", "high": "High", "medium": "Medium", "low": "Low"}

#: Mirrors ziren_dashboard/components/incidents/incident-vocabulary.ts's
#: DISPATCH_TARGET_MINUTES exactly. Those are documented there as
#: provisional numbers, not yet agency policy — when BFP/PNP/MDRRMO confirm
#: their own, both this copy and that one need updating together until the
#: targets move to a per-agency setting alongside the rubric configs.
_DISPATCH_TARGET_MINUTES = {"critical": 5, "high": 10, "medium": 30, "low": 60}
_DEFAULT_TARGET_MINUTES = 5  # untriaged — same reasoning as the frontend's DEFAULT_TARGET_MINUTES

Rows = tuple[list[str], list[list[Any]]]


def _inclusive_end(date_to: str | None) -> str | None:
    """Identical to analytics_service's own copy — see its doc comment."""
    if date_to and "T" not in date_to:
        return f"{date_to}T23:59:59.999999"
    return date_to


def _agency_ids_for_type(agency_type: str) -> list[str]:
    """Same two-step lookup dispatch_service._agency_ids_for_type/analytics_service
    use — no agency_type column on incidents/responders, only on agencies."""
    db = get_supabase()
    return [
        row["id"] for row in (
            db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
        )
    ]


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


# ── Row builders ─────────────────────────────────────────────────────────

def _monthly_incidents(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    data = analytics_service.incident_analytics(
        period="month", agency_id=agency_id, agency_type=agency_type,
        date_from=start_date, date_to=end_date,
    )
    headers = ["Month", "Incident Count"]
    rows = [[p["bucket"], p["count"]] for p in data["by_period"]]
    return headers, rows


def _agency_performance(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    data = analytics_service.agency_analytics(
        agency_id=agency_id, agency_type=agency_type, date_from=start_date, date_to=end_date,
    )
    per_agency = data["agency"] if agency_id else data
    headers = ["Agency", "Handled", "Resolved", "Cancelled", "Resolution Rate", "Avg Response (min)", "Avg Resolution (min)"]
    rows = [
        [
            agency, stats["incidents_handled"], stats["resolved"], stats["cancelled"],
            f"{round(stats['resolution_rate'] * 100)}%" if stats["resolution_rate"] is not None else "—",
            stats["avg_response_minutes"] if stats["avg_response_minutes"] is not None else "—",
            stats["avg_resolution_minutes"] if stats["avg_resolution_minutes"] is not None else "—",
        ]
        for agency, stats in per_agency.items()
    ]
    return headers, rows


def _municipality_incidents(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    # agency_id/agency_type ignored on purpose — this report has no per-agency cut (see
    # AGENCY_ADMIN_REPORT_TYPES's own comment); accepted anyway so build_report
    # can call every builder the same way.
    data = analytics_service.incident_analytics(date_from=start_date, date_to=end_date)
    headers = ["Municipality", "Incident Count"]
    rows = sorted(data["by_municipality"].items(), key=lambda kv: -kv[1])
    return headers, [[m, c] for m, c in rows]


def _barangay_incidents(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    """
    Incidents grouped by the REPORTER's barangay — a different, and more
    schema-honest, cut than "which station handled it" (used by
    municipality_incidents / geographic_service): incidents carry a
    station_id but no barangay of their own, while the reporting resident
    carries a real barangay_id. This answers "where are reports coming
    from", which a barangay-level report is more naturally about anyway.

    agency_id/agency_type ignored — same reasoning as _municipality_incidents above.
    """
    db = get_supabase()
    query = db.table("incidents").select(
        "id, created_at, users!incidents_reporter_id_fkey(barangays(name, municipality))"
    )
    if start_date:
        query = query.gte("created_at", start_date)
    if end_date:
        query = query.lte("created_at", _inclusive_end(end_date))
    rows = query.execute().data or []
    counts: dict[str, int] = {}
    for row in rows:
        reporter = row.get("users") or {}
        barangay = reporter.get("barangays") if isinstance(reporter, dict) else None
        if not isinstance(barangay, dict) or not barangay.get("name"):
            continue
        key = f"{barangay['municipality']} / {barangay['name']}"
        counts[key] = counts.get(key, 0) + 1

    headers = ["Barangay", "Incident Count"]
    ordered = sorted(counts.items(), key=lambda kv: -kv[1])
    return headers, [[b, c] for b, c in ordered]


def _resident_registrations(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    # agency_id/agency_type ignored — residents aren't tied to an agency. With a date
    # range, this becomes "who registered in this period" rather than the
    # all-time cumulative total — see user_analytics's own doc comment.
    data = analytics_service.user_analytics(date_from=start_date, date_to=end_date)
    headers = ["Barangay", "Registered Residents"]
    ordered = sorted(data["by_barangay"].items(), key=lambda kv: -kv[1])
    return headers, [[b, c] for b, c in ordered]


def _responders(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    # start_date/end_date ignored — this is the CURRENT roster, a snapshot of
    # who exists and their present status, not a log of events over time.
    db = get_supabase()
    query = (
        db.table("users")
        .select("full_name, badge_id, approval_status, availability, agencies(agency_type, name)")
        .eq("role", "responder")
        .order("full_name")
    )
    if agency_id:
        query = query.eq("agency_id", agency_id)
    elif agency_type:
        query = query.in_("agency_id", _agency_ids_for_type(agency_type))
    rows = query.execute().data or []
    headers = ["Name", "Badge ID", "Agency", "Approval Status", "Availability"]
    out = []
    for r in rows:
        agency = r.get("agencies") or {}
        agency_label = f"{agency.get('agency_type')} — {agency.get('name')}" if agency.get("name") else "—"
        out.append([r.get("full_name"), r.get("badge_id") or "—", agency_label, r.get("approval_status"), r.get("availability") or "—"])
    return headers, out


def _incident_resolution(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    # Filtered by WHEN RESOLVED, not when reported — "resolutions in this
    # period" is the reading a station chief handing this to a mayor wants;
    # an incident reported in August and resolved in September belongs to
    # September's report.
    db = get_supabase()
    query = (
        db.table("incidents")
        .select("id, status, created_at, resolved_at, stations(agencies(agency_type, name))")
        .eq("status", "resolved")
        .order("resolved_at", desc=True)
    )
    if agency_id:
        query = query.eq("assigned_agency_id", agency_id)
    elif agency_type:
        query = query.in_("assigned_agency_id", _agency_ids_for_type(agency_type))
    if start_date:
        query = query.gte("resolved_at", start_date)
    if end_date:
        query = query.lte("resolved_at", _inclusive_end(end_date))
    rows = query.execute().data or []
    headers = ["Incident ID", "Agency", "Reported At", "Resolved At", "Resolution Time (min)"]
    out = []
    for r in rows:
        agency = (r.get("stations") or {}).get("agencies") or {}
        agency_label = f"{agency.get('agency_type')} — {agency.get('name')}" if agency.get("name") else "—"
        created = r.get("created_at")
        resolved = r.get("resolved_at")
        minutes = "—"
        c, rt = _parse_dt(created), _parse_dt(resolved)
        if c and rt:
            minutes = round((rt - c).total_seconds() / 60, 1)
        out.append([r["id"], agency_label, created, resolved, minutes])
    return headers, out


def _severity_breakdown(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    """
    Counts by the severity actually assigned at dispatch (the `severity`
    column) — not a live re-run of the triage rubric, which would make a
    historical report a moving target every time the rubric config changes.
    A report never dispatched (severity still NULL) counts as Untriaged
    rather than being silently dropped; an agency's untriaged backlog is
    itself something a report should be able to show.
    """
    db = get_supabase()
    query = db.table("incidents").select("severity, created_at")
    if agency_id:
        query = query.eq("assigned_agency_id", agency_id)
    elif agency_type:
        query = query.in_("assigned_agency_id", _agency_ids_for_type(agency_type))
    if start_date:
        query = query.gte("created_at", start_date)
    if end_date:
        query = query.lte("created_at", _inclusive_end(end_date))
    rows = query.execute().data or []

    order = (*_SEVERITY_ORDER, "untriaged")
    counts: dict[str, int] = {s: 0 for s in order}
    for r in rows:
        sev = r.get("severity")
        counts[sev if sev in counts else "untriaged"] += 1

    total = sum(counts.values())
    headers = ["Severity", "Incident Count", "Share of Total"]
    out = []
    for sev in order:
        count = counts[sev]
        share = f"{round(count / total * 100)}%" if total else "—"
        out.append([_SEVERITY_LABEL.get(sev, "Untriaged"), count, share])
    return headers, out


def _sla_compliance(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    """
    Measures created_at -> dispatched_at against _DISPATCH_TARGET_MINUTES,
    per severity — "how often did we actually dispatch within the promised
    window", not just the average response time _agency_performance already
    shows. A report never dispatched at all counts under "Still Awaiting
    Dispatch" rather than as a miss or a pass — it has not been decided
    either way yet, and folding it into "late" would make an agency's
    current backlog look like a completed failure instead of open work.
    """
    db = get_supabase()
    query = db.table("incidents").select("severity, created_at, dispatched_at")
    if agency_id:
        query = query.eq("assigned_agency_id", agency_id)
    elif agency_type:
        query = query.in_("assigned_agency_id", _agency_ids_for_type(agency_type))
    if start_date:
        query = query.gte("created_at", start_date)
    if end_date:
        query = query.lte("created_at", _inclusive_end(end_date))
    rows = query.execute().data or []

    order = (*_SEVERITY_ORDER, "untriaged")
    buckets: dict[str, dict[str, int]] = {s: {"on_time": 0, "late": 0, "awaiting": 0} for s in order}
    for r in rows:
        sev = r.get("severity") if r.get("severity") in _SEVERITY_ORDER else "untriaged"
        target = _DISPATCH_TARGET_MINUTES.get(sev, _DEFAULT_TARGET_MINUTES)
        dispatched = _parse_dt(r.get("dispatched_at"))
        if not dispatched:
            buckets[sev]["awaiting"] += 1
            continue
        created = _parse_dt(r.get("created_at"))
        if not created:
            continue
        minutes = (dispatched - created).total_seconds() / 60
        buckets[sev]["on_time" if minutes <= target else "late"] += 1

    headers = [
        "Severity", "Target (min)", "Dispatched On Time", "Dispatched Late",
        "Still Awaiting Dispatch", "Compliance Rate",
    ]
    out = []
    for sev in order:
        b = buckets[sev]
        decided = b["on_time"] + b["late"]
        rate = f"{round(b['on_time'] / decided * 100)}%" if decided else "—"
        target = _DISPATCH_TARGET_MINUTES.get(sev, _DEFAULT_TARGET_MINUTES)
        out.append([_SEVERITY_LABEL.get(sev, "Untriaged"), target, b["on_time"], b["late"], b["awaiting"], rate])
    return headers, out


def _flagged_reports(
    agency_id: str | None = None, agency_type: str | None = None,
    start_date: str | None = None, end_date: str | None = None,
) -> Rows:
    """
    Two different kinds of "this report needs scrutiny" event, in one table:
    Rejected (an agency_admin looked at it and decided it was not real) and
    SOS-Flagged Reporter (the SOS button was used by a reporter who already
    had at least one prior confirmed false alarm at the moment they filed
    THIS report).

    The second is NOT "this incident was confirmed false" — flag_false_sos
    (dispatch_service.py) only ever updates the REPORTER's account
    (sos_warning_count / sos_suspended_until), never a column on the
    incident itself, so there is no per-incident "confirmed false" marker to
    query here. `sos_flagged` on the incident is the closest real signal
    available, and the Reason column says exactly what it does and does not
    mean rather than letting the row be misread as a finding it is not.
    """
    db = get_supabase()
    select_cols = (
        "id, review_status, rejection_reason, reviewed_at, sos_flagged, created_at, "
        "stations(agencies(agency_type, name)), "
        "users!incidents_reporter_id_fkey(full_name, sos_warning_count)"
    )

    def _scoped(query):
        if agency_id:
            query = query.eq("assigned_agency_id", agency_id)
        elif agency_type:
            query = query.in_("assigned_agency_id", _agency_ids_for_type(agency_type))
        if start_date:
            query = query.gte("created_at", start_date)
        if end_date:
            query = query.lte("created_at", _inclusive_end(end_date))
        return query

    rejected = _scoped(
        db.table("incidents").select(select_cols).eq("review_status", "rejected")
    ).execute().data or []
    sos_flagged = _scoped(
        db.table("incidents").select(select_cols).eq("sos_flagged", True)
    ).execute().data or []

    def _agency_label(r: dict) -> str:
        agency = (r.get("stations") or {}).get("agencies") or {}
        return f"{agency.get('agency_type')} — {agency.get('name')}" if agency.get("name") else "—"

    def _reporter_name(r: dict) -> str:
        return (r.get("users") or {}).get("full_name") or "—"

    headers = ["Incident ID", "Type", "Reason", "Reporter", "Agency", "Date"]
    out = []
    for r in rejected:
        out.append([
            r["id"], "Rejected", r.get("rejection_reason") or "—",
            _reporter_name(r), _agency_label(r), r.get("reviewed_at") or r.get("created_at"),
        ])
    for r in sos_flagged:
        warn_count = (r.get("users") or {}).get("sos_warning_count") or 0
        out.append([
            r["id"], "SOS-Flagged Reporter",
            f"Reporter had {warn_count} prior confirmed false alarm(s) at submission",
            _reporter_name(r), _agency_label(r), r.get("created_at"),
        ])
    out.sort(key=lambda row: row[5] or "", reverse=True)
    return headers, out


_BUILDERS = {
    "monthly_incidents": _monthly_incidents,
    "agency_performance": _agency_performance,
    "municipality_incidents": _municipality_incidents,
    "barangay_incidents": _barangay_incidents,
    "resident_registrations": _resident_registrations,
    "responders": _responders,
    "incident_resolution": _incident_resolution,
    "severity_breakdown": _severity_breakdown,
    "sla_compliance": _sla_compliance,
    "flagged_reports": _flagged_reports,
}

_TITLES = {
    "monthly_incidents": "Monthly Incident Report",
    "agency_performance": "Agency Performance Report",
    "municipality_incidents": "Municipality Incident Report",
    "barangay_incidents": "Barangay Incident Report",
    "resident_registrations": "Resident Registration Report",
    "responders": "Responder Roster Report",
    "incident_resolution": "Incident Resolution Report",
    "severity_breakdown": "Severity Breakdown Report",
    "sla_compliance": "SLA Compliance Report",
    "flagged_reports": "Flagged Reports (False SOS & Rejected)",
}


# ── Renderers ────────────────────────────────────────────────────────────

def _to_csv(headers: list[str], rows: list[list[Any]]) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(headers)
    writer.writerows(rows)
    return buf.getvalue().encode("utf-8")


def _to_xlsx(headers: list[str], rows: list[list[Any]]) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import Font

    wb = Workbook()
    ws = wb.active
    ws.append(headers)
    for cell in ws[1]:
        cell.font = Font(bold=True)
    for row in rows:
        ws.append(row)
    for col in ws.columns:
        width = max((len(str(c.value)) for c in col if c.value is not None), default=10)
        ws.column_dimensions[col[0].column_letter].width = min(max(width + 2, 10), 40)

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def _to_pdf(
    title: str, headers: list[str], rows: list[list[Any]], period_label: str | None = None,
) -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import letter
    from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
    from reportlab.lib.styles import getSampleStyleSheet

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=letter)
    styles = getSampleStyleSheet()

    table_data = [headers] + [[str(v) if v is not None else "—" for v in row] for row in rows]
    table = Table(table_data, repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#FC5A05")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F7F6F3")]),
    ]))

    elements = [Paragraph(title, styles["Title"])]
    # The reporting period, right under the title — a printed report with no
    # stated period is unreadable proof of anything, since nobody looking at
    # it later can tell whether it covers a week, a year, or all of history.
    if period_label:
        elements.append(Paragraph(period_label, styles["Normal"]))
    elements.append(Paragraph(f"Generated {datetime.now().strftime('%Y-%m-%d %H:%M')}", styles["Normal"]))
    elements.append(Spacer(1, 12))
    elements.append(table)
    doc.build(elements)
    return buf.getvalue()


_MEDIA_TYPES = {
    "csv": "text/csv",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "pdf": "application/pdf",
}


def build_report(
    report_type: str,
    fmt: str,
    *,
    agency_id: str | None = None,
    agency_type: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
) -> tuple[bytes, str, str]:
    if report_type not in _BUILDERS:
        raise ValueError(f"Unknown report_type: {report_type}")
    if fmt not in FORMATS:
        raise ValueError(f"Unknown format: {fmt}")

    # Every builder now takes the same four keyword args — including the
    # ones that ignore one or more of them (_responders ignores the dates,
    # three others ignore agency_id/agency_type; each says so in its own
    # docstring). One calling convention for all ten means adding an
    # eleventh report never again requires touching this dispatch function.
    # agency_id (Agency Admin, one station) and agency_type (Provincial
    # Admin, every station of one type) are mutually exclusive — the router
    # passes exactly one or neither, never both.
    builder = _BUILDERS[report_type]
    headers, rows = builder(
        agency_id=agency_id, agency_type=agency_type, start_date=start_date, end_date=end_date,
    )
    title = _TITLES[report_type]

    if fmt == "csv":
        content = _to_csv(headers, rows)
    elif fmt == "xlsx":
        content = _to_xlsx(headers, rows)
    else:
        period_label = (
            f"For {start_date} through {end_date}" if start_date and end_date
            else f"From {start_date} onward" if start_date
            else f"Through {end_date}" if end_date
            else "All-time — no date range applied"
        )
        content = _to_pdf(title, headers, rows, period_label)

    filename = f"{report_type}_{datetime.now().strftime('%Y-%m-%d')}.{fmt}"
    return content, filename, _MEDIA_TYPES[fmt]
