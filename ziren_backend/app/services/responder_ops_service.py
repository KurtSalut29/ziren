"""
Responder operations — everything the crew does that is not a status flip.

WHY THIS IS NOT IN responder_service.py

That module is the read path plus the FSM: queue, detail, media, location,
dashboard. It is already 475 lines and coherent. What migration 024 unlocks is
a different kind of work — acceptance, refusal, after-action, mutual aid,
distress — and folding it in would have produced a 900-line file whose name no
longer described it. These are the WRITE verbs a responder has that change the
shape of an incident rather than advancing it.

The security contract is identical to responder_service and is not relaxed
anywhere in this file:

  - responder_id always comes from the authenticated token, never the body.
  - Every incident-scoped call goes through _load_assigned(), which 404s on a
    missing incident and 403s on one assigned to somebody else. There is no
    path in this module that reads or writes an incident without it.
  - The service key bypasses RLS, so these checks ARE the boundary. Migration
    024's policies are the second gate, not the first.
"""

from datetime import datetime, timedelta, timezone

import structlog
from fastapi import HTTPException, status
from supabase import Client

from app.core.dependencies import assert_agency_scope
from app.db.supabase_client import get_supabase
from app.services import notification_service

# Reused rather than reimplemented. These two are the same maths the incident
# router already trusts to route an emergency to the correct station, and a
# second copy would be a second thing to get wrong — the failure mode of a
# subtly different distance is an ETA that is quietly always 20% short. The
# distance is ellipsoidal (Vincenty, WGS-84) - see app.core.geo.
from app.core import geo
from app.services.incident_service import _distance_km, _parse_point

log = structlog.get_logger()


# =============================================================================
# Vocabulary — mirrors the CHECK constraints in migration 024
#
# Duplicated from the database on purpose. The constraint is the real gate, but
# a violation surfaces from PostgREST as an opaque 23514 with the constraint
# name in it, which reaches the responder as "something went wrong". Checking
# here turns that into a 422 that names the field and lists what is allowed.
# =============================================================================

_DECLINE_REASONS = frozenset({
    "vehicle_down",
    "already_committed",
    "out_of_area",
    "insufficient_crew",
    "road_impassable",
    "other",
})

_OUTCOMES = frozenset({
    "handled_on_scene",
    "transported",
    "turned_over",
    "false_alarm",
    "nobody_found",
    "refused_assistance",
    "unable_to_access",
    "other",
})

_HAZARD_TYPES = frozenset({
    "road_impassable",
    "access_difficult",
    "security",
    "animal",
    "structural",
    "other",
})

_AGENCY_TYPES = frozenset({"BFP", "PNP", "MDRRMO"})

#: Statuses a responder may still accept or decline from. Once they are moving
#: the question has answered itself.
_PENDING_STATUSES = frozenset({"dispatched"})

#: Assumed average road speed for the ETA, in km/h.
#:
#: Low on purpose. These are provincial roads — single carriageway, unlit,
#: with barangay traffic on them — and the number is applied to a STRAIGHT-LINE
#: distance, which always understates the real route. Both errors point the
#: same way, so the ETA shown to a resident runs long rather than short. A
#: crew arriving before the app said they would is a good surprise; the
#: opposite is a family standing in the road watching an empty street.
_ASSUMED_SPEED_KMH = geo.ASSUMED_SPEED_KMH

#: Distance within which a standing hazard is worth showing on approach.
_HAZARD_SEARCH_KM = 3.0


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _agency_ids_for_type(db: Client, agency_type: str | None) -> list[str]:
    """
    Two-step lookup: a provincial_admin's agency_type -> every `agencies.id`
    it covers. Same pattern as dispatch_service._agency_ids_for_type — this
    module's distress/en-route reads key off agency_id, not agency_type, so
    the type has to be resolved before it can filter anything.
    """
    if not agency_type:
        return []
    rows = db.table("agencies").select("id").eq("agency_type", agency_type).execute().data or []
    return [row["id"] for row in rows]



def _clamp_occurred_at(
    occurred_at: str | None,
    not_before: str | None,
    label: str,
) -> str:
    """Resolve a client-supplied timestamp into one the server will store.

    THE PROBLEM THIS SOLVES. The responder is the one person in this system
    guaranteed to lose signal — they are driving into the barangays, which is
    the job. Their acceptances and closures are queued on the handset and sent
    when coverage returns, and if the server stamped its own clock then a call
    accepted at 14:02 and synced at 14:40 would be recorded as a 38-minute
    response. The measurement would be of the mountain, not the crew.

    WHY IT IS CLAMPED RATHER THAN TRUSTED. A client that sets its own
    timestamps without bound can rewrite its own performance, and this figure
    is the one the whole product reports. So the value is accepted only inside
    [not_before, now]:

      - later than now      -> now. A phone with a fast clock, or a crew that
                               would like a better number.
      - before not_before   -> not_before. An acceptance cannot predate the
                               dispatch that caused it.
      - unparseable/absent  -> now. The ordinary online path sends nothing.

    The clamp is silent on purpose. There is no legitimate flow in which a
    responder can act on this, and refusing the write would throw away a real
    acceptance over a clock-skew of two seconds.
    """
    now = datetime.now(timezone.utc)

    def parse(value):
        if not value:
            return None
        try:
            return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except (ValueError, TypeError):
            return None

    claimed = parse(occurred_at)
    if claimed is None:
        return now.isoformat()

    if claimed.tzinfo is None:
        claimed = claimed.replace(tzinfo=timezone.utc)

    floor = parse(not_before)
    resolved = claimed
    if resolved > now:
        resolved = now
    if floor is not None and resolved < floor:
        resolved = floor

    if resolved != claimed:
        log.info(
            "responder.occurred_at_clamped",
            label=label,
            claimed=claimed.isoformat(),
            stored=resolved.isoformat(),
        )
    return resolved.isoformat()


def _coords(geo) -> tuple[float | None, float | None]:
    """(lat, lng) out of whatever PostgREST returned for a geometry column.

    Handles the GeoJSON dict PostgREST normally produces and falls back to the
    WKT parser for the cases where it does not — the map router assumes GeoJSON
    and the incident router assumes WKT, and both are right some of the time.
    """
    if isinstance(geo, dict):
        pair = geo.get("coordinates")
        if isinstance(pair, (list, tuple)) and len(pair) >= 2:
            return float(pair[1]), float(pair[0])
        return None, None
    if geo:
        return _parse_point(geo)
    return None, None


# =============================================================================
# Shared guard
# =============================================================================

def _load_assigned(
    db: Client,
    incident_id: str,
    responder_id: str,
    columns: str = "*",
    allow_unassigned: bool = False,
) -> dict:
    """Load an incident, or refuse.

    Every write in this module starts here. `allow_unassigned` exists for one
    caller — decline, which must still work on the row it is about to release
    — and defaults to False so that forgetting to think about it fails closed.
    """
    result = (
        db.table("incidents")
        .select(columns)
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )

    # maybe_single() returns None for zero rows rather than raising PGRST116.
    # `result is None` is a real case, not defensive padding — see the 404 in
    # user_service.get_my_profile that was unreachable for exactly this reason.
    if result is None or not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Incident not found.",
        )

    row = result.data
    assigned = row.get("assigned_responder_id")
    if assigned != responder_id and not (allow_unassigned and assigned is None):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not assigned to this incident.",
        )
    return row


# =============================================================================
# 1. Acceptance and refusal
# =============================================================================

def accept_incident(
    incident_id: str,
    responder_id: str,
    occurred_at: str | None = None,
) -> dict:
    """Record that this responder is taking the call.

    The button that makes 'dispatched' mean something. Until this exists, a
    dispatcher watching the board cannot distinguish a crew already rolling
    from a handset face-down in a locker.

    IDEMPOTENT. A responder on a bad connection will press this twice, and the
    second press must not be an error — it must be the same success, with the
    original timestamp preserved. Overwriting accepted_at on a re-press would
    quietly reset the response-time measurement this feature exists to produce.
    """
    db: Client = get_supabase()
    row = _load_assigned(
        db, incident_id, responder_id,
        columns=(
            "id, status, accepted_at, dispatched_at, assigned_responder_id, "
            "assigned_agency_id"
        ),
    )

    if row.get("accepted_at"):
        return {
            "incident_id": incident_id,
            "accepted_at": row["accepted_at"],
            "already_accepted": True,
        }

    if row.get("status") not in _PENDING_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"This incident is already '{row.get('status')}' — "
                "there is nothing left to accept."
            ),
        )

    # The moment the responder pressed the button, which is not the moment
    # this request arrived if it waited out a dead zone on the handset.
    # Floored at dispatched_at: an acceptance cannot predate its dispatch.
    now = _clamp_occurred_at(occurred_at, row.get("dispatched_at"), "accept")
    db.table("incidents").update({
        "accepted_at": now,
        # A previous crew's refusal is cleared from the live fields so the
        # board does not show this incident as declined while a new responder
        # is driving to it. decline_count is deliberately NOT reset: it counts
        # the incident's whole history, and three refusals is a coverage
        # finding that must survive the fourth assignment.
        "declined_at": None,
        "declined_reason": None,
    }).eq("id", incident_id).execute()

    log.info(
        "responder.accepted",
        incident_id=incident_id,
        responder_id=responder_id,
        seconds_to_accept=_elapsed_seconds(row.get("dispatched_at"), now),
    )

    agency_id = row.get("assigned_agency_id")
    if agency_id:
        try:
            notification_service.create_for_agency_role(
                str(agency_id), "agency_admin",
                type_="responder.accepted",
                title="Responder accepted assignment",
                link=f"/incidents/{incident_id}",
            )
        except Exception:
            log.error("responder.accept_notify_failed", incident_id=incident_id, exc_info=True)

    return {"incident_id": incident_id, "accepted_at": now, "already_accepted": False}


def decline_incident(
    incident_id: str,
    responder_id: str,
    reason: str,
    note: str | None = None,
) -> dict:
    """Hand the incident back to the dispatcher, with a reason.

    THE EXIT THE FSM NEVER HAD. _VALID_TRANSITIONS is forward-only, so a crew
    whose truck would not start had no way to say so — the dispatcher found out
    by nobody arriving.

    What this does NOT do is pick the next responder. The incident returns to
    'processing' and lands back on the board carrying the reason, and a human
    decides. Auto-reassignment can stand two crews down without either knowing,
    and there is nobody left who can see that happened.
    """
    if reason not in _DECLINE_REASONS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                "Unknown decline reason. Must be one of: "
                f"{', '.join(sorted(_DECLINE_REASONS))}."
            ),
        )

    db: Client = get_supabase()
    row = _load_assigned(
        db, incident_id, responder_id,
        columns=(
            "id, status, accepted_at, decline_count, "
            "assigned_responder_id, assigned_agency_id"
        ),
    )

    # Declining after arriving is not a refusal, it is an abandonment, and it
    # would leave the incident with arrival evidence and no responder. A crew
    # already on scene who cannot continue needs the dispatcher, not a button.
    if row.get("status") not in _PENDING_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"You have already started responding (status "
                f"'{row.get('status')}'). Contact your dispatcher to hand this over."
            ),
        )

    now = _now()
    db.table("incidents").update({
        "status": "processing",       # back on the dispatcher's board
        "assigned_responder_id": None,
        "dispatched_at": None,        # the next dispatch starts a fresh clock
        "accepted_at": None,
        "declined_at": now,
        "declined_reason": reason,
        "declined_by": responder_id,
        "decline_count": (row.get("decline_count") or 0) + 1,
    }).eq("id", incident_id).execute()

    log.warning(
        "responder.declined",
        incident_id=incident_id,
        responder_id=responder_id,
        reason=reason,
        decline_count=(row.get("decline_count") or 0) + 1,
        note=note,
    )
    return {
        "incident_id": incident_id,
        "declined_at": now,
        "declined_reason": reason,
        "decline_count": (row.get("decline_count") or 0) + 1,
    }


def _elapsed_seconds(start, end) -> int | None:
    def parse(v):
        if v is None:
            return None
        if isinstance(v, datetime):
            return v if v.tzinfo else v.replace(tzinfo=timezone.utc)
        try:
            return datetime.fromisoformat(str(v).replace("Z", "+00:00"))
        except (ValueError, TypeError):
            return None

    a, b = parse(start), parse(end)
    if a is None or b is None:
        return None
    return max(int((b - a).total_seconds()), 0)


# =============================================================================
# 2. After-action — closing a call with what was actually found
# =============================================================================

def close_incident(
    incident_id: str,
    responder_id: str,
    outcome: str,
    outcome_notes: str | None = None,
    casualties_injured: int | None = None,
    casualties_fatal: int | None = None,
    casualties_transported: int | None = None,
    occurred_at: str | None = None,
) -> dict:
    """Resolve an incident WITH a disposition.

    Replaces the bare status flip for the resolve step. The old path wrote
    {"status": "resolved", "resolved_at": now} and nothing else, which is why
    the incident archive has never recorded a single fact about what a crew
    found. Every severity the rubric has ever produced has been unfalsifiable
    for want of this column.

    outcome is REQUIRED. Making it optional would have meant it was filled in
    on the calls where nothing interesting happened and skipped on the ones
    that mattered, which is the opposite of useful.
    """
    if outcome not in _OUTCOMES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown outcome. Must be one of: {', '.join(sorted(_OUTCOMES))}.",
        )

    for label, value in (
        ("casualties_injured", casualties_injured),
        ("casualties_fatal", casualties_fatal),
        ("casualties_transported", casualties_transported),
    ):
        if value is not None and value < 0:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"{label} cannot be negative.",
            )

    db: Client = get_supabase()
    row = _load_assigned(
        db, incident_id, responder_id,
        columns=(
            "id, status, severity, assigned_responder_id, dispatched_at, "
            "assigned_agency_id"
        ),
    )

    # Only from 'arrived'. Closing a call you never reached is either a mistake
    # or an 'unable_to_access' that should be recorded as a decline instead —
    # and letting it through here would put a fabricated arrival in the data
    # the rubric is about to be scored against.
    if row.get("status") != "arrived":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Cannot close from '{row.get('status')}'. Mark yourself on "
                "scene first, or decline if you could not reach it."
            ),
        )

    # Same clamp as accept. A crew that closed a call in a dead zone and
    # synced on the way back must not have the drive home counted as part
    # of the response.
    now = _clamp_occurred_at(occurred_at, row.get("dispatched_at"), "close")
    db.table("incidents").update({
        "status": "resolved",
        "resolved_at": now,
        "outcome": outcome,
        "outcome_notes": (outcome_notes or "").strip() or None,
        "casualties_injured": casualties_injured,
        "casualties_fatal": casualties_fatal,
        "casualties_transported": casualties_transported,
        "closed_by": responder_id,
    }).eq("id", incident_id).execute()

    # Logged at this level of detail because it is the raw material for rubric
    # validation: severity is what the machine said, outcome is what was true.
    # A 'critical' that closes 'false_alarm' is a measurable miss, and this
    # line is where that pair first exists in one place.
    log.info(
        "responder.closed",
        incident_id=incident_id,
        responder_id=responder_id,
        outcome=outcome,
        rubric_severity=row.get("severity"),
        casualties_injured=casualties_injured,
        casualties_fatal=casualties_fatal,
        response_seconds=_elapsed_seconds(row.get("dispatched_at"), now),
    )

    agency_id = row.get("assigned_agency_id")
    if agency_id:
        try:
            notification_service.create_for_agency_role(
                str(agency_id), "agency_admin",
                type_="incident.resolved",
                title="Incident resolved",
                body=outcome.replace("_", " "),
                link=f"/incidents/{incident_id}",
            )
        except Exception:
            log.error("responder.close_notify_failed", incident_id=incident_id, exc_info=True)

    return {
        "incident_id": incident_id,
        "status": "resolved",
        "resolved_at": now,
        "outcome": outcome,
    }


def attach_scene_media(
    incident_id: str,
    responder_id: str,
    paths: list[str],
) -> dict:
    """Append responder-taken photos to the incident.

    Kept in `scene_media_urls`, never in `media_urls`. That separation is the
    whole value: media_urls is what was known BEFORE anyone arrived, and mixing
    the two would destroy the only way to tell a reporter's photo of smoke from
    a crew's photo of the room it came from.

    Appends rather than replaces, and de-duplicates, because a retried upload
    on a bad connection is normal here and must not produce the same photo
    twice in the review.
    """
    if not paths:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No media paths supplied.",
        )

    db: Client = get_supabase()
    row = _load_assigned(
        db, incident_id, responder_id,
        columns="id, scene_media_urls, assigned_responder_id",
    )

    existing = list(row.get("scene_media_urls") or [])
    for path in paths:
        cleaned = (path or "").strip()
        if cleaned and cleaned not in existing:
            existing.append(cleaned)

    db.table("incidents").update(
        {"scene_media_urls": existing}
    ).eq("id", incident_id).execute()

    log.info(
        "responder.scene_media_attached",
        incident_id=incident_id,
        responder_id=responder_id,
        added=len(paths),
        total=len(existing),
    )
    return {"incident_id": incident_id, "scene_media_urls": existing}


# =============================================================================
# 3. Mutual aid
# =============================================================================

def request_backup(
    incident_id: str,
    responder_id: str,
    agency_type: str,
    reason: str,
) -> dict:
    """Ask a second agency to attend the same emergency.

    Creates a real, linked incident rather than raising a flag. The ambulance
    crew needs something to be dispatched TO — with its own severity, its own
    dispatcher, its own acceptance and its own after-action — and a boolean on
    the parent gives them none of that.

    NOT TRIAGED. The child inherits the parent's severity directly instead of
    passing the responder's request through the rubric. Two reasons: the rubric
    reads a civilian's account of an emergency and this text is a professional's
    request for a resource, so the signals it looks for are not there; and a
    responder standing in front of the incident is better evidence of its
    severity than any classifier reading about it.
    """
    agency_type = (agency_type or "").strip().upper()
    if agency_type not in _AGENCY_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown agency. Must be one of: {', '.join(sorted(_AGENCY_TYPES))}.",
        )
    if not (reason or "").strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Say what you need the other agency for.",
        )

    db: Client = get_supabase()
    parent = _load_assigned(
        db, incident_id, responder_id,
        columns=(
            "id, report_text, severity, location, location_address, "
            "landmark_note, incident_category, assigned_responder_id, "
            "assigned_agency_id, backup_of_incident_id"
        ),
    )

    # One level deep. A backup incident cannot itself request backup, or a
    # confused night turns into a chain of linked incidents nobody can read.
    if parent.get("backup_of_incident_id"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                "This is already a mutual-aid request. Ask your dispatcher to "
                "bring in a third agency."
            ),
        )

    lat, lng = _coords(parent.get("location"))

    # Nearest station OF THE REQUESTED TYPE — not simply the nearest station,
    # which would be the one already attending.
    station = _nearest_station_of_type(db, lat, lng, agency_type)
    if station is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"No active {agency_type} station could be found to receive this.",
        )

    requester = (
        db.table("users")
        .select("full_name, badge_id")
        .eq("id", responder_id)
        .maybe_single()
        .execute()
    )
    who = (requester.data or {}) if requester else {}
    name = who.get("full_name") or "A responder"
    badge = f" ({who['badge_id']})" if who.get("badge_id") else ""

    child_text = (
        f"MUTUAL AID REQUEST from {name}{badge} on scene.\n\n"
        f"Needed: {reason.strip()}\n\n"
        f"Original report: {parent.get('report_text') or '(none)'}"
    )

    insert_payload = {
        # The requesting responder is the reporter. They are a real user with a
        # real row, and attributing the request to the original resident would
        # put words in the mouth of someone who never said them.
        "reporter_id": responder_id,
        "report_text": child_text,
        "station_id": station["id"],
        "assigned_agency_id": station["agency_id"],
        "location": f"POINT({lng} {lat})" if lat is not None and lng is not None else None,
        "location_address": parent.get("location_address"),
        "landmark_note": parent.get("landmark_note"),
        "incident_category": parent.get("incident_category"),
        "severity": parent.get("severity"),
        "status": "received",
        "submitted_via": "internet",
        "media_urls": [],
        "backup_of_incident_id": incident_id,
        "backup_reason": reason.strip(),
        "backup_requested_by": responder_id,
    }

    created = db.table("incidents").insert(insert_payload).execute()
    if not created.data:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not raise the mutual-aid request. Use the radio.",
        )

    child = created.data[0]
    log.info(
        "responder.backup_requested",
        parent_incident_id=incident_id,
        child_incident_id=child["id"],
        responder_id=responder_id,
        agency_type=agency_type,
        station_id=station["id"],
    )
    return {
        "parent_incident_id": incident_id,
        "incident_id": child["id"],
        "agency_type": agency_type,
        "station_name": station.get("name"),
        "severity": child.get("severity"),
    }


def escalate_incident(
    incident_id: str,
    responder_id: str,
    reason: str,
) -> dict:
    """Responder spec Section 14 — "the situation is worse than assessed."

    Deliberately does NOT touch `incidents.severity`. The spec is explicit
    that a responder notifies the Agency Admin so the incident can be
    reassessed rather than reassessing it themselves — severity change stays
    with whatever surface already does that (the Agency Admin's own
    dispatch tools), and this function's only effect is a notification the
    Agency Admin acts on.

    No new column or table: unlike accept/decline, an escalation is not a
    state the incident holds — it is a moment-in-time flag, and the
    notification row itself (with its own created_at) is the durable record,
    the same way `responder.accepted` leaves no trace beyond its
    notification and the `accepted_at` timestamp it also happens to set.
    Escalation sets nothing, because there is nothing official to set.
    """
    if not (reason or "").strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Say what changed since the incident was first assessed.",
        )

    db: Client = get_supabase()
    row = _load_assigned(
        db, incident_id, responder_id,
        columns="id, severity, assigned_agency_id",
    )

    requester = (
        db.table("users")
        .select("full_name, badge_id")
        .eq("id", responder_id)
        .maybe_single()
        .execute()
    )
    who = (requester.data or {}) if requester else {}
    name = who.get("full_name") or "A responder"
    badge = f" ({who['badge_id']})" if who.get("badge_id") else ""

    now = _now()
    log.info(
        "responder.escalated",
        incident_id=incident_id,
        responder_id=responder_id,
        current_severity=row.get("severity"),
        reason=reason.strip(),
    )

    agency_id = row.get("assigned_agency_id")
    if agency_id:
        try:
            notification_service.create_for_agency_role(
                str(agency_id), "agency_admin",
                type_="responder.escalated",
                title=f"{name}{badge} flagged this incident as worse than assessed",
                body=reason.strip()[:200],
                link=f"/incidents/{incident_id}",
                is_important=True,
            )
        except Exception:
            log.error("responder.escalate_notify_failed", incident_id=incident_id, exc_info=True)

    return {"incident_id": incident_id, "escalated_at": now, "reason": reason.strip()}


def _nearest_station_of_type(
    db: Client,
    lat: float | None,
    lng: float | None,
    agency_type: str,
) -> dict | None:
    """Closest active station belonging to the given agency type.

    Note `agencies!inner`. With a plain embed PostgREST does NOT filter parent
    rows on an embedded condition — it returns every station and sets
    `agencies` to null on the ones that do not match. That exact mistake once
    routed GPS-less SOS reports to an arbitrary agency; see the comment on
    _resolve_nearest_station in incident_service.
    """
    result = (
        db.table("stations")
        .select("id, agency_id, name, location, agencies!inner(agency_type)")
        .eq("is_active", True)
        .eq("agencies.agency_type", agency_type)
        .execute()
    )
    rows = result.data or []
    if not rows:
        return None

    if lat is None or lng is None:
        # No coordinates on the parent — any station of the right type beats
        # failing the request outright, and the dispatcher will re-route.
        return rows[0]

    best, best_dist = None, float("inf")
    for row in rows:
        s_lat, s_lng = _coords(row.get("location"))
        if s_lat is None:
            continue
        dist = _distance_km(lat, lng, s_lat, s_lng)
        if dist < best_dist:
            best, best_dist = row, dist
    return best or rows[0]


# =============================================================================
# 4. ETA
# =============================================================================

def refresh_eta(
    responder_id: str,
    lat: float,
    lng: float,
    db: Client | None = None,
) -> list[dict]:
    """Recompute the ETA on every incident this responder is driving to.

    Called from the location ping, so it costs no extra round trip from the
    phone. Only 'en_route' incidents are touched: before that the crew has not
    committed to a route, and after arriving the number is meaningless.

    Straight-line distance over an assumed speed. Deliberately not a routing
    API — there is no road graph for Biliran's barangay roads worth paying for,
    and a confidently wrong turn-by-turn ETA is worse than an honest rough one.
    Every approximation here rounds the number UP.

    TAKES THE CALLER'S CLIENT. This is called from the middle of
    responder_service.update_location, which already holds one. Building a
    second here was wrong twice over: it constructs a client per ping for no
    reason, and it opens a second database seam that a caller's test cannot
    patch. The test suite caught the second one immediately — conftest blocks
    create_client with a BaseException specifically so that an unreachable
    seam cannot hide inside somebody's `except Exception`, which is exactly
    where this one landed.
    """
    db = db or get_supabase()

    active = (
        db.table("incidents")
        .select("id, location, status")
        .eq("assigned_responder_id", responder_id)
        .eq("status", "en_route")
        .execute()
        .data
        or []
    )

    updated: list[dict] = []
    now = _now()
    for row in active:
        i_lat, i_lng = _coords(row.get("location"))
        if i_lat is None:
            continue
        km = _distance_km(lat, lng, i_lat, i_lng)
        # The one ETA model, shared with the who-is-nearest ranking: rounded up,
        # never 0, capped at the column's CHECK.
        minutes = geo.estimate_eta_minutes(km)
        db.table("incidents").update({
            "eta_minutes": minutes,
            "eta_updated_at": now,
        }).eq("id", row["id"]).execute()
        updated.append({"incident_id": row["id"], "eta_minutes": minutes})

    return updated


# =============================================================================
# 5. Approach hazards
# =============================================================================

def hazards_near(
    lat: float,
    lng: float,
    radius_km: float = _HAZARD_SEARCH_KM,
    db: Client | None = None,
) -> list[dict]:
    """Standing local knowledge within reach of a set of coordinates.

    Filtered in Python rather than with ST_DWithin because this client cannot
    call a PostGIS function, and the active hazard set for one province is
    small enough that the difference is unmeasurable. If it ever is not, this
    becomes an RPC.

    Takes the caller's client for the same reason refresh_eta does — this
    runs inside responder_service.get_incident_detail, which already has one.
    """
    db = db or get_supabase()
    rows = (
        db.table("location_hazards")
        .select("id, location, radius_m, hazard_type, note, created_at")
        .eq("is_active", True)
        .execute()
        .data
        or []
    )

    near: list[dict] = []
    for row in rows:
        h_lat, h_lng = _coords(row.get("location"))
        if h_lat is None:
            continue
        km = _distance_km(lat, lng, h_lat, h_lng)
        # Either the hazard is within the search radius of the destination, or
        # the destination sits inside the hazard's own declared radius.
        if km <= radius_km or km * 1000 <= (row.get("radius_m") or 0):
            near.append({
                "id": row["id"],
                "hazard_type": row["hazard_type"],
                "note": row["note"],
                "distance_km": round(km, 2),
                "latitude": h_lat,
                "longitude": h_lng,
            })

    near.sort(key=lambda h: h["distance_km"])
    return near


def create_hazard(
    user: dict,
    latitude: float,
    longitude: float,
    hazard_type: str,
    note: str,
    radius_m: int = 300,
) -> dict:
    """Record something about getting to a place that the map cannot show."""
    if hazard_type not in _HAZARD_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown hazard type. Must be one of: {', '.join(sorted(_HAZARD_TYPES))}.",
        )
    if not (note or "").strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A hazard needs a note — the type alone tells the next crew nothing.",
        )
    if not (0 < radius_m <= 5000):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Radius must be between 1 and 5000 metres.",
        )

    db: Client = get_supabase()
    created = db.table("location_hazards").insert({
        "location": f"SRID=4326;POINT({longitude} {latitude})",
        "radius_m": radius_m,
        "hazard_type": hazard_type,
        "note": note.strip(),
        # Scoped to the author's agency. A hazard is not made province-wide by
        # a responder — that is an agency admin decision, made by clearing
        # agency_id, because a province-wide warning diverts everybody.
        "agency_id": user.get("agency_id"),
        "created_by": str(user["id"]),
    }).execute()

    if not created.data:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not save the hazard.",
        )

    log.info(
        "responder.hazard_created",
        hazard_id=created.data[0]["id"],
        created_by=str(user["id"]),
        hazard_type=hazard_type,
    )
    return created.data[0]


# =============================================================================
# 6. Responder distress
# =============================================================================

def raise_distress(
    responder_id: str,
    agency_id: str | None,
    kind: str = "panic",
    latitude: float | None = None,
    longitude: float | None = None,
    incident_id: str | None = None,
    note: str | None = None,
) -> dict:
    """The responder's own emergency.

    Every safety affordance in this product points at residents. The people who
    walk into the burning building have had none, on a device that is already a
    location-aware panic button for everybody else.

    THIS FUNCTION IS DELIBERATELY HARD TO FAIL. A missing location, an unknown
    agency, an incident_id that does not resolve — none of them refuse the
    signal, because the worst possible outcome here is a responder pressing the
    button and being told 422. Everything except the responder's own identity
    is optional, and the row is written even when it is nearly empty.
    """
    if kind not in ("panic", "no_movement"):
        kind = "panic"

    db: Client = get_supabase()
    payload: dict = {
        "responder_id": responder_id,
        "kind": kind,
        "agency_id": agency_id,
        "incident_id": incident_id,
        "note": (note or "").strip() or None,
    }
    if latitude is not None and longitude is not None:
        payload["location"] = f"SRID=4326;POINT({longitude} {latitude})"

    created = db.table("responder_distress").insert(payload).execute()

    log.error(
        "responder.distress_raised",
        responder_id=responder_id,
        kind=kind,
        incident_id=incident_id,
        has_location=latitude is not None,
    )

    if not created.data:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not raise the alert. Call your station on the radio now.",
        )
    return created.data[0]


#: How long a responder may be en_route with no fresh position before the
#: console asks about them.
#:
#: Twelve minutes, not three. The ordinary explanation for a quiet handset is a
#: phone in a cupholder in a barangay with no signal, which is most of this
#: province — so a short threshold would fire on almost every call and teach
#: dispatchers to ignore the one that mattered. This is tuned to be RARE.
_NO_MOVEMENT_MINUTES = 12


def _stale_responders(db: Client, staff: dict) -> list[dict]:
    """Responders who are en_route and have gone quiet.

    COMPUTED ON READ, NOT BY A SCHEDULER. There is no background job in this
    deployment and adding one for this would be the wrong trade: the signal is
    only ever acted on by a dispatcher looking at the console, so computing it
    when they look costs one query and needs no new infrastructure.

    Presented as a QUESTION rather than an alarm. Unlike a panic press, this is
    inference — and the ordinary cause is bad coverage, not a crew in trouble.
    Rendering it as loudly as a real distress signal would spend the console's
    one red bar on a phone in a cupholder.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=_NO_MOVEMENT_MINUTES)

    query = (
        db.table("incidents")
        .select(
            "id, dispatched_at, assigned_responder_id, assigned_agency_id, "
            "users!incidents_assigned_responder_id_fkey("
            "id, full_name, badge_id, phone_number, location, location_updated_at"
            ")"
        )
        .eq("status", "en_route")
    )
    if staff.get("role") == "agency_admin":
        query = query.eq("assigned_agency_id", str(staff.get("agency_id")))
    elif staff.get("role") == "provincial_admin":
        agency_ids = _agency_ids_for_type(db, staff.get("agency_type"))
        if not agency_ids:
            return []
        query = query.in_("assigned_agency_id", agency_ids)

    out: list[dict] = []
    for row in (query.execute().data or []):
        who = row.get("users") or {}
        if not isinstance(who, dict):
            continue

        last = who.get("location_updated_at")
        if not last:
            # No timestamp at all. Either the responder has never pinged, or
            # the position predates migration 024. Both are "unknown age", and
            # raising an alert on unknown age would fire on every historical
            # row the day this ships.
            continue

        try:
            seen = datetime.fromisoformat(str(last).replace("Z", "+00:00"))
        except (ValueError, TypeError):
            continue
        if seen.tzinfo is None:
            seen = seen.replace(tzinfo=timezone.utc)
        if seen > cutoff:
            continue

        lat, lng = _coords(who.get("location"))
        out.append({
            # Synthetic id. These rows are not in responder_distress — nothing
            # was inserted — so the console must not offer to "clear" one. The
            # prefix is what tells it apart.
            "id": f"stale:{row['id']}",
            "responder_id": who.get("id"),
            "incident_id": row["id"],
            "agency_id": row.get("assigned_agency_id"),
            "kind": "no_movement",
            "latitude": lat,
            "longitude": lng,
            "note": (
                f"No position reported for over {_NO_MOVEMENT_MINUTES} minutes "
                "while en route. Usually no signal — worth a radio check."
            ),
            "raised_at": last,
            "responder_name": who.get("full_name"),
            "responder_badge": who.get("badge_id"),
            "responder_phone": who.get("phone_number"),
        })
    return out


def list_open_distress(staff: dict) -> list[dict]:
    """Unresolved distress signals, for the dispatcher console.

    Agency-scoped for agency_admin, agency_type-scoped (every station of
    that type) for provincial_admin — the same rule every other
    dispatcher-facing read follows.
    """
    db: Client = get_supabase()
    query = (
        db.table("responder_distress")
        .select(
            "id, responder_id, incident_id, agency_id, kind, location, note, "
            "raised_at, users!responder_distress_responder_id_fkey("
            "full_name, badge_id, phone_number)"
        )
        .is_("cleared_at", "null")
        .order("raised_at", desc=True)
    )
    if staff.get("role") == "agency_admin":
        query = query.eq("agency_id", str(staff.get("agency_id")))
    elif staff.get("role") == "provincial_admin":
        agency_ids = _agency_ids_for_type(db, staff.get("agency_type"))
        if not agency_ids:
            return []
        query = query.in_("agency_id", agency_ids)

    rows = query.execute().data or []
    for row in rows:
        lat, lng = _coords(row.pop("location", None))
        row["latitude"], row["longitude"] = lat, lng
        who = row.pop("users", None) or {}
        row["responder_name"] = who.get("full_name")
        row["responder_badge"] = who.get("badge_id")
        row["responder_phone"] = who.get("phone_number")

    # Real presses first, always. An inferred no-movement warning must never
    # push an actual panic press below the fold.
    try:
        rows.extend(_stale_responders(db, staff))
    except Exception:
        # The inferred half is a nicety; the real signals are not. A failure
        # here must not take the panic presses down with it.
        log.warning("responder.stale_check_failed")

    return rows


def clear_distress(distress_id: str, staff: dict, note: str | None = None) -> dict:
    """Close a distress signal.

    Only a dispatcher or agency admin, never the responder and never a timeout.
    A distress signal that ages out on its own is a distress signal nobody
    answered, and the responder is the one person who might not be in a
    position to close it.
    """
    db: Client = get_supabase()
    existing = (
        db.table("responder_distress")
        .select("id, agency_id, cleared_at")
        .eq("id", distress_id)
        .maybe_single()
        .execute()
    )
    if existing is None or not existing.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Distress signal not found.",
        )

    row = existing.data
    if staff.get("role") in ("agency_admin", "provincial_admin"):
        assert_agency_scope(staff, str(row.get("agency_id") or ""))

    if row.get("cleared_at"):
        return {"id": distress_id, "cleared_at": row["cleared_at"], "already_cleared": True}

    now = _now()
    db.table("responder_distress").update({
        "cleared_at": now,
        "cleared_by": str(staff["id"]),
        "clear_note": (note or "").strip() or None,
    }).eq("id", distress_id).execute()

    log.info("responder.distress_cleared", distress_id=distress_id, cleared_by=str(staff["id"]))
    return {"id": distress_id, "cleared_at": now, "already_cleared": False}
