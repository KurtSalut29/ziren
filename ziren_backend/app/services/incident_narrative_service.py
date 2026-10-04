"""
incident_narrative_service — the post-resolution Narrative Report.

One report per incident, written by the Agency Admin after it closes. Migration
038 made it a page of prose; migration 040 makes it the full Incident Record Form
(IRF) an agency actually files — the reporting person, the suspects, the victims,
the narrative, the certification and the officers, on the same Item A to D layout
as the police form it is modelled on — and this module stores it, lists it, and
prints it.

Read is agency_admin (own agency) + provincial_admin (own agency_type,
oversight); write is agency_admin only — the router enforces which via
`_admin_read` / `_dispatcher`, this module enforces the agency SCOPE within
whichever role got through.

WHAT LIVES WHERE

The narrative, the byline fields and the agency's own reference number are
columns (migration 038). Everything else the form asks for goes in one JSONB
column, `details` (migration 040): a report holds a variable number of suspects
and victims, each a couple of dozen fields, and a column per field would be a
schema nobody could keep in step with the form. `_clean_details` is the one place
that decides what may be stored in it.

BEFORE MIGRATION 040 IS APPLIED

The `details` column will not exist, and the rest of the feature must not fall
over because of it. Saving then stores the columns it can, reports
`details_saved: false` to the caller, and `details_supported` is false on every
read so the dashboard can say so instead of pretending. `_details_supported()` is
the single probe for that.
"""

import io
import time
from datetime import date, datetime, timedelta, timezone

import structlog
from fastapi import HTTPException, status
from supabase import Client

from app.core.dependencies import assert_agency_scope
from app.db.supabase_client import get_supabase
from app.services import audit_service

log = structlog.get_logger()

#: The Philippines keeps one offset all year. A fixed offset, rather than a tz
#: database lookup, because a slim container may not ship one.
PH_TZ = timezone(timedelta(hours=8), "PHT")

#: The categories a report can be filed under — the same five real ones the
#: rest of the console offers, plus the catch-all.
CATEGORIES = (
    "fire", "medical_trauma", "vehicular", "flood_landslide_calamity",
    "domestic_dispute_crime", "other",
)
#: What "other" stands for in the database: the catch-all, and two categories
#: that were retired into it by migration 019.
_OTHER_CATEGORIES = ["other", "hazmat", "missing_person"]

CATEGORY_LABELS = {
    "fire": "Fire",
    "medical_trauma": "Medical / Trauma",
    "vehicular": "Vehicular Incident",
    "flood_landslide_calamity": "Flood / Landslide / Calamity",
    "domestic_dispute_crime": "Domestic Dispute / Crime",
    "other": "Other",
    "hazmat": "Other",
    "missing_person": "Other",
}


# =============================================================================
# The `details` column — whether it exists, and what may go in it
# =============================================================================

_probe: dict = {"ok": None, "checked_at": 0.0}
#: A negative answer is re-checked after this long, so the feature lights up on
#: its own once the migration is applied, without restarting the server.
_PROBE_RETRY_SECONDS = 30


def _details_supported(db: Client) -> bool:
    """True once migration 040's `details` column exists.

    A positive answer is cached for good (a column does not go away); a negative
    one only briefly.
    """
    if _probe["ok"]:
        return True
    if _probe["ok"] is False and (time.monotonic() - _probe["checked_at"]) < _PROBE_RETRY_SECONDS:
        return False
    try:
        db.table("incident_narrative_reports").select("details").limit(1).execute()
        _probe["ok"] = True
    except Exception:
        _probe["ok"] = False
    _probe["checked_at"] = time.monotonic()
    return bool(_probe["ok"])


def _reset_probe() -> None:
    """For tests: forget what the last probe said."""
    _probe["ok"] = None
    _probe["checked_at"] = 0.0


def _is_missing_details_column(exc: Exception) -> bool:
    text = str(exc).lower()
    return "details" in text and (
        "column" in text or "pgrst204" in text or "42703" in text or "schema cache" in text
    )


# The person block of the form — the same twenty-odd boxes for the reporting
# person, every suspect and every victim. Order is the order the form prints.
PERSON_FIELDS = (
    "family_name", "first_name", "middle_name", "qualifier", "nickname",
    "citizenship", "gender", "civil_status", "date_of_birth", "age",
    "place_of_birth", "phone",
    "address_street", "barangay", "town_city", "province",
    "education", "occupation", "relation",
)
# What only a suspect's entry asks for.
SUSPECT_FIELDS = (
    "rank", "unit_assignment", "group_affiliation",
    "previous_record", "previous_case_status",
    "height", "weight", "eye_color", "hair_color",
    "distinguishing_marks", "under_influence",
    "guardian_name", "guardian_address",
)
_TOP_TEXT_FIELDS = (
    "copy_for", "offense", "offense_detail",
    "place_barangay", "place_town", "place_province",
    "witnesses", "property_damage", "actions_taken",
)
_CERTIFICATION_FIELDS = ("administering_officer", "investigator_rank_name", "desk_officer_rank_name")
_STATION_FIELDS = ("name", "telephone", "mobile", "chief")

#: Long-form boxes get room; everything else is a name, a number or a word.
_LONG_TEXT = {"witnesses", "property_damage", "actions_taken", "offense_detail", "distinguishing_marks"}
_SHORT_MAX = 300
_LONG_MAX = 4000
MAX_SUSPECTS = 25
MAX_VICTIMS = 100
FORM_VERSION = 1


def _text(value, limit: int) -> str:
    if value is None:
        return ""
    return str(value).strip()[:limit]


def _clean_person(raw, extra: tuple = ()) -> dict:
    raw = raw if isinstance(raw, dict) else {}
    keys = PERSON_FIELDS + extra
    return {k: _text(raw.get(k), _LONG_MAX if k in _LONG_TEXT else _SHORT_MAX) for k in keys}


def _clean_details(raw) -> dict:
    """The form's structured part, reduced to what the form actually has.

    Unknown keys are dropped, everything is text, lists and lengths are capped.
    The body of this request is a browser's word for what to store in a JSONB
    column that is later printed onto a legal-looking document; none of it is
    trusted to be the shape the form would have sent.
    """
    raw = raw if isinstance(raw, dict) else {}

    out: dict = {"form_version": FORM_VERSION}
    for key in _TOP_TEXT_FIELDS:
        out[key] = _text(raw.get(key), _LONG_MAX if key in _LONG_TEXT else _SHORT_MAX)

    out["reporting_person"] = _clean_person(raw.get("reporting_person"))
    out["suspects"] = [
        _clean_person(s, SUSPECT_FIELDS)
        for s in (raw.get("suspects") if isinstance(raw.get("suspects"), list) else [])[:MAX_SUSPECTS]
    ]
    out["victims"] = [
        _clean_person(v)
        for v in (raw.get("victims") if isinstance(raw.get("victims"), list) else [])[:MAX_VICTIMS]
    ]

    cert = raw.get("certification") if isinstance(raw.get("certification"), dict) else {}
    out["certification"] = {k: _text(cert.get(k), _SHORT_MAX) for k in _CERTIFICATION_FIELDS}
    station = raw.get("station") if isinstance(raw.get("station"), dict) else {}
    out["station"] = {k: _text(station.get(k), _SHORT_MAX) for k in _STATION_FIELDS}
    return out


# =============================================================================
# Reading and writing one report
# =============================================================================

def _load_incident_for_scope(db: Client, incident_id: str, actor: dict) -> dict:
    """Fetch the incident's scope-relevant columns and check the caller may
    act on it. Shared by every function below — a narrative report is
    always reached through its incident, never looked up on its own."""
    result = (
        db.table("incidents")
        .select("id, status, assigned_agency_id")
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )
    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    incident = result.data
    assert_agency_scope(actor, str(incident.get("assigned_agency_id") or ""))
    return incident


def get_narrative_report(incident_id: str, actor: dict) -> dict:
    """The saved report (or None if nobody has started one yet — a normal state
    for any incident not yet written up, not an error), and whether this
    database can hold the form's detailed sections."""
    db: Client = get_supabase()
    _load_incident_for_scope(db, incident_id, actor)

    result = (
        db.table("incident_narrative_reports")
        .select("*, created:users!incident_narrative_reports_created_by_fkey(full_name), "
                "updated:users!incident_narrative_reports_updated_by_fkey(full_name), "
                "finalized:users!incident_narrative_reports_finalized_by_fkey(full_name)")
        .eq("incident_id", incident_id)
        .maybe_single()
        .execute()
    )
    return {
        "report": result.data if result else None,
        "details_supported": _details_supported(db),
    }


def save_narrative_report(
    incident_id: str,
    actor: dict,
    *,
    narrative: str,
    reporting_person_name: str | None,
    incident_occurred_at: str | None,
    place_of_incident: str | None,
    prepared_by_name: str | None,
    investigator_name: str | None,
    reference_no: str | None,
    finalize: bool,
    details: dict | None = None,
    amendment_reason: str | None = None,
) -> dict:
    """Create or update the one narrative report an incident may have.

    Only ever callable by an agency_admin (the router's `_dispatcher`
    dependency), and only once the incident the report is ABOUT has
    actually closed — a narrative report describes what happened, and
    nothing "happened" in the past tense on a report still open in the
    queue. `finalize` marks it signed-off without locking it; see migration
    038's header for why editing after finalizing stays allowed.

    A DRAFT may be saved with nothing written yet, because the form is long and
    a person completing the reporting-person box and coming back for the rest is
    the normal way to fill it in. FINALIZING needs the narrative: a report with no
    account of what happened is not a report.
    """
    narrative = (narrative or "").strip()
    if finalize and not narrative:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Write the narrative of the incident before finalizing the report.",
        )

    db: Client = get_supabase()
    incident = _load_incident_for_scope(db, incident_id, actor)

    if incident.get("status") != "resolved":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A narrative report can only be written once the incident is resolved.",
        )

    now = datetime.now(timezone.utc).isoformat()
    actor_id = str(actor["id"])

    # The whole row, not just its status: when it is finalized, it is the
    # version that gets kept before it is changed (finding #8).
    existing = (
        db.table("incident_narrative_reports")
        .select("*")
        .eq("incident_id", incident_id)
        .maybe_single()
        .execute()
    )
    existing_row = existing.data if existing else None

    payload: dict = {
        "narrative": narrative,
        "reporting_person_name": reporting_person_name,
        "incident_occurred_at": incident_occurred_at,
        "place_of_incident": place_of_incident,
        "prepared_by_name": prepared_by_name,
        "investigator_name": investigator_name,
        "reference_no": reference_no,
        "updated_by": actor_id,
        "updated_at": now,
    }
    if details is not None:
        payload["details"] = _clean_details(details)
    if finalize:
        payload["status"] = "finalized"
        payload["finalized_at"] = now
        payload["finalized_by"] = actor_id

    def _write(body: dict):
        if existing_row:
            return (
                db.table("incident_narrative_reports")
                .update(body)
                .eq("id", existing_row["id"])
                .execute()
            )
        new_row = {**body, "incident_id": incident_id, "created_by": actor_id}
        # A brand-new row is 'draft' unless finalized in the same save —
        # the column default only applies when the key is omitted entirely.
        new_row.setdefault("status", "draft")
        return db.table("incident_narrative_reports").insert(new_row).execute()

    def _write_with_fallback() -> tuple[object, bool]:
        try:
            return _write(payload), details is not None
        except Exception as exc:
            if "details" not in payload or not _is_missing_details_column(exc):
                raise
            # Migration 040 has not been applied: keep everything the table can
            # hold and say plainly that the rest was not stored.
            _probe["ok"] = False
            _probe["checked_at"] = time.monotonic()
            payload.pop("details")
            log.warning("narrative_report.details_column_missing", incident_id=incident_id)
            return _write(payload), False

    amending = bool(existing_row and existing_row.get("status") == "finalized")
    if amending:
        changed = _changed_fields(existing_row, payload)
        if not changed:
            # Saving a finalized report with nothing different is not an edit:
            # no version, no reason asked for, nothing written.
            row = dict(existing_row)
            row["details_saved"] = details is not None
            row["details_supported"] = _details_supported(db)
            row["unchanged"] = True
            return row
        reason = (amendment_reason or "").strip()
        if len(reason) < 5:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="This report is finalized. Say why you are changing it (at least a few words); "
                       "the previous version is kept with your reason.",
            )
        with audit_service.action(
            actor=actor,
            action="narrative_report.amended",
            target_type="narrative_report",
            target_id=str(existing_row["id"]),
            target_label=existing_row.get("reference_no") or incident_id,
            new={"changed_fields": changed, "reason": reason[:300]},
        ):
            _keep_version(db, existing_row, changed=changed, reason=reason, actor=actor)
            result, details_saved = _write_with_fallback()
    elif finalize:
        with audit_service.action(
            actor=actor,
            action="narrative_report.finalized",
            target_type="narrative_report",
            target_id=str(existing_row["id"]) if existing_row else None,
            target_label=reference_no or incident_id,
            new={"incident_id": incident_id},
        ):
            result, details_saved = _write_with_fallback()
    else:
        result, details_saved = _write_with_fallback()

    row = dict((result.data or [payload])[0])
    row["details_saved"] = details_saved
    row["details_supported"] = _details_supported(db)
    log.info(
        "narrative_report.saved",
        incident_id=incident_id,
        actor_id=actor_id,
        finalized=finalize,
        was_new=existing_row is None,
        details_saved=details_saved,
    )
    return row


# Compared to decide whether a finalized report actually changed.
_VERSIONED_FIELDS = (
    "narrative", "reporting_person_name", "incident_occurred_at", "place_of_incident",
    "prepared_by_name", "investigator_name", "reference_no", "details",
)


def _same(a, b) -> bool:
    if isinstance(a, str) and isinstance(b, str) and ("T" in a or "T" in b):
        # Timestamps come back from Postgres with a zone and seconds the client
        # did not send: compare instants, not spellings.
        try:
            return datetime.fromisoformat(a.replace("Z", "+00:00")) == datetime.fromisoformat(b.replace("Z", "+00:00"))
        except ValueError:
            pass
    return (a or None) == (b or None)


def _changed_fields(existing: dict, payload: dict) -> list[str]:
    return [f for f in _VERSIONED_FIELDS if f in payload and not _same(existing.get(f), payload.get(f))]


def _keep_version(db: Client, existing: dict, *, changed: list[str], reason: str, actor: dict) -> None:
    """Store the finalized report as it was, before it is changed (finding #8).

    Refuses the edit when the history cannot be kept: a finalized report that
    could be overwritten without its previous version is exactly the gap.
    """
    try:
        count = (
            db.table("incident_narrative_report_versions")
            .select("id", count="exact")
            .eq("report_id", str(existing["id"]))
            .execute()
        )
        version_no = int(getattr(count, "count", None) or len(count.data or [])) + 1
        snapshot = {k: v for k, v in existing.items() if k not in ("created", "updated", "finalized")}
        db.table("incident_narrative_report_versions").insert({
            "report_id": str(existing["id"]),
            "incident_id": str(existing["incident_id"]),
            "version_no": version_no,
            "snapshot": snapshot,
            "changed_fields": changed,
            "change_reason": reason[:1000],
            "changed_by": str(actor.get("id")),
            "changed_by_name": actor.get("full_name"),
        }).execute()
    except Exception as exc:
        log.error("narrative_report.version_write_failed", report_id=existing.get("id"), exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="This finalized report was not changed: its previous version could not be saved. "
                   "If this keeps happening, migration 044 has not been applied yet.",
        ) from exc


def list_versions(incident_id: str, actor: dict) -> list[dict]:
    """Every kept version of an incident's narrative report, newest first."""
    db: Client = get_supabase()
    _load_incident_for_scope(db, incident_id, actor)
    try:
        res = (
            db.table("incident_narrative_report_versions")
            .select("id, version_no, snapshot, changed_fields, change_reason, changed_by, changed_by_name, changed_at")
            .eq("incident_id", incident_id)
            .order("version_no", desc=True)
            .execute()
        )
    except Exception:
        # Before migration 044 there is no history to show.
        return []
    return res.data or []


# =============================================================================
# The library — every report an agency has written
# =============================================================================

#: Ceiling on the rows read to build the tab counts. A province's narrative
#: reports are counted in hundreds; hitting this means something is wrong, not
#: that the counts should quietly be short.
_COUNT_ROWS_MAX = 5000


def list_narrative_reports(
    actor: dict,
    *,
    category: str | None = None,
    report_status: str | None = None,
    days: int = 0,
    date_from: str | None = None,
    date_to: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> dict:
    """Every narrative report the caller may see, newest first.

    `category` narrows to one kind of incident (the library's tabs). `report_status`
    is draft or finalized. Both are applied in the database, and the counts that
    label the tabs describe the OTHER filter's result — the category tabs count
    within the chosen status, the status chips within the chosen category — so a
    tab never promises reports it will not show.
    """
    if category and category not in CATEGORIES:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Unknown incident category.")
    if report_status and report_status not in ("draft", "finalized"):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Unknown report status.")

    from app.services.dispatch_service import _agency_ids_for_type, _date_window

    db: Client = get_supabase()
    role = actor.get("role")

    agency_ids: list[str] | None = None
    if role == "agency_admin":
        if not actor.get("agency_id"):
            return _empty_library()
    elif role == "provincial_admin":
        agency_ids = _agency_ids_for_type(db, actor.get("agency_type"))
        if not agency_ids:
            return _empty_library()

    since, until = _date_window(days, date_from, date_to)

    def _scoped(q):
        if role == "agency_admin":
            q = q.eq("incidents.assigned_agency_id", actor.get("agency_id"))
        elif agency_ids is not None:
            q = q.in_("incidents.assigned_agency_id", agency_ids)
        if since:
            q = q.gte("updated_at", since)
        if until:
            q = q.lt("updated_at", until)
        return q

    def _in_category(q, cat: str):
        return q.in_("incidents.incident_category", _OTHER_CATEGORIES) if cat == "other" \
            else q.eq("incidents.incident_category", cat)

    # The rows themselves.
    with_offense = _details_supported(db)
    columns = (
        "id, incident_id, status, reference_no, prepared_by_name, investigator_name, "
        "reporting_person_name, place_of_incident, finalized_at, created_at, updated_at, "
        + ("offense:details->>offense, " if with_offense else "")
        + "incidents!inner("
        "id, record_number, incident_category, severity, location_address, created_at, "
        "resolved_at, assigned_agency_id, "
        "stations(name, agencies(agency_type, municipality, name)), "
        "users!incidents_reporter_id_fkey(full_name))"
    )
    query = _scoped(db.table("incident_narrative_reports").select(columns, count="exact"))
    if report_status:
        query = query.eq("status", report_status)
    if category:
        query = _in_category(query, category)
    resp = query.order("updated_at", desc=True).range(offset, offset + limit - 1).execute()

    items = [_flatten(r) for r in (resp.data or [])]
    total = resp.count if resp.count is not None else len(items)

    # The tab counts: one light read of (status, category), tallied here.
    tally_query = _scoped(
        db.table("incident_narrative_reports")
        .select("status, incidents!inner(incident_category)")
    ).limit(_COUNT_ROWS_MAX)
    tally_rows = tally_query.execute().data or []

    by_category = {c: 0 for c in CATEGORIES}
    by_status = {"draft": 0, "finalized": 0}
    for r in tally_rows:
        cat = ((r.get("incidents") or {}).get("incident_category")) or "other"
        cat = "other" if cat in _OTHER_CATEGORIES else cat
        st = r.get("status")
        if (not category or cat == category) and st in by_status:
            by_status[st] += 1
        if (not report_status or st == report_status) and cat in by_category:
            by_category[cat] += 1

    return {
        "items": items,
        "total": total,
        "counts": {
            "by_category": by_category,
            "by_status": by_status,
            "all": sum(by_category.values()),
        },
    }


def _empty_library() -> dict:
    return {
        "items": [],
        "total": 0,
        "counts": {
            "by_category": {c: 0 for c in CATEGORIES},
            "by_status": {"draft": 0, "finalized": 0},
            "all": 0,
        },
    }


def _flatten(row: dict) -> dict:
    """One library row: the report's own facts plus the incident's, side by side."""
    inc = row.get("incidents") or {}
    station = inc.get("stations") or {}
    agency = station.get("agencies") or {}
    category = inc.get("incident_category") or "other"
    return {
        "id": row.get("id"),
        "incident_id": row.get("incident_id"),
        "status": row.get("status"),
        "reference_no": row.get("reference_no"),
        "prepared_by_name": row.get("prepared_by_name"),
        "investigator_name": row.get("investigator_name"),
        "reporting_person_name": row.get("reporting_person_name") or (inc.get("users") or {}).get("full_name"),
        "place_of_incident": row.get("place_of_incident") or inc.get("location_address"),
        "offense": row.get("offense"),
        "finalized_at": row.get("finalized_at"),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
        "record_number": inc.get("record_number"),
        "incident_category": "other" if category in _OTHER_CATEGORIES else category,
        "severity": inc.get("severity"),
        "incident_created_at": inc.get("created_at"),
        "resolved_at": inc.get("resolved_at"),
        "station_name": station.get("name"),
        "agency_type": agency.get("agency_type"),
        "agency_name": agency.get("name"),
        "municipality": agency.get("municipality"),
    }


# =============================================================================
# The document
# =============================================================================

def render_narrative_report_pdf(incident_id: str, actor: dict) -> bytes:
    """The document itself — see _build_pdf for the layout. 404s if nobody
    has written a report yet; there is nothing to print."""
    db: Client = get_supabase()
    incident, report = load_for_print(db, incident_id, actor)
    return _build_pdf(incident, report)


def load_for_print(db: Client, incident_id: str, actor: dict) -> tuple[dict, dict]:
    """(incident, report) for printing one narrative report, scope-checked.

    Shared by the single-report PDF above and the Reports & Export bundle
    (printable_reports.build_narrative_bundle), so both print exactly the
    same document from exactly the same data.
    """
    _load_incident_for_scope(db, incident_id, actor)

    # Pull the same incident context the dashboard's detail view already
    # shows, so the printed document is self-contained rather than only
    # readable next to a browser tab. Selected fresh (not reused from
    # _load_incident_for_scope's trimmed columns) because the PDF needs the
    # reporter/station/agency joins that scope-checking does not.
    inc_result = (
        db.table("incidents")
        .select(
            "id, record_number, report_text, incident_category, severity, created_at, "
            "accepted_at, dispatched_at, resolved_at, location_address, "
            "outcome, outcome_notes, casualties_injured, casualties_fatal, casualties_transported, "
            "stations(name, agencies(agency_type, name, municipality)), "
            "responder:users!incidents_assigned_responder_id_fkey(full_name), "
            "users!incidents_reporter_id_fkey(full_name, phone_number)"
        )
        .eq("id", incident_id)
        .single()
        .execute()
    )
    incident = inc_result.data or {}

    report_result = (
        db.table("incident_narrative_reports")
        .select("*")
        .eq("incident_id", incident_id)
        .maybe_single()
        .execute()
    )
    if report_result is None or not report_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No narrative report has been written for this incident yet.",
        )
    return incident, report_result.data


def _ph(value) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(PH_TZ)


def _stamp(value) -> str:
    """`2024-05-20 16:00` in Philippine time - the form's own way of writing it."""
    dt = _ph(value)
    return dt.strftime("%Y-%m-%d %H:%M") if dt else ""


def _person_age(dob: str, on: datetime | None) -> str:
    try:
        born = date.fromisoformat(dob[:10])
    except (ValueError, TypeError):
        return ""
    ref = (on or datetime.now(PH_TZ)).date()
    years = ref.year - born.year - ((ref.month, ref.day) < (born.month, born.day))
    return str(years) if years >= 0 else ""


def _build_pdf(incident: dict, report: dict) -> bytes:
    """One Incident Record Form as a PDF — see irf_flowables for the layout."""
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.units import inch
    from reportlab.platypus import SimpleDocTemplate

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=letter,
        topMargin=0.5 * inch, bottomMargin=0.55 * inch,
        leftMargin=0.5 * inch, rightMargin=0.5 * inch,
        title="Incident Record Form",
    )
    doc.build(irf_flowables(incident, report))
    return buf.getvalue()


def irf_flowables(incident: dict, report: dict) -> list:
    """The Incident Record Form, printed.

    Laid out the way the paper form is - boxed cells with the caption above the
    entry, grey bars for the four Items - because an agency files this document
    next to the paper ones and a reader who knows the form should not have to
    learn a new one. Items B and C repeat once per suspect and per victim.
    """
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import inch
    from reportlab.platypus import (
        CondPageBreak, KeepTogether, Paragraph, Spacer, Table, TableStyle,
    )
    from xml.sax.saxutils import escape

    from app.services.pdf_text import printable

    details = report.get("details") if isinstance(report.get("details"), dict) else {}
    station = incident.get("stations") or {}
    agency = station.get("agencies") or {}
    reporter = incident.get("users") or {}

    styles = getSampleStyleSheet()
    cap = ParagraphStyle("Cap", parent=styles["Normal"], fontName="Helvetica-Bold", fontSize=6.6, leading=8, textColor=colors.HexColor("#333333"))
    val = ParagraphStyle("Val", parent=styles["Normal"], fontName="Helvetica", fontSize=9, leading=11.5)
    small = ParagraphStyle("Small", parent=styles["Normal"], fontName="Helvetica", fontSize=7.4, leading=9.4)
    bar = ParagraphStyle("Bar", parent=styles["Normal"], fontName="Helvetica-Bold", fontSize=9.5, leading=12, alignment=TA_CENTER)
    title = ParagraphStyle("IrfTitle", parent=styles["Normal"], fontName="Helvetica-Bold", fontSize=13, leading=16, alignment=TA_CENTER)
    prose = ParagraphStyle("Prose", parent=styles["Normal"], fontName="Helvetica", fontSize=10, leading=14.5, alignment=4)
    foot = ParagraphStyle("Foot", parent=styles["Normal"], fontName="Helvetica", fontSize=7.4, leading=9.4, textColor=colors.HexColor("#888888"))

    def esc(x) -> str:
        return escape(printable(str(x))) if x not in (None, "") else ""

    def cell(caption: str, value="") -> list:
        """One boxed cell: caption above, entry below."""
        return [Paragraph(esc(caption).upper(), cap), Paragraph(esc(value) or "&nbsp;", val)]

    W = 7.5 * inch
    GREY = colors.HexColor("#D9D9D9")
    LINE = colors.HexColor("#444444")

    def grid(rows, widths, *, extra=()):
        t = Table(rows, colWidths=[w * inch for w in widths])
        t.setStyle(TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.6, LINE),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 4),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ("TOPPADDING", (0, 0), (-1, -1), 3),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            *extra,
        ]))
        return t

    def band(text: str):
        t = Table([[Paragraph(esc(text), bar)]], colWidths=[W])
        t.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), GREY),
            ("BOX", (0, 0), (-1, -1), 0.6, LINE),
            ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        return t

    reported_at = incident.get("created_at")
    occurred_at = report.get("incident_occurred_at") or reported_at
    place_barangay = details.get("place_barangay", "")
    place_town = details.get("place_town", "") or agency.get("municipality", "")
    place_province = details.get("place_province", "") or ("Biliran" if agency else "")
    place = report.get("place_of_incident") or incident.get("location_address") or ""
    place_line = ", ".join(p for p in (place_barangay, place_town, place_province) if p) or place

    category = incident.get("incident_category") or "other"
    type_line = details.get("offense") or CATEGORY_LABELS.get(category, "Incident")
    reporting_person = report.get("reporting_person_name") or reporter.get("full_name") or ""

    def person_rows(p: dict, *, relation_caption: str, on: datetime | None):
        age = p.get("age") or _person_age(p.get("date_of_birth", ""), on)
        return [
            [cell("Family Name", p.get("family_name")), cell("First Name", p.get("first_name")),
             cell("Middle Name", p.get("middle_name")), cell("Qualifier", p.get("qualifier")),
             cell("Nickname", p.get("nickname"))],
            [cell("Citizenship", p.get("citizenship")), cell("Gender", p.get("gender")),
             cell("Civil Status", p.get("civil_status")), cell("Date of Birth", p.get("date_of_birth")),
             cell("Age", age), cell("Place of Birth", p.get("place_of_birth")),
             cell("Phone Number", p.get("phone"))],
            [cell("Address (House Number/Street) Village/Sitio", p.get("address_street")),
             cell("Barangay", p.get("barangay")), cell("Town/City", p.get("town_city")),
             cell("Province", p.get("province"))],
            [cell("Highest Educational Attainment", p.get("education")),
             cell("Occupation", p.get("occupation")), cell(relation_caption, p.get("relation"))],
        ]

    occurred_dt = _ph(occurred_at)
    widths5 = [1.6, 1.6, 1.6, 1.35, 1.35]
    widths7 = [1.05, 0.8, 0.95, 1.05, 0.55, 1.6, 1.5]
    widths4 = [2.7, 1.6, 1.6, 1.6]
    widths3 = [2.8, 2.4, 2.3]

    def person_block(p: dict, *, relation_caption: str):
        rows = person_rows(p, relation_caption=relation_caption, on=occurred_dt)
        return [
            grid([rows[0]], widths5), grid([rows[1]], widths7),
            grid([rows[2]], widths4), grid([rows[3]], widths3),
        ]

    els: list = []

    # ── Header ────────────────────────────────────────────────────────────
    agency_line = " / ".join(p for p in (agency.get("agency_type"), agency.get("name")) if p)
    els.append(Paragraph("INCIDENT RECORD FORM", title))
    if agency_line:
        els.append(Paragraph(esc(agency_line), ParagraphStyle("Ag", parent=small, alignment=TA_CENTER, fontSize=8.5, leading=11)))
    els.append(Spacer(1, 5))
    els.append(grid([[
        cell("IRF Entry Number", report.get("reference_no") or ""),
        [Paragraph("TYPE OF INCIDENT", cap), Paragraph(esc(type_line), val),
         Paragraph(esc(details.get("offense_detail", "")), small)],
        cell("Copy for", details.get("copy_for") or "Complainant"),
    ]], [2.3, 3.6, 1.6]))
    els.append(grid([[Paragraph(
        "INSTRUCTIONS: Refer to the agency's standard operating procedure on recording of incidents "
        "in filling up this form. This Incident Record Form (IRF) may be reproduced, photocopied and/or "
        "downloaded.", small)]], [7.5]))
    els.append(grid([[
        cell("Date and Time Reported", _stamp(reported_at)),
        cell("Date and Time of Incident", _stamp(occurred_at)),
        cell("Place of Incident: Barangay, Town/City, Province", place_line),
    ]], [1.7, 1.9, 3.9]))

    # ── Item A ────────────────────────────────────────────────────────────
    reporting = dict(details.get("reporting_person") or {})
    if not (reporting.get("family_name") or reporting.get("first_name")) and reporting_person:
        reporting.setdefault("first_name", reporting_person)
    if not reporting.get("phone") and reporter.get("phone_number"):
        reporting["phone"] = reporter["phone_number"]
    els.append(KeepTogether([
        band('ITEM "A" - REPORTING PERSON'),
        *person_block(reporting, relation_caption="Relation to Suspect"),
    ]))

    # ── Item B — once per suspect ─────────────────────────────────────────
    suspects = details.get("suspects") or []
    item_b = band("ITEM \"B\" - SUSPECT'S DATA")
    if not suspects:
        els.append(KeepTogether([
            item_b, grid([[Paragraph("No suspect recorded for this incident.", val)]], [7.5]),
        ]))
    for n, sus in enumerate(suspects, start=1):
        # One suspect is one unit: a person's boxes are never split across pages,
        # and "For children in conflict with the law" stays with its own row.
        block = [item_b] if n == 1 else []
        if len(suspects) > 1:
            block.append(grid([[Paragraph(f"SUSPECT {n} OF {len(suspects)}", cap)]], [7.5]))
        block.extend(person_block(sus, relation_caption="Relation to Victim"))
        block.append(grid([[
            cell("Rank (AFP/PNP Personnel)", sus.get("rank")), cell("Unit Assignment", sus.get("unit_assignment")),
            cell("Group Affiliation", sus.get("group_affiliation")),
            cell("Prev. Criminal Record", sus.get("previous_record")),
            cell("Stat. of Prev. Case", sus.get("previous_case_status")),
        ]], [1.4, 1.5, 1.7, 1.5, 1.4]))
        block.append(grid([[
            cell("Height", sus.get("height")), cell("Weight", sus.get("weight")),
            cell("Color of Eyes", sus.get("eye_color")), cell("Color of Hair", sus.get("hair_color")),
            cell("Distinguishing Marks", sus.get("distinguishing_marks")),
            cell("Under the Influence", sus.get("under_influence")),
        ]], [0.8, 0.8, 1.1, 1.1, 2.0, 1.7]))
        block.append(band("FOR CHILDREN IN CONFLICT WITH THE LAW"))
        block.append(grid([[
            cell("Name of Guardian", sus.get("guardian_name")), cell("Guardian Address", sus.get("guardian_address")),
        ]], [3.75, 3.75]))
        els.append(KeepTogether(block))

    # ── Item C — once per victim ──────────────────────────────────────────
    victims = details.get("victims") or []
    item_c = band("ITEM \"C\" - VICTIM'S DATA")
    if not victims:
        els.append(KeepTogether([
            item_c, grid([[Paragraph("No victim recorded for this incident.", val)]], [7.5]),
        ]))
    for n, vic in enumerate(victims, start=1):
        block = [item_c] if n == 1 else []
        if len(victims) > 1:
            block.append(grid([[Paragraph(f"VICTIM {n} OF {len(victims)}", cap)]], [7.5]))
        block.extend(person_block(vic, relation_caption="Relation to Suspect"))
        els.append(KeepTogether(block))

    # ── Item D — the narrative ────────────────────────────────────────────
    # Item D starts a fresh page only when too little of this one is left to hold
    # its heading and the first lines of the narrative. It used to always start on
    # its own page, which left a nearly empty sheet whenever Items A to C ended
    # just past a page.
    els.append(CondPageBreak(3.2 * inch))
    els.append(KeepTogether([
        band('ITEM "D" - NARRATIVE OF INCIDENT'),
        grid([[
            cell("Date and Time Reported", _stamp(reported_at)),
            cell("Date and Time of Incident", _stamp(occurred_at)),
            cell("Place of Incident: Barangay, Town/City, Province", place_line),
        ]], [1.7, 1.9, 3.9]),
        grid([[Paragraph(
            "THE NARRATIVE OF THE INCIDENT OR EVENT, ANSWERING THE WHO, WHAT, WHEN, WHERE, WHY AND HOW OF REPORTING.",
            cap)]], [7.5]),
    ]))
    paragraphs = [p.strip() for p in (report.get("narrative") or "").split("\n\n") if p.strip()] or [""]
    prose_rows = [[Paragraph(esc(p).replace("\n", "<br/>") or "&nbsp;", prose)] for p in paragraphs]
    prose_table = Table(prose_rows, colWidths=[W])
    prose_table.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 0.6, LINE),
        ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    els.append(prose_table)

    # Additional information, only the boxes that were filled.
    extras = [
        ("Witnesses", details.get("witnesses")),
        ("Estimated damage / property involved", details.get("property_damage")),
        ("Actions taken", details.get("actions_taken")),
    ]
    extras = [(c, v) for c, v in extras if v]
    if extras:
        block = [band("ADDITIONAL INFORMATION")]
        for caption, value in extras:
            block.append(grid([[cell(caption, "")[0]], [Paragraph(esc(value).replace("\n", "<br/>"), val)]], [7.5]))
        els.append(KeepTogether(block))

    # ── The response, as Ziren recorded it ────────────────────────────────
    responder = (incident.get("responder") or {}).get("full_name")
    response = [
        band("RESPONSE RECORD (FROM THE ZIREN DISPATCH SYSTEM)"),
        grid([[
            cell("Record No.", incident.get("record_number")),
            cell("Station", station.get("name")),
            cell("Responder assigned", responder),
            cell("Severity", (incident.get("severity") or "").upper()),
        ]], [1.9, 2.1, 2.0, 1.5]),
        grid([[
            cell("Reported", _stamp(incident.get("created_at"))),
            cell("Dispatched", _stamp(incident.get("dispatched_at"))),
            cell("Accepted by crew", _stamp(incident.get("accepted_at"))),
            cell("Resolved", _stamp(incident.get("resolved_at"))),
        ]], [1.9, 1.9, 1.9, 1.8]),
    ]
    if incident.get("outcome") or incident.get("outcome_notes") or any(
        incident.get(k) for k in ("casualties_injured", "casualties_fatal", "casualties_transported")
    ):
        response.append(grid([[
            cell("Outcome", str(incident.get("outcome") or "").replace("_", " ")),
            cell("Injured", incident.get("casualties_injured") or 0),
            cell("Fatal", incident.get("casualties_fatal") or 0),
            cell("Transported", incident.get("casualties_transported") or 0),
        ]], [3.3, 1.4, 1.4, 1.4]))
        if incident.get("outcome_notes"):
            response.append(grid([[cell("Crew's outcome notes", incident.get("outcome_notes"))]], [7.5]))
    els.append(KeepTogether(response))

    # ── Certification and endorsement ─────────────────────────────────────
    cert = details.get("certification") or {}
    els.append(Spacer(1, 6))
    els.append(KeepTogether([
        grid([[
            Paragraph("I HEREBY CERTIFY TO THE CORRECTNESS OF THE FOREGOING TO THE BEST OF MY KNOWLEDGE AND BELIEF.", cap),
            cell("Name of Reporting Person", reporting_person or ""),
            cell("Signature of Reporting Person", ""),
        ]], [2.6, 2.6, 2.3], extra=[("BOTTOMPADDING", (0, 0), (-1, -1), 18)]),
        grid([[
            Paragraph("SUBSCRIBED AND SWORN TO BEFORE ME", cap),
            cell("Name of Administering Officer (Duty Officer)", cert.get("administering_officer")),
            cell("Signature of Administering Officer (Duty Officer)", ""),
        ]], [2.6, 2.6, 2.3], extra=[("BOTTOMPADDING", (0, 0), (-1, -1), 18)]),
        grid([[
            Paragraph("RANK, NAME AND DESIGNATION OF OFFICER (WHETHER HE/SHE IS THE DUTY INVESTIGATOR, "
                      "INVESTIGATOR ON CASE OR THE ASSISTING OFFICER)", cap),
            cell("Signature of Duty Investigator / Investigator on Case / Assisting Officer",
                 cert.get("investigator_rank_name") or report.get("investigator_name")),
        ]], [3.4, 4.1], extra=[("BOTTOMPADDING", (0, 0), (-1, -1), 18)]),
        grid([[
            Paragraph("INCIDENT RECORDED IN THE BLOTTER BY", cap),
            cell("Rank/Name of Desk Officer", cert.get("desk_officer_rank_name") or report.get("prepared_by_name")),
            cell("Signature of Desk Officer", ""),
            cell("Blotter Entry Nr.", report.get("reference_no")),
        ]], [1.9, 2.1, 1.9, 1.6], extra=[("BOTTOMPADDING", (0, 0), (-1, -1), 14)]),
    ]))

    # ── Where to follow up ────────────────────────────────────────────────
    st = details.get("station") or {}
    els.append(Spacer(1, 6))
    els.append(KeepTogether([
        Paragraph(
            "Keep the copy of this Incident Record Form (IRF). An update on the progress of the investigation "
            "of the incident that you reported will be given to you upon presentation of this IRF. For your "
            "reference, the data below is the contact details of this station.", small),
        Spacer(1, 3),
        grid([
            [cell("Name of Station", st.get("name") or station.get("name")), cell("Telephone", st.get("telephone"))],
            [cell("Investigator-on-Case", report.get("investigator_name")), cell("Mobile Phone", st.get("mobile"))],
            [cell("Name of Chief/Head of Office", st.get("chief")), cell("", "")],
        ], [4.6, 2.9]),
    ]))

    status_label = "FINALIZED" if report.get("status") == "finalized" else "DRAFT - subject to revision"
    els.append(Spacer(1, 8))
    els.append(Paragraph(
        f"Status: {status_label}  |  Record {esc(incident.get('record_number') or '')}  |  "
        f"Generated {datetime.now(PH_TZ).strftime('%Y-%m-%d %H:%M')} PHT by Ziren", foot))

    return els
