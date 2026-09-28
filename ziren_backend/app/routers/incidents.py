"""
/incidents — Incident reporting endpoints.

Residents submit reports and track their own.
Dispatchers/admins see all incidents (enforced by RLS + RBAC).

Routes:
  POST /           — normal multi-step report (station required, min 10 chars)
  POST /sos        — SOS quick-report (no station, no min chars, PostGIS auto-routing)
  GET  /my         — reporter's own incident list
  GET  /{id}       — single incident (reporter-scoped)
"""

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request

from pydantic import BaseModel, Field

from app.core.config import settings
from app.core.rate_limit import limiter
from app.core.dependencies import get_current_user
from app.db.supabase_client import get_supabase
from app.models.incident import IncidentResponse, IncidentSubmitRequest, SosSubmitRequest, SosResponse
from app.services import feedback_service, incident_notes_service, incident_service, transcription_service

router = APIRouter()


@router.post("/", response_model=IncidentResponse, status_code=201)
@limiter.limit(settings.rate_limit_incident_submit)
def submit_incident(
    request: Request,
    background: BackgroundTasks,
    body: IncidentSubmitRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Submit a new incident report (normal multi-step flow).
    Only residents and approved responders can submit.
    reporter_id is taken from the authenticated token, never from the body.
    """
    if current_user.get("role") not in ("resident", "responder"):
        from fastapi import HTTPException, status as http_status
        raise HTTPException(
            status_code=http_status.HTTP_403_FORBIDDEN,
            detail="Only residents can submit incident reports.",
        )

    incident = incident_service.submit_incident(
        request=body,
        reporter_id=str(current_user["id"]),
    )

    # If the resident recorded their voice, recover the words from it — after
    # this response has been sent, never before. The report is already saved
    # and the dispatcher can already play the recording; the transcript arrives
    # a moment later and re-ranks the incident in the queue.
    transcription_service.schedule(background, incident.id, body.media_urls)

    return incident


@router.post("/sos", response_model=SosResponse, status_code=201)
@limiter.limit(settings.rate_limit_sos_submit)
def submit_sos(
    request: Request,
    body: SosSubmitRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    SOS Quick-Report — fast path for life-threatening emergencies.

    Differences from POST /:
    - No station_id: nearest station resolved server-side via PostGIS
    - No minimum report_text length
    - No media attachments (speed over evidence)
    - Stricter rate limiting (see rate_limit_sos_submit in config)
    - Server-side cooldown + suspension check (in service layer)
    - Reporter identity always attached — no anonymous SOS

    Only residents can submit SOS reports.
    Responders and admin roles use their own dedicated flows.
    """
    if current_user.get("role") != "resident":
        from fastapi import HTTPException, status as http_status
        raise HTTPException(
            status_code=http_status.HTTP_403_FORBIDDEN,
            detail="SOS reports can only be submitted by Resident accounts.",
        )

    return incident_service.submit_sos(
        request=body,
        reporter_id=str(current_user["id"]),
    )


@router.get("/coverage-check")
def check_station_coverage(
    station_id: str = Query(..., description="UUID of the selected station"),
    lat:        float = Query(..., ge=-90,  le=90),
    lng:        float = Query(..., ge=-180, le=180),
    current_user: dict = Depends(get_current_user),
):
    """
    Phase 9 — Coverage-area validation (informational, never blocks submission).

    Returns whether the given GPS coordinates fall within the coverage polygon
    of the agency that owns the selected station.  The mobile client shows a
    mismatch warning in the report form UI; the dispatcher sees it on the
    incident detail view.

    Requires authentication — never exposes coverage data to anonymous callers.
    Fail-open: if PostGIS is unavailable, returns within_coverage=True.
    """
    db = get_supabase()
    return incident_service.check_coverage(
        station_id=station_id,
        lat=lat,
        lng=lng,
        db=db,
    )


@router.get("/my", response_model=list[IncidentResponse])
def get_my_incidents(
    current_user: dict = Depends(get_current_user),
):
    """
    Get all incidents submitted by the authenticated resident.
    Ordered newest first.
    """
    return incident_service.get_my_incidents(
        reporter_id=str(current_user["id"]),
    )


class TranscriptConfirmRequest(BaseModel):
    """Empty text means "you heard me right"."""

    corrected_text: str | None = None


@router.post("/{incident_id}/confirm", response_model=IncidentResponse)
def confirm_transcript(
    incident_id: str,
    body: TranscriptConfirmRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    The resident confirms or corrects what we heard in their recording.

    They are at the scene and the recogniser is not. Their wording replaces
    the machine's, the incident is re-ranked on it, and the pair is kept as
    labelled speech data.
    """
    return incident_service.confirm_transcript(
        incident_id=incident_id,
        reporter_id=str(current_user["id"]),
        corrected_text=body.corrected_text,
    )


class WithdrawRequest(BaseModel):
    """A reason is welcome, never required."""

    reason: str | None = Field(None, max_length=500)


@router.post("/{incident_id}/withdraw", response_model=IncidentResponse)
def withdraw_incident(
    incident_id: str,
    body: WithdrawRequest | None = None,
    current_user: dict = Depends(get_current_user),
):
    """
    The resident takes back their own report.

    Sets the incident to `cancelled`, which removes it from the dispatcher's
    queue (/dispatch/queue excludes cancelled by design) while keeping the row
    as an audit record. Allowed only while the report is still `received` and
    unassigned — once responders are moving, the resident is told to call the
    station instead of pulling it out from under them.
    """
    return incident_service.withdraw_incident(
        incident_id=incident_id,
        reporter_id=str(current_user["id"]),
        reason=(body.reason if body else None),
    )


@router.get("/{incident_id}", response_model=IncidentResponse)
def get_incident(
    incident_id: str,
    current_user: dict = Depends(get_current_user),
):
    """
    Get a single incident by ID.
    Residents can only access their own reports.
    """
    return incident_service.get_incident_by_id(
        incident_id=incident_id,
        reporter_id=str(current_user["id"]),
    )


class ResidentNoteRequest(BaseModel):
    body: str = Field(..., min_length=1, max_length=1000)


@router.get("/{incident_id}/notes")
def list_own_incident_notes(
    incident_id: str,
    current_user: dict = Depends(get_current_user),
):
    """
    Resident spec Sections 14 and 16 — the same thread the agency side reads
    and writes on dispatch.py's /queue/{id}/notes, scoped here to the
    reporter's own incident. See incident_notes_service and migration 031.
    """
    return incident_notes_service.list_notes(incident_id=incident_id, actor=current_user)


@router.post("/{incident_id}/notes", status_code=201)
def add_own_incident_note(
    incident_id: str,
    body: ResidentNoteRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Add a follow-up to the resident's own incident — "Add Information to an
    Existing Report" (Section 14) is the same act as "Incident-Specific
    Communication" (Section 16) from the reporter's side: a message on the
    thread, not a second report.
    """
    return incident_notes_service.add_note(incident_id=incident_id, actor=current_user, body=body.body)


class FeedbackRequest(BaseModel):
    rating: int = Field(..., ge=1, le=5)
    comment: str | None = Field(None, max_length=1000)


@router.get("/{incident_id}/feedback")
def get_own_feedback(
    incident_id: str,
    current_user: dict = Depends(get_current_user),
):
    """
    Whether (and what) the reporter already rated this incident — the mobile
    app calls this before showing the "rate your experience" prompt so it is
    never shown twice. Returns null, not 404, when nothing has been given yet.
    """
    return feedback_service.get_my_feedback(
        incident_id=incident_id,
        reporter_id=str(current_user["id"]),
    )


@router.post("/{incident_id}/feedback", status_code=201)
def submit_feedback(
    incident_id: str,
    body: FeedbackRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Resident spec Section 26 — optional, one-shot, post-resolution rating.
    Never consulted by triage or dispatch ordering — see migration 032.
    """
    return feedback_service.submit_feedback(
        incident_id=incident_id,
        reporter_id=str(current_user["id"]),
        rating=body.rating,
        comment=body.comment,
    )
