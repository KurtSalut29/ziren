"""
Incident service — submit, fetch, and manage incident reports.

All reporter_id values come from the authenticated token,
never from the client request body.

Architecture note:
  submit_incident()  — normal multi-step report path (POST /incidents/)
  submit_sos()       — SOS quick-report path       (POST /incidents/sos)
  Both call _create_incident_row(), the single shared DB-write function,
  so the core insert logic is never duplicated.
"""

import math
import structlog
from datetime import datetime, timezone, timedelta
from fastapi import HTTPException, status
from supabase import Client

from app.core import geo
from app.db.supabase_client import get_supabase
from app.services import notification_service, proximity, triage_service
from app.models.incident import (
    IncidentResponse,
    IncidentStatus,
    IncidentSubmitRequest,
    SosSubmitRequest,
    SosResponse,
    SubmissionChannel,
    IncidentCategory,
)

log = structlog.get_logger()

# Split by responsibility (evaluator finding #23): these live in their own
# modules now and are re-exported here, so every existing import keeps working.
from app.services.incident_rows import (  # noqa: E402,F401
    _agency_type_of, _coords_of, _distance_km, _lat_of, _lng_of, _parse_dt, _parse_point,
    _row_to_response,
)
from app.services.incident_routing import (  # noqa: E402,F401
    REPORTER_LOCATION_COLUMNS, _extract_station_tuple, _is_missing_reporter_column,
    _reporter_location, _resolve_nearest_station, check_coverage,
)
from app.services.incident_standing import (  # noqa: E402,F401
    SOS_COOLDOWN_MINUTES, SOS_SUSPEND_THRESHOLD, SOS_SUSPENSION_DAYS, SOS_TRUST_FLAG_THRESHOLD,
    _refuse_if_suspended, _update_sos_timestamp, ensure_reporting_allowed,
)

# How long a withdrawn report stays visible in Trash before it is purged for
# good. Matches the confirmation copy shown at withdraw time on mobile — if
# this changes, that copy has to change with it.
TRASH_RETENTION_DAYS = 30

# Which agency an SOS category should prefer when picking a station.
# Mirrors NearestStationResolver.agencyFor in the mobile app's
# nearest_station.dart exactly, so a resident's tap means the same thing on
# both submission paths. `other` and unset are deliberately absent — nearest
# station of ANY agency, same as SOS behaved before this field existed.
SOS_AGENCY_FOR_CATEGORY: dict[IncidentCategory, str] = {
    IncidentCategory.fire:                     "BFP",
    IncidentCategory.domestic_dispute_crime:   "PNP",
    IncidentCategory.medical_trauma:           "MDRRMO",
    IncidentCategory.vehicular:                "MDRRMO",
    IncidentCategory.flood_landslide_calamity: "MDRRMO",
}


# =============================================================================
# Public interface
# =============================================================================

def submit_incident(
    request: IncidentSubmitRequest,
    reporter_id: str,
) -> IncidentResponse:
    """
    Normal multi-step incident report submission (POST /incidents/).

    station_id is OPTIONAL. When the reporter supplies one it is honoured
    (they explicitly overrode the suggestion); when omitted, the nearest
    active station is resolved server-side from their coordinates — the same
    logic the SOS path already used. This removes the station-picker step
    from the reporting wizard, which asked a person in an emergency to know
    which station covers them.

    Agency is always derived server-side from the resolved station, never
    from the client.

    submitted_via is always 'internet' here, never read from the request
    body — request.submitted_via is only what a client claims, and a phone
    must not be able to label its own report as anything else.
    """
    db: Client = get_supabase()

    ensure_reporting_allowed(db, reporter_id)

    if request.station_id is not None:
        # Reporter explicitly chose a station — honour it, but validate it exists.
        station_result = (
            db.table("stations")
            .select("id, agency_id")
            .eq("id", str(request.station_id))
            .single()
            .execute()
        )
        if not station_result.data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Selected station not found. Please choose a valid station.",
            )
        station_id = str(request.station_id)
        agency_id  = station_result.data["agency_id"]
    else:
        # No station supplied — resolve the nearest active one from coordinates.
        # The model validator guarantees coordinates are present in this branch.
        station_id, agency_id, _, _, _ = _resolve_nearest_station(
            db, request.latitude, request.longitude
        )

    row = _create_incident_row(
        db=db,
        reporter_id=reporter_id,
        report_text=request.report_text.strip(),
        station_id=station_id,
        agency_id=agency_id,
        latitude=request.latitude,
        longitude=request.longitude,
        location_address=request.location_address,
        media_urls=request.media_urls,
        submitted_via=SubmissionChannel.internet,
        incident_category=request.incident_category,
        wizard_answers=request.wizard_answers,
        overlap_agencies=[f.value for f in request.overlap_agencies] if request.overlap_agencies else None,
        landmark_note=request.landmark_note,
        victim_relationship=request.victim_relationship.value if request.victim_relationship else None,
        reporter_location=_reporter_location(request),
    )
    return _row_to_response(row)


def submit_sos(
    request: SosSubmitRequest,
    reporter_id: str,
) -> SosResponse:
    """
    SOS Quick-Report submission (POST /incidents/sos).

    Key differences from submit_incident():
    - No station_id from client — nearest active station resolved via PostGIS
      (falls back to Naval if coordinates unavailable), preferring a station
      that matches request.incident_category's agency when one is given.
    - No minimum report_text length — stored as "SOS" if no description given.
    - No media_urls — SOS path skips attachments for speed.
    - Additional anti-abuse checks: cooldown, suspension, warning tracking.
    - submitted_via = 'sos' for dashboard distinction.
    """
    db: Client = get_supabase()

    # ── 1. Fetch reporter profile (identity + anti-abuse fields) ──────────────
    profile_result = (
        db.table("users")
        .select("id, full_name, role, sos_warning_count, sos_suspended_until, sos_last_submitted_at, is_verified")
        .eq("id", reporter_id)
        .single()
        .execute()
    )
    if not profile_result.data:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Reporter profile not found.",
        )
    profile = profile_result.data

    # ── 2. Suspension check ───────────────────────────────────────────────────
    # One rule and one message for every kind of report - see
    # ensure_reporting_allowed.
    _refuse_if_suspended(profile.get("sos_suspended_until"))

    # ── 3. Cooldown check (server-side — client cooldown is advisory only) ────
    last_submitted = profile.get("sos_last_submitted_at")
    if last_submitted:
        last_dt = _parse_dt(last_submitted)
        elapsed = datetime.now(timezone.utc) - last_dt
        remaining = timedelta(minutes=SOS_COOLDOWN_MINUTES) - elapsed
        if remaining.total_seconds() > 0:
            minutes_left = math.ceil(remaining.total_seconds() / 60)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    f"You submitted an SOS report recently. "
                    f"Please wait {minutes_left} minute(s) before sending another. "
                    f"If this is an ongoing emergency, call 911 directly."
                ),
            )

    # ── 4. Resolve nearest station via PostGIS ────────────────────────────────
    agency_hint = SOS_AGENCY_FOR_CATEGORY.get(request.incident_category) \
        if request.incident_category else None
    station_id, agency_id, station_name, agency_type, municipality = \
        _resolve_nearest_station(
            db, request.latitude, request.longitude, agency_hint,
        )

    # ── 5. Build report text ──────────────────────────────────────────────────
    report_text = "SOS"
    if request.description:
        report_text = f"SOS — {request.description}"

    # ── 6. Trust indicator (informational — goes into the incident row) ───────
    warning_count = profile.get("sos_warning_count", 0)
    is_flagged    = warning_count >= SOS_TRUST_FLAG_THRESHOLD
    # The flag is stored in a dedicated column for the dashboard to surface
    # No automatic rejection — human dispatcher sees it and decides

    # ── 7. Write the incident row (shared internal function) ──────────────────
    row = _create_incident_row(
        db=db,
        reporter_id=reporter_id,
        report_text=report_text,
        station_id=station_id,
        agency_id=agency_id,
        latitude=request.latitude,
        longitude=request.longitude,
        location_address=request.location_address,
        media_urls=[],
        submitted_via=SubmissionChannel.sos,
        is_sos_flagged=is_flagged,
        incident_category=request.incident_category,
        landmark_note=request.landmark_note,
    )

    # ── 8. Update sos_last_submitted_at (marks cooldown start) ────────────────
    _update_sos_timestamp(db, reporter_id)

    log.info(
        "sos.submitted",
        incident_id=row["id"],
        reporter_id=reporter_id,
        station_id=station_id,
        flagged=is_flagged,
        warning_count=warning_count,
    )

    return SosResponse(
        id=row["id"],
        report_text=row["report_text"],
        status=row["status"],
        submitted_via=row["submitted_via"],
        created_at=row["created_at"],
        station_id=station_id,
        station_name=station_name,
        agency_type=agency_type,
        municipality=municipality,
        latitude=request.latitude,
        longitude=request.longitude,
    )


def record_false_sos(reporter_id: str, acting_dispatcher_id: str) -> dict:
    """
    Called by Agency Admin when marking an SOS report as a confirmed false alarm.
    Increments sos_warning_count; if threshold reached, sets sos_suspended_until.

    Returns the updated abuse fields for the dispatcher's audit log.
    Only call from a dispatcher-authenticated endpoint — never from mobile.
    """
    db: Client = get_supabase()

    profile_result = (
        db.table("users")
        .select("id, sos_warning_count, sos_suspended_until")
        .eq("id", reporter_id)
        .single()
        .execute()
    )
    if not profile_result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")

    profile       = profile_result.data
    new_count     = (profile.get("sos_warning_count") or 0) + 1
    suspended_until = profile.get("sos_suspended_until")

    update_payload: dict = {"sos_warning_count": new_count}

    # Escalating consequences
    if new_count >= SOS_SUSPEND_THRESHOLD and not suspended_until:
        # First time hitting the threshold — set suspension
        suspend_until_dt = datetime.now(timezone.utc) + timedelta(days=SOS_SUSPENSION_DAYS)
        update_payload["sos_suspended_until"] = suspend_until_dt.isoformat()
        log.warning(
            "sos.account_suspended",
            reporter_id=reporter_id,
            warning_count=new_count,
            suspended_until=suspend_until_dt.isoformat(),
            acting_dispatcher_id=acting_dispatcher_id,
        )

    db.table("users").update(update_payload).eq("id", reporter_id).execute()

    log.info(
        "sos.false_alarm_recorded",
        reporter_id=reporter_id,
        new_warning_count=new_count,
        acting_dispatcher_id=acting_dispatcher_id,
    )
    return {
        "reporter_id":     reporter_id,
        "warning_count":   new_count,
        "suspended_until": update_payload.get("sos_suspended_until"),
    }


def _purge_expired_trash(reporter_id: str) -> None:
    """
    Permanently delete this reporter's own withdrawn reports once they have
    sat in Trash for TRASH_RETENTION_DAYS.

    Run lazily, scoped to one reporter, on every My Reports fetch rather than
    as a standalone cron job — there is no scheduler in this process, and a
    sweep this narrow (one reporter, one status, one indexed timestamp) costs
    nothing extra to run on a read that was happening anyway. The trade-off is
    that a report expires the next time ITS OWN reporter opens the app, not at
    the exact instant it turns 30 days old — acceptable for a "will be
    deleted" notice, not acceptable for anything a dispatcher depends on,
    which is why this never touches a row anyone else can still act on
    (withdrawn incidents are already excluded from /dispatch/queue).
    """
    db: Client = get_supabase()
    cutoff = (datetime.now(timezone.utc) - timedelta(days=TRASH_RETENTION_DAYS)).isoformat()
    db.table("incidents").delete().eq("reporter_id", reporter_id).eq(
        "status", IncidentStatus.cancelled.value
    ).lt("withdrawn_at", cutoff).execute()


def get_my_incidents(reporter_id: str) -> list[IncidentResponse]:
    """Fetch all incidents submitted by the authenticated resident, newest first."""
    _purge_expired_trash(reporter_id)

    db: Client = get_supabase()
    result = (
        db.table("incidents")
        .select(
            "id, reporter_id, station_id, report_text, location_address, status, "
            "severity, suggested_agency_id, assigned_agency_id, signals, "
            "signals_confidence, submitted_via, created_at, updated_at, "
            "dispatched_at, resolved_at, withdrawn_at, incident_category, "
            # Migration 029: the agency's decision, so the app can say a report
            # was rejected (and why) instead of filing it under Trash.
            "review_status, reviewed_at, rejection_reason, clarification_note, "
            "clarification_requested_at, "
            # Migration 024. The reporter's half of the loop — see
            # IncidentResponse.eta_minutes.
            "eta_minutes, eta_updated_at, location, "
            "agencies!incidents_assigned_agency_id_fkey(agency_type)"
        )
        .eq("reporter_id", reporter_id)
        .order("created_at", desc=True)
        .execute()
    )
    return [_row_to_response(row) for row in (result.data or [])]


def get_incident_by_id(incident_id: str, reporter_id: str) -> IncidentResponse:
    """Get a single incident. Residents can only see their own."""
    db: Client = get_supabase()
    result = (
        db.table("incidents")
        .select("*")
        .eq("id", incident_id)
        .single()
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Incident not found.",
        )
    row = result.data
    if row["reporter_id"] != reporter_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this incident.",
        )
    return _row_to_response(row)


def withdraw_incident(
    incident_id: str,
    reporter_id: str,
    *,
    reason: str | None = None,
) -> IncidentResponse:
    """The resident takes back their own report.

    Why this exists
    ---------------
    A resident who tapped submit by mistake, or whose neighbour turned out to
    be fine, previously had no way to say so. The only cancel path was
    dispatcher-side, so a false report sat in the queue until somebody spent
    attention triaging it — attention that in a dispatch queue is the scarce
    thing.

    Withdrawn, not deleted
    ----------------------
    The row survives with status 'cancelled'. /dispatch/queue already excludes
    cancelled incidents, so it leaves the dispatcher's working queue, which is
    what a resident means by "delete it". What it does not do is destroy the
    record: an emergency report is an audit artefact, and a report that
    responders may have already read should not be erasable by the person who
    filed it.

    Guards
    ------
    Only the reporter, and only before anyone has acted. Once a dispatcher has
    moved the incident out of `received` — or an agency has been assigned —
    the resident can no longer pull it out from under them; a truck may already
    be moving. They are told to call the station instead, which is the only
    correct answer once a response is in flight.

    The same principle governs confirm_transcript and
    dispatch_service.correct_transcript: a human decision outranks a later
    automatic one.
    """
    db: Client = get_supabase()

    result = (
        db.table("incidents").select("*").eq("id", incident_id).single().execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found."
        )

    row = result.data
    if row["reporter_id"] != reporter_id:
        # Deliberately the same message get_incident_by_id gives, so this
        # cannot be used to probe which incident ids exist.
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this incident.",
        )

    if row.get("status") == IncidentStatus.cancelled.value:
        # Withdrawing twice is not an error worth failing a screen over.
        return _row_to_response(row)

    # What "help is already moving" actually means here.
    #
    # NOT assigned_agency_id. _create_incident_row sets that at submission from
    # the station's geography — it says which agency's queue the report belongs
    # in, not that anybody has acted on it. Reading it as a dispatch decision
    # made every report unwithdrawable the moment it was filed, which is how
    # this shipped the first time: the tests defaulted the field to None, which
    # no real row ever is, so they passed while production refused everything.
    #
    # The real signals are a status past `received`, a dispatch timestamp, or a
    # named responder — each of which means a person is committed.
    if (
        row.get("status") != IncidentStatus.received.value
        or row.get("dispatched_at")
        or row.get("assigned_responder_id")
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Help is already on the way for this report. Call the station "
                "to stand it down."
            ),
        )

    update = {
        "status": IncidentStatus.cancelled.value,
        "withdrawn_at": datetime.now(timezone.utc).isoformat(),
        "withdrawn_reason": (reason or "").strip() or None,
    }
    db.table("incidents").update(update).eq("id", incident_id).execute()

    log.info(
        "incident.withdrawn_by_reporter",
        incident_id=incident_id,
        reporter_id=reporter_id,
        had_reason=bool(update["withdrawn_reason"]),
    )
    return _row_to_response({**row, **update})


def confirm_transcript(
    incident_id: str,
    reporter_id: str,
    *,
    corrected_text: str | None = None,
) -> IncidentResponse:
    """The resident says whether we heard them right, and fixes it if not.

    Why this exists
    ---------------
    No recogniser reads Waray well. Measured on real recordings from a real
    handset: 51% word error rate, and the one clip that came out nearly
    perfect still lost the child left inside a burning house. Chasing a model
    that reads Waray correctly is chasing something that does not exist.

    The person who made the report is standing at the scene and knows the
    truth. Asking them costs two seconds and is the only source of certainty
    in the whole pipeline.

    What a correction does
    ----------------------
    Replaces the text, re-runs triage on it, and re-ranks the incident. The
    resident's own words outrank the machine's guess at them, always — that is
    the entire point.

    It also records the pair (what the machine heard, what was actually said)
    on the row. That pair is labelled Waray emergency speech, which is exactly
    the data that does not exist anywhere and the reason the recogniser is bad
    in the first place.

    Guards
    ------
    Only the reporter may confirm, and only while the incident is still
    untouched. Once a dispatcher has acted, rewriting the text underneath them
    would be worse than leaving it wrong — they have already read it and, if
    the recording mattered, listened to it.
    """
    db: Client = get_supabase()

    result = (
        db.table("incidents").select("*").eq("id", incident_id).single().execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found."
        )

    row = result.data
    if row["reporter_id"] != reporter_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this incident.",
        )

    signals = dict(row.get("signals") or {})
    transcript = dict(signals.get("transcript") or {})
    heard = transcript.get("text")

    said = (corrected_text or "").strip()
    if not said:
        # Confirmed as heard. Recorded because "the resident agreed" is itself
        # a label, and a transcript nobody objected to is evidence the
        # recogniser handled that utterance.
        transcript["confirmed_by_reporter"] = True
        signals["transcript"] = transcript
        db.table("incidents").update({"signals": signals}).eq(
            "id", incident_id
        ).execute()
        log.info("incident.transcript_confirmed", incident_id=incident_id)
        return _row_to_response({**row, "signals": signals})

    if row.get("status") != IncidentStatus.received.value:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "This report is already being handled. Call the station to "
                "correct it."
            ),
        )

    category = None
    if row.get("incident_category"):
        try:
            category = IncidentCategory(row["incident_category"])
        except ValueError:
            category = None

    update: dict = {"report_text": said}

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
        "confirmed_by_reporter": False,
        "note": (
            "The reporter corrected this transcript. Their wording is "
            "authoritative; `text` is what the recogniser produced."
        ),
    })
    signals["transcript"] = transcript
    update["signals"] = signals

    db.table("incidents").update(update).eq("id", incident_id).execute()
    log.info(
        "incident.transcript_corrected",
        incident_id=incident_id,
        severity=update.get("severity"),
        heard_chars=len(heard or ""),
        said_chars=len(said),
    )
    return _row_to_response({**row, **update})


# =============================================================================
# Internal helpers
# =============================================================================

def _create_incident_row(
    *,
    db: Client,
    reporter_id: str,
    report_text: str,
    station_id: str,
    agency_id: str,
    latitude: float | None,
    longitude: float | None,
    location_address: str | None,
    media_urls: list[str],
    submitted_via: SubmissionChannel,
    is_sos_flagged: bool = False,
    incident_category: "IncidentCategory | None" = None,
    wizard_answers: dict | None = None,
    overlap_agencies: list[str] | None = None,
    landmark_note: str | None = None,
    victim_relationship: str | None = None,
    reporter_location: dict | None = None,
) -> dict:
    """
    Single DB-write function for all incident submissions.

    Both submit_incident() and submit_sos() call this.
    Never call this directly from a router — always go through the
    public service functions so validation and auth checks are applied.

    is_sos_flagged: when True, sets sos_flagged=True on the row so the
    Agency Admin dashboard can surface the trust indicator.

    nlp_review_needed: set True when the report needs a human to look at the
    triage result before it is acted on — either the model could not read it,
    or the model's reading disagrees with what the resident selected.
    """
    location_wkt = None
    if latitude is not None and longitude is not None:
        location_wkt = f"POINT({longitude} {latitude})"

    # Phase 4 NLP pipeline — the trained model runs inline, before the insert,
    # so the dispatcher queue is ordered by severity from the moment the report
    # lands. There is no background pass and no second write.
    #
    # triage() never raises and never blocks the save. When it returns None the
    # report is stored with severity NULL, which the queue already renders as
    # "needs human triage". A resident in an emergency must never lose their
    # report because a classifier is down.
    triage_result = triage_service.triage(
        report_text=report_text,
        incident_category=incident_category,
        wizard_answers=wizard_answers,
        overlap_agencies=overlap_agencies,
        landmark_note=landmark_note,
    )

    if triage_result is None:
        severity = None
        signals = None
        # Nothing was read, so a human has to read it.
        nlp_review_needed = True
        log.warning(
            "incident.triage_unavailable",
            reporter_id=reporter_id,
            reason=triage_service.status().get("error"),
        )
    else:
        severity = (
            triage_result["severity"].value if triage_result["severity"] else None
        )
        signals = triage_result["signals"]
        # The resident is at the scene and the model is not, so a mismatch is
        # never resolved silently — it is raised for the dispatcher to settle.
        nlp_review_needed = (
            signals["verification_status"] == "MISMATCH_FLAGGED"
            or severity is None
        )
        log.info(
            "incident.triaged",
            reporter_id=reporter_id,
            severity=severity,
            rule=signals["severity_rule"],
            verification=signals["verification_status"],
            engine_version=signals["engine_version"],
        )

    insert_payload = {
        "reporter_id":        reporter_id,
        "station_id":         station_id,
        "assigned_agency_id": agency_id,
        "report_text":        report_text,
        "location":           location_wkt,
        "location_address":   location_address,
        "status":             IncidentStatus.received.value,
        "submitted_via":      submitted_via.value,
        "media_urls":         media_urls,
        "severity":           severity,
        "signals":            signals,
        "sos_flagged":        is_sos_flagged,
        # 5W1H wizard fields
        "incident_category":   incident_category.value if incident_category else None,
        "wizard_answers":      wizard_answers,
        "overlap_agencies":    overlap_agencies,
        "landmark_note":       landmark_note,
        "victim_relationship": victim_relationship,
        "nlp_review_needed":   nlp_review_needed,
    }
    if reporter_location:
        insert_payload.update(reporter_location)

    try:
        result = db.table("incidents").insert(insert_payload).execute()
    except Exception as e:
        if reporter_location and _is_missing_reporter_column(e):
            # Migration 042 not applied yet. The incident itself is what
            # matters; save it without the reporter's position rather than
            # lose the report over a column that does not exist yet.
            log.warning("incident.reporter_location_columns_missing", reporter_id=reporter_id)
            for key in reporter_location:
                insert_payload.pop(key, None)
            try:
                result = db.table("incidents").insert(insert_payload).execute()
            except Exception as e2:
                log.error("incident.create_failed", reporter_id=reporter_id, error=str(e2))
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Failed to save incident report. Please try again.",
                )
        else:
            log.error("incident.create_failed", reporter_id=reporter_id, error=str(e))
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to save incident report. Please try again.",
            )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Incident was not saved.",
        )

    row = result.data[0]

    # Tell the receiving agency's dispatchers a report just landed. Agency
    # Admin's bell was otherwise silent for the one event they most need to
    # hear about first — nothing upstream of this call notifies anyone.
    if agency_id:
        try:
            notification_service.create_for_agency_role(
                str(agency_id), "agency_admin",
                type_="incident.received",
                title="New incident received",
                body=(location_address or "Location not provided")[:140],
                link=f"/incidents/{row['id']}",
                is_important=(severity == "critical"),
            )
        except Exception:
            log.error("incident.notify_failed", incident_id=row.get("id"), exc_info=True)

    # And the responders near it, at the same moment - without waiting for a
    # dispatcher to assign them. notify_nearby already never raises; the try is a
    # second lock on the same door, because the report is saved and the admins
    # told, and nothing about a ranking may cost the resident their report.
    try:
        proximity.notify_nearby(db, row, lat=latitude, lng=longitude)
    except Exception:
        log.error("incident.nearby_notify_failed", incident_id=row.get("id"), exc_info=True)

    return row


