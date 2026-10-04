"""
Responder service — incident queue, status updates, availability management.

Security contract:
  - All functions accept responder_id from the authenticated token (never from client).
  - Responders can only see incidents assigned to them (query-level filter + RLS).
  - Status transitions are validated server-side against a strict forward-only FSM:
      dispatched → en_route → arrived → resolved
  - Availability toggle is Responder-only (require_approved_responder enforced in router).
"""

from datetime import datetime, timedelta, timezone

import structlog
from fastapi import HTTPException, status
from supabase import Client

from app.db.supabase_client import get_supabase
from app.services import notification_service, responder_ack, responder_ops_service

log = structlog.get_logger()

# Valid responder status transitions — forward-only, no rollback
_VALID_TRANSITIONS: dict[str, list[str]] = {
    "dispatched": ["en_route"],
    "en_route":   ["arrived"],
    "arrived":    ["resolved"],
    # resolved is terminal — no further transitions
}

# Responder availability values
_VALID_AVAILABILITY = {"on_duty", "off_duty"}

# Attachments live in the same private bucket the dispatcher console reads.
_MEDIA_BUCKET = "incident-media"
_MEDIA_URL_TTL = 300

_AUDIO_EXT = (".m4a", ".aac", ".mp3", ".wav", ".ogg", ".opus")
_VIDEO_EXT = (".mp4", ".mov", ".3gp", ".webm")


# =============================================================================
# Public interface
# =============================================================================

def get_my_queue(responder_id: str) -> list[dict]:
    """
    Return all incidents currently assigned to this Responder.
    Ordered by severity (critical first), then created_at (oldest first).

    Only returns active incidents: dispatched, en_route, arrived.
    Resolved/cancelled incidents are excluded from the queue (use history endpoint).
    """
    db: Client = get_supabase()

    result = (
        db.table("incidents")
        .select(
            "id, report_text, status, severity, location_address, "
            "incident_category, landmark_note, victim_relationship, "
            "overlap_agencies, wizard_answers, sos_flagged, "
            "created_at, dispatched_at, "
            # Migration 024. Without these the phone cannot tell an
            # assignment it has already accepted from one still waiting,
            # and would show the ACCEPT button on both.
            "accepted_at, declined_at, declined_reason, decline_count, "
            "eta_minutes, backup_of_incident_id, "
            # The geometry, without which the crew has an address and no
            # point to navigate to. The queue never selected it, and the
            # phone reads json['latitude'] — a key these endpoints have
            # never sent — so the Navigate button had nothing but the
            # address string to work with.
            "location, "
            "stations(name, address, agencies(agency_type, municipality, name)), "
            "users!incidents_reporter_id_fkey(full_name, phone_number, is_verified, sos_warning_count)"
        )
        .eq("assigned_responder_id", responder_id)
        .in_("status", ["dispatched", "en_route", "arrived"])
        .order("created_at", desc=False)
        .execute()
    )

    rows = result.data or []

    # Sort by severity rank client-friendly (critical > high > medium > low > None)
    _SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, None: 4}
    rows.sort(key=lambda r: _SEVERITY_ORDER.get(r.get("severity"), 4))

    # The derived acceptance verdict, computed in exactly one place so the
    # responder's countdown and the dispatcher's OVERDUE badge can never
    # disagree. See responder_ack.
    return responder_ack.annotate(rows)


def get_incident_detail(incident_id: str, responder_id: str) -> dict:
    """
    Return full incident detail for a Responder-assigned incident.
    Raises 403 if the incident is not assigned to this Responder.
    Raises 404 if the incident does not exist.
    """
    db: Client = get_supabase()

    result = (
        db.table("incidents")
        .select(
            "*, "
            "stations(name, address, location, agencies(agency_type, municipality, name, contact_number)), "
            # Accessibility fields are included deliberately: a crew that knows
            # the reporter is deaf will not burn minutes on a voice callback,
            # and one that knows they use a wheelchair arrives prepared to
            # carry them. See migration 012.
            "users!incidents_reporter_id_fkey("
            "full_name, phone_number, is_verified, sos_warning_count, "
            "emergency_contact_name, emergency_contact_number, "
            "is_pwd, disability_types, accessibility_notes, "
            "preferred_contact_mode, verification_level, "
            "barangays(name, municipality)"
            ")"
        )
        .eq("id", incident_id)
        # maybe_single(), not single(): PostgREST raises PGRST116 on zero rows
        # rather than returning an empty result, which made the 404 below
        # unreachable and turned a missing incident into a 500.
        .maybe_single()
        .execute()
    )

    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    row = result.data
    if row.get("assigned_responder_id") != responder_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not assigned to this incident.",
        )

    row["ack"] = responder_ack.ack_state(row)

    # Standing local knowledge about reaching this place — cut bridges,
    # roads only a motorcycle fits down, dogs. A crew that learns about the
    # washed-out bridge by arriving at it has lost the call.
    lat, lng = responder_ops_service._coords(row.get("location"))
    row["hazards"] = (
        responder_ops_service.hazards_near(lat, lng, db=db)
        if lat is not None
        else []
    )

    return row


def update_incident_status(
    incident_id: str,
    responder_id: str,
    new_status: str,
) -> dict:
    """
    Advance an incident's status through the Responder FSM.
    Only forward transitions are allowed — see _VALID_TRANSITIONS.

    Returns the updated incident row.
    """
    db: Client = get_supabase()

    # Fetch current state
    result = (
        db.table("incidents")
        .select("id, status, assigned_responder_id, assigned_agency_id, reporter_id")
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )
    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    row = result.data
    if row.get("assigned_responder_id") != responder_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not assigned to this incident.",
        )

    current_status = row["status"]
    allowed_next = _VALID_TRANSITIONS.get(current_status, [])

    if new_status not in allowed_next:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Cannot transition from '{current_status}' to '{new_status}'. "
                f"Allowed: {allowed_next or ['none — terminal state']}."
            ),
        )

    moved_at = datetime.now(timezone.utc).isoformat()
    update_payload: dict = {"status": new_status}
    if new_status == "resolved":
        update_payload["resolved_at"] = moved_at

    updated = (
        db.table("incidents")
        .update(update_payload)
        .eq("id", incident_id)
        .execute()
    )

    log.info(
        "responder.status_updated",
        incident_id=incident_id,
        responder_id=responder_id,
        from_status=current_status,
        to_status=new_status,
    )

    # The resident hears about the crew's progress in the words for it.
    _RESIDENT_COPY = {
        "en_route": ("The responder is on the way", "The responder is heading to your location now."),
        "arrived": ("The responder has arrived", "The responder has reached your location."),
        "resolved": ("Your report was resolved", "The responder marked your report as resolved. You can rate the response from My Reports."),
    }
    if new_status in _RESIDENT_COPY:
        title, body = _RESIDENT_COPY[new_status]
        notification_service.notify_reporter(
            row.get("reporter_id"),
            incident_id=incident_id,
            type_=f"incident.{new_status}",
            title=title,
            body=body,
            at=moved_at,
        )

    agency_id = row.get("assigned_agency_id")
    if agency_id and new_status in ("arrived", "resolved"):
        try:
            notification_service.create_for_agency_role(
                str(agency_id), "agency_admin",
                type_=f"incident.{new_status}",
                title="Responder arrived at scene" if new_status == "arrived" else "Incident resolved",
                link=f"/incidents/{incident_id}",
            )
        except Exception:
            log.error("responder.status_notify_failed", incident_id=incident_id, exc_info=True)

    return updated.data[0] if updated.data else row


def set_availability(responder_id: str, availability: str) -> dict:
    """
    Toggle a Responder's on_duty / off_duty status.
    Only the Responder themselves can change their own availability.
    """
    if availability not in _VALID_AVAILABILITY:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid availability value. Must be one of: {_VALID_AVAILABILITY}.",
        )

    db: Client = get_supabase()

    result = (
        db.table("users")
        .update({"availability": availability})
        .eq("id", responder_id)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Responder not found.",
        )

    log.info(
        "responder.availability_changed",
        responder_id=responder_id,
        availability=availability,
    )

    return {"responder_id": responder_id, "availability": availability}


def get_incident_history(responder_id: str) -> list[dict]:
    """
    Return resolved/cancelled incidents previously assigned to this Responder.
    Ordered newest first. Paginated to last 50.
    """
    db: Client = get_supabase()

    result = (
        db.table("incidents")
        .select(
            "id, report_text, status, severity, location_address, "
            "incident_category, created_at, dispatched_at, resolved_at"
        )
        .eq("assigned_responder_id", responder_id)
        .in_("status", ["resolved", "cancelled"])
        .order("resolved_at", desc=True)
        .limit(50)
        .execute()
    )

    return result.data or []


# =============================================================================
# Attachments
# =============================================================================

def _media_kind(path: str) -> str:
    lowered = path.lower()
    if lowered.endswith(_AUDIO_EXT):
        return "audio"
    if lowered.endswith(_VIDEO_EXT):
        return "video"
    return "image"


def get_incident_media(incident_id: str, responder_id: str) -> list[dict]:
    """Short-lived signed links to one assigned incident's attachments.

    The voice note is why this exists, and its absence was a real gap: the
    dispatcher console has been able to play the resident's recording since
    Phase 6, and the crew actually driving to the scene could not. That is the
    wrong way round. A transcript can be wrong — the whole reason
    transcript correction exists — and the person who will be standing in front
    of the emergency in four minutes is the one who most needs to hear what was
    actually said, in the language it was said in.

    Same 5-minute TTL and per-request minting as the dispatcher's copy: a link
    pasted into a group chat has expired before anyone else opens it.

    Scoped to the incident the responder is assigned to, using the same check
    as get_incident_detail. Attachments are MORE sensitive than the report
    text, not less — a recording identifies the person who made it.
    """
    db: Client = get_supabase()

    result = (
        db.table("incidents")
        .select("id, media_urls, assigned_responder_id")
        .eq("id", incident_id)
        .maybe_single()
        .execute()
    )
    if result is None or not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found.")

    row = result.data
    if row.get("assigned_responder_id") != responder_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not assigned to this incident.",
        )

    items: list[dict] = []
    for path in row.get("media_urls") or []:
        if not path:
            continue
        try:
            signed = db.storage.from_(_MEDIA_BUCKET).create_signed_url(path, _MEDIA_URL_TTL)
            url = signed.get("signedURL") or signed.get("signedUrl")
        except Exception:
            # One unreadable object must not take the whole incident down with
            # it — the crew still gets the report and the other attachments.
            log.warning("responder.media_sign_failed", incident_id=incident_id, path=path)
            url = None
        items.append({"path": path, "url": url, "kind": _media_kind(path), "source": "reporter"})

    return items


# =============================================================================
# Location
# =============================================================================

def update_location(responder_id: str, lat: float, lng: float) -> dict:
    """Record a responder's last-known position.

    THE ENDPOINT MIGRATION 011 PROMISED AND NOBODY WROTE.

    That migration added `users.location`, a GIST-indexed PostGIS point, and
    its own header says it is "updated by the mobile app via
    PATCH /responder/location (endpoint added in Phase 6C backend work)". The
    column shipped. The endpoint did not. Nothing in this codebase has ever
    written to it.

    The consequence is quiet and total: /map/data selects on-duty responders
    with a location, so the dashboard map has been rendering zero responders
    since the day it was built, on a province where some of them are always on
    duty. An empty responder layer looks exactly like an empty responder layer
    — there is no error, no warning, and no way to tell "nobody is out" from
    "nobody has ever reported where they are".

    Written as WKT rather than GeoJSON because PostgREST casts a WKT string to
    geometry directly; a GeoJSON object would need ST_GeomFromGeoJSON and a
    function call this client cannot make.
    """
    if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Coordinates out of range.",
        )

    db: Client = get_supabase()

    result = (
        db.table("users")
        # SRID is stated explicitly. Migration 011 declares the column as
        # GEOMETRY(POINT, 4326), and an unqualified WKT string is SRID 0 —
        # which Postgres rejects against a typed column rather than silently
        # coercing, so leaving it off turns every ping into a 22023.
        .update({
            "location": f"SRID=4326;POINT({lng} {lat})",
            # Migration 024. Without a timestamp a stale position is
            # indistinguishable from a current one, and the no-movement check
            # in responder_ops_service has nothing to measure.
            "location_updated_at": datetime.now(timezone.utc).isoformat(),
        })
        .eq("id", responder_id)
        .eq("role", "responder")
        .execute()
    )

    if not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Responder not found.")

    # Turn the ping around and point it at the person waiting.
    #
    # A resident who reports an emergency has never been told anything
    # afterwards — not who is coming, not whether anyone is. The position
    # needed to answer that has been arriving here all along and being
    # written to a column only the dispatcher map reads.
    #
    # Failure here must never break the ping. The map layer depends on the
    # write above having happened, and an ETA is a nicety by comparison.
    try:
        etas = responder_ops_service.refresh_eta(responder_id, lat, lng, db=db)
    except Exception:
        log.warning("responder.eta_refresh_failed", responder_id=responder_id)
        etas = []

    return {
        "responder_id": responder_id,
        "latitude": lat,
        "longitude": lng,
        "eta_updates": etas,
    }


# =============================================================================
# Dashboard
# =============================================================================

#: How far back the "recent" figures look. A shift, not a career.
_STATS_DAYS = 30


def _own_availability(db: Client, responder_id: str) -> str | None:
    """on_duty / off_duty as stored, or None if it could not be read.

    None rather than a guess: the app keeps whatever it already shows, which
    is better than flipping a responder off duty because one read failed.
    """
    try:
        res = (
            db.table("users")
            .select("availability")
            .eq("id", responder_id)
            .maybe_single()
            .execute()
        )
    except Exception:
        log.warning("responder.availability_read_failed", responder_id=responder_id)
        return None
    row = res.data if res is not None and isinstance(res.data, dict) else {}
    value = row.get("availability")
    return value if value in _VALID_AVAILABILITY else None


def get_dashboard(responder_id: str) -> dict:
    """The numbers a responder's own dashboard is made of.

    Deliberately about THEM, not about the agency. A responder cannot dispatch,
    cannot reassign and cannot see anyone else's queue, so agency-wide totals
    would be a figure they can neither act on nor affect. What they can act on
    is: what is on me right now, how much of it is critical, how long the
    oldest one has been waiting, and what I have closed.

    `median_response_minutes` is median rather than mean on purpose. One
    incident that sat overnight because a road was cut drags a mean far enough
    to make a good month look bad, and a responder reading their own figures
    should see the typical call, not the worst one.
    """
    db: Client = get_supabase()

    since = (datetime.now(timezone.utc) - timedelta(days=_STATS_DAYS)).isoformat()

    active = (
        db.table("incidents")
        .select("id, severity, status, created_at, dispatched_at")
        .eq("assigned_responder_id", responder_id)
        .in_("status", ["dispatched", "en_route", "arrived"])
        .execute()
        .data
        or []
    )

    closed = (
        db.table("incidents")
        .select("id, severity, status, created_at, dispatched_at, resolved_at")
        .eq("assigned_responder_id", responder_id)
        .in_("status", ["resolved", "cancelled"])
        .gte("created_at", since)
        .limit(500)
        .execute()
        .data
        or []
    )

    now = datetime.now(timezone.utc)

    def _parse(value: str | None) -> datetime | None:
        if not value:
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None

    # Longest wait among what is still open. Answers "am I behind", which no
    # count of open incidents can.
    oldest_minutes = None
    for row in active:
        started = _parse(row.get("created_at"))
        if started:
            minutes = int((now - started).total_seconds() // 60)
            if oldest_minutes is None or minutes > oldest_minutes:
                oldest_minutes = minutes

    # Dispatch -> resolved, per closed incident. dispatched_at is the start,
    # not created_at: the responder is not accountable for the minutes an
    # incident spent waiting in a dispatcher's queue before it reached them.
    durations: list[float] = []
    for row in closed:
        if row.get("status") != "resolved":
            continue
        start = _parse(row.get("dispatched_at")) or _parse(row.get("created_at"))
        end = _parse(row.get("resolved_at"))
        if start and end and end > start:
            durations.append((end - start).total_seconds() / 60)

    median_minutes = None
    if durations:
        durations.sort()
        mid = len(durations) // 2
        median_minutes = (
            durations[mid]
            if len(durations) % 2
            else (durations[mid - 1] + durations[mid]) / 2
        )

    resolved_rows = [r for r in closed if r.get("status") == "resolved"]
    today = now.date()
    resolved_today = sum(
        1
        for r in resolved_rows
        if (d := _parse(r.get("resolved_at"))) and d.date() == today
    )

    return {
        # The duty state the server holds. The app never read it back: it
        # started every launch as off duty, so a responder who was on duty when
        # the app was closed came back with the switch showing "off", position
        # reporting never resumed, and the dispatcher's map kept showing them
        # on duty at wherever they had last been.
        "availability": _own_availability(db, responder_id),
        "active_count": len(active),
        "active_critical": sum(1 for r in active if r.get("severity") == "critical"),
        "en_route_count": sum(1 for r in active if r.get("status") == "en_route"),
        "on_scene_count": sum(1 for r in active if r.get("status") == "arrived"),
        "oldest_waiting_minutes": oldest_minutes,
        "resolved_today": resolved_today,
        "resolved_period": len(resolved_rows),
        "median_response_minutes": (
            round(median_minutes, 1) if median_minutes is not None else None
        ),
        "period_days": _STATS_DAYS,
    }
