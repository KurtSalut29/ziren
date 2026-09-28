"""
Dispatch service — Agency Admin and Provincial Admin incident management.

Security contract:
  - All functions receive dispatcher_id from the authenticated token (never client).
  - Agency Admins can only see incidents assigned to their agency (query filter + RLS).
  - Provincial Admins can see incidents assigned to any agency of their own
    agency_type — every station of that type, province-wide (query filter + RLS).
  - Every dispatch action (assign, override, resolve, cancel) writes an immutable
    row to dispatch_log for full audit traceability.
  - Responder assignment validates that the Responder belongs to the same agency
    and has approved status + on_duty availability.
"""

import re
import structlog
from datetime import date, datetime, timedelta, timezone
from fastapi import HTTPException, status
from supabase import Client

from app.core.dependencies import assert_agency_scope
from app.db.supabase_client import get_supabase
from app.services import notification_service
from app.services import proximity
from app.services import responder_ack
from app.services import triage_service
from app.services.rubric_service import evaluate as rubric_evaluate

log = structlog.get_logger()

_SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, None: 4}


def _agency_ids_for_type(db: Client, agency_type: str | None) -> list[str]:
    """
    Two-step lookup: resolve a Provincial Admin's agency_type to the list of
    `agencies.id`s it covers, since incidents/dispatch_log/users all key off
    agency_id, not agency_type directly. Same pattern get_incident_history
    already uses for the `?agency_type=` query filter — reused here for the
    ROLE-based scope instead of a caller-supplied filter.

    Returns [] (not None) when agency_type is unset or matches no agency, so
    every call site can treat "no ids" as "scope resolves to nothing" without
    a separate None check.
    """
    if not agency_type:
        return []
    rows = db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
    return [row["id"] for row in rows]


# =============================================================================
# Queue
# =============================================================================

# Ceiling on a single queue fetch. Sized well above any plausible open-incident
# count for a province of Biliran's size, so hitting it means something is
# wrong (a seeding accident, a stuck resolver) rather than a busy day.
QUEUE_MAX = 500


def get_incident_activity(dispatcher: dict, *, days: int = 30) -> list[dict]:
    """
    Every incident created in the last [days], whatever its status.

    This is the counterpart to get_incident_queue, and the difference is the
    whole point: the queue deliberately excludes resolved and cancelled work
    because a dispatcher is looking at what still needs doing. That filter is
    correct for a queue and fatal for a chart.

    Anything counting incidents over time off the queue is survivorship-biased:
    an incident opened on Monday and resolved on Tuesday has vanished from it,
    so every past day is undercounted and the series always appears to climb
    toward today no matter what actually happened. The Overview's "Reports per
    day" was reading the queue and was therefore never reports per day -- it
    was still-open reports by day created.

    Rows are trimmed to what a chart needs. The three timestamps are the
    payload: created_at opens the incident, dispatched_at is when a human
    acted, resolved_at closes it, and the gaps between them are the only
    response-time evidence this system actually holds.

    incident_category rides along for the same reason. It is on the queue
    already, but counting categories off the queue answers "which kinds are
    open right now", not "which kinds does this province get" -- a fire
    resolved yesterday is gone from the queue and would vanish from the
    total. Note that `other` is not a sixth kind of emergency: it means the
    resident skipped the wizard's category step, and migration 019 also
    rewrote the retired hazmat/missing_person rows into it. Anything charting
    this must hold `other` apart from the five real categories.
    """
    db: Client = get_supabase()

    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()

    query = (
        db.table("incidents")
        .select(
            "id, status, severity, incident_category, "
            "created_at, dispatched_at, resolved_at, station_id, "
            "stations(name, agencies(agency_type))"
        )
        .gte("created_at", since)
        .order("created_at", desc=False)
        # A month of a province's incidents is small, but the cap keeps a
        # runaway seed or an import from turning a dashboard load into a
        # multi-megabyte response.
        .limit(2000)
    )

    role = dispatcher.get("role")
    if role == "agency_admin":
        agency_id = dispatcher.get("agency_id")
        if not agency_id:
            return []
        query = query.eq("assigned_agency_id", agency_id)
    elif role == "provincial_admin":
        agency_ids = _agency_ids_for_type(db, dispatcher.get("agency_type"))
        if not agency_ids:
            return []
        query = query.in_("assigned_agency_id", agency_ids)

    rows = query.execute().data or []

    for row in rows:
        stations = row.pop("stations", None) or {}
        agencies = (stations or {}).get("agencies") or {}
        row["agency_type"] = agencies.get("agency_type")
        # Which station took it — what the Provincial Admin's "Reports by
        # station" card groups by. Null when routing found no station.
        row["station_name"] = stations.get("name")

    return rows


# A single page of history. Deliberately smaller than QUEUE_MAX: the queue is
# bounded by how many incidents are open at once, while history grows without
# limit for the life of the deployment, so it is the one list that must be
# paged rather than capped.
HISTORY_PAGE_MAX = 100


_EMPTY_HISTORY_COUNTS = {
    "total": 0, "critical": 0, "resolved": 0, "cancelled": 0,
    "avg_response_minutes": None, "stations_with_incidents": 0,
}

# What a record number can contain: ZIR-2026-000123. The lookup builds a LIKE
# pattern from it, so anything outside this set — a `%` or `_` above all — would
# act as a wildcard and turn "find this record" into a scan of the table.
_RECORD_NO_RE = re.compile(r"^[A-Z0-9-]{1,24}$")


def _normalise_record_no(value: str | None) -> str | None:
    """Trim and uppercase a record-number lookup; refuse anything else."""
    if value is None:
        return None
    cleaned = value.strip().upper()
    if not cleaned:
        return None
    if not _RECORD_NO_RE.match(cleaned):
        raise ValueError("record_no may contain only letters, digits and hyphens.")
    return cleaned


def _parse_dt(value: str | None):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _date_window(
    days: int, date_from: str | None, date_to: str | None,
) -> tuple[str | None, str | None]:
    """
    Resolve the (since, until) bounds for a history query. `until` is
    EXCLUSIVE; `since` is inclusive; either may be None for an open end.

    An explicit day range wins over the rolling `days` window whenever either
    bound is given — an agency picking a specific date and getting quietly
    clamped back to "last 30 days" would make the date fields lie about what
    they had just searched.

    `date_from`/`date_to` are bare calendar dates from an <input type="date">,
    e.g. "2026-03-15". Comparing `date_to` directly with `.lte` would mean
    "created_at <= midnight of that day", which excludes every incident from
    that day itself after 00:00 — the one day an agency actually asked to see.
    The upper bound is midnight of the NEXT day instead, so a single date in
    both fields shows that whole day, and a month's first/last date shows that
    whole month.

    `days <= 0` means All time — the same sentinel Operational Area's own
    get_operational_area uses — and returns an open (None, None) window
    rather than "the last 0 days", which would match nothing.
    """
    if date_from or date_to:
        until = None
        if date_to:
            until = (date.fromisoformat(date_to) + timedelta(days=1)).isoformat()
        return date_from, until

    if days <= 0:
        return None, None

    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    return since, None


def get_incident_history(
    dispatcher: dict,
    *,
    days: int = 30,
    limit: int = HISTORY_PAGE_MAX,
    offset: int = 0,
    status: str | None = None,
    severity: str | None = None,
    agency_type: str | None = None,
    station_id: str | None = None,
    category: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    record_no: str | None = None,
) -> dict:
    """
    One page of every incident, whatever its status.

    This is the counterpart to get_incident_queue for the history view, and the
    difference from get_incident_activity matters: activity returns three
    timestamps and a category for CHARTS, trimmed to keep a dashboard load
    small. A history list has to render the report itself — its text, where it
    was, who filed it — so it carries the queue's full row shape.

    The Incident History page was reading /dispatch/queue, which excludes
    resolved and cancelled by design. A history view built on it could never
    show history: it listed only what was still open, under a heading promising
    the opposite, and its own resolved/cancelled filters could never match a
    single row.

    PAGED, NOT CAPPED. Every other list here takes a ceiling because it is
    naturally bounded. History is not: it is every report the province has ever
    filed, and a cap on it silently hides the past rather than the excess.
    `total` is the count BEFORE paging, so a caller can say "showing 100 of
    2,431" instead of leaving a reader to guess whether the list ended or ran
    out of room.

    Filtering is applied in the database, not after. Fetching a page and then
    filtering it client-side returns a page that is mostly empty whenever a
    filter is narrow, which reads as "no results" when it means "not on this
    page".

    `agency_type` filters to one of BFP/PNP/MDRRMO — the three-way distinction
    the whole console already colours by (see AG_COLOR in the dashboard's
    incident-vocabulary.ts), not a specific station. A province has several
    `agencies` rows per type (one per municipality), so this resolves the type
    to the matching agency ids first rather than filtering a joined column —
    PostgREST can filter an embedded resource, but this project has no existing
    use of that, and a two-step lookup over a small `agencies` table reads
    plainly next to the rest of this function's style.

    `station_id` narrows to one `stations` row directly — meaningful only for
    a Provincial Admin, whose `agency_type` scope already spans several
    stations (an Agency Admin has exactly one, so the dashboard never offers
    this filter to them). It composes safely with the role scoping below: a
    caller cannot widen their own scope by passing another agency's station
    id, since `assigned_agency_id` is still filtered to `agency_ids` first —
    a mismatched `station_id` just narrows an already-empty intersection to
    zero rows, not another agency's data.

    `record_no` finds a record by its number (a prefix match, so a partial
    number narrows). It takes over from the time window, exactly as an explicit
    date range does: a record filed last year must be findable by its number,
    and left under the default 30-day window it would come back as "no results"
    for a number that exists. It only narrows — the role scoping below still
    applies to it, so it cannot reach outside the caller's own agency.
    """
    db: Client = get_supabase()

    record_no = _normalise_record_no(record_no)
    since, until = (None, None) if record_no else _date_window(days, date_from, date_to)

    agency_ids: list[str] | None = None
    if agency_type:
        agency_ids = _agency_ids_for_type(db, agency_type)
        # No agency of this type exists — answer "nothing matched" rather than
        # dropping the filter and returning every agency's incidents instead.
        if not agency_ids:
            return {"items": [], "total": 0, "counts": _EMPTY_HISTORY_COUNTS}

    role = dispatcher.get("role")
    if role == "provincial_admin":
        # A Provincial Admin's own agency_type always wins — same rule as
        # agency_admin below, which ignores whatever the query string asked
        # for and is pinned to its own agency_id. Without this a Provincial
        # Admin could pass ?agency_type=<a different type> and read another
        # agency's history, since the `agency_type` param above is otherwise
        # just a caller-supplied filter with no role check of its own.
        own_ids = set(_agency_ids_for_type(db, dispatcher.get("agency_type")))
        if not own_ids:
            return {"items": [], "total": 0, "counts": _EMPTY_HISTORY_COUNTS}
        agency_ids = [a for a in agency_ids if a in own_ids] if agency_ids is not None else list(own_ids)
        if not agency_ids:
            return {"items": [], "total": 0, "counts": _EMPTY_HISTORY_COUNTS}

    # An Agency Admin with no agency fails closed — nothing, never everything.
    if role == "agency_admin" and not dispatcher.get("agency_id"):
        return {"items": [], "total": 0, "counts": _EMPTY_HISTORY_COUNTS}

    def _scoped(q):
        """Apply this request's window, filters and role scope to a query.

        The page, the three head counts, the response-time average and the
        station tally all describe the SAME set of incidents, so they all go
        through this one function. They used to repeat these nine lines each,
        which is how a filter added to one and forgotten in another would have
        made the summary line disagree with the table beneath it.
        """
        if since:
            q = q.gte("created_at", since)
        if until:
            q = q.lt("created_at", until)
        if status == "open":
            # Not a real status: "everything still being worked", i.e. neither
            # closed way. It is what a Provincial Admin's "Open now" means on
            # Incident Records, where the live queue is not theirs to open.
            q = q.not_.in_("status", ["resolved", "cancelled"])
        elif status:
            q = q.eq("status", status)
        if severity:
            q = q.eq("severity", severity)
        if category:
            q = q.eq("incident_category", category)
        if station_id:
            q = q.eq("station_id", station_id)
        if record_no:
            q = q.like("record_number", f"{record_no}%")
        if agency_ids is not None:
            q = q.in_("assigned_agency_id", agency_ids)
        if role == "agency_admin":
            q = q.eq("assigned_agency_id", dispatcher.get("agency_id"))
        return q

    query = (
        db.table("incidents")
        # count="exact" makes PostgREST return the unpaged total in the
        # Content-Range header, which is the only way to know how many rows the
        # filters actually matched without a second round trip.
        # NOT suggested_severity. It looks like a column — migration 002 even
        # declares one — but the live schema has no such field and the app does
        # not need it to: it is a Phase 5 RUBRIC SUGGESTION computed at read
        # time by _suggest_severity(), the same way get_incident_queue does it
        # below. Selecting it returns Postgres 42703 and a 500.
        .select(
            # No latitude/longitude here. They are fields of the REQUEST model
            # (IncidentCreate), not columns: the database keeps the point in one
            # `location` column, and asking for `latitude` returns Postgres
            # 42703 and a 500. Coordinates reach the record panel through the
            # detail endpoint, whose `*` select includes `location`.
            "id, record_number, report_text, status, severity, "
            "location_address, signals, "
            "incident_category, sos_flagged, "
            "nlp_review_needed, overlap_agencies, wizard_answers, "
            "media_urls, station_id, "
            "created_at, accepted_at, dispatched_at, resolved_at, "
            "assigned_responder_id, "
            # Migration 024: what the crew reported when they closed it. The
            # Incident Records table has an Outcome column and a casualty tally
            # that read exactly these fields; left out of this list they came
            # back absent, and both rendered blank on every row.
            "outcome, outcome_notes, casualties_injured, casualties_fatal, "
            "casualties_transported, "
            "stations(name, agencies(agency_type, municipality, name)), "
            # incidents has THREE foreign keys to users (reporter, responder,
            # reviewer), so a bare `users(...)` join is ambiguous and PostgREST
            # answers with an error. Each is named by its constraint, and the
            # responder gets an alias so the two don't collide in the row.
            "responder:users!incidents_assigned_responder_id_fkey(full_name), "
            "users!incidents_reporter_id_fkey("
            "  full_name, is_verified, sos_warning_count, created_at"
            ")",
            count="exact",
        )
        # Newest first, unlike the queue. A queue is worked oldest-first
        # because the longest wait is the most urgent; history is read
        # newest-first because the most recent report is the one being
        # looked up.
        .order("created_at", desc=True)
    )
    query = _scoped(query)

    # .range() is inclusive at both ends, so the last index is offset+limit-1.
    # Off by one here silently returns an extra row on every page.
    resp = query.range(offset, offset + limit - 1).execute()

    rows = resp.data or []

    # Same derivation the queue applies, so a row reads identically on both
    # pages. An untriaged incident carries the rubric's suggestion; a triaged
    # one carries what the dispatcher actually chose.
    for row in rows:
        if not row.get("severity"):
            row["suggested_severity"] = _suggest_severity(row)
        else:
            row["suggested_severity"] = row["severity"]
        row["media_count"] = len(row.pop("media_urls", None) or [])

    # Narrative Report status per row — one extra query, not N+1: a single
    # IN() over the page's own ids, same shape as every other per-page
    # enrichment above. Only resolved incidents can have one (migration 038),
    # but querying every id on the page is simpler than filtering first and
    # costs nothing extra — an empty result for the open rows is exactly
    # correct. None means "not started yet", the same as no row existing.
    row_ids = [r["id"] for r in rows]
    if row_ids:
        narrative_rows = (
            db.table("incident_narrative_reports")
            .select("incident_id, status")
            .in_("incident_id", row_ids)
            .execute()
            .data or []
        )
        narrative_by_incident = {r["incident_id"]: r["status"] for r in narrative_rows}
        for row in rows:
            row["narrative_report_status"] = narrative_by_incident.get(row["id"])

    # ── Window counts ────────────────────────────────────────
    #
    # Counted over the WHOLE filtered window, not the page that was just
    # fetched. The history page previously derived its figures from `rows`,
    # which is one page of at most a hundred — so on a window holding three
    # hundred incidents the tiles described an arbitrary third of them while
    # the header above said "Last 30 days". Labelling them "on this page"
    # made that honest without making it useful.
    #
    # SHAPE: {total, critical, resolved, cancelled, avg_response_minutes}.
    # This used to be {critical, high, untriaged, closed} — four numbers that
    # mixed two different dimensions of the same incident (its SEVERITY and
    # its STATUS) into one strip, so "Closed" silently double-counted rows
    # "Critical" and "High" had already counted. The five here are each a
    # single, disjoint fact: `total` is every incident in the window (the
    # denominator the other four sit against), `critical` is a severity,
    # `resolved`/`cancelled` are the two ways a status closes, and
    # `avg_response_minutes` is a duration — none of them overlap.
    #
    # `total` reuses resp.count rather than a sixth query — it is already the
    # unpaged count of this exact filtered query.
    #
    # `critical`/`resolved`/`cancelled` are HEAD requests: count="exact" puts
    # the number in the Content-Range header and `head=True` returns no rows
    # at all, so each is a count, not a page fetch.
    def _window_count(build) -> int:
        q = _scoped(db.table("incidents").select("id", count="exact", head=True))
        return build(q).execute().count or 0

    total = resp.count if resp.count is not None else len(rows)

    # avg_response_minutes: created_at -> dispatched_at, the same "time to
    # dispatch" the queue and history cards already show per row (see
    # dispatchLatency in incident-row.tsx) — NOT time to resolve. It needs the
    # actual timestamps, not just a count, so this is one real data fetch
    # rather than a HEAD request — narrowed to the two columns it needs and to
    # rows that have a dispatched_at at all, since undispatched incidents have
    # no response time to average in.
    response_query = _scoped(
        db.table("incidents")
        .select("created_at, dispatched_at")
        .not_.is_("dispatched_at", "null")
    )
    response_rows = response_query.execute().data or []

    response_minutes: list[float] = []
    for row in response_rows:
        created = _parse_dt(row.get("created_at"))
        dispatched = _parse_dt(row.get("dispatched_at"))
        if created and dispatched:
            response_minutes.append((dispatched - created).total_seconds() / 60)

    avg_response_minutes = (
        round(sum(response_minutes) / len(response_minutes), 1) if response_minutes else None
    )

    # Distinct stations represented in the window — only meaningful for a
    # Provincial Admin, whose scope spans several (an Agency Admin's is
    # always 0 or 1). Needs the actual station_id column, not a head count,
    # since a count can't tell two rows at the same station from two at
    # different ones — so this is one more real fetch, same reasoning as
    # response_query above, narrowed to the one column it needs.
    stations_query = _scoped(db.table("incidents").select("station_id"))
    stations_rows = stations_query.execute().data or []
    stations_with_incidents = len({r["station_id"] for r in stations_rows if r.get("station_id")})

    counts = {
        "total":                  total,
        "critical":               _window_count(lambda q: q.eq("severity", "critical")),
        "resolved":               _window_count(lambda q: q.eq("status", "resolved")),
        "cancelled":              _window_count(lambda q: q.eq("status", "cancelled")),
        "avg_response_minutes":   avg_response_minutes,
        "stations_with_incidents": stations_with_incidents,
    }

    return {
        "items": rows,
        "total": total,
        "counts": counts,
    }


def get_incident_queue(dispatcher: dict) -> list[dict]:
    """
    Return the live incident queue for the dispatcher.

    Agency Admin: incidents assigned to their agency only (agency-scoped).
    Provincial Admin: incidents assigned to any agency of their own
    agency_type — every station of that type, province-wide.

    Includes: received, processing, dispatched, en_route, arrived.
    Excludes: resolved, cancelled (use history).
    Ordered: critical first, then by created_at.
    """
    db: Client = get_supabase()

    query = (
        db.table("incidents")
        .select(
            "id, report_text, status, severity, location_address, "
            # `signals` carries severity_rule and severity_reason — the answer
            # to "why is this HIGH". The queue is where a dispatcher decides
            # what to look at first, so the justification has to travel with
            # the row, not wait for the detail view.
            "signals, "
            "incident_category, sos_flagged, nlp_review_needed, "
            "overlap_agencies, wizard_answers, landmark_note, victim_relationship, "
            # Raw storage paths only — never signed URLs here. The queue is a
            # lighter-trust surface than the detail view (get_incident_media
            # signs links behind the same agency-scope check this query
            # already applies), so this row reveals only that attachments
            # exist, collapsed to media_count below and never returned as-is.
            "media_urls, "
            "created_at, dispatched_at, assigned_responder_id, "
            # Migration 024. This is what turns "assigned" into "assigned
            # and nobody has answered for 90 seconds" on the board.
            "accepted_at, declined_at, declined_reason, decline_count, "
            "backup_of_incident_id, backup_reason, "
            # Agency Admin spec Section 3 (Verification) — whether an
            # agency_admin has looked at this report at all yet, separate
            # from the responder-dispatch machinery above.
            "review_status, rejection_reason, clarification_note, clarification_requested_at, "
            "stations(name, agencies(agency_type, municipality, name)), "
            "users!incidents_reporter_id_fkey("
            "  full_name, is_verified, sos_warning_count, created_at"
            ")"
        )
        .in_("status", ["received", "processing", "dispatched", "en_route", "arrived"])
        # NEWEST first here, oldest first in the response. The two are not in
        # conflict — this ordering exists only to decide WHICH rows survive the
        # cap, and the sort below decides what order they arrive in.
        #
        # An explicit cap, because the implicit one is worse. PostgREST applies
        # its own max-rows ceiling to an unbounded select and says nothing about
        # having done it, so a province with more open incidents than that
        # ceiling would have silently served a truncated queue that looked
        # complete.
        #
        # This used to read `desc=False`, which meant the rows the cap threw
        # away were the newest ones. On the day that matters — a typhoon, a
        # fire that spreads — that is the queue silently hiding the report that
        # came in thirty seconds ago while faithfully showing five hundred it
        # already knew about. Losing the OLDEST row instead is not good either,
        # but an incident that has been open for hours has been on this screen
        # for hours; a new one has never been seen at all. Either way the
        # client is told: a response of exactly QUEUE_MAX rows means
        # "there may be more".
        .order("created_at", desc=True)
        .limit(QUEUE_MAX)
    )

    # Agency Admin is scoped to their own agency; Provincial Admin to every
    # agency of their own agency_type.
    role = dispatcher.get("role")
    if role == "agency_admin":
        agency_id = dispatcher.get("agency_id")
        if not agency_id:
            return []
        query = query.eq("assigned_agency_id", agency_id)
    elif role == "provincial_admin":
        agency_ids = _agency_ids_for_type(db, dispatcher.get("agency_type"))
        if not agency_ids:
            return []
        query = query.in_("assigned_agency_id", agency_ids)

    result = query.execute()
    rows = result.data or []

    # Rubric evaluation FIRST, then sort. The order of these two matters and
    # was wrong: the sort ran against `severity`, which is NULL on every
    # incident no dispatcher has ranked yet — that is, on every incident still
    # awaiting a decision. So the rubric could call a brand-new report CRITICAL
    # and it would still sort below every already-dispatched `low`, because the
    # column the sort read had not been written. The rows most in need of
    # attention were the ones the ordering pushed furthest down.
    #
    # This is the Phase 5 integration: wizard answers → rubric → suggestion.
    for row in rows:
        row["suggested_severity"] = row.get("severity") or _suggest_severity(row)
        # Count only — the raw paths never leave this function. A dispatcher
        # scanning the board needs to know evidence exists before deciding
        # what to open next; they don't need a playable link until they've
        # already committed to that incident, which is what /queue/{id}/media
        # is for.
        row["media_count"] = len(row.pop("media_urls", None) or [])

    # Two keys, and both are the answer to a question a dispatcher asked.
    #
    #   1. Effective severity. A critical report outranks a low one whatever
    #      time either arrived — triage is not a queue discipline.
    #   2. Within a severity, OLDEST FIRST. First come, first served: whoever
    #      has been waiting longest at the same level of danger goes next.
    #      This is the rule the console states out loud in its band headers,
    #      and stating a rule the server does not follow is worse than not
    #      stating one.
    rows.sort(
        key=lambda r: (
            _SEVERITY_ORDER.get(r.get("suggested_severity"), 4),
            r.get("created_at") or "",
        )
    )

    # The acceptance verdict, from the same function the responder's own
    # queue uses. Computing it separately here is how a board that says
    # OVERDUE in red ends up sitting next to a phone still counting down.
    return responder_ack.annotate(rows)


# ── Incident attachments ────────────────────────────────────────

# incident-media is a PRIVATE bucket, so a stored path is not a URL anyone can
# open. Every playback needs a short-lived signed link minted for a dispatcher
# who has already passed the agency scope check below.
_MEDIA_BUCKET = "incident-media"

# Five minutes. Long enough to listen to a sixty-second report several times,
# short enough that a link pasted into a chat has expired by the time anyone
# else opens it.
_MEDIA_URL_TTL = 300

_AUDIO_EXT = (".m4a", ".aac", ".mp3", ".wav", ".ogg", ".opus")
_VIDEO_EXT = (".mp4", ".mov", ".3gp", ".webm")


def _media_kind(path: str) -> str:
    lowered = path.lower()
    if lowered.endswith(_AUDIO_EXT):
        return "audio"
    if lowered.endswith(_VIDEO_EXT):
        return "video"
    return "image"


def correct_transcript(
    incident_id: str, dispatcher: dict, *, corrected_text: str
) -> dict:
    """The dispatcher fixes what the recogniser misheard.

    The resident can already do this, on the screen that opens right after
    they report. But the person with a bad transcript is usually the person
    who was panicking, and they are the least likely to stand in front of a
    burning house proofreading it. So the correction cannot depend on them.

    The dispatcher is better placed for it than anyone: they are playing the
    recording anyway to check the address, they speak the language, and unlike
    the resident they have a minute. This gives them one field to fix it in.

    What it changes
    ---------------
    The report text, and the severity SUGGESTION derived from it — but only
    while the incident is still untriaged. Once a dispatcher has set a
    severity by hand, that is a human decision and re-running a classifier
    over it would quietly undo their judgement.

    Both halves are kept, as with the resident's correction: what the machine
    heard and what a person who could understand the audio says it was. That
    pair is labelled Waray emergency speech, which is the data whose absence
    made the transcript bad in the first place.
    """
    said = (corrected_text or "").strip()
    if not said:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A correction cannot be empty.",
        )

    db: Client = get_supabase()
    result = (
        db.table("incidents")
        .select("id, report_text, status, severity, signals, assigned_agency_id, "
                "incident_category, wizard_answers, overlap_agencies, landmark_note")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found."
        )

    row = result.data
    if dispatcher.get("role") in ("agency_admin", "provincial_admin"):
        assert_agency_scope(dispatcher, str(row.get("assigned_agency_id") or ""))

    signals = dict(row.get("signals") or {})
    transcript = dict(signals.get("transcript") or {})
    heard = transcript.get("text")

    update: dict = {"report_text": said}

    # Only while no human has ruled on it. A dispatcher-set severity is a
    # decision, not a guess to be recomputed.
    if not row.get("severity"):
        from app.models.incident import IncidentCategory

        category = None
        if row.get("incident_category"):
            try:
                category = IncidentCategory(row["incident_category"])
            except ValueError:
                category = None

        triaged = triage_service.triage(
            report_text=said,
            incident_category=category,
            wizard_answers=row.get("wizard_answers"),
            overlap_agencies=row.get("overlap_agencies"),
            landmark_note=row.get("landmark_note"),
        )
        if triaged is not None:
            signals = dict(triaged["signals"])
            if triaged["severity"] is not None:
                update["severity"] = triaged["severity"].value

    transcript.update({
        "text": heard,
        "corrected_to": said,
        "corrected_by": "dispatcher",
        "confirmed_by_reporter": transcript.get("confirmed_by_reporter", False),
        "note": (
            "Corrected by a dispatcher who listened to the recording. Their "
            "wording is authoritative; `text` is what the recogniser produced."
        ),
    })
    signals["transcript"] = transcript
    update["signals"] = signals

    db.table("incidents").update(update).eq("id", incident_id).execute()
    log.info(
        "dispatch.transcript_corrected",
        incident_id=incident_id,
        dispatcher_id=dispatcher.get("id"),
        severity=update.get("severity"),
    )
    return {**row, **update}


def get_incident_media(incident_id: str, dispatcher: dict) -> list[dict]:
    """Signed, short-lived links to an incident's attachments.

    The voice note is the reason this exists. A recording of the resident
    saying what happened is the one artefact that survives transcription being
    wrong — a dispatcher who speaks Waray hears exactly what was said — so it
    has to be playable from the dashboard, not merely stored.
    """
    db: Client = get_supabase()

    result = (
        db.table("incidents")
        .select("id, media_urls, assigned_agency_id")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found."
        )

    row = result.data
    # Same scope rule as the detail view. Attachments are more sensitive than
    # the text, not less: a voice recording identifies the person who made it.
    if dispatcher.get("role") in ("agency_admin", "provincial_admin"):
        assert_agency_scope(dispatcher, str(row.get("assigned_agency_id") or ""))

    items: list[dict] = []
    for path in row.get("media_urls") or []:
        if not path:
            continue
        try:
            signed = db.storage.from_(_MEDIA_BUCKET).create_signed_url(
                path, _MEDIA_URL_TTL
            )
            url = signed.get("signedURL") or signed.get("signedUrl")
        except Exception:
            # One unreadable object must not take the whole incident down with
            # it. The dispatcher still gets the report and the other
            # attachments, and a null url renders as "unavailable".
            log.warning("dispatch.media_sign_failed", incident_id=incident_id, path=path)
            url = None
        items.append({"path": path, "url": url, "kind": _media_kind(path)})

    return items


def get_incident_detail_admin(incident_id: str, dispatcher: dict) -> dict:
    """
    Full incident detail for the dispatcher view.
    Agency Admins can only view incidents assigned to their agency.
    Provincial Admins can view any incident assigned to their own agency_type.
    """
    db: Client = get_supabase()

    result = (
        db.table("incidents")
        .select(
            "*, "
            "stations(name, address, location, agencies(agency_type, municipality, name, contact_number)), "
            # The crew member's name, for the record panel. Named by
            # constraint and aliased for the same reason as in
            # get_incident_history: incidents has three foreign keys to users.
            "responder:users!incidents_assigned_responder_id_fkey(full_name, badge_id), "
            "users!incidents_reporter_id_fkey("
            "  id, full_name, phone_number, is_verified, sos_warning_count, "
            "  sos_suspended_until, created_at, "
            "  emergency_contact_name, emergency_contact_number"
            ")"
        )
        .eq("id", incident_id)
        .single()
        .execute()
    )

    if not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    row = result.data

    # Agency Admin scope check
    if dispatcher.get("role") == "agency_admin":
        if str(row.get("assigned_agency_id")) != str(dispatcher.get("agency_id")):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only view incidents assigned to your agency.",
            )
    elif dispatcher.get("role") == "provincial_admin":
        # The agency_type is already on this row via the stations->agencies
        # join above — reading it off `row` avoids a second DB round trip
        # that assert_agency_scope's generic version would otherwise need.
        incident_agency_type = ((row.get("stations") or {}).get("agencies") or {}).get("agency_type")
        if incident_agency_type != dispatcher.get("agency_type"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only view incidents assigned to your own agency type.",
            )

    # Attach severity suggestion from rubric
    if not row.get("severity"):
        row["suggested_severity"] = _suggest_severity(row)
    else:
        row["suggested_severity"] = row["severity"]

    # Attach dispatch log for this incident
    log_result = (
        db.table("dispatch_log")
        .select("*, users!dispatch_log_dispatcher_id_fkey(full_name, role)")
        .eq("incident_id", incident_id)
        .order("created_at", desc=True)
        .execute()
    )
    row["dispatch_log"] = log_result.data or []

    # Attach available responders for assignment (same agency, approved, on_duty)
    agency_id = row.get("assigned_agency_id")
    if agency_id:
        responders_result = (
            db.table("users")
            .select("id, full_name, badge_id, availability")
            .eq("role", "responder")
            .eq("agency_id", agency_id)
            .eq("approval_status", "approved")
            .execute()
        )
        row["available_responders"] = [
            r for r in (responders_result.data or [])
            if r.get("availability") == "on_duty"
        ]
    else:
        row["available_responders"] = []

    # How far the report is from the station it was routed to (ellipsoidal
    # distance, the same one that chose the station), and who is near the incident
    # right now - best fit first, with each responder's state and what they are
    # already committed to. The roster above says WHO is on duty; this says who is
    # actually close and who is already busy, which is what a dispatcher chooses by.
    # Best effort: a failure here must never stop the detail loading.
    row["station_distance_km"] = proximity.station_distance_km(row)
    row["nearby"] = None
    if agency_id:
        try:
            nearby = proximity.nearby_for_admin(db, row)
            row["nearby"] = nearby
            order = {r["responder_id"]: i for i, r in enumerate(nearby["responders"])}
            by_id = {r["responder_id"]: r for r in nearby["responders"]}
            enriched = []
            for r in row["available_responders"]:
                n = by_id.get(str(r["id"]))
                if n:
                    r = {
                        **r,
                        "state": n["state"], "distance_km": n["distance_km"], "eta_min": n["eta_min"],
                        "direction": n["direction"], "located": n["located"], "level": n["level"],
                        "reason": n["reason"], "current_calls": n["current_calls"],
                        "notified_at": n["notified_at"], "answer": n["answer"],
                        "answered_at": n["answered_at"],
                    }
                enriched.append(r)
            enriched.sort(key=lambda r: order.get(str(r["id"]), len(order)))
            row["available_responders"] = enriched
        except Exception:
            log.warning("dispatch.nearby_enrich_failed", incident_id=incident_id, exc_info=True)

    # Self-assign option for the dispatching Agency Admin. Not a real
    # Responder row (role stays a single, DB-constrained column — see
    # assign_responder's matching carve-out for why this can never be a
    # relaxed version of the query above), so it never entered that query
    # and is appended here instead. Kept out of get_available_responders'
    # general roster on purpose: that list is the actual on-duty roster
    # page, and it must not describe an admin who cannot patrol, ping a
    # location or answer a status change as if they were a Responder.
    # Excluded for Provincial Admin — they dispatch for no single agency (see
    # the identical !canDispatch gate on the dashboard's own dispatch console).
    if dispatcher.get("role") == "agency_admin":
        row["available_responders"].append({
            "id": dispatcher["id"],
            "full_name": f"{dispatcher.get('full_name') or 'You'} (yourself)",
            "badge_id": dispatcher.get("badge_id"),
            "availability": "on_duty",
        })

    return row


def get_nearby_responders(incident_id: str, dispatcher: dict) -> dict:
    """Who is near this incident, best fit first - the live panel's read.

    Same scoping as the detail view: an Agency Admin sees only their agency's
    incidents, a Provincial Admin only those of their own agency_type. The ranking
    itself is proximity.nearby_for_admin, the one function that also decides who
    a responder's phone is told about, so the panel can never disagree with what
    the responders actually received.
    """
    db: Client = get_supabase()
    result = (
        db.table("incidents")
        .select(
            "id, severity, status, assigned_agency_id, assigned_responder_id, location, "
            "stations(agencies(agency_type))"
        )
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )
    row = result.data if result is not None else None
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    if dispatcher.get("role") == "agency_admin":
        if str(row.get("assigned_agency_id")) != str(dispatcher.get("agency_id")):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only view incidents assigned to your agency.",
            )
    elif dispatcher.get("role") == "provincial_admin":
        incident_agency_type = ((row.get("stations") or {}).get("agencies") or {}).get("agency_type")
        if incident_agency_type != dispatcher.get("agency_type"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only view incidents assigned to your own agency type.",
            )

    return proximity.nearby_for_admin(db, row)


# =============================================================================
# Dispatch actions
# =============================================================================

def assign_responder(
    incident_id: str,
    responder_id: str,
    chosen_severity: str,
    suggested_severity: str | None,
    override_reason: str | None,
    notes: str | None,
    dispatcher: dict,
) -> dict:
    """
    Assign a Responder to an incident and record the dispatch action.

    Validates:
    - Incident belongs to dispatcher's agency (Agency Admin only)
    - Responder belongs to the same agency, is approved, and is on_duty
    - chosen_severity is a valid SeverityLevel

    Writes an immutable row to dispatch_log.
    Updates incident status → 'dispatched', sets dispatched_at and assigned_responder_id.
    """
    db: Client = get_supabase()
    dispatcher_id = str(dispatcher["id"])
    agency_id = str(dispatcher.get("agency_id") or "")

    # Load incident
    inc_result = (
        db.table("incidents")
        .select("id, status, assigned_agency_id, assigned_responder_id, review_status, reporter_id")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not inc_result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    incident = inc_result.data

    # Agency Admin scope check
    if dispatcher.get("role") == "agency_admin":
        if str(incident.get("assigned_agency_id")) != agency_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only dispatch incidents assigned to your agency.",
            )

    # Validate incident is in a dispatchable state
    if incident["status"] not in ("received", "processing"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Incident is already '{incident['status']}' — cannot re-dispatch.",
        )

    # Validate responder
    resp_result = (
        db.table("users")
        .select("id, full_name, agency_id, approval_status, availability, role")
        .eq("id", responder_id)
        .single()
        .execute()
    )
    if not resp_result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Responder not found.")

    resp = resp_result.data

    # An Agency Admin dispatching an incident to THEMSELVES, not a
    # Responder. role stays one hard-constrained column doing double duty
    # across this whole app (see require_approved_responder and the mobile
    # app's own login routing, both of which send agency_admin accounts
    # away from every responder screen) — an admin's account has no
    # approval_status/availability worth checking and never will, and this
    # is record-keeping, not a real field assignment: they resolve the
    # incident from this same dashboard afterward (see resolve_incident),
    # never through the mobile accept/en-route/arrived flow those two
    # fields exist for. Same-agency is true by construction here (it is
    # their own account), so that check is skipped too, not just relaxed.
    is_self_assign = (
        str(responder_id) == dispatcher_id and dispatcher.get("role") == "agency_admin"
    )

    if not is_self_assign:
        if resp.get("role") != "responder":
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail="Selected user is not a Responder.")
        if resp.get("approval_status") != "approved":
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail="Responder account is not approved.")
        if resp.get("availability") != "on_duty":
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail="Responder is currently off-duty.")

        # For Agency Admin, validate responder belongs to same agency
        if dispatcher.get("role") == "agency_admin":
            if str(resp.get("agency_id")) != agency_id:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Responder does not belong to your agency.",
                )

    was_override = suggested_severity is not None and chosen_severity != suggested_severity

    # Write dispatch_log row (immutable audit trail)
    _write_dispatch_log(
        db=db,
        incident_id=incident_id,
        dispatcher_id=dispatcher_id,
        agency_id=str(incident.get("assigned_agency_id") or agency_id),
        suggested_severity=suggested_severity,
        chosen_severity=chosen_severity,
        suggested_agency_id=None,
        chosen_agency_id=str(incident.get("assigned_agency_id") or agency_id),
        was_override=was_override,
        override_reason=override_reason if was_override else None,
        action="dispatched",
        notes=notes,
    )

    # Update incident
    now = datetime.now(timezone.utc).isoformat()
    update_payload = {
        "status": "dispatched",
        "severity": chosen_severity,
        "assigned_responder_id": responder_id,
        "dispatched_at": now,
        # A fresh assignment starts a fresh acceptance clock. Without
        # this, an incident a previous crew declined would arrive on the
        # new responder's phone already marked DECLINED, and the board
        # would keep showing the old refusal next to the new assignment.
        #
        # decline_count is untouched on purpose — it counts the incident's
        # whole history. Three refusals is a coverage problem, and it has
        # to survive the fourth assignment to be visible as one.
        "accepted_at": None,
        "declined_at": None,
        "declined_reason": None,
    }
    # Assigning a still-pending report is itself a Verification decision — a
    # dispatcher who assigns a responder has necessarily judged the report
    # real, whether or not they clicked a separate Accept button first. This
    # is what keeps review_status accurate without FORCING an extra click
    # before every dispatch (see dispatch_service.accept_report's docstring
    # for the explicit path, still available for triaging before assigning).
    if incident.get("review_status") in (None, "pending"):
        update_payload["review_status"] = "accepted"
        update_payload["reviewed_at"] = now
        update_payload["reviewed_by"] = dispatcher_id
    db.table("incidents").update(update_payload).eq("id", incident_id).execute()

    # The resident is told the moment help is sent, in those words. `at` is the
    # dispatch time the row itself carries (`dispatched_at`), which is what lets
    # the phone recognise this and the live update as one event.
    _tell_reporter(
        incident,
        type_="incident.dispatched",
        title="A responder is on the way",
        body="A responder has been assigned to your report.",
        at=now,
    )

    log.info(
        "dispatch.assigned",
        incident_id=incident_id,
        responder_id=responder_id,
        dispatcher_id=dispatcher_id,
        chosen_severity=chosen_severity,
        was_override=was_override,
    )

    return {
        "incident_id": incident_id,
        "responder_id": responder_id,
        "chosen_severity": chosen_severity,
        "was_override": was_override,
        "status": "dispatched",
        "dispatched_at": now,
    }


def override_severity(
    incident_id: str,
    chosen_severity: str,
    suggested_severity: str | None,
    override_reason: str,
    notes: str | None,
    dispatcher: dict,
) -> dict:
    """
    Override the severity of an incident without (re)assigning a Responder.
    Used when the dispatcher wants to escalate/de-escalate before full dispatch,
    or after dispatch to correct a rubric mis-classification.

    Every override writes to dispatch_log with was_override=True.
    override_reason is required for overrides.
    """
    db: Client = get_supabase()
    dispatcher_id = str(dispatcher["id"])

    if not override_reason or not override_reason.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="override_reason is required when overriding severity.",
        )

    # Load incident
    inc_result = (
        db.table("incidents")
        .select("id, status, severity, assigned_agency_id")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not inc_result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    incident = inc_result.data

    if dispatcher.get("role") == "agency_admin":
        if str(incident.get("assigned_agency_id")) != str(dispatcher.get("agency_id") or ""):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only modify incidents assigned to your agency.",
            )

    agency_id = str(incident.get("assigned_agency_id") or dispatcher.get("agency_id") or "")

    _write_dispatch_log(
        db=db,
        incident_id=incident_id,
        dispatcher_id=dispatcher_id,
        agency_id=agency_id,
        suggested_severity=suggested_severity or incident.get("severity"),
        chosen_severity=chosen_severity,
        suggested_agency_id=None,
        chosen_agency_id=agency_id,
        was_override=True,
        override_reason=override_reason.strip(),
        action="dispatched",  # re-logged as a dispatch action with override
        notes=notes,
    )

    db.table("incidents").update({"severity": chosen_severity}).eq("id", incident_id).execute()

    log.info(
        "dispatch.severity_overridden",
        incident_id=incident_id,
        dispatcher_id=dispatcher_id,
        from_severity=suggested_severity,
        to_severity=chosen_severity,
        reason=override_reason,
    )

    return {
        "incident_id": incident_id,
        "chosen_severity": chosen_severity,
        "was_override": True,
    }


def _load_for_review(db: Client, incident_id: str, dispatcher: dict) -> dict:
    """Shared load + scope check for accept/reject/request_clarification."""
    result = (
        db.table("incidents")
        .select("id, status, review_status, assigned_agency_id, reporter_id")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    incident = result.data
    if dispatcher.get("role") == "agency_admin":
        if str(incident.get("assigned_agency_id")) != str(dispatcher.get("agency_id") or ""):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only review incidents assigned to your agency.",
            )
    return incident


def _tell_reporter(
    incident: dict, *, type_: str, title: str, body: str, at: str, important: bool = True,
) -> None:
    """Put a decision about a report in front of the resident who filed it.

    Rejecting a report sets status to 'cancelled' and asking for clarification
    changes no status at all, so neither one moved anything the resident's app
    was watching - the rejection surfaced as a bare "Cancelled" and the
    question never surfaced. A notifications row gives both a persistent,
    readable home in the bell, and the incident row itself (which the app
    reads) carries the reason.

    Never raises: a failed notification must not undo a decision the agency has
    already made.
    """
    reporter_id = incident.get("reporter_id")
    if not reporter_id:
        return
    try:
        notification_service.create_for_user(
            str(reporter_id),
            type_=type_,
            title=title,
            body=body[:240],
            link="/my-reports",
            is_important=important,
            # `at` is the timestamp written to the incident row for this same
            # decision. The app keys a notification on (incident, kind, at), so
            # the copy that arrives over realtime and this stored copy are
            # recognised as one event instead of being shown twice.
            metadata={"incident_id": str(incident.get("id")), "at": at},
        )
    except Exception:
        log.error("dispatch.reporter_notify_failed", incident_id=incident.get("id"), exc_info=True)


def _post_to_thread(db: Client, incident_id: str, author: dict, body: str) -> None:
    """Add a message the agency sent to the incident's own thread.

    Best-effort, like _tell_reporter: the decision it accompanies (a question
    put to the resident) has already been made and recorded, and a thread that
    could not be written to must not undo it.
    """
    try:
        db.table("incident_notes").insert({
            "incident_id": incident_id,
            "author_id": str(author["id"]),
            "author_role": author.get("role"),
            "body": body,
        }).execute()
    except Exception:
        log.error("dispatch.thread_post_failed", incident_id=incident_id, exc_info=True)


def accept_report(incident_id: str, dispatcher: dict) -> dict:
    """
    Verification step (Agency Admin spec Section 3): the agency confirms this
    report is real, before anyone is assigned to it.

    Deliberately does not touch `status` — see migration 029's header for why
    'received' keeps its existing meaning. Idempotent the same way responder
    acceptance is: pressing it twice on an already-accepted report returns the
    existing decision rather than erroring or overwriting reviewed_at.
    """
    db: Client = get_supabase()
    incident = _load_for_review(db, incident_id, dispatcher)

    if incident.get("review_status") == "accepted":
        return {"incident_id": incident_id, "review_status": "accepted", "already_reviewed": True}
    if incident.get("review_status") == "rejected":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="This report was already rejected — it cannot also be accepted.",
        )

    now = datetime.now(timezone.utc).isoformat()
    db.table("incidents").update({
        "review_status": "accepted",
        "reviewed_at": now,
        "reviewed_by": str(dispatcher["id"]),
    }).eq("id", incident_id).execute()

    _write_dispatch_log(
        db=db, incident_id=incident_id, dispatcher_id=str(dispatcher["id"]),
        agency_id=str(incident.get("assigned_agency_id") or dispatcher.get("agency_id") or ""),
        suggested_severity=None, chosen_severity=None,
        suggested_agency_id=None, chosen_agency_id=str(incident.get("assigned_agency_id") or ""),
        was_override=False, override_reason=None, action="accepted", notes=None,
    )

    _tell_reporter(
        incident,
        type_="incident.accepted",
        title="Your report was accepted",
        body="The agency confirmed your report is real and is preparing a response.",
        at=now,
        important=False,
    )

    log.info("dispatch.report_accepted", incident_id=incident_id, dispatcher_id=str(dispatcher["id"]))
    return {"incident_id": incident_id, "review_status": "accepted", "already_reviewed": False}


def reject_report(incident_id: str, reason: str, dispatcher: dict) -> dict:
    """
    Verification step: the agency has looked at this report and it is not a
    real (or not their) incident. Also cancels the incident — a rejected
    report has nothing left to dispatch, and 'cancelled' is the status every
    existing queue/history filter already knows means "stop showing this".
    """
    if not reason or not reason.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A reason is required to reject a report.",
        )

    db: Client = get_supabase()
    incident = _load_for_review(db, incident_id, dispatcher)

    if incident.get("review_status") in ("accepted", "rejected"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"This report was already {incident['review_status']} — it cannot be rejected now.",
        )
    if incident["status"] in ("resolved", "cancelled"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Incident is already '{incident['status']}' — nothing left to reject.",
        )

    now = datetime.now(timezone.utc).isoformat()
    db.table("incidents").update({
        "review_status": "rejected",
        "reviewed_at": now,
        "reviewed_by": str(dispatcher["id"]),
        "rejection_reason": reason.strip(),
        "status": "cancelled",
    }).eq("id", incident_id).execute()

    _write_dispatch_log(
        db=db, incident_id=incident_id, dispatcher_id=str(dispatcher["id"]),
        agency_id=str(incident.get("assigned_agency_id") or dispatcher.get("agency_id") or ""),
        suggested_severity=None, chosen_severity=None,
        suggested_agency_id=None, chosen_agency_id=str(incident.get("assigned_agency_id") or ""),
        was_override=False, override_reason=reason.strip(), action="rejected", notes=reason.strip(),
    )

    _tell_reporter(
        incident,
        type_="incident.rejected",
        title="Your report was not accepted",
        body=f"Reason: {reason.strip()}",
        at=now,
    )

    log.info("dispatch.report_rejected", incident_id=incident_id, dispatcher_id=str(dispatcher["id"]), reason=reason)
    return {"incident_id": incident_id, "review_status": "rejected", "status": "cancelled"}


def request_clarification(incident_id: str, note: str, dispatcher: dict) -> dict:
    """
    Verification step: the agency needs more detail before deciding. Leaves
    `status` untouched — the report stays in the live queue, since nothing
    has actually been decided about it yet.

    The resident's app shows the note on the report and in the bell, and the
    resident answers on the incident's own thread - see incident_notes_service,
    which puts the report back in the review queue when the answer arrives.
    """
    if not note or not note.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A note is required to request clarification.",
        )

    db: Client = get_supabase()
    incident = _load_for_review(db, incident_id, dispatcher)

    if incident.get("review_status") in ("accepted", "rejected"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"This report was already {incident['review_status']} — clarification can no longer be requested.",
        )

    now = datetime.now(timezone.utc).isoformat()
    db.table("incidents").update({
        "review_status": "clarification_requested",
        "clarification_note": note.strip(),
        "clarification_requested_at": now,
    }).eq("id", incident_id).execute()

    _write_dispatch_log(
        db=db, incident_id=incident_id, dispatcher_id=str(dispatcher["id"]),
        agency_id=str(incident.get("assigned_agency_id") or dispatcher.get("agency_id") or ""),
        suggested_severity=None, chosen_severity=None,
        suggested_agency_id=None, chosen_agency_id=str(incident.get("assigned_agency_id") or ""),
        was_override=False, override_reason=None, action="clarification_requested", notes=note.strip(),
    )

    # The question is also a message in the incident's thread. It used to live
    # only on the incident row, which holds one question at a time: a second
    # question overwrote the first, and the chat window showed the agency's own
    # message nowhere. In the thread it stays, in order, between the answers.
    _post_to_thread(db, incident_id, dispatcher, note.strip())

    _tell_reporter(
        incident,
        type_="incident.clarification_requested",
        title="The agency needs more information",
        body=note.strip(),
        at=now,
    )

    log.info("dispatch.clarification_requested", incident_id=incident_id, dispatcher_id=str(dispatcher["id"]))
    return {"incident_id": incident_id, "review_status": "clarification_requested"}


def resolve_incident(
    incident_id: str,
    notes: str | None,
    dispatcher: dict,
) -> dict:
    """Mark a dispatched incident as resolved."""
    db: Client = get_supabase()
    dispatcher_id = str(dispatcher["id"])
    now = datetime.now(timezone.utc).isoformat()

    inc_result = (
        db.table("incidents")
        .select("id, status, severity, assigned_agency_id, reporter_id")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not inc_result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    incident = inc_result.data

    if dispatcher.get("role") == "agency_admin":
        if str(incident.get("assigned_agency_id")) != str(dispatcher.get("agency_id") or ""):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="You can only resolve incidents assigned to your agency.")

    agency_id = str(incident.get("assigned_agency_id") or dispatcher.get("agency_id") or "")

    _write_dispatch_log(
        db=db,
        incident_id=incident_id,
        dispatcher_id=dispatcher_id,
        agency_id=agency_id,
        suggested_severity=incident.get("severity"),
        chosen_severity=incident.get("severity") or "low",
        suggested_agency_id=None,
        chosen_agency_id=agency_id,
        was_override=False,
        override_reason=None,
        action="resolved",
        notes=notes,
    )

    db.table("incidents").update({
        "status": "resolved",
        "resolved_at": now,
    }).eq("id", incident_id).execute()

    _tell_reporter(
        incident,
        type_="incident.resolved",
        title="Your report was resolved",
        body="The agency marked your report as resolved. You can rate the response from My Reports.",
        at=now,
    )

    return {"incident_id": incident_id, "status": "resolved", "resolved_at": now}


def cancel_incident(
    incident_id: str,
    reason: str,
    dispatcher: dict,
) -> dict:
    """Cancel an incident. Requires a reason."""
    db: Client = get_supabase()
    dispatcher_id = str(dispatcher["id"])

    if not reason or not reason.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A reason is required to cancel an incident.",
        )

    inc_result = (
        db.table("incidents")
        .select("id, status, severity, assigned_agency_id, reporter_id")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not inc_result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    incident = inc_result.data

    if incident["status"] == "resolved":
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail="Cannot cancel an already resolved incident.")

    if dispatcher.get("role") == "agency_admin":
        if str(incident.get("assigned_agency_id")) != str(dispatcher.get("agency_id") or ""):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                                detail="You can only cancel incidents assigned to your agency.")

    agency_id = str(incident.get("assigned_agency_id") or dispatcher.get("agency_id") or "")

    _write_dispatch_log(
        db=db,
        incident_id=incident_id,
        dispatcher_id=dispatcher_id,
        agency_id=agency_id,
        suggested_severity=incident.get("severity"),
        chosen_severity=incident.get("severity") or "low",
        suggested_agency_id=None,
        chosen_agency_id=agency_id,
        was_override=False,
        override_reason=reason.strip(),
        action="cancelled",
        notes=reason.strip(),
    )

    db.table("incidents").update({"status": "cancelled"}).eq("id", incident_id).execute()

    # Said in the thread as well as pushed: the reason then stays on the report,
    # readable in its messages whenever the resident opens it, instead of living
    # only in a notification they may have dismissed.
    _post_to_thread(db, incident_id, dispatcher, f"This report was cancelled. Reason: {reason.strip()}")

    # Told WHY. Before this the phone only saw the status go to "cancelled" - the
    # same word a report the resident trashed themselves shows - and the reason the
    # agency gave was written to the audit log and never reached the person it
    # was about.
    _tell_reporter(
        incident,
        type_="incident.cancelled",
        title="The agency cancelled your report",
        body=f"Reason: {reason.strip()}",
        at=datetime.now(timezone.utc).isoformat(),
        important=True,
    )

    return {"incident_id": incident_id, "status": "cancelled"}


def get_available_responders(agency_id: str, dispatcher: dict) -> list[dict]:
    """
    Return approved, on_duty Responders for an agency.
    Agency Admins can only query their own agency.
    Provincial Admins can query any agency of their own agency_type.
    """
    if dispatcher.get("role") in ("agency_admin", "provincial_admin"):
        assert_agency_scope(dispatcher, agency_id)

    db: Client = get_supabase()
    result = (
        db.table("users")
        .select("id, full_name, badge_id, availability, phone_number")
        .eq("role", "responder")
        .eq("agency_id", agency_id)
        .eq("approval_status", "approved")
        .execute()
    )
    return result.data or []


def flag_false_sos(
    incident_id: str,
    dispatcher: dict,
) -> dict:
    """
    Mark an SOS report as a confirmed false alarm.
    Increments the reporter's sos_warning_count and may trigger suspension.
    Delegates to incident_service.record_false_sos().
    """
    db: Client = get_supabase()
    dispatcher_id = str(dispatcher["id"])

    # Get reporter_id from incident
    inc_result = (
        db.table("incidents")
        .select("id, reporter_id, submitted_via, assigned_agency_id")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not inc_result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    incident = inc_result.data

    if dispatcher.get("role") in ("agency_admin", "provincial_admin"):
        assert_agency_scope(dispatcher, str(incident.get("assigned_agency_id") or ""))

    from app.services.incident_service import record_false_sos
    return record_false_sos(
        reporter_id=str(incident["reporter_id"]),
        acting_dispatcher_id=dispatcher_id,
    )


# =============================================================================
# Internal helpers
# =============================================================================

def _write_dispatch_log(
    *,
    db: Client,
    incident_id: str,
    dispatcher_id: str,
    agency_id: str,
    suggested_severity: str | None,
    chosen_severity: str | None,
    suggested_agency_id: str | None,
    chosen_agency_id: str,
    was_override: bool,
    override_reason: str | None,
    action: str,
    notes: str | None,
) -> None:
    """Append an immutable row to dispatch_log."""
    try:
        db.table("dispatch_log").insert({
            "incident_id":        incident_id,
            "dispatcher_id":      dispatcher_id,
            "agency_id":          agency_id,
            "suggested_severity": suggested_severity,
            "chosen_severity":    chosen_severity,
            "suggested_agency_id": suggested_agency_id,
            "chosen_agency_id":   chosen_agency_id,
            "was_override":       was_override,
            "override_reason":    override_reason,
            "action":             action,
            "notes":              notes,
        }).execute()
    except Exception as e:
        # Log but don't fail the dispatch — the dispatch action itself is more critical
        log.error("dispatch_log.write_failed", incident_id=incident_id, error=str(e))


def _suggest_severity(row: dict) -> str | None:
    """
    Run the Phase 5 rubric against wizard answers to produce a severity suggestion.
    Returns None if no agency type is determinable.
    Falls back gracefully on any error.
    """
    try:
        stations = row.get("stations") or {}
        agencies = stations.get("agencies") or {}
        agency_type = agencies.get("agency_type")
        if not agency_type:
            return None

        # Build a signals dict from wizard_answers + overlap_agencies
        # What the model read from the spoken report, when it read anything.
        # The wizard mapping stays as the fallback: reports filed by older
        # builds carry chip answers and no model signals, and a report the
        # model could not read at all should still score off its category.
        signals = _model_to_signals(row) or _wizard_to_signals(row)
        from app.models.rubric import AgencyType as RubricAgencyType
        agency_enum = RubricAgencyType(agency_type)
        # evaluate(signals, agency_type) — signals first. Passing these the
        # other way round raises TypeError deep inside _load_config ("unhashable
        # type: 'dict'", from using the signals dict as a cache key), which the
        # except below swallows into None. That is how this function returned
        # no suggestion for every incident ever queued while looking healthy.
        result = rubric_evaluate(signals, agency_enum)

        # No rule matched. The engine's own default for that is 'low', which is
        # the right floor for a scored report but the wrong thing to hand a
        # dispatcher as a suggestion: nothing about this report was understood,
        # and "low" reads as a judgement rather than an absence of one.
        # Returning None leaves it as "needs human triage", which is what it is.
        if result.no_rules_triggered:
            return None

        return result.severity
    except Exception:
        return None


# ── Model signals → rubric vocabulary ─────────────────────────────────
#
# The resident flow asks no questions — one tap on a category goes straight to
# the confirm screen — so `wizard_answers` is empty on every report the app
# files today. What the report DOES carry is what the model read out of the
# spoken text: `incidents.signals.signals`, produced by predict.extract().
#
# Those two vocabularies do not share a single name beyond `injured_count` and
# `weapon_mentioned`. This is the translation between them. Without it the
# rubric fallback sees only the category, which is why a fire scored `critical`
# on the catch-all and everything else came back unscored.

# predict.extract() name -> rubric signal name, for the fields that map 1:1.
_MODEL_DIRECT = {
    "injured_count":    "injured_count",
    "weapon_mentioned": "weapon_mentioned",
}


def _model_to_signals(row: dict) -> dict | None:
    """Rubric signals from what the model read, or None if it read nothing.

    Returns None — not an empty dict — when the model recorded no signals, so
    the caller can fall back to wizard answers rather than evaluate a report
    it knows nothing about.
    """
    blob = row.get("signals") or {}
    if not isinstance(blob, dict):
        return None
    extracted = blob.get("signals")
    if not isinstance(extracted, dict) or not extracted:
        return None

    signals: dict = {}
    category = row.get("incident_category") or blob.get("model_predicted_category")
    signals["incident_type"] = category

    for src, dest in _MODEL_DIRECT.items():
        signals[dest] = extracted.get(src)

    injured = extracted.get("injured")
    entrapment = extracted.get("entrapment")
    fatalities = extracted.get("fatalities")

    # Trapped counts as a casualty here because that is how the product already
    # words it: the wizard's own question is "May nasugatan o nakulong?" — hurt
    # OR trapped, one answer. The rubric schema has no entrapment signal of its
    # own, which is a gap worth closing with the stations; until then, folding
    # it in preserves the meaning rather than discarding it.
    if injured is True or entrapment is True or fatalities:
        signals["casualty_mentioned"] = True
    elif injured is False:
        signals["casualty_mentioned"] = False
    else:
        signals["casualty_mentioned"] = None

    signals["dead_count"] = fatalities

    # A headcount only becomes an injured count once someone is said to be hurt.
    # "duha ka motor nag bangga" is two vehicles, not two casualties.
    if signals["injured_count"] is None and injured is True:
        signals["injured_count"] = extracted.get("people_involved")

    # STRUCT matches dwellings and premises alike (balay, building, eskwelahan,
    # tindahan), so it supports "a structure is burning" and nothing finer. The
    # rules that need house-vs-building still cannot fire, and inventing the
    # distinction here would be worse than leaving it unknown.
    if category == "fire" and extracted.get("structure_involved") is True:
        signals["fire_type"] = "structural"
    else:
        signals["fire_type"] = None
    signals["structure_type"] = None

    # No extractor output speaks to these. None, never False.
    signals["weapon_type"] = None
    signals["why_category"] = None
    signals["children_involved"] = None

    signals["multi_agency_needed"] = _infer_multi_agency(
        category, row.get("wizard_answers") or {},
        row.get("overlap_agencies") or [], signals,
    )

    # Urgency from what was actually said. Someone unresponsive, trapped, or
    # dead is a different call from a report that mentions none of those.
    if (extracted.get("unresponsive") is True or entrapment is True or fatalities):
        signals["urgency_level"] = "critical"
    elif injured is True:
        signals["urgency_level"] = "high"
    elif extracted.get("hazard_spreading") is True:
        signals["urgency_level"] = "high"
    elif category == "fire":
        signals["urgency_level"] = "high"
    elif category in ("domestic_dispute_crime", "hazmat"):
        signals["urgency_level"] = "medium"
    elif injured is False:
        signals["urgency_level"] = "low"
    else:
        signals["urgency_level"] = "unknown"

    return signals


# ── Wizard answer vocabulary ─────────────────────────────────────────────────
#
# The values the report screen actually sends. `triage_service` already reads
# this same vocabulary in `_chips_from_wizard`; what follows is the rubric's
# copy of it, and the two having drifted apart is what left the fallback blind:
# this function used to read keys (`fire_type`, `may_nasugatan`, `may_bata`)
# that no build of the app has ever sent, so almost every signal was a
# constant and only five of the thirty-seven rules could ever match.
#
# Tri-state on purpose. "Hindi ko alam", and a question that was never
# answered, are NOT False. A rule testing `casualty_mentioned: false` must not
# match a report where nobody knows whether anyone is hurt. None fails every
# condition, which is the conservative reading for triage — the same reasoning
# `_chips_from_wizard` gives for keeping unknowns out of the model's chips.

_YES = ("Oo",)
_NO = ("Wala", "Hindi")

# "Ano ang nasusunog?" → (fire_type, structure_type)
_FIRE_MATERIAL = {
    "Bahay":             ("residential", "house"),
    "Gusali / Bodega":   ("structural",  "building"),
    "Sasakyan":          ("vehicle",     None),
    "Kagubatan / Bukid": ("grass",       "forest"),
}

# Head counts. The upper bound of each range is used deliberately, matching
# `_COUNT_ANSWERS` in triage_service: sending too many responders is
# recoverable, sending too few is not.
_COUNTS = {
    "1": 1, "2–5": 5, "Higit sa 5": 6,        # medical: victim_count
    "1–5": 5, "6–20": 20, "Higit sa 20": 21,  # calamity: affected families
}

# "Uri ng insidente?" on the crime step.
_CRIME_TYPE = {
    "Pagnanakaw / Holdap": "robbery",
    "Pambubugbog":         "assault",
}


# Spellings older rows may carry. No shipped build ever wrote these keys, but
# a stored row costs nothing to accept and silently losing one costs a signal.
_LEGACY_YES = {"oo", "opo", "yes", "true", "1"}
_LEGACY_NO = {"wala", "hindi", "no", "false", "0", "none"}


def _tri(value, yes=_YES, no=_NO):
    """True / False / None from one wizard answer.

    Anything not recognised — "Hindi ko alam" included — is None, never False.
    Compared case-insensitively: a stored "oo" means the same as "Oo", and
    dropping it over a capital letter would lose a casualty signal.
    """
    if not isinstance(value, str):
        return None
    v = value.strip().lower()
    if v in {y.lower() for y in yes} or v in _LEGACY_YES:
        return True
    if v in {n.lower() for n in no} or v in _LEGACY_NO:
        return False
    return None


def _first_tri(wizard: dict, *keys, yes=_YES, no=_NO):
    """The first answered question among `keys`, tri-state.

    A "yes" anywhere wins: on the medical step both `injured` and `bleeding`
    speak to the same thing, and one of them saying yes settles it.
    """
    seen_false = False
    for key in keys:
        result = _tri(wizard.get(key), yes=yes, no=no)
        if result is True:
            return True
        if result is False:
            seen_false = True
    return False if seen_false else None


def _wizard_to_signals(row: dict) -> dict:
    """
    Map wizard_answers + incident_category + overlap_agencies to the
    15-signal schema understood by the rubric engine.

    Reads the keys and values the report screen sends today, and the legacy
    keys older stored rows may carry. Signals the app has no question for are
    left as None rather than invented — see the note above on tri-state.
    """
    signals: dict = {}
    category = row.get("incident_category")
    wizard = row.get("wizard_answers") or {}
    overlap = row.get("overlap_agencies") or []

    # Signal 1: incident type is the category the resident chose.
    signals["incident_type"] = category

    # Signal 2 + 10: what is burning, and what kind of place it is.
    fire_type = structure_type = None
    if category == "fire":
        fire_type, structure_type = _FIRE_MATERIAL.get(
            wizard.get("material"), (None, None)
        )
        # Legacy rows written before the material question existed.
        fire_type = fire_type or wizard.get("fire_type")
    elif category == "flood_landslide_calamity":
        # A flood that reached homes and a landslide across a road are
        # different responses. Homes win when both are true: MDRRMO-004 and
        # MDRRMO-003 are both "high", and people outrank a road.
        if _tri(wizard.get("evacuation"), yes=("Oo, urgent",)) or wizard.get("affected") in _COUNTS:
            structure_type = "residential"
        elif _tri(wizard.get("road_blocked"), yes=("Oo", "Oo, nakabara")):
            structure_type = "road"
    signals["fire_type"] = fire_type
    signals["structure_type"] = structure_type

    # Signal 3: is anyone hurt. `injured` on the fire and vehicular steps,
    # `bleeding` on the medical one.
    signals["casualty_mentioned"] = _first_tri(
        wizard, "injured", "bleeding", "may_nasugatan", "casualty"
    )

    # Signal 4: how many. Only the medical and calamity steps ask.
    injured = _COUNTS.get(wizard.get("victim_count"))
    if injured is None:
        injured = _COUNTS.get(wizard.get("affected"))
    if injured is None:
        legacy = wizard.get("injured_count") or wizard.get("bilang_nasugatan")
        try:
            injured = int(legacy) if legacy else None
        except (ValueError, TypeError):
            injured = None
    signals["injured_count"] = injured

    # Signal 5: deaths. No question asks this — the app deliberately does not
    # ask a bystander to count bodies — so it stays unknown unless a legacy
    # row carries it.
    dead_raw = wizard.get("dead_count") or wizard.get("bilang_patay")
    try:
        signals["dead_count"] = int(dead_raw) if dead_raw else None
    except (ValueError, TypeError):
        signals["dead_count"] = None

    # Signal 6 + 7: weapons. This used to be `bool(answer)`, which made every
    # non-empty string true — so answering "Wala" reported a weapon.
    weapon = _first_tri(wizard, "weapon", "may_sandata")
    if wizard.get("type") == "May armas":
        weapon = True
    signals["weapon_mentioned"] = weapon
    # The app never asks whether it was a gun or a blade, so the rules that
    # split on that stay unreachable. That distinction is one of the questions
    # for the PNP field interview.
    signals["weapon_type"] = wizard.get("weapon_type")

    # Signal 8: what kind of crime, for the rules about a crime in progress.
    signals["why_category"] = _CRIME_TYPE.get(wizard.get("type"))

    # Signal 11: children. No question asks, so this is unknown, not False.
    signals["children_involved"] = _first_tri(wizard, "may_bata", "children")

    # Signal 14: multi-agency.
    # Previously this trusted `overlap_agencies`, a screen that asked the
    # RESIDENT which other agencies were needed — that is dispatcher judgment,
    # not something a bystander watching a fire can answer. It is now INFERRED
    # from evidence already collected, and the resident's answer (when an older
    # client still sends one) is treated as an additional hint, never the
    # sole source.
    signals["multi_agency_needed"] = _infer_multi_agency(category, wizard, overlap, signals)

    # Signal 12: urgency.
    # For a medical call the answers say more than the category does: someone
    # unconscious or bleeding is a different call from one where the reporter
    # cannot tell. Everything else still reads from the category.
    if category == "medical_trauma":
        if (_tri(wizard.get("conscious"), yes=("Hindi, nawalan ng malay",), no=("Oo, gising",)) is True
                or _tri(wizard.get("bleeding")) is True):
            signals["urgency_level"] = "critical"
        elif wizard.get("conscious") or wizard.get("bleeding"):
            signals["urgency_level"] = "moderate"
        else:
            signals["urgency_level"] = "unknown"
    elif category == "fire":
        signals["urgency_level"] = "high"
    elif category in ("domestic_dispute_crime", "hazmat"):
        signals["urgency_level"] = "medium"
    else:
        signals["urgency_level"] = "low"

    return signals


# Categories that inherently pull in a second agency regardless of what
# else the reporter said. Fire always implies medical standby; hazmat and
# calamity always imply MDRRMO coordination.
_INHERENTLY_MULTI_AGENCY = {"fire", "hazmat", "flood_landslide_calamity", "vehicular"}


def _infer_multi_agency(
    category: str | None,
    wizard: dict,
    overlap: list,
    signals: dict,
) -> bool:
    """
    Decide whether an incident needs more than one agency, WITHOUT relying on
    the reporter to make that call.

    Evidence used, in order of reliability:
      1. Category — some incident types always cross agency lines.
      2. Casualties — any injury or death on a non-medical incident means
         medical support is needed alongside the primary agency.
      3. Weapon on a non-police incident — police support needed.
      4. The legacy `overlap_agencies` answer, if an older client sent one.
         Kept as a hint so existing rows still evaluate sensibly, but it can
         no longer be the only thing that triggers the signal.
    """
    if category in _INHERENTLY_MULTI_AGENCY:
        return True

    # Casualties on a non-medical incident → medical support needed
    if category != "medical_trauma":
        if signals.get("casualty_mentioned"):
            return True
        if (signals.get("injured_count") or 0) > 0:
            return True
        if (signals.get("dead_count") or 0) > 0:
            return True

    # Weapon present on a non-crime incident → police support needed
    if category != "domestic_dispute_crime" and signals.get("weapon_mentioned"):
        return True

    # Legacy hint from the removed overlap screen (older mobile clients)
    if overlap and "none" not in overlap:
        return True

    return False
