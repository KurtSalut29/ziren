"""
/dispatch — the dispatch console, for Agency Admins and Provincial Admins.

Every dispatch action is fully logged in dispatch_log (immutable audit trail).
dispatcher_id is always taken from the authenticated token — never from the body.

WHO MAY DO WHAT

Two dependencies, and the split between them is the point:

  _admin_read   agency_admin + provincial_admin. Everything that only looks.
  _dispatcher   agency_admin ONLY. Everything that commits an agency to act.

A Provincial Admin oversees every station of one agency_type across the
province and belongs to none of them individually. That is not a
technicality about a null column — it is what the role means, and it makes them
the wrong person to dispatch:

  - They have no responders of their own. `get_available_responders` is
    agency-scoped, so a Provincial Admin dispatching has to pick a stranger
    out of some other station's roster, with no idea who is actually near
    the incident or already committed to a call.
  - Accountability breaks. dispatch_log.agency_id records which agency owns a
    decision. A Provincial Admin's own agency_id is NULL, so falling back to
    the incident's assigned_agency_id would stamp an agency with a decision
    nobody in that agency made — and if the incident had no agency yet, wrote
    an empty string into a NOT NULL uuid column and 500'd.
  - It silently bypasses the scope checks. Every guard in dispatch_service is
    written `if role == "agency_admin"`, so without the explicit
    provincial_admin branches added alongside them a Provincial Admin would
    either be blocked entirely or pass straight through unscoped — see
    dispatch_service.py's own module docstring for the agency_type-scoped
    reads that replace that gap.

So the Provincial Admin sees all of their agency_type's activity and commits
none of it. Their equivalent action on the queue is spatial — see where an
incident sits relative to everything else — which is why the console offers
them "View on map" where an Agency Admin gets "Assign".

Two mutations stay open to them, and neither is a dispatch decision:
transcript correction (a data-quality fix that only re-scores while no human
has set a severity) and false-SOS flagging (platform abuse control against a
resident's account, not an instruction to an agency).

Routes:
  GET  /queue                       — Live incident queue (agency-scoped for Admin)
  GET  /queue/{id}                  — Full incident detail + dispatch log + responders
  GET  /queue/{id}/nearby-responders — Who is near this incident: distance, ETA, busy or free
  POST /queue/{id}/transcript       — Correct what the recogniser misheard
  POST /queue/{id}/accept           — Verification: confirm the report is real [agency_admin]
  POST /queue/{id}/reject           — Verification: reject + cancel (reason required) [agency_admin]
  POST /queue/{id}/request-clarification — Verification: ask reporter for more detail [agency_admin]
  POST /queue/{id}/assign           — Assign Responder + set severity   [agency_admin]
  POST /queue/{id}/override         — Override severity without reassigning [agency_admin]
  POST /queue/{id}/resolve          — Mark incident resolved            [agency_admin]
  POST /queue/{id}/cancel           — Cancel incident (requires reason) [agency_admin]
  POST /queue/{id}/flag-false-sos   — Flag SOS report as false alarm
  GET  /queue/{id}/notes            — Operational notes / Agency Communication thread
  POST /queue/{id}/notes            — Add a note [agency_admin]
  GET  /queue/{id}/narrative-report      — The post-resolution narrative report (the full IRF)
  PUT  /queue/{id}/narrative-report      — Create/update it [agency_admin]
  GET  /queue/{id}/narrative-report/pdf  — Printable PDF of it
  GET  /narrative-reports                — The library: every report, filterable by incident type
  GET  /responders                  — Available on_duty responders for an agency
"""

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from typing import Optional

from pydantic import BaseModel

from app.core.dependencies import require_role
from app.services import (
    dispatch_service, feedback_service, incident_narrative_service,
    incident_notes_service, responder_ops_service,
)

router = APIRouter()

#: Reads and non-dispatch actions. Both admin roles.
_admin_read = Depends(require_role("agency_admin", "provincial_admin"))

#: Anything that commits an agency to act. Agency Admin only — see the module
#: docstring for why a Provincial Admin is excluded rather than merely discouraged.
_dispatcher = Depends(require_role("agency_admin"))


# ── Request models ──────────────────────────────────────────

class AssignRequest(BaseModel):
    responder_id:       str
    chosen_severity:    str          # "critical" | "high" | "medium" | "low"
    suggested_severity: str | None = None
    override_reason:    str | None = None
    notes:              str | None = None
    # The dispatcher's own statement that they read the severity and the rule
    # behind it before sending a crew (evaluator finding #4). The severity is a
    # recommendation; this is where a person takes the decision.
    severity_confirmed: bool = False


class OverrideRequest(BaseModel):
    chosen_severity:    str
    suggested_severity: str | None = None
    override_reason:    str          # required for overrides
    notes:              str | None = None


class ResolveRequest(BaseModel):
    notes: str | None = None


class CancelRequest(BaseModel):
    reason: str          # required — cancellations must have a stated reason


class RejectReportRequest(BaseModel):
    reason: str          # required — rejections must have a stated reason


class ClarificationRequest(BaseModel):
    note: str            # required — what the agency needs clarified


# ── Endpoints ────────────────────────────────────────────────

@router.get("/queue")
def get_incident_queue(
    current_user: dict = _admin_read,
):
    """
    Live incident queue:
    - Agency Admin: incidents assigned to their agency only.
    - Provincial Admin: every agency of their own agency_type.

    Sorted: critical first, then by arrival time.
    Each incident carries a suggested_severity from the rubric engine.
    Excludes resolved and cancelled incidents.
    """
    return dispatch_service.get_incident_queue(dispatcher=current_user)


@router.get("/activity")
def get_incident_activity(
    days: int = Query(30, ge=1, le=90),
    current_user: dict = _admin_read,
):
    """
    Incidents created in the last `days`, **including resolved and cancelled**.

    Separate from /queue on purpose. /queue answers "what still needs doing"
    and so must exclude closed work; this answers "what happened", and so must
    include it. Charting the queue over time undercounts every past day,
    because anything already closed has dropped out of it.

    Trimmed to the fields a chart reads: the three lifecycle timestamps,
    status, severity, and agency.
    """
    return dispatch_service.get_incident_activity(dispatcher=current_user, days=days)


@router.get("/history")
def get_history(
    days: int = Query(30, ge=0, le=365, description="How far back to look; 0 = all time"),
    limit: int = Query(100, ge=1, le=100, description="Page size"),
    offset: int = Query(0, ge=0, description="Rows to skip"),
    status: str | None = Query(None, description="Exact status match, or \"open\" for everything not yet resolved or cancelled"),
    severity: str | None = Query(None, description="Exact severity match"),
    agency_type: str | None = Query(None, description="BFP, PNP or MDRRMO"),
    station_id: str | None = Query(None, description="Exact stations.id match — Provincial Admin's Station filter"),
    category: str | None = Query(None, description="Exact incident_category match"),
    date_from: str | None = Query(None, description="YYYY-MM-DD, inclusive — overrides `days`"),
    date_to: str | None = Query(None, description="YYYY-MM-DD, inclusive (whole day) — overrides `days`"),
    record_no: str | None = Query(
        None,
        min_length=1,
        max_length=24,
        # Letters, digits and hyphens only — the lookup becomes a LIKE pattern,
        # and a `%` or `_` from the caller would act as a wildcard. A 422 here
        # is visible to the caller; the service refuses the same set again.
        pattern=r"^[A-Za-z0-9-]+$",
        description="Record number or its prefix, e.g. ZIR-2026-000123 — overrides `days`",
    ),
    current_user: dict = _admin_read,
):
    """
    One page of incident history — every status, newest first.

    Distinct from /queue, which excludes resolved and cancelled by design, and
    from /activity, which returns a trimmed row shape for charts. Returns
    {items, total, counts}, where total is the match count BEFORE paging and
    counts describes the whole filtered window — see get_incident_history.

    `date_from`/`date_to` pick an exact calendar range (a day, a month via its
    first/last date, a year likewise) and take over from the rolling `days`
    window whenever either is set — see _date_window's docstring for why
    `date_to` includes the whole day rather than stopping at its midnight.
    `days=0` means all time, the same sentinel Operational Area uses.

    `limit` is capped at 100 by the signature rather than by the service, so an
    over-large request is a 422 the caller can see instead of a silent trim.
    """
    return dispatch_service.get_incident_history(
        current_user,
        days=days,
        limit=limit,
        offset=offset,
        status=status,
        severity=severity,
        agency_type=agency_type,
        station_id=station_id,
        category=category,
        date_from=date_from,
        date_to=date_to,
        record_no=record_no,
    )


@router.get("/queue/{incident_id}")
def get_incident_detail(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """
    Full incident detail for dispatch:
    - Raw report text + 5W1H wizard answers
    - Rubric-suggested severity
    - Reporter identity + trust indicators (is_verified, sos_warning_count)
    - Station + agency info
    - Dispatch history (dispatch_log entries for this incident)
    - Available on_duty Responders in the same agency
    """
    return dispatch_service.get_incident_detail_admin(
        incident_id=incident_id,
        dispatcher=current_user,
    )


class TranscriptCorrection(BaseModel):
    corrected_text: str


@router.get("/queue/{incident_id}/nearby-responders")
def get_nearby_responders(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """
    Every on-duty responder of the incident's agency, ranked by how well they fit
    it, with who has been told and who has answered.

    Distance is the ellipsoidal (Vincenty) distance from each responder's last
    FRESH position; a position older than ten minutes is treated as unknown rather
    than trusted. A responder already committed to a call is shown with that call,
    and is never alarmed for a new one unless it is more severe than what they hold
    - see app.services.proximity for the whole policy. Read-only: it assigns nothing.
    """
    return dispatch_service.get_nearby_responders(
        incident_id=incident_id,
        dispatcher=current_user,
    )


@router.post("/queue/{incident_id}/transcript")
def correct_transcript(
    incident_id: str,
    body: TranscriptCorrection,
    current_user: dict = _admin_read,
):
    """
    Fix what the recogniser misheard in the resident's recording.

    The dispatcher is playing the audio anyway and speaks the language. Unlike
    the resident — who was standing in front of the emergency — they have a
    minute to get it right.

    Re-scores the incident only while no severity has been set by hand.
    """
    return dispatch_service.correct_transcript(
        incident_id=incident_id,
        dispatcher=current_user,
        corrected_text=body.corrected_text,
    )


@router.get("/queue/{incident_id}/media")
def get_incident_media(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """
    Short-lived signed links to this incident's attachments.

    Chiefly the resident's voice note: the recording is what a dispatcher who
    speaks the language listens to, and it is the check on a transcript that
    may have read Waray or Bisaya wrong.

    Links expire in five minutes and are minted per request, so they are not
    cached and cannot be shared onward usefully.
    """
    return dispatch_service.get_incident_media(
        incident_id=incident_id,
        dispatcher=current_user,
    )


@router.get("/queue/{incident_id}/responder-position")
def get_responder_position(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """
    Where the responder assigned to this incident last reported being.

    {responder_id, full_name, lat, lng, updated_at}, with lat/lng null if they
    have not reported a position yet, or null overall when nobody is assigned.
    Small on purpose: the incident dialog asks for it every half minute while
    a crew is on the way, and re-reading the whole incident for one point
    would be the expensive way to move a dot.
    """
    return dispatch_service.get_responder_position(
        incident_id=incident_id,
        dispatcher=current_user,
    )


@router.get("/queue/{incident_id}/feedback")
def get_incident_feedback(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """
    The resident's own post-resolution rating (Resident spec Section 26), if
    they gave one. Returns null, not 404, when nothing has been submitted —
    most incidents never get one, since rating is optional, and that is not
    an error a dispatcher needs to see.
    """
    return feedback_service.get_feedback_for_admin(
        incident_id=incident_id,
        dispatcher=current_user,
    )


@router.post("/queue/{incident_id}/accept")
def accept_report(
    incident_id: str,
    current_user: dict = _dispatcher,
):
    """
    Verification step (Agency Admin spec Section 3): confirm this report is
    real. Does not assign a responder or change the incident's dispatch
    status — see dispatch_service.accept_report's docstring.
    """
    return dispatch_service.accept_report(incident_id=incident_id, dispatcher=current_user)


@router.post("/queue/{incident_id}/reject")
def reject_report(
    incident_id: str,
    body: RejectReportRequest,
    current_user: dict = _dispatcher,
):
    """
    Verification step: the report is not real (or not this agency's).
    Requires a reason. Also cancels the incident — see dispatch_service.
    reject_report's docstring for why.
    """
    return dispatch_service.reject_report(
        incident_id=incident_id, reason=body.reason, dispatcher=current_user,
    )


@router.post("/queue/{incident_id}/request-clarification")
def request_clarification(
    incident_id: str,
    body: ClarificationRequest,
    current_user: dict = _dispatcher,
):
    """
    Verification step: ask the reporter for more detail before deciding.
    Leaves the incident in the live queue — nothing has been decided yet.
    """
    return dispatch_service.request_clarification(
        incident_id=incident_id, note=body.note, dispatcher=current_user,
    )


@router.post("/queue/{incident_id}/assign")
def assign_incident(
    incident_id: str,
    body: AssignRequest,
    current_user: dict = _dispatcher,
):
    """
    Assign a Responder to an incident and record the dispatch.

    - Validates Responder is approved, on_duty, and in the same agency.
    - Writes to dispatch_log: suggested_severity vs chosen_severity, was_override flag.
    - Updates incident status → dispatched.

    Every override (chosen != suggested) must include override_reason.
    """
    if not body.severity_confirmed:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Confirm that you have checked the severity and the reason for it before dispatching.",
        )
    return dispatch_service.assign_responder(
        incident_id=incident_id,
        responder_id=body.responder_id,
        chosen_severity=body.chosen_severity,
        suggested_severity=body.suggested_severity,
        override_reason=body.override_reason,
        notes=body.notes,
        dispatcher=current_user,
    )


@router.post("/queue/{incident_id}/override")
def override_dispatch(
    incident_id: str,
    body: OverrideRequest,
    current_user: dict = _dispatcher,
):
    """
    Override the severity of an incident without reassigning.
    override_reason is required — every override must be justified.
    Writes to dispatch_log with was_override=True.
    """
    return dispatch_service.override_severity(
        incident_id=incident_id,
        chosen_severity=body.chosen_severity,
        suggested_severity=body.suggested_severity,
        override_reason=body.override_reason,
        notes=body.notes,
        dispatcher=current_user,
    )


@router.post("/queue/{incident_id}/resolve")
def resolve_incident(
    incident_id: str,
    body: ResolveRequest,
    current_user: dict = _dispatcher,
):
    """
    Mark an incident as resolved.
    Updates incident status → resolved, sets resolved_at timestamp.
    Writes to dispatch_log with action='resolved'.
    """
    return dispatch_service.resolve_incident(
        incident_id=incident_id,
        notes=body.notes,
        dispatcher=current_user,
    )


@router.post("/queue/{incident_id}/cancel")
def cancel_incident(
    incident_id: str,
    body: CancelRequest,
    current_user: dict = _dispatcher,
):
    """
    Cancel an incident. Requires a reason.
    Cannot cancel an already-resolved incident.
    Writes to dispatch_log with action='cancelled'.
    """
    return dispatch_service.cancel_incident(
        incident_id=incident_id,
        reason=body.reason,
        dispatcher=current_user,
    )


@router.post("/queue/{incident_id}/flag-false-sos")
def flag_false_sos(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """
    Flag an SOS report as a confirmed false alarm.
    Increments the reporter's sos_warning_count.
    At threshold 3, sets sos_suspended_until (+30 days).
    Only Agency Admin / Provincial Admin can flag.
    """
    return dispatch_service.flag_false_sos(
        incident_id=incident_id,
        dispatcher=current_user,
    )


class NoteRequest(BaseModel):
    body: str


@router.get("/queue/{incident_id}/notes")
def list_incident_notes(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """
    Operational notes / Agency Communication thread for one incident (Agency
    Admin spec Sections 5 and 18). Provincial Admin sees every note for
    their own agency_type (oversight); Agency Admin sees their own agency's.
    """
    return incident_notes_service.list_notes(incident_id=incident_id, actor=current_user)


@router.post("/queue/{incident_id}/notes")
def add_incident_note(
    incident_id: str,
    body: NoteRequest,
    current_user: dict = _dispatcher,
):
    """
    Add an operational note. Agency Admin only — Provincial Admin has
    oversight, not a seat in the conversation, same split as every dispatch action.
    """
    return incident_notes_service.add_note(incident_id=incident_id, actor=current_user, body=body.body)


class NarrativeReportRequest(BaseModel):
    # May be empty on a DRAFT (the form is long and is filled in over more than
    # one sitting); finalizing needs it. See save_narrative_report.
    narrative: str = ""
    reporting_person_name: Optional[str] = None
    incident_occurred_at: Optional[str] = None
    place_of_incident: Optional[str] = None
    prepared_by_name: Optional[str] = None
    investigator_name: Optional[str] = None
    reference_no: Optional[str] = None
    # The Incident Record Form's structured part: the reporting person, the
    # suspects, the victims, the certification and the station. Cleaned to the
    # form's own shape by the service before it is stored.
    details: Optional[dict] = None
    # False saves a draft. True marks it finalized without locking it —
    # see incident_narrative_service.save_narrative_report's doc comment.
    finalize: bool = False
    # Required when changing a report that is already finalized: why. The
    # previous version is kept beside it (evaluator finding #8).
    amendment_reason: Optional[str] = None


@router.get("/queue/{incident_id}/narrative-report")
def get_narrative_report(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """
    The post-resolution Narrative Report as {report, details_supported} —
    `report` is null if nobody has started one yet, and `details_supported` says
    whether this database can hold the form's detailed sections (migration 040).
    Provincial Admin sees their own agency_type's (oversight, read-only);
    Agency Admin sees their own agency's.
    """
    return incident_narrative_service.get_narrative_report(incident_id=incident_id, actor=current_user)


@router.put("/queue/{incident_id}/narrative-report")
def save_narrative_report(
    incident_id: str,
    body: NarrativeReportRequest,
    current_user: dict = _dispatcher,
):
    """
    Create or update the Narrative Report. Agency Admin only — the same
    population that can Resolve the incident this report is about.
    409s if the incident is not yet resolved.
    """
    return incident_narrative_service.save_narrative_report(
        incident_id=incident_id,
        actor=current_user,
        narrative=body.narrative,
        reporting_person_name=body.reporting_person_name,
        incident_occurred_at=body.incident_occurred_at,
        place_of_incident=body.place_of_incident,
        prepared_by_name=body.prepared_by_name,
        investigator_name=body.investigator_name,
        reference_no=body.reference_no,
        finalize=body.finalize,
        details=body.details,
        amendment_reason=body.amendment_reason,
    )


@router.get("/queue/{incident_id}/narrative-report/versions")
def list_narrative_report_versions(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """
    Earlier versions of a finalized Narrative Report, newest first: each is the
    report as it stood before a change, with who changed it, which fields and
    why. Empty when it was never changed after finalizing.
    """
    return incident_narrative_service.list_versions(incident_id=incident_id, actor=current_user)


@router.get("/narrative-reports")
def list_narrative_reports(
    category: str | None = Query(None, description="One incident type: fire, medical_trauma, vehicular, flood_landslide_calamity, domestic_dispute_crime or other"),
    report_status: str | None = Query(None, alias="status", description="draft or finalized"),
    days: int = Query(0, ge=0, le=3650, description="Reports saved in the last N days; 0 = all time"),
    date_from: str | None = Query(None, description="YYYY-MM-DD, inclusive — overrides `days`"),
    date_to: str | None = Query(None, description="YYYY-MM-DD, inclusive (whole day) — overrides `days`"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: dict = _admin_read,
):
    """
    The narrative report library: every report this agency (or, for a Provincial
    Admin, every station of their agency type) has written, newest first, with
    the counts that label its incident-type tabs.
    """
    return incident_narrative_service.list_narrative_reports(
        current_user,
        category=category,
        report_status=report_status,
        days=days,
        date_from=date_from,
        date_to=date_to,
        limit=limit,
        offset=offset,
    )


@router.get("/queue/{incident_id}/narrative-report/pdf")
def download_narrative_report_pdf(
    incident_id: str,
    current_user: dict = _admin_read,
):
    """Printable PDF of the saved Narrative Report. 404s if none exists yet."""
    content = incident_narrative_service.render_narrative_report_pdf(
        incident_id=incident_id, actor=current_user,
    )
    return Response(
        content=content,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="narrative-report-{incident_id[:8]}.pdf"'},
    )


@router.get("/responders")
def get_available_responders(
    agency_id: str = Query(..., description="UUID of the agency"),
    current_user: dict = _admin_read,
):
    """
    Return approved, on_duty Responders for the given agency.
    Agency Admins can only query their own agency.
    Provincial Admins can query any agency of their own agency_type.
    """
    return dispatch_service.get_available_responders(
        agency_id=agency_id,
        dispatcher=current_user,
    )


# -- Phase 6D: responder distress ----------------------------


class ClearDistressRequest(BaseModel):
    note: Optional[str] = None


@router.get("/distress")
def get_open_distress(
    current_user: dict = _admin_read,
):
    """
    Unresolved responder distress signals.

    The console side of the responder panic button. Agency-scoped for an
    Agency Admin, and to their own agency_type for a Provincial Admin - the same rule every other
    dispatcher-facing read follows.

    responder_distress is on the Realtime publication (migration 024), so the
    console learns about a press in the second it happens rather than on the
    next poll. This endpoint is the initial load and the fallback for a
    console whose socket has dropped.
    """
    return responder_ops_service.list_open_distress(staff=current_user)


@router.post("/distress/{distress_id}/clear")
def clear_distress(
    distress_id: str,
    body: ClearDistressRequest,
    current_user: dict = _admin_read,
):
    """
    Close a distress signal, once somebody has actually answered it.

    Only a dispatcher or agency admin, never the responder and never a
    timeout. A distress signal that ages out on its own is a distress signal
    nobody answered - and the responder is the one person who may not be in a
    position to close it themselves.
    """
    return responder_ops_service.clear_distress(
        distress_id=distress_id,
        staff=current_user,
        note=body.note,
    )
