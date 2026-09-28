"""
/responder — Responder-facing incident queue and status management.

All endpoints require an approved Responder account (require_approved_responder).
Responders can only see and update incidents assigned to them — enforced at
both the service layer (query filter) and database layer (RLS policies).

Routes:
  GET   /dashboard         — The responder's own figures (see get_dashboard)
  GET   /queue             — Active assigned incidents (dispatched/en_route/arrived)
  GET   /queue/{id}        — Full detail for one assigned incident
  GET   /queue/{id}/media  — Signed links to the resident's voice note / photos
  PATCH /queue/{id}/status — Advance status (dispatched→en_route→arrived→resolved)
  PATCH /availability      — Toggle on_duty / off_duty
  PATCH /location          — Last-known GPS position (drives the dashboard map)
  GET   /history           — Past resolved/cancelled assignments (last 50)
  GET   /nearby            — Undispatched incidents NEAR me that I should know about
  POST  /nearby/{id}/answer — "I can respond" / "not available" (tells the dispatcher; assigns nothing)

  Phase 6D — the responder stops being a write-only endpoint (migration 024):
  POST  /queue/{id}/accept       — "I am taking this call"
  POST  /queue/{id}/decline      — hand it back, with a reason
  POST  /queue/{id}/close        — resolve WITH an after-action disposition
  POST  /queue/{id}/scene-media  — attach photos taken on scene
  POST  /queue/{id}/backup       — request mutual aid from another agency
  POST  /queue/{id}/escalate     — flag "worse than assessed" to the Agency Admin,
                                   without changing the incident's own severity
  GET   /hazards                 — standing local knowledge near a point
  POST  /hazards                 — record some
  POST  /distress                — the responder's own panic button

  GET   /queue/{id}/notes  — Operational notes / Agency Communication thread
  POST  /queue/{id}/notes  — Add a note. No mobile screen calls this yet —
                             see migration 030's header — but the endpoint
                             and its RLS policy are ready for one.
"""

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from typing import Optional

from app.core.dependencies import require_approved_responder
from app.db.supabase_client import get_supabase
from app.services import (
    incident_notes_service, proximity, responder_ops_service, responder_service,
)

router = APIRouter()

_responder_only = Depends(require_approved_responder)


class StatusUpdateRequest(BaseModel):
    status: str  # "en_route" | "arrived" | "resolved"


class AvailabilityRequest(BaseModel):
    availability: str  # "on_duty" | "off_duty"


class AcceptRequest(BaseModel):
    # Sent only by the offline queue. The ordinary online path posts an
    # empty body and the server uses its own clock.
    occurred_at: Optional[str] = None


class DeclineRequest(BaseModel):
    # Constrained rather than free text so the dispatcher can act on it in
    # one glance and so the reasons aggregate — "vehicle_down" twenty times
    # in a month is a fleet finding, not twenty anecdotes.
    reason: str
    note: Optional[str] = None


class CloseRequest(BaseModel):
    outcome: str
    outcome_notes: Optional[str] = None
    # Counts, not flags. NULL and 0 mean different things and both are
    # kept: NULL is "not recorded", 0 is "we counted, nobody was hurt".
    casualties_injured: Optional[int] = Field(None, ge=0)
    casualties_fatal: Optional[int] = Field(None, ge=0)
    casualties_transported: Optional[int] = Field(None, ge=0)
    occurred_at: Optional[str] = None


class SceneMediaRequest(BaseModel):
    paths: list[str]


class BackupRequest(BaseModel):
    agency_type: str          # BFP | PNP | MDRRMO
    reason: str


class EscalateRequest(BaseModel):
    reason: str


class HazardRequest(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    hazard_type: str
    note: str
    radius_m: int = Field(300, gt=0, le=5000)


class DistressRequest(BaseModel):
    # EVERY FIELD IS OPTIONAL, including the location. A responder pressing
    # this button must never be answered with a 422 because their GPS had
    # not fixed yet.
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    incident_id: Optional[str] = None
    note: Optional[str] = None


class NearbyAnswerRequest(BaseModel):
    # "can_respond" | "unavailable" - validated in the service so the 422 names
    # the allowed values.
    answer: str
    # The phone's own reading, so the dispatcher is told the distance from where
    # the responder actually is rather than from the last two-minute ping.
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)


class LocationRequest(BaseModel):
    # Bounds are declared here as well as checked in the service. The service
    # check is the real one — it also runs for any future caller — but a 422
    # from the signature names the offending field, which a hand-written check
    # cannot do as cleanly.
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


@router.get("/dashboard")
def get_dashboard(
    current_user: dict = _responder_only,
):
    """
    The responder's own figures: what is on them now, and what they have closed.

    Scoped to this responder alone. An agency-wide total would be a number they
    can neither act on nor affect — they cannot dispatch, reassign, or see
    another responder's queue.
    """
    return responder_service.get_dashboard(
        responder_id=str(current_user["id"]),
    )


@router.get("/queue")
def get_my_queue(
    current_user: dict = _responder_only,
):
    """
    Return all active incidents assigned to this Responder.
    Sorted: critical first, then by creation time (oldest first).
    Only includes dispatched / en_route / arrived incidents.
    """
    return responder_service.get_my_queue(
        responder_id=str(current_user["id"]),
    )


@router.get("/queue/{incident_id}")
def get_incident_detail(
    incident_id: str,
    current_user: dict = _responder_only,
):
    """
    Full incident detail for a single assigned incident.
    Includes reporter identity, station details, and wizard answers.
    Returns 403 if the incident is not assigned to this Responder.
    """
    return responder_service.get_incident_detail(
        incident_id=incident_id,
        responder_id=str(current_user["id"]),
    )


@router.get("/queue/{incident_id}/media")
def get_incident_media(
    incident_id: str,
    current_user: dict = _responder_only,
):
    """
    Short-lived signed links to the resident's attachments — chiefly the voice
    note.

    The dispatcher console has had this since Phase 6 and the crew did not,
    which is backwards: a transcript can be wrong, and the person about to
    arrive at the scene is the one who most needs to hear what was actually
    said. Links expire in five minutes and are minted per request.
    """
    return responder_service.get_incident_media(
        incident_id=incident_id,
        responder_id=str(current_user["id"]),
    )


class NoteRequest(BaseModel):
    body: str


@router.get("/queue/{incident_id}/notes")
def list_incident_notes(
    incident_id: str,
    current_user: dict = _responder_only,
):
    """Operational notes / Agency Communication thread for this incident."""
    return incident_notes_service.list_notes(incident_id=incident_id, actor=current_user)


@router.post("/queue/{incident_id}/notes")
def add_incident_note(
    incident_id: str,
    body: NoteRequest,
    current_user: dict = _responder_only,
):
    """Add a note to this incident's thread."""
    return incident_notes_service.add_note(incident_id=incident_id, actor=current_user, body=body.body)


@router.patch("/queue/{incident_id}/status")
def update_incident_status(
    incident_id: str,
    body: StatusUpdateRequest,
    current_user: dict = _responder_only,
):
    """
    Advance the incident through the Responder FSM:
      dispatched → en_route → arrived → resolved

    Only forward transitions are allowed — no rollback.
    Resolved is a terminal state.
    Returns 422 for invalid transitions.
    Returns 403 if the incident is not assigned to this Responder.
    """
    return responder_service.update_incident_status(
        incident_id=incident_id,
        responder_id=str(current_user["id"]),
        new_status=body.status,
    )


@router.patch("/availability")
def set_availability(
    body: AvailabilityRequest,
    current_user: dict = _responder_only,
):
    """
    Toggle the Responder's availability: on_duty or off_duty.
    Only the Responder themselves can change their own availability.
    Agency Admins can change availability via the /users admin endpoint.
    """
    return responder_service.set_availability(
        responder_id=str(current_user["id"]),
        availability=body.availability,
    )


@router.get("/history")
def get_incident_history(
    current_user: dict = _responder_only,
):
    """
    Return the last 50 resolved/cancelled incidents assigned to this Responder.
    Ordered by resolved_at descending.
    """
    return responder_service.get_incident_history(
        responder_id=str(current_user["id"]),
    )


@router.patch("/location")
def update_location(
    body: LocationRequest,
    current_user: dict = _responder_only,
):
    """
    Record this responder's last-known position.

    The endpoint migration 011 said would exist and never did. `users.location`
    has been on the schema, indexed, and empty ever since — so /map/data, which
    selects on-duty responders that have one, has always rendered an empty
    responder layer. That failure is invisible from the dashboard: no responder
    on the map looks identical whether nobody is out or nobody has ever
    reported where they are.

    Fire-and-forget from the client's point of view. A ping that fails must
    never interrupt a responder driving to a scene, so the mobile side
    swallows the error and tries again on the next tick.
    """
    return responder_service.update_location(
        responder_id=str(current_user["id"]),
        lat=body.latitude,
        lng=body.longitude,
    )


# -- Nearby: told about an incident before being dispatched to it -----------


@router.get("/nearby")
def get_nearby(
    latitude: Optional[float] = Query(None, ge=-90, le=90),
    longitude: Optional[float] = Query(None, ge=-180, le=180),
    current_user: dict = _responder_only,
):
    """
    Undispatched incidents near this responder that they should know about.

    Until now a responder heard about an incident only once a dispatcher assigned
    it, and every second the dispatcher spent choosing a crew was a second nobody
    was moving. Responders on duty near a new report are now told at the same
    moment as the agency.

    Distance is ellipsoidal (Vincenty, WGS-84), measured from the phone's own
    position when it sends one (`latitude`/`longitude`), else the last reported
    one. A responder who is free is alarmed; one who is already committed to a call
    is told only when the new incident is MORE severe than what they hold (or
    nobody free is close), and quietly - and is never reassigned. See
    app.services.proximity for the whole policy.
    """
    return proximity.nearby_for_responder(
        get_supabase(), current_user, lat=latitude, lng=longitude,
    )


@router.post("/nearby/{incident_id}/answer")
def answer_nearby(
    incident_id: str,
    body: NearbyAnswerRequest,
    current_user: dict = _responder_only,
):
    """
    Reply to a nearby-incident alert: "can_respond" or "unavailable".

    `can_respond` tells the agency's admins who is ready and how long they would
    take. It does NOT take the call: the dispatcher decides and assigns, exactly
    as before. 409 once someone has been assigned.
    """
    return proximity.answer_nearby(
        get_supabase(), current_user, incident_id, body.answer,
        lat=body.latitude, lng=body.longitude,
    )


# -- Phase 6D: acceptance -------------------------------------


@router.post("/queue/{incident_id}/accept")
def accept_incident(
    incident_id: str,
    body: AcceptRequest | None = None,
    current_user: dict = _responder_only,
):
    """
    Confirm that this responder is taking the call.

    The endpoint that makes 'dispatched' mean something. Until it existed, a
    dispatcher could not tell a crew already rolling from a handset in a
    locker - both looked identical on the board, and the difference only
    surfaced when nobody arrived.

    Idempotent: pressing twice on a bad connection returns the same success
    with the ORIGINAL timestamp, never a fresh one. Overwriting it would
    silently reset the response-time measurement this exists to produce.
    """
    return responder_ops_service.accept_incident(
        incident_id=incident_id,
        responder_id=str(current_user["id"]),
        occurred_at=body.occurred_at if body else None,
    )


@router.post("/queue/{incident_id}/decline")
def decline_incident(
    incident_id: str,
    body: DeclineRequest,
    current_user: dict = _responder_only,
):
    """
    Hand the incident back to the dispatcher, with a reason.

    The exit the FSM never had - _VALID_TRANSITIONS is forward-only, so a crew
    whose truck would not start had no way to say so.

    Returns the incident to 'processing' and clears the assignment. It does
    NOT pick the next responder: auto-reassignment can stand two crews down
    without either of them knowing, and nobody is left who can see it happened.
    """
    return responder_ops_service.decline_incident(
        incident_id=incident_id,
        responder_id=str(current_user["id"]),
        reason=body.reason,
        note=body.note,
    )


# -- Phase 6D: after-action -----------------------------------


@router.post("/queue/{incident_id}/close")
def close_incident(
    incident_id: str,
    body: CloseRequest,
    current_user: dict = _responder_only,
):
    """
    Resolve an incident WITH a disposition.

    The old resolve wrote a status and a timestamp and nothing else, which is
    why the archive has never recorded one fact about what a crew found - and
    why every severity the rubric has produced has been unfalsifiable.

    `outcome` is required. Optional, it would have been filled in on the quiet
    calls and skipped on the ones that mattered.
    """
    return responder_ops_service.close_incident(
        incident_id=incident_id,
        responder_id=str(current_user["id"]),
        outcome=body.outcome,
        outcome_notes=body.outcome_notes,
        casualties_injured=body.casualties_injured,
        casualties_fatal=body.casualties_fatal,
        casualties_transported=body.casualties_transported,
        occurred_at=body.occurred_at,
    )


@router.post("/queue/{incident_id}/scene-media")
def attach_scene_media(
    incident_id: str,
    body: SceneMediaRequest,
    current_user: dict = _responder_only,
):
    """
    Attach photos the responder took on scene.

    Stored in scene_media_urls, never in media_urls. That separation is the
    point: media_urls is what was known BEFORE anyone arrived, and merging the
    two would destroy the only way to tell a reporter's photo of smoke from a
    crew's photo of the room it came from.
    """
    return responder_ops_service.attach_scene_media(
        incident_id=incident_id,
        responder_id=str(current_user["id"]),
        paths=body.paths,
    )


# -- Phase 6D: mutual aid -------------------------------------


@router.post("/queue/{incident_id}/backup")
def request_backup(
    incident_id: str,
    body: BackupRequest,
    current_user: dict = _responder_only,
):
    """
    Ask a second agency to attend the same emergency.

    Multi-agency response is the norm here: a structure fire needs BFP on the
    fire, MDRRMO on the casualties and PNP on the crowd. Until now that
    happened entirely on the radio and left no record, so the archive shows
    one agency attending incidents that three attended.

    Creates a real linked incident - the ambulance crew needs something to be
    dispatched TO, with its own dispatcher, acceptance and after-action. A flag
    on the parent would give them nothing.
    """
    return responder_ops_service.request_backup(
        incident_id=incident_id,
        responder_id=str(current_user["id"]),
        agency_type=body.agency_type,
        reason=body.reason,
    )


@router.post("/queue/{incident_id}/escalate")
def escalate_incident(
    incident_id: str,
    body: EscalateRequest,
    current_user: dict = _responder_only,
):
    """
    Responder spec Section 14 — "the situation is worse than assessed."

    Notifies the Agency Admin so THEY can reassess; this endpoint never
    touches the incident's own severity. That split matches request_backup:
    a responder standing at the scene is the best source of what changed,
    but changing the official record stays with whoever already owns that —
    see escalate_incident's docstring in responder_ops_service.
    """
    return responder_ops_service.escalate_incident(
        incident_id=incident_id,
        responder_id=str(current_user["id"]),
        reason=body.reason,
    )


# -- Phase 6D: approach hazards -------------------------------


@router.get("/hazards")
def get_hazards(
    latitude: float,
    longitude: float,
    current_user: dict = _responder_only,
):
    """
    Standing local knowledge near a point - cut bridges, roads only a
    motorcycle fits down, dogs, unsafe structures.

    This knowledge exists in Biliran entirely inside the heads of the crews
    who have been there, and it leaves with them. A responder who learns about
    the washed-out bridge by arriving at it has lost the call.
    """
    return responder_ops_service.hazards_near(latitude, longitude)


@router.post("/hazards", status_code=201)
def create_hazard(
    body: HazardRequest,
    current_user: dict = _responder_only,
):
    """
    Record something about reaching a place that the map cannot show.

    Scoped to the author's agency. Making a hazard province-wide diverts every
    agency's units and is an agency-admin decision, not a responder's.
    """
    return responder_ops_service.create_hazard(
        user=current_user,
        latitude=body.latitude,
        longitude=body.longitude,
        hazard_type=body.hazard_type,
        note=body.note,
        radius_m=body.radius_m,
    )


# -- Phase 6D: the responder's own emergency ------------------


@router.post("/distress", status_code=201)
def raise_distress(
    body: DistressRequest,
    current_user: dict = _responder_only,
):
    """
    The responder's panic button.

    Every safety affordance in this product points at residents. The people
    who walk into the burning building and the armed domestic dispute have had
    none, on a device that is already a location-aware panic button for
    everybody else.

    Deliberately almost impossible to fail. A missing GPS fix, an unknown
    agency, an incident_id that does not resolve - none of them refuse the
    signal. The worst outcome here is a responder pressing this and being told
    their request was invalid.
    """
    return responder_ops_service.raise_distress(
        responder_id=str(current_user["id"]),
        agency_id=current_user.get("agency_id"),
        kind="panic",
        latitude=body.latitude,
        longitude=body.longitude,
        incident_id=body.incident_id,
        note=body.note,
    )
